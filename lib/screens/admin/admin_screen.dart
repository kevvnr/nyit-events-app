import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import 'qr_scanner_screen.dart';
import 'attendee_list_screen.dart';
import 'edit_event_screen.dart';
import 'teacher_approval_screen.dart';
import 'super_admin_dashboard.dart';
import 'announcement_screen.dart';
import 'campaigns_screen.dart';
import 'room_capacity_screen.dart';
import 'campus_groups_import_screen.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  bool _showPastEvents = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(eventsNotifierProvider.notifier).loadEvents(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userModelProvider).asData?.value;
    final eventsState = ref.watch(eventsNotifierProvider);
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1a3a6b), Color(0xFF1565C0)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + toggle
                      Row(
                        children: [
                          const Text(
                            'Manage',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          // Active/Past toggle
                          GestureDetector(
                            onTap: () => setState(
                              () => _showPastEvents = !_showPastEvents,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _showPastEvents
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _showPastEvents
                                        ? Icons.event_rounded
                                        : Icons.history_rounded,
                                    color: _showPastEvents
                                        ? const Color(0xFF1565C0)
                                        : Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _showPastEvents ? 'Active' : 'Past',
                                    style: TextStyle(
                                      color: _showPastEvents
                                          ? const Color(0xFF1565C0)
                                          : Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _showPastEvents
                            ? 'Past events view'
                            : 'Hi ${user?.name.split(' ').first ?? ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 13,
                        ),
                      ),
                      // Superadmin quick actions — Wrap so every chip stays on-screen (no sideways scroll).
                      if (isSuperAdmin) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.start,
                          children: [
                            _HeaderAction(
                              icon: Icons.campaign_rounded,
                              label: 'Announce',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AnnouncementScreen(),
                                ),
                              ),
                            ),
                            _HeaderAction(
                              icon: Icons.send_to_mobile_rounded,
                              label: 'Campaigns',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CampaignsScreen(),
                                ),
                              ),
                            ),
                            _HeaderAction(
                              icon: Icons.analytics_rounded,
                              label: 'Analytics',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SuperAdminDashboard(),
                                ),
                              ),
                            ),
                            _HeaderAction(
                              icon: Icons.person_add_rounded,
                              label: 'Approvals',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TeacherApprovalScreen(),
                                ),
                              ),
                            ),
                            _HeaderAction(
                              icon: Icons.cloud_download_rounded,
                              label: 'CG import',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const CampusGroupsImportScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'After you install a new build (SideStore / sideload), open CG import again to refresh CampusGroups events in the app.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _HeaderAction(
                        icon: Icons.meeting_room_rounded,
                        label: 'Room limits',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RoomCapacityScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: eventsState.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  const Center(child: Text('Something went wrong')),
              data: (events) {
                // Filter by host and active/past
                final allMyEvents = isSuperAdmin
                    ? events.where((e) => !e.isCancelled).toList()
                    : events
                          .where((e) => e.hostId == user?.uid && !e.isCancelled)
                          .toList();

                final myEvents = allMyEvents
                    .where(
                      (e) => _showPastEvents
                          ? e.endTime.isBefore(now)
                          : e.endTime.isAfter(now),
                    )
                    .toList();

                myEvents.sort(
                  (a, b) => _showPastEvents
                      ? b.startTime.compareTo(a.startTime)
                      : a.startTime.compareTo(b.startTime),
                );

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Premium stat cards
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFFFFF), Color(0xFFF8FBFF)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF1565C0).withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1A3A6B).withOpacity(0.07),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatPill(
                                label: 'Total',
                                value:
                                    '${allMyEvents.where((e) => e.endTime.isAfter(now)).length}',
                                color: const Color(0xFF1565C0),
                                icon: Icons.calendar_month_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatPill(
                                label: 'Live now',
                                value:
                                    '${allMyEvents.where((e) => e.isHappeningNow).length}',
                                color: Colors.green.shade700,
                                icon: Icons.bolt_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatPill(
                                label: 'Total RSVPs',
                                value:
                                    '${allMyEvents.where((e) => e.endTime.isAfter(now)).fold(0, (sum, e) => sum + e.rsvpCount)}',
                                color: const Color(0xFF7B1FA2),
                                icon: Icons.people_alt_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section label
                      Row(
                        children: [
                          Text(
                            _showPastEvents ? 'PAST EVENTS' : 'ACTIVE EVENTS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _showPastEvents
                                  ? Colors.grey.shade200
                                  : const Color(0xFF1565C0).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${myEvents.length}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _showPastEvents
                                    ? Colors.grey.shade600
                                    : const Color(0xFF1565C0),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (myEvents.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _showPastEvents
                                    ? Icons.history_rounded
                                    : Icons.event_note_rounded,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _showPastEvents
                                    ? 'No past events'
                                    : 'No active events',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _showPastEvents
                                    ? 'Past events will appear here'
                                    : 'Tap + to create your first event',
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...myEvents.asMap().entries.map(
                          (entry) => _AdminEventCard(
                            event: entry.value,
                            index: entry.key,
                            isSuperAdmin: isSuperAdmin,
                            isPast: _showPastEvents,
                            onRefresh: () => ref
                                .read(eventsNotifierProvider.notifier)
                                .loadEvents(),
                          ),
                        ),
                    ],
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

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.88, end: 1),
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.16), color.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEventCard extends ConsumerWidget {
  final EventModel event;
  final int index;
  final bool isSuperAdmin;
  final bool isPast;
  final VoidCallback onRefresh;

  const _AdminEventCard({
    required this.event,
    required this.index,
    required this.isSuperAdmin,
    required this.isPast,
    required this.onRefresh,
  });

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catColor = _categoryColor(event.category);
    final pct = event.fillPercent;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: isPast
                  ? Colors.grey.shade400
                  : event.isHappeningNow
                  ? Colors.green.shade600
                  : catColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isPast
                              ? Colors.grey.shade500
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (event.isHappeningNow && !isPast)
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
                        child: Text(
                          'Live',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade700,
                          ),
                        ),
                      )
                    else if (isPast)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Ended',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      )
                    else if (event.isPinned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Pinned',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 13,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d · h:mm a').format(event.startTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${event.rsvpCount}/${event.capacity} RSVPs',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (event.waitlistCount > 0)
                      Text(
                        '+${event.waitlistCount} waitlist',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
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
                      pct >= 1.0
                          ? Colors.orange
                          : isPast
                          ? Colors.grey.shade400
                          : catColor,
                    ),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _ActionBtn(
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Scan',
                      color: const Color(0xFF1565C0),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrScannerScreen(event: event),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      icon: Icons.people_rounded,
                      label: 'Attendees',
                      color: const Color(0xFF7B1FA2),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AttendeeListScreen(event: event),
                        ),
                      ),
                    ),
                    if (isPast) ...[
                      const SizedBox(width: 8),
                      _ActionBtn(
                        icon: event.postEventSummary.isNotEmpty
                            ? Icons.edit_note_rounded
                            : Icons.note_add_rounded,
                        label: event.postEventSummary.isNotEmpty
                            ? 'Edit Summary'
                            : 'Add Summary',
                        color: const Color(0xFF00838F),
                        onTap: () => _showSummaryDialog(context, ref),
                      ),
                    ],
                    if (!isPast) ...[
                      const SizedBox(width: 8),
                      _ActionBtn(
                        icon: Icons.edit_rounded,
                        label: 'Edit',
                        color: const Color(0xFFE65100),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditEventScreen(event: event),
                          ),
                        ).then((_) => onRefresh()),
                      ),
                      const SizedBox(width: 8),
                      _ActionBtn(
                        icon: Icons.cancel_outlined,
                        label: 'Cancel',
                        color: Colors.red.shade600,
                        onTap: () => _confirmCancel(context, ref),
                      ),
                    ],
                  ],
                ),
                if (_canPermanentDelete(ref)) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmPermanentDelete(context, ref),
                      icon: Icon(
                        Icons.delete_forever_rounded,
                        color: Colors.red.shade700,
                        size: 18,
                      ),
                      label: Text(
                        'Delete everywhere',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
                if (!isPast && event.rsvpCount > 0) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _showNotifyDialog(context, ref),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_rounded,
                            size: 16,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Notify ${event.rsvpCount} RSVP\'d Student${event.rsvpCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNotifyDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: 'Reminder: "${event.title}" is coming up! We\'ll see you there.',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.notifications_rounded,
              color: Colors.amber.shade700,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('Notify students'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send an in-app notification to all ${event.rsvpCount} student${event.rsvpCount != 1 ? 's' : ''} who RSVP\'d for this event.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: 'Enter your notification message…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    final message = controller.text.trim();
    controller.dispose();
    if (confirmed != true || message.isEmpty) return;

    try {
      final count = await EventService().sendEventReminder(
        eventId: event.id,
        eventTitle: event.title,
        message: message,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notification sent to $count student${count != 1 ? 's' : ''}!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showSummaryDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: event.postEventSummary);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          event.postEventSummary.isNotEmpty
              ? 'Edit post-event summary'
              : 'Add post-event summary',
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Share highlights, outcomes, or photos link…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (saved == null) return;

    try {
      await FirebaseFirestore.instance
          .collection(AppConfig.eventsCol)
          .doc(event.id)
          .update({'postEventSummary': saved});
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Summary saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving summary: $e')));
      }
    }
  }

  bool _canPermanentDelete(WidgetRef ref) {
    final me = ref.read(userModelProvider).asData?.value;
    if (me == null) return false;
    if (isSuperAdmin) return true;
    return me.uid == event.hostId;
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everywhere?'),
        content: Text(
          'Permanently remove "${event.title}", all RSVPs, in-app notifications, '
          'and attendance history for this event. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await EventService().permanentlyDeleteEvent(event.id);
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event removed everywhere'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel event?'),
        content: Text(
          'Cancel "${event.title}"? All attendees will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel event',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await EventService().cancelEvent(event.id);
      onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event cancelled'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

class _ActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: widget.color.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Icon(widget.icon, color: widget.color, size: 18),
                const SizedBox(height: 3),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
