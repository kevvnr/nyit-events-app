import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../config/app_config.dart';
import '../admin/attendee_list_screen.dart';
import '../admin/edit_event_screen.dart';
import '../admin/qr_scanner_screen.dart';
import '../../utils/map_directions.dart';
import '../map/ar_wayfinding_screen.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../services/experiment_service.dart';
import '../../services/live_activity_service.dart';
import '../../services/siri_shortcuts_service.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _userRsvp;
  bool _rsvpLoaded = false;
  int? _waitlistPosition;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _rsvpSub;

  // Category image map
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
  void dispose() {
    _rsvpSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUserRsvp();
    _startRsvpStream();
    AnalyticsService.instance.logScreenView('event_detail_screen');
    final variant = ExperimentService.instance.rsvpCtaVariant;
    ExperimentService.instance.logExposure(
      experimentId: 'rsvp_cta_variant',
      variant: variant,
      placement: 'event_detail',
    );
    SiriShortcutsService.instance.donateOpenEvent(
      eventId: widget.eventId,
      eventTitle: 'Event',
    );
  }

  void _startRsvpStream() {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;

    _rsvpSub = FirebaseFirestore.instance
        .collection(AppConfig.rsvpsCol)
        .where('userId', isEqualTo: user.uid)
        .where('eventId', isEqualTo: widget.eventId)
        .where(
          'status',
          whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
        )
        .snapshots()
        .listen((snap) {
          if (mounted) {
            setState(() {
              _userRsvp = snap.docs.isEmpty
                  ? null
                  : {'id': snap.docs.first.id, ...snap.docs.first.data()};
              _rsvpLoaded = true;
            });
          }
        });
  }

  Future<void> _loadUserRsvp() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;
    final rsvp = await ref
        .read(eventServiceProvider)
        .getUserRsvp(eventId: widget.eventId, userId: user.uid);
    if (mounted) {
      setState(() {
        _userRsvp = rsvp;
        _rsvpLoaded = true;
      });
      if (rsvp != null && rsvp['status'] == AppConfig.rsvpWaitlist) {
        await _loadWaitlistPosition(user.uid);
      } else if (mounted) {
        setState(() => _waitlistPosition = null);
      }
    }
  }

  Future<void> _loadWaitlistPosition(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: widget.eventId)
          .where('status', isEqualTo: AppConfig.rsvpWaitlist)
          .orderBy('createdAt', descending: false)
          .get();
      final index = snap.docs.indexWhere((d) => d['userId'] == userId);
      if (mounted) {
        setState(() => _waitlistPosition = index == -1 ? null : index + 1);
      }
    } catch (_) {}
  }

  Future<void> _handleRsvp(EventModel event) async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      final status = await ref
          .read(eventServiceProvider)
          .rsvpEvent(
            eventId: event.id,
            userId: user.uid,
            qrToken: const Uuid().v4(),
          );
      await _loadUserRsvp();

      // Schedule a local reminder only for confirmed RSVPs
      if (status == AppConfig.rsvpConfirmed) {
        final reminderMinutes = user.reminderMinutes;
        await NotificationService.scheduleEventReminder(
          eventId: event.id,
          eventTitle: event.title,
          eventStartTime: event.startTime,
          reminderMinutes: reminderMinutes,
        );
        await LiveActivityService.instance.startOrUpdate(
          eventId: event.id,
          title: event.title,
          startTime: event.startTime,
          endTime: event.endTime,
          location: event.locationName,
        );
        await SiriShortcutsService.instance.donateOpenEvent(
          eventId: event.id,
          eventTitle: event.title,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == AppConfig.rsvpConfirmed
                  ? "You're confirmed for ${event.title}!"
                  : "You've been added to the waitlist.",
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCancel(EventModel event) async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel RSVP?'),
        content: const Text(
          'Are you sure? The next person on the waitlist will be promoted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep RSVP'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel RSVP',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(eventServiceProvider)
          .cancelRsvp(eventId: event.id, userId: user.uid);
      // Cancel any pending local reminder for this event
      await NotificationService.cancelEventReminder(event.id);
      await LiveActivityService.instance.end(event.id);
      await _loadUserRsvp();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('RSVP cancelled.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openDirections(EventModel event) async {
    if (event.locationLat == 0.0 && event.locationLng == 0.0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No location coordinates available for this event.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await openWalkingDirections(
      context: context,
      destinationLat: event.locationLat,
      destinationLng: event.locationLng,
      destinationTitle: event.title,
    );
  }

  void _addToCalendar(EventModel event) {
    final calEvent = Event(
      title: event.title,
      description: event.description,
      location: event.locationName,
      startDate: event.startTime,
      endDate: event.endTime,
    );
    Add2Calendar.addEvent2Cal(calEvent);
  }

  void _showEventQr(BuildContext context, EventModel event) {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) return;
    SiriShortcutsService.instance.donateShowQr(
      eventId: event.id,
      eventTitle: event.title,
    );

    // Build a URL so any phone camera can scan and open the check-in page.
    // Falls back to user.uid for legacy RSVPs created before UUID tokens.
    final token = (_userRsvp?['qrToken'] as String?)?.isNotEmpty == true
        ? _userRsvp!['qrToken'] as String
        : user.uid;
    final qrData =
        'https://campuseventapp-a56f7.web.app/checkin?token=$token&eventId=${event.id}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your Check-in QR',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              event.title,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF1E293B),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppConfig.primaryColor,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Show this QR to your teacher. It only works for this specific event.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppConfig.primaryColor,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  String _countdown(DateTime time) {
    final diff = time.difference(DateTime.now());
    if (diff.isNegative) return '';
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventStreamProvider(widget.eventId));
    final user = ref.watch(userModelProvider).asData?.value;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: eventAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (event) {
          if (event == null) {
            return const Center(child: Text('Event not found'));
          }

          final catColor = _categoryColor(event.category);
          final pct = event.fillPercent;
          final isRsvpd =
              _userRsvp != null &&
              _userRsvp!['status'] == AppConfig.rsvpConfirmed;
          final isWaitlisted =
              _userRsvp != null &&
              _userRsvp!['status'] == AppConfig.rsvpWaitlist;
          final isCheckedIn = _userRsvp?['checkedIn'] == true;
          final now = DateTime.now();
          final qrOpensAt = event.startTime.subtract(
            const Duration(minutes: 15),
          );
          final qrClosesAt = event.endTime.add(const Duration(minutes: 15));
          final isQrWindowOpen =
              !now.isBefore(qrOpensAt) && !now.isAfter(qrClosesAt);
          final imageUrl = event.imageUrl.isNotEmpty
              ? event.imageUrl
              : (_categoryImages[event.category] ?? _categoryImages['Other']!);

          return CustomScrollView(
            slivers: [
              // Hero image app bar
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: catColor,
                leading: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                actions: [
                  GestureDetector(
                    onTap: () => _addToCalendar(event),
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: catColor),
                      ),
                      // Dark gradient overlay
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                      // Status badges
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: catColor,
                                    borderRadius: BorderRadius.circular(20),
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
                                const SizedBox(width: 8),
                                if (event.isHappeningNow)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade600,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Happening Now',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
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
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main content card
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            Text(
                              event.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Info rows
                            _DetailRow(
                              icon: Icons.person_rounded,
                              label: 'Host',
                              value: event.hostName,
                              color: catColor,
                            ),
                            _DetailRow(
                              icon: Icons.access_time_rounded,
                              label: 'Starts',
                              value: DateFormat(
                                'EEEE, MMM d · h:mm a',
                              ).format(event.startTime),
                              color: catColor,
                            ),
                            _DetailRow(
                              icon: Icons.access_time_filled_rounded,
                              label: 'Ends',
                              value: DateFormat(
                                'EEEE, MMM d · h:mm a',
                              ).format(event.endTime),
                              color: catColor,
                            ),
                            _DetailRow(
                              icon: Icons.location_on_rounded,
                              label: 'Location',
                              value: event.locationName,
                              color: catColor,
                            ),

                            // Directions button
                            if (event.locationLat != 0.0 ||
                                event.locationLng != 0.0) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => _openDirections(event),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF1565C0,
                                    ).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF1565C0,
                                      ).withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.directions_rounded,
                                        size: 18,
                                        color: catColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Get Directions',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: catColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.open_in_new_rounded,
                                        size: 14,
                                        color: catColor.withOpacity(0.7),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // AR Wayfinding button
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ARWayfindingScreen(event: event),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          Colors.deepPurple.withOpacity(0.22),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.view_in_ar_rounded,
                                        size: 18,
                                        color: Colors.deepPurple.shade300,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'AR Navigate',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.deepPurple.shade300,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 13,
                                        color: Colors.deepPurple.shade200
                                            .withOpacity(0.7),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],

                            if (event.isUpcoming && !event.isHappeningNow) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: catColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.timer_rounded,
                                      size: 18,
                                      color: catColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Starts in ${_countdown(event.startTime)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: catColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Live pulse
                      if (event.isHappeningNow)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: _LivePulseCard(eventId: event.id),
                        ),

                      // Capacity card
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  event.isFull
                                      ? 'Event is full'
                                      : '${event.spotsLeft} spots left',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: event.isFull
                                        ? Colors.orange.shade700
                                        : catColor,
                                  ),
                                ),
                                Text(
                                  '${event.rsvpCount} / ${event.capacity}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  pct >= 1.0 ? Colors.orange : catColor,
                                ),
                                minHeight: 8,
                              ),
                            ),
                            if (event.waitlistCount > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${event.waitlistCount} on waitlist',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Vibe tags
                      if (event.vibeTags.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: event.vibeTags
                                .map(
                                  (tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: catColor.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: catColor.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: catColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),

                      // About section
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'About this event',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              event.description,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF475569),
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Post-event summary
                      if (event.postEventSummary.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.summarize_rounded,
                                    size: 16,
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Event Recap',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                event.postEventSummary,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade800,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Reactions
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Reactions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ReactionsWidget(
                              eventId: widget.eventId,
                              reactions: event.reactions,
                              userId: user?.uid ?? '',
                            ),
                          ],
                        ),
                      ),

                      // RSVP section
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        child: Column(
                          children: [
                            // Checked in banner
                            if (_rsvpLoaded && isRsvpd && isCheckedIn) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: const Icon(
                                        Icons.verified_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "You're checked in!",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            _userRsvp?['checkedInViaWeb'] ==
                                                    true
                                                ? 'Checked in via QR scan ✓'
                                                : _userRsvp?['manualCheckIn'] ==
                                                      true
                                                ? 'Manually checked in ✓'
                                                : 'Checked in via app ✓',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (_rsvpLoaded &&
                                isRsvpd &&
                                !isCheckedIn) ...[
                              // Confirmed banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.green.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "You're confirmed for this event!",
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              if (isQrWindowOpen)
                                GestureDetector(
                                  onTap: () => _showEventQr(context, event),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: catColor,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: catColor.withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.qr_code_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Show Check-in QR Code',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    'QR available ${DateFormat('MMM d, h:mm a').format(qrOpensAt)} '
                                    'to ${DateFormat('MMM d, h:mm a').format(qrClosesAt)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                            ],

                            if (user != null && user.canCreateEvents) ...[
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AttendeeListScreen(
                                              event: event,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.groups_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Attendees'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                QrScannerScreen(event: event),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Check in'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EditEventScreen(event: event),
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 16,
                                      ),
                                      label: const Text('Edit'),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Waitlist banner
                            if (_rsvpLoaded && isWaitlisted)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.hourglass_empty_rounded,
                                      color: Colors.orange.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "You're on the waitlist",
                                            style: TextStyle(
                                              color: Colors.orange.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (_waitlistPosition != null)
                                            Text(
                                              'Position #$_waitlistPosition — you\'ll be notified if a spot opens',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.orange.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // RSVP button
                            if (user != null &&
                                user.isStudent &&
                                _rsvpLoaded &&
                                !isCheckedIn)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          if (isRsvpd || isWaitlisted) {
                                            _handleCancel(event);
                                          } else {
                                            _handleRsvp(event);
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isRsvpd || isWaitlisted
                                        ? Colors.red.shade600
                                        : catColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          isRsvpd
                                              ? 'Cancel RSVP'
                                              : isWaitlisted
                                              ? 'Leave waitlist'
                                              : event.isFull
                                              ? 'Join waitlist'
                                              : 'RSVP Now',
                                        ),
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
          );
        },
      ),
    );
  }
}

// ─── Detail Row ────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
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

// ─── Live Pulse Card ───────────────────────────────────
class _LivePulseCard extends ConsumerWidget {
  final String eventId;
  const _LivePulseCard({required this.eventId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<int>(
      stream: FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: eventId)
          .where('checkedIn', isEqualTo: true)
          .snapshots()
          .map((s) => s.docs.length),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.people_rounded,
                  color: Colors.green.shade700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count people checked in',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade700,
                    ),
                  ),
                  Text(
                    'Live · updates in real time',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _PulseDot(),
            ],
          ),
        );
      },
    );
  }
}

