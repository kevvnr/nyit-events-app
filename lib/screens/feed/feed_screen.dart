import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/announcement_service.dart';
import '../../services/event_service.dart';
import '../../services/analytics_service.dart';
import '../../services/experiment_service.dart';
import '../../services/algolia_service.dart';
import '../../services/live_activity_service.dart';
import '../../services/siri_shortcuts_service.dart';
import 'event_detail_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showPastEvents = false;
  bool _showSearch = false;
  String? _dismissedAnnouncementId;
  static const _prefKeyDismissed = 'dismissed_announcement_id';

  // Algolia search state
  List<String>? _algoliaIds;   // null = not searching; list = Algolia results
  bool _algoliaSearching = false;
  Timer? _debounce;
  /// 0 = main event list only; 1 = smart picks / tonight / conflict blocks + list.
  int _feedSegment = 0;
  final Map<String, int> _categoryAffinity = {};
  final Set<String> _conflictingEventIds = {};

  @override
  void initState() {
    super.initState();
    _loadDismissedAnnouncement();
    _loadSmartSignals();
    AnalyticsService.instance.logScreenView('feed_screen');
    final headerVariant = ExperimentService.instance.feedHeaderVariant;
    ExperimentService.instance.logExposure(
      experimentId: 'feed_header_variant',
      variant: headerVariant,
      placement: 'feed_header',
    );
  }

  Future<void> _loadDismissedAnnouncement() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyDismissed);
    if (saved != null && mounted) {
      setState(() => _dismissedAnnouncementId = saved);
    }
  }

  Future<void> _dismissAnnouncement(String id) async {
    setState(() => _dismissedAnnouncementId = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDismissed, id);
  }

  Future<void> _loadSmartSignals() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null || !user.isStudent) return;
    try {
      final rsvpSnap = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: user.uid)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();
      final now = DateTime.now();
      final categoryCounts = <String, int>{};
      final upcomingSlots =
          <({DateTime start, DateTime end, String eventId})>[];
      final eventService = ref.read(eventServiceProvider);
      for (final r in rsvpSnap.docs) {
        final eid = r.data()['eventId']?.toString();
        if (eid == null || eid.isEmpty) continue;
        final e = await eventService.getEventById(eid);
        if (e == null || e.isCancelled) continue;
        categoryCounts[e.category] = (categoryCounts[e.category] ?? 0) + 1;
        if (e.endTime.isAfter(now)) {
          upcomingSlots.add((
            start: e.startTime,
            end: e.endTime,
            eventId: e.id,
          ));
        }
      }

      final events = await eventService.getEvents();
      final conflicts = <String>{};
      for (final e in events) {
        for (final s in upcomingSlots) {
          if (s.eventId == e.id) continue;
          if (EventService.timeRangesOverlap(
            e.startTime,
            e.endTime,
            s.start,
            s.end,
          )) {
            conflicts.add(e.id);
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _categoryAffinity
          ..clear()
          ..addAll(categoryCounts);
        _conflictingEventIds
          ..clear()
          ..addAll(conflicts);
      });
    } catch (_) {}
  }

  double _discoveryScore(EventModel event) {
    var score = 0.0;
    score += (_categoryAffinity[event.category] ?? 0) * 2.0;
    if (event.isHappeningNow) score += 2.5;
    if (event.isPinned) score += 1.5;
    if (event.spotsLeft > 0 && event.spotsLeft <= 5) score += 0.7;
    if (_conflictingEventIds.contains(event.id)) score -= 4.0;
    return score;
  }

  bool get _isDiscoveryContext =>
      _selectedCategory == 'All' &&
      _searchQuery.trim().isEmpty &&
      !_showPastEvents;

  String _copilotReason(EventModel event) {
    final likes = _categoryAffinity[event.category] ?? 0;
    if (event.isHappeningNow) {
      return 'Live now and matches your discovery profile.';
    }
    if (likes >= 2) {
      return 'You often RSVP to ${event.category} events.';
    }
    if (event.spotsLeft > 0 && event.spotsLeft <= 8) {
      return 'Limited spots left, good time to lock this in.';
    }
    return 'Strong fit based on timing, category, and availability.';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _debounce?.cancel();
    if (val.trim().isEmpty) {
      setState(() { _algoliaIds = null; _algoliaSearching = false; });
      return;
    }
    setState(() => _algoliaSearching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final ids = await AlgoliaService.instance.searchEventIds(
        val.trim(),
        category: _selectedCategory == 'All' ? null : _selectedCategory,
      );
      if (mounted) setState(() { _algoliaIds = ids; _algoliaSearching = false; });
    });
  }

  List<EventModel> _filterEvents(List<EventModel> events) {
    final now = DateTime.now();

    // When Algolia search is active, filter by Algolia IDs and preserve
    // relevance order returned by Algolia.
    if (_algoliaIds != null) {
      final order = {
        for (var i = 0; i < _algoliaIds!.length; i++) _algoliaIds![i]: i,
      };
      final matched = events
          .where((e) => order.containsKey(e.id) && !e.isCancelled)
          .toList()
        ..sort((a, b) => (order[a.id] ?? 999).compareTo(order[b.id] ?? 999));
      return matched;
    }

    // Normal local filter when no search query.
    var filtered = events.where((event) {
      final matchesCategory =
          _selectedCategory == 'All' || event.category == _selectedCategory;
      final notEnded = event.endTime.isAfter(now);
      final isPast = event.endTime.isBefore(now);
      return matchesCategory &&
          !event.isCancelled &&
          (notEnded || (_showPastEvents && isPast));
    }).toList();

    filtered.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isHappeningNow && !b.isHappeningNow) return -1;
      if (!a.isHappeningNow && b.isHappeningNow) return 1;
      final scoreCmp = _discoveryScore(b).compareTo(_discoveryScore(a));
      if (scoreCmp != 0) return scoreCmp;
      return a.startTime.compareTo(b.startTime);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventsStreamProvider);
    final user = ref.watch(userModelProvider).asData?.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
          ),
        ),
        child: Column(
          children: [
            _CompactFeedHeader(
              userName: user?.name ?? '',
              showPast: _showPastEvents,
              feedSegment: _feedSegment,
              onFeedSegmentChanged: (v) => setState(() => _feedSegment = v),
            ),
            // Announcement banner
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: AnnouncementService.announcementsStream(),
              builder: (context, snapshot) {
                final announcements = snapshot.data ?? [];
                if (announcements.isEmpty) {
                  return const SizedBox.shrink();
                }
                final latest = announcements.first;
                final announcementId =
                    latest['id']?.toString() ?? latest['message']?.toString() ?? '';
                // Dismissed by user — hide until a new announcement comes in
                if (_dismissedAnnouncementId == announcementId) {
                  return const SizedBox.shrink();
                }
                final isUrgent = latest['priority'] == 'urgent';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: isUrgent
                      ? Colors.red.shade600
                      : const Color(0xFF1a3a6b),
                  child: Row(
                    children: [
                      Icon(
                        isUrgent
                            ? Icons.warning_rounded
                            : Icons.campaign_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          latest['message'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _dismissAnnouncement(announcementId),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Offline banner
            Consumer(
              builder: (context, ref, _) {
                final isFromCache =
                    ref.watch(eventsFromCacheProvider).asData?.value ?? false;
                if (!isFromCache) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: Colors.orange.shade700,
                  child: const Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'You\'re offline — showing cached events',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Search bar
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    prefixIcon: _algoliaSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _debounce?.cancel();
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _showSearch = false;
                          _algoliaIds = null;
                          _algoliaSearching = false;
                        });
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF1565C0),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),

            // Category chips + search + history
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: ['All', ...AppConfig.defaultCategories].map((
                        cat,
                      ) {
                        final selected = _selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8, top: 10),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedCategory = cat);
                              if (_searchQuery.isNotEmpty) {
                                _onSearchChanged(_searchQuery);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF1565C0)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF1565C0)
                                      : const Color(0xFFE2E8F0),
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF1565C0,
                                          ).withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Text(
                                cat,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Search button
                  GestureDetector(
                    onTap: () => setState(() => _showSearch = true),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8, top: 10),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),

                  // Past events toggle
                  Tooltip(
                    message: _showPastEvents
                        ? 'Hide past events'
                        : 'Show past events',
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _showPastEvents = !_showPastEvents);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _showPastEvents
                                  ? 'Showing past events'
                                  : 'Past events hidden',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 16, top: 10),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _showPastEvents
                              ? const Color(0xFF1565C0).withOpacity(0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _showPastEvents
                                ? const Color(0xFF1565C0)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Icon(
                          Icons.history_rounded,
                          size: 18,
                          color: _showPastEvents
                              ? const Color(0xFF1565C0)
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Past events indicator
            if (_showPastEvents)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 14,
                      color: const Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Showing past events',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _showPastEvents = false),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Color(0xFF1565C0),
                      ),
                    ),
                  ],
                ),
              ),

            // Events list
            Expanded(
              child: eventsState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 56,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Could not load events',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Check your connection and try again.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => ref.refresh(eventsStreamProvider),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (events) {
                  final filtered = _filterEvents(events);
                  final recommended =
                      filtered
                          .where(
                            (e) =>
                                !e.isPast &&
                                !_conflictingEventIds.contains(e.id),
                          )
                          .toList()
                        ..sort(
                          (a, b) =>
                              _discoveryScore(b).compareTo(_discoveryScore(a)),
                        );
                  final now = DateTime.now();
                  final tonight = filtered
                      .where(
                        (e) =>
                            e.startTime.year == now.year &&
                            e.startTime.month == now.month &&
                            e.startTime.day == now.day &&
                            e.endTime.isAfter(now),
                      )
                      .take(5)
                      .toList();
                  final discovery =
                      _feedSegment == 1 && _isDiscoveryContext;
                  final showTonight = discovery && tonight.isNotEmpty;
                  final showPicks = discovery && recommended.isNotEmpty;
                  final aiPick = recommended.isNotEmpty
                      ? recommended.first
                      : null;
                  final showAiCopilot = discovery && aiPick != null;
                  final conflictSuggestions = filtered
                      .where(
                        (e) => _conflictingEventIds.contains(e.id) && !e.isPast,
                      )
                      .take(4)
                      .toList();
                  final showConflictAssistant =
                      discovery && conflictSuggestions.isNotEmpty;
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy_rounded,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No events found',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check back later or try a different filter',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      final _ = ref.refresh(eventsStreamProvider);
                      await _loadSmartSignals();
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: ListView.builder(
                        key: ValueKey(
                          '${_selectedCategory}_${_searchQuery}_${_showPastEvents}_${_feedSegment}_${filtered.length}',
                        ),
                        padding: EdgeInsets.fromLTRB(
                          16, 8, 16,
                          MediaQuery.paddingOf(context).bottom + 88,
                        ),
                        itemCount:
                            filtered.length +
                            (showTonight ? 1 : 0) +
                            (showPicks ? 1 : 0) +
                            (showAiCopilot ? 1 : 0) +
                            (showConflictAssistant ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (showTonight && index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TonightSpotlightSection(events: tonight),
                            );
                          }
                          final picksIndex = showTonight ? 1 : 0;
                          if (showPicks && index == picksIndex) {
                            final picks = recommended.take(3).toList();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SmartPicksSection(events: picks),
                            );
                          }
                          final conflictIndex =
                              (showTonight ? 1 : 0) + (showPicks ? 1 : 0);
                          if (showAiCopilot && index == conflictIndex) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _AiCopilotSection(
                                event: aiPick,
                                reason: _copilotReason(aiPick),
                              ),
                            );
                          }
                          final conflictAssistantIndex =
                              conflictIndex + (showAiCopilot ? 1 : 0);
                          if (showConflictAssistant &&
                              index == conflictAssistantIndex) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ConflictAssistantSection(
                                events: conflictSuggestions,
                              ),
                            );
                          }
                          final effectiveIndex =
                              index -
                              (showTonight ? 1 : 0) -
                              (showPicks ? 1 : 0) -
                              (showAiCopilot ? 1 : 0) -
                              (showConflictAssistant ? 1 : 0);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EventCard(
                              event: filtered[effectiveIndex],
                              hasConflict: _conflictingEventIds.contains(
                                filtered[effectiveIndex].id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactFeedHeader extends StatelessWidget {
  final String userName;
  final bool showPast;
  final int feedSegment;
  final ValueChanged<int> onFeedSegmentChanged;

  const _CompactFeedHeader({
    required this.userName,
    required this.showPast,
    required this.feedSegment,
    required this.onFeedSegmentChanged,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = userName.trim().isEmpty
        ? 'there'
        : userName.trim().split(' ').first;
    final topInset = MediaQuery.paddingOf(context).top;
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Good to see you, $firstName',
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              showPast ? 'Browsing past events' : 'Upcoming events & filters below',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Events'),
                  icon: Icon(Icons.event_note_rounded, size: 18),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('For you'),
                  icon: Icon(Icons.auto_awesome_rounded, size: 18),
                ),
              ],
              selected: {feedSegment},
              onSelectionChanged: (next) {
                if (next.isEmpty) return;
                onFeedSegmentChanged(next.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return const Color(0xFF475569);
                }),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color(0xFF1565C0);
                  }
                  return const Color(0xFFF1F5F9);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPicksSection extends StatelessWidget {
  final List<EventModel> events;
  const _SmartPicksSection({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE3F2FD), Color(0xFFF8FBFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF1565C0),
                size: 15,
              ),
              SizedBox(width: 6),
              Text(
                'Smart picks for you',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1565C0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...events.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SmartPickTile(event: e),
            ),
          ),
        ],
      ),
    );
  }
}

