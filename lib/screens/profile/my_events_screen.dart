import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../services/live_activity_service.dart';
import '../../services/review_prompt_service.dart';

class MyEventsScreen extends ConsumerStatefulWidget {
  const MyEventsScreen({super.key});

  @override
  ConsumerState<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends ConsumerState<MyEventsScreen> {
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _past = [];
  bool _isLoading = true;
  bool _showPastSection = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    try {
      // Get all RSVPs for this user
      final rsvpSnap = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: user.uid)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();

      final eventIds = rsvpSnap.docs
          .map((d) => d.data()['eventId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final eventsById = <String, Map<String, dynamic>>{};
      for (var i = 0; i < eventIds.length; i += 10) {
        final chunk = eventIds.sublist(
          i,
          (i + 10 > eventIds.length) ? eventIds.length : i + 10,
        );
        final snap = await FirebaseFirestore.instance
            .collection(AppConfig.eventsCol)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          eventsById[doc.id] = doc.data();
        }
      }

      final upcoming = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (final doc in rsvpSnap.docs) {
        final data = doc.data();
        try {
          final eventId = data['eventId']?.toString();
          if (eventId == null || eventId.isEmpty) continue;
          final rawEvent = eventsById[eventId];
          if (rawEvent == null) continue;
          final status = (rawEvent['status'] ?? '').toString();
          if (status == AppConfig.eventCancelled) continue;
          final startTs = rawEvent['startTime'] as Timestamp?;
          final endTs = rawEvent['endTime'] as Timestamp?;
          if (startTs == null || endTs == null) continue;
          final eventStart = startTs.toDate();
          final eventEnd = endTs.toDate();

          final enriched = {
            'rsvpId': doc.id,
            ...data,
            'eventTitle': (rawEvent['title'] ?? 'Event').toString(),
            'eventDate': eventStart,
            'endTime': eventEnd,
            'locationName': (rawEvent['locationName'] ?? '').toString(),
            'category': (rawEvent['category'] ?? '').toString(),
            'hostName': (rawEvent['hostName'] ?? '').toString(),
            'checkedIn': data['checkedIn'] ?? false,
            'checkedInViaWeb': data['checkedInViaWeb'] ?? false,
            'manualCheckIn': data['manualCheckIn'] ?? false,
          };

          // Ended events move to past immediately at end time.
          if (!eventEnd.isAfter(now)) {
            past.add(enriched);
          } else {
            upcoming.add(enriched);
          }
        } catch (e) {
          print('loadData event error: $e');
        }
      }

      // Sort upcoming by date asc, past by date desc
      upcoming.sort(
        (a, b) =>
            (a['eventDate'] as DateTime).compareTo(b['eventDate'] as DateTime),
      );
      past.sort(
        (a, b) =>
            (b['eventDate'] as DateTime).compareTo(a['eventDate'] as DateTime),
      );

      if (mounted) {
        setState(() {
          _upcoming = upcoming;
          _past = past;
          _isLoading = false;
        });
      }

      if (upcoming.isNotEmpty) {
        final next = upcoming.first;
        final nextId = (next['eventId'] ?? '').toString();
        final nextTitle = (next['eventTitle'] ?? 'Upcoming event').toString();
        final nextStart = next['eventDate'] as DateTime?;
        final nextEnd = next['endTime'] as DateTime?;
        final nextLocation = (next['locationName'] ?? '').toString();
        if (nextId.isNotEmpty && nextStart != null && nextEnd != null) {
          await LiveActivityService.instance.syncNextUpcoming(
            eventId: nextId,
            title: nextTitle,
            startTime: nextStart,
            endTime: nextEnd,
            location: nextLocation,
          );
        }
      }
      final attendedCount = past.where((e) => e['checkedIn'] == true).length;
      if (attendedCount >= 2) {
        await ReviewPromptService.instance.registerPositiveSignal();
      }
    } catch (e) {
      print('loadData error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendedCount = _past.where((e) => e['checkedIn'] == true).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My events'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                setState(() => _showPastSection = !_showPastSection),
            icon: Icon(
              _showPastSection
                  ? Icons.visibility_off_outlined
                  : Icons.history_rounded,
            ),
            label: Text(
              _showPastSection ? 'Hide past' : 'Past (${_past.length})',
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showPastSection && _past.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    color: AppConfig.primaryColor,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(
                          value: '${_past.length}',
                          label: 'Past RSVPs',
                          icon: Icons.event_rounded,
                        ),
                        Container(width: 1, height: 30, color: Colors.white24),
                        _StatItem(
                          value: '$attendedCount',
                          label: 'Checked in',
                          icon: Icons.qr_code_rounded,
                        ),
                        Container(width: 1, height: 30, color: Colors.white24),
                        _StatItem(
                          value: _past.isEmpty
                              ? '0%'
                              : '${(attendedCount / _past.length * 100).round()}%',
                          label: 'Attendance rate',
                          icon: Icons.bar_chart_rounded,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'Upcoming (${_upcoming.length})',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        if (_upcoming.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            sliver: SliverToBoxAdapter(
                              child: _UpcomingCalendarCard(upcoming: _upcoming),
                            ),
                          ),
                        if (_upcoming.isEmpty &&
                            !(_showPastSection && _past.isNotEmpty))
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyState(
                              icon: Icons.event_outlined,
                              message: 'No upcoming events',
                              subtitle: 'Find events in Feed.',
                            ),
                          )
                        else if (_upcoming.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No upcoming events',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _UpcomingCard(rsvp: _upcoming[index]),
                                );
                              }, childCount: _upcoming.length),
                            ),
                          ),
                        if (_showPastSection) ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                'Past (${_past.length})',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (_past.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyState(
                                icon: Icons.history_rounded,
                                message: 'No past events',
                                subtitle: 'Ended events appear here.',
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _PastCard(event: _past[index]),
                                  );
                                }, childCount: _past.length),
                              ),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _UpcomingCalendarCard extends StatelessWidget {
  final List<Map<String, dynamic>> upcoming;
  const _UpcomingCalendarCard({required this.upcoming});

  @override
  Widget build(BuildContext context) {
    final dateMap = <DateTime, int>{};
    for (final e in upcoming) {
      final start = e['eventDate'] as DateTime?;
      if (start == null) continue;
      final day = DateTime(start.year, start.month, start.day);
      dateMap[day] = (dateMap[day] ?? 0) + 1;
    }
    final days = dateMap.keys.toList()..sort();
    final shownDays = days.take(7).toList();
    final nextEvent = upcoming.first['eventDate'] as DateTime?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: Color(0xFF1565C0),
              ),
              SizedBox(width: 6),
              Text(
                'Upcoming calendar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shownDays.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final day = shownDays[index];
                final count = dateMap[day] ?? 0;
                return Container(
                  width: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(day),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (nextEvent != null) ...[
            const SizedBox(height: 8),
            Text(
              'Next: ${DateFormat('EEE, MMM d • h:mm a').format(nextEvent)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final Map<String, dynamic> rsvp;
  const _UpcomingCard({required this.rsvp});

  @override
  Widget build(BuildContext context) {
    final isWaitlist = rsvp['status'] == AppConfig.rsvpWaitlist;
    final eventDate = rsvp['eventDate'] as DateTime?;
    final endTime = rsvp['endTime'] as DateTime?;
    final now = DateTime.now();
    final startsIn = eventDate == null ? null : eventDate.difference(now);
    final isSoon =
        startsIn != null && startsIn.inMinutes >= 0 && startsIn.inMinutes <= 90;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWaitlist ? Colors.orange.shade200 : const Color(0xFFE2E8F0),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isWaitlist
                  ? Colors.orange.withOpacity(0.1)
                  : AppConfig.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isWaitlist
                  ? Icons.hourglass_empty_rounded
                  : Icons.check_circle_outline_rounded,
              color: isWaitlist
                  ? Colors.orange.shade700
                  : AppConfig.primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rsvp['eventTitle'] ?? 'Event',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (eventDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM d • h:mm a').format(eventDate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                if ((rsvp['locationName'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    rsvp['locationName'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (isSoon && endTime != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    startsIn.inMinutes <= 1
                        ? 'Starting now'
                        : 'Starts in ${startsIn.inMinutes} min',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isWaitlist
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isWaitlist ? 'On waitlist' : 'Confirmed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isWaitlist
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _PastCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final checkedIn = event['checkedIn'] == true;
    final isManual = event['manualCheckIn'] == true;
    final isWeb = event['checkedInViaWeb'] == true;
    final eventDate = event['eventDate'] as DateTime?;

    String checkInMethod = '';
    if (checkedIn) {
      if (isWeb)
        checkInMethod = 'via QR scan';
      else if (isManual)
        checkInMethod = 'manually';
      else
        checkInMethod = 'via app';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: checkedIn
            ? LinearGradient(
                colors: [Colors.green.shade50, const Color(0xFFF8FFFB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: checkedIn ? Colors.green.shade200 : const Color(0xFFE2E8F0),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: checkedIn
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              checkedIn
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: checkedIn ? Colors.green.shade700 : Colors.grey,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['eventTitle'] ?? 'Event',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (eventDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM d, yyyy').format(eventDate),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
                if ((event['hostName'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'By ${event['hostName']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
                if (checkedIn && checkInMethod.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Checked in $checkInMethod',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if ((event['locationName'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    event['locationName'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: checkedIn
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              checkedIn ? 'Attended' : 'RSVP only',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: checkedIn ? Colors.green.shade700 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