// ─── Reactions Widget ──────────────────────────────────
class _ReactionsWidget extends ConsumerStatefulWidget {
  final String eventId;
  final Map<String, int> reactions;
  final String userId;

  const _ReactionsWidget({
    required this.eventId,
    required this.reactions,
    required this.userId,
  });

  @override
  ConsumerState<_ReactionsWidget> createState() => _ReactionsWidgetState();
}

class _ReactionsWidgetState extends ConsumerState<_ReactionsWidget> {
  Map<String, bool> _userReactions = {};

  @override
  void initState() {
    super.initState();
    _loadUserReactions();
  }

  Future<void> _loadUserReactions() async {
    if (widget.userId.isEmpty) return;
    final reactions = await ref
        .read(eventServiceProvider)
        .getUserReactions(eventId: widget.eventId, userId: widget.userId);
    if (mounted) setState(() => _userReactions = reactions);
  }

  Future<void> _toggle(String emoji) async {
    if (widget.userId.isEmpty) return;
    setState(() => _userReactions[emoji] = !(_userReactions[emoji] ?? false));
    await ref
        .read(eventServiceProvider)
        .toggleReaction(
          eventId: widget.eventId,
          userId: widget.userId,
          emoji: emoji,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ['👍', '❤️', '🎉', '🔥', '😮'].map((emoji) {
        final count = widget.reactions[emoji] ?? 0;
        final reacted = _userReactions[emoji] == true;
        return GestureDetector(
          onTap: () => _toggle(emoji),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: reacted
                  ? AppConfig.primaryColor.withOpacity(0.12)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: reacted
                    ? AppConfig.primaryColor
                    : const Color(0xFFE2E8F0),
                width: reacted ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: reacted
                          ? AppConfig.primaryColor
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
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
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