class _TonightSpotlightSection extends StatelessWidget {
  final List<EventModel> events;
  const _TonightSpotlightSection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E1), Color(0xFFFFFBF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.nights_stay_rounded,
                color: Color(0xFFE65100),
                size: 15,
              ),
              SizedBox(width: 6),
              Text(
                'Tonight at NYIT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final e = events[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventDetailScreen(eventId: e.id),
                    ),
                  ),
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('h:mm a').format(e.startTime),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.locationName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${e.rsvpCount}/${e.capacity} going',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartPickTile extends StatelessWidget {
  final EventModel event;
  const _SmartPickTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.event_rounded,
                size: 18,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${event.category} • ${DateFormat('EEE, MMM d · h:mm a').format(event.startTime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _ConflictAssistantSection extends StatelessWidget {
  final List<EventModel> events;
  const _ConflictAssistantSection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFFFBF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.schedule_rounded, color: Color(0xFFC2410C), size: 15),
              SizedBox(width: 6),
              Text(
                'Conflict assistant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC2410C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'These events overlap with your current RSVP schedule.',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
          ),
          const SizedBox(height: 8),
          ...events.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDetailScreen(eventId: e.id),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFC2410C),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.title} · ${DateFormat('EEE h:mm a').format(e.startTime)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCopilotSection extends StatelessWidget {
  final EventModel event;
  final String reason;
  const _AiCopilotSection({required this.event, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEDE9FE), Color(0xFFF8F5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDD6FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF6D28D9),
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                'Smart picks',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6D28D9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(eventId: event.id),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE9D5FF)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.recommend_rounded,
                    color: Color(0xFF6D28D9),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reason,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Event Card ────────────────────────────────────────
class _EventCard extends ConsumerStatefulWidget {
  final EventModel event;
  final bool hasConflict;
  const _EventCard({required this.event, this.hasConflict = false});

  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  bool _isRsvping = false;
  Map<String, dynamic>? _userRsvp;

  static const Map<String, String> _categoryImages = {
    'Academic':
        'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80',
    'Social':
        'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&q=80',
    'Sports':
        'https://images.unsplash.com/photo-1461896836934-ffe607ba8211?w=800&q=80',
    'Career / Networking':
        'https://images.unsplash.com/photo-1551836022-d5d88e9218df?w=800&q=80',
    'Arts & Culture':
        'https://images.unsplash.com/photo-1499781350541-7783f6c6a0c8?w=800&q=80',
    'Health & Wellness':
        'https://images.unsplash.com/photo-1506126613408-eca07ce68773?w=800&q=80',
    'Club / Org':
        'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&q=80',
    'Food & Dining':
        'https://images.unsplash.com/photo-1567521464027-f127ff144326?w=800&q=80',
    'Other':
        'https://images.unsplash.com/photo-1523580494863-6f3031224c94?w=800&q=80',
  };

  @override
  void initState() {
    super.initState();
    _loadRsvp();
  }

  Future<void> _loadRsvp() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;
    final rsvp = await ref
        .read(eventServiceProvider)
        .getUserRsvp(eventId: widget.event.id, userId: user.uid);
    if (mounted) setState(() => _userRsvp = rsvp);
  }

  Future<void> _quickRsvp() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null || !user.isStudent) return;
    setState(() => _isRsvping = true);
    try {
      if (_userRsvp != null) {
        await ref
            .read(eventServiceProvider)
            .cancelRsvp(eventId: widget.event.id, userId: user.uid);
        await LiveActivityService.instance.end(widget.event.id);
        if (mounted) setState(() => _userRsvp = null);
      } else {
        final status = await ref
            .read(eventServiceProvider)
            .rsvpEvent(
              eventId: widget.event.id,
              userId: user.uid,
              qrToken: user.uid,
            );
        if (status == AppConfig.rsvpConfirmed) {
          await LiveActivityService.instance.startOrUpdate(
            eventId: widget.event.id,
            title: widget.event.title,
            startTime: widget.event.startTime,
            endTime: widget.event.endTime,
            location: widget.event.locationName,
          );
          await SiriShortcutsService.instance.donateOpenEvent(
            eventId: widget.event.id,
            eventTitle: widget.event.title,
          );
        }
        await _loadRsvp();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == AppConfig.rsvpConfirmed
                    ? '✓ You\'re going to ${widget.event.title}!'
                    : 'Added to waitlist',
              ),
              backgroundColor: status == AppConfig.rsvpConfirmed
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRsvping = false);
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Academic':
        return const Color(0xFF1565C0);
      case 'Social':
        return const Color(0xFF7B1FA2);
      case 'Sports':
        return const Color(0xFF2E7D32);
      case 'Career / Networking':
        return const Color(0xFFE65100);
      case 'Arts & Culture':
        return const Color(0xFFC62828);
      case 'Health & Wellness':
        return const Color(0xFF00838F);
      case 'Club / Org':
        return const Color(0xFF4527A0);
      case 'Food & Dining':
        return const Color(0xFF558B2F);
      default:
        return const Color(0xFF546E7A);
    }
  }

  String _formatEventTime(EventModel event) {
    final now = DateTime.now();
    final start = event.startTime;

    if (event.isHappeningNow) {
      final endDiff = event.endTime.difference(now);
      if (endDiff.inHours > 0) {
        return 'Ends in ${endDiff.inHours}h ${endDiff.inMinutes % 60}m';
      }
      return 'Ends in ${endDiff.inMinutes}m';
    }

    final nowDay = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    final daysDiff = startDay.difference(nowDay).inDays;

    if (daysDiff == 0) {
      return 'Today, ${DateFormat('h:mm a').format(start)}';
    } else if (daysDiff == 1) {
      return 'Tomorrow, ${DateFormat('h:mm a').format(start)}';
    } else if (daysDiff < 7) {
      return DateFormat('EEEE, h:mm a').format(start);
    }
    return DateFormat('MMM d, h:mm a').format(start);
  }

  Widget _buildColorBanner(Color catColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [catColor, catColor.withOpacity(0.7)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.event_rounded,
          color: Colors.white.withOpacity(0.3),
          size: 64,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final catColor = _categoryColor(event.category);
    final pct = event.fillPercent;
    final isPast = event.endTime.isBefore(DateTime.now());
    final isRsvpd =
        _userRsvp != null && _userRsvp!['status'] == AppConfig.rsvpConfirmed;
    final isWaitlisted =
        _userRsvp != null && _userRsvp!['status'] == AppConfig.rsvpWaitlist;
    final isCheckedIn = _userRsvp?['checkedIn'] == true;
    final user = ref.watch(userModelProvider).asData?.value;

    final imageUrl = event.imageUrl.isNotEmpty
        ? event.imageUrl
        : (_categoryImages[event.category] ?? _categoryImages['Other']!);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)),
      ).then((_) => _loadRsvp()),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image banner
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 115,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return _buildColorBanner(catColor);
                      },
                      errorBuilder: (_, __, ___) => _buildColorBanner(catColor),
                    ),

                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.55),
                          ],
                        ),
                      ),
                    ),

                    // Category badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          event.category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    // Status badges
                    if (event.isPinned && !isPast)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.push_pin_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Pinned',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (event.isHappeningNow)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulseDot(),
                              const SizedBox(width: 4),
                              const Text(
                                'Happening Now',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    if (isPast)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Ended',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                    // Title overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 4),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Card body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Host + time
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: catColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: catColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.hostName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _formatEventTime(event),
                              style: TextStyle(
                                fontSize: 11,
                                color: event.isHappeningNow
                                    ? Colors.green.shade700
                                    : const Color(0xFF64748B),
                                fontWeight: event.isHappeningNow
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCheckedIn)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 11,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Checked in',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.hasConflict &&
                          !isPast &&
                          user?.isStudent == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 10, color: Colors.orange.shade700),
                              const SizedBox(width: 3),
                              Text(
                                'Conflict',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Location
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.locationName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Vibe tags
                  if (event.vibeTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: event.vibeTags
                          .take(3)
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Capacity bar
                  if (!isPast) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          event.isFull
                              ? 'Full · waitlist open'
                              : '${event.spotsLeft} spots left',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: event.isFull
                                ? Colors.orange.shade700
                                : Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '${event.rsvpCount}/${event.capacity}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          pct >= 1.0 ? Colors.orange : const Color(0xFF1565C0),
                        ),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action row
                  Row(
                    children: [
                      if (!isPast && user?.isStudent == true)
                        Expanded(
                          child: GestureDetector(
                            onTap: _isRsvping ? null : _quickRsvp,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isCheckedIn
                                    ? Colors.green.shade600
                                    : isRsvpd
                                    ? const Color(0xFF1565C0)
                                    : isWaitlisted
                                    ? Colors.orange
                                    : const Color(0xFF1565C0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: _isRsvping
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        isCheckedIn
                                            ? '✓ Checked In'
                                            : isRsvpd
                                            ? "You're Going!"
                                            : isWaitlisted
                                            ? 'On Waitlist'
                                            : event.isFull
                                            ? 'Join Waitlist'
                                            : 'RSVP',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      if (!isPast && user?.isStudent == true)
                        const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 15,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isPast
                                  ? '${event.rsvpCount} attended'
                                  : '${event.rsvpCount} going',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pulse Dot ─────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
