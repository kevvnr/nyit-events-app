import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../config/app_config.dart';
import '../../services/admin_user_service.dart';
import '../../services/event_service.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() =>
      _SuperAdminDashboardState();
}

class _SuperAdminDashboardState
    extends State<SuperAdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isRecalculating = false;
  bool _isArchiving = false;

  int _totalEvents = 0;
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalRsvps = 0;
  int _totalCheckins = 0;
  int _pendingApprovals = 0;
  List<Map<String, dynamic>> _topEvents = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _teachers = [];

  bool _loadingPast = true;
  List<Map<String, dynamic>> _archivedEvents = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 &&
          _archivedEvents.isEmpty) {
        _loadArchivedEvents();
      }
    });
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

Future<void> _loadStats() async {
  setState(() => _isLoading = true);
  try {
    final db = FirebaseFirestore.instance;

    // Recalculate all counts first for accuracy
    await EventService().recalculateAllEventCounts();

    final results = await Future.wait([
      db.collection(AppConfig.eventsCol)
          .where('status', isEqualTo: AppConfig.eventPublished)
          .get(),
      db.collection(AppConfig.usersCol)
          .where('role', isEqualTo: AppConfig.roleStudent)
          .get(),
      // Fetch ALL teachers in one query — filter approved/pending client-side
      // to avoid needing a composite Firestore index.
      db.collection(AppConfig.usersCol)
          .where('role', isEqualTo: AppConfig.roleTeacher)
          .get(),
      db.collection(AppConfig.rsvpsCol)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get(),
    ]);

    final events = results[0].docs;
    final publishedIds =
        events.map((e) => e.id).toSet();

    final sortedEvents = events
        .map((e) => {
              'id': e.id,
              ...e.data() as Map<String, dynamic>
            })
        .toList()
      ..sort((a, b) => (b['rsvpCount'] ?? 0)
          .compareTo(a['rsvpCount'] ?? 0));

    final studentDocs = results[1].docs;
    final allTeacherDocs = results[2].docs;
    // Split teachers client-side — no composite index needed
    final approvedTeacherDocs = allTeacherDocs
        .where((d) => d.data()['approved'] == true)
        .toList();
    final pendingTeacherDocs = allTeacherDocs
        .where((d) => d.data()['approved'] != true)
        .toList();

    // Only RSVPs/check-ins for events that still exist and are still published
    int liveRsvps = 0;
    int liveCheckins = 0;
    for (final doc in results[3].docs) {
      final eid = doc.data()['eventId'] as String?;
      if (eid == null || !publishedIds.contains(eid)) continue;
      liveRsvps++;
      if (doc.data()['checkedIn'] == true) {
        liveCheckins++;
      }
    }

    if (mounted) {
      setState(() {
        _totalEvents = results[0].docs.length;
        _totalStudents = studentDocs.length;
        _totalTeachers = approvedTeacherDocs.length;
        _totalRsvps = liveRsvps;
        _totalCheckins = liveCheckins;
        _pendingApprovals = pendingTeacherDocs.length;
        _topEvents = sortedEvents.take(5).toList();
        _students = studentDocs
            .map((d) => {
                  'id': d.id,
                  ...d.data() as Map<String, dynamic>
                })
            .toList();
        _teachers = approvedTeacherDocs
            .map((d) => {
                  'id': d.id,
                  ...d.data() as Map<String, dynamic>
                })
            .toList();
        _isLoading = false;
      });
    }
  } catch (e) {
    print('loadStats error: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<void> _loadArchivedEvents() async {
    setState(() => _loadingPast = true);
    try {
      final events =
          await EventService().getArchivedEvents();
      if (mounted) {
        setState(() {
          _archivedEvents = events;
          _loadingPast = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingPast = false);
    }
  }

  Future<void> _archiveEndedEvents() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive ended events?'),
        content: const Text(
            'This will archive all events that have ended. They will move to Past Events tab.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isArchiving = true);
    try {
      final count =
          await EventService().archiveEndedEvents();
      await _loadStats();
      await _loadArchivedEvents();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$count event${count != 1 ? 's' : ''} archived!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isArchiving = false);
    }
  }

  Future<void> _recalculateCounts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalculate all counts?'),
        content: const Text(
            'This will fix any incorrect RSVP counts across all events.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fix counts'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isRecalculating = true);
    try {
      await EventService().recalculateAllEventCounts();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All counts recalculated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRecalculating = false);
    }
  }

  Future<void> _confirmDeleteUserSheet(
    BuildContext sheetContext,
    Map<String, dynamic> user,
  ) async {
    final uid = user['id'] as String?;
    final name = user['name'] ?? 'User';
    if (uid == null) return;
    final confirm = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove account completely?'),
        content: Text(
          'Delete all app data for $name (RSVPs, notifications, hosted events and RSVPs, study groups, profile). '
          'To free the email for signup, also delete the user in Firebase Authentication (Console or Admin SDK).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Remove data',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AdminUserService().permanentlyDeleteUserFirestoreData(uid);
      if (!mounted) return;
      if (sheetContext.mounted) {
        Navigator.pop(sheetContext);
      }
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name’s app data was removed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remove failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showUserList(
      BuildContext context,
      String title,
      List<Map<String, dynamic>> users,
      Color color,
      String currentUid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius:
                          BorderRadius.circular(18),
                    ),
                    child: Icon(
                      title == 'Students'
                          ? Icons.school_rounded
                          : Icons.person_rounded,
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$title (${users.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        'No $title found',
                        style: TextStyle(
                            color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final user = users[i];
                        final name =
                            user['name'] ?? 'Unknown';
                        final email =
                            user['email'] ?? '';
                        final studentId =
                            user['studentId'] ?? '';
                        final initials = name
                                .split(' ')
                                .map((w) => w.isNotEmpty
                                    ? w[0].toUpperCase()
                                    : '')
                                .take(2)
                                .join();

                        final userId =
                            user['id'] as String? ?? '';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color:
                                      color.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(
                                          22),
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: TextStyle(
                                      color: color,
                                      fontWeight:
                                          FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight:
                                            FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors
                                            .grey.shade500,
                                      ),
                                    ),
                                    if (studentId
                                        .isNotEmpty)
                                      Text(
                                        'ID: $studentId',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors
                                              .grey.shade400,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (userId.isNotEmpty &&
                                  userId != currentUid)
                                IconButton(
                                  tooltip:
                                      'Remove all app data for this user',
                                  icon: Icon(
                                    Icons
                                        .delete_forever_outlined,
                                    color: Colors.red.shade400,
                                    size: 22,
                                  ),
                                  onPressed: () =>
                                      _confirmDeleteUserSheet(
                                          ctx, user),
                                ),
                            ],
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

  void _showEventAttendees(
      BuildContext context, Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          _PastEventDetailSheet(eventId: event['id']),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text('Analytics dashboard'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F4FA8), Color(0xFF1565C0)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        actions: [
          if (_isRecalculating || _isArchiving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.archive_rounded),
              tooltip: 'Archive ended events',
              onPressed: _archiveEndedEvents,
            ),
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'Recalculate all counts',
              onPressed: _recalculateCounts,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStats,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Live'),
            Tab(text: 'Past Events'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1 — Live stats
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: SingleChildScrollView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // Pending approvals alert
                        if (_pendingApprovals > 0) ...[
                          Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors
                                      .orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                    Icons.warning_rounded,
                                    color: Colors
                                        .orange.shade700),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$_pendingApprovals teacher account${_pendingApprovals > 1 ? 's' : ''} pending approval',
                                    style: TextStyle(
                                      fontWeight:
                                          FontWeight.w600,
                                      color: Colors
                                          .orange.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        Text('Overview',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                        const SizedBox(height: 12),

                        // Stats grid — clickable
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.6,
                          children: [
                            _StatCard(
                              label: 'Active events',
                              value: '$_totalEvents',
                              icon: Icons.event_rounded,
                              color: AppConfig.primaryColor,
                              onTap: null,
                            ),
                            _StatCard(
                              label: 'Students',
                              value: '$_totalStudents',
                              icon: Icons.people_rounded,
                              color:
                                  const Color(0xFF7B1FA2),
                              onTap: () => _showUserList(
                                context,
                                'Students',
                                _students,
                                const Color(0xFF7B1FA2),
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                              ),
                            ),
                            _StatCard(
                              label: 'Total RSVPs',
                              value: '$_totalRsvps',
                              icon:
                                  Icons.how_to_reg_rounded,
                              color:
                                  const Color(0xFF2E7D32),
                              onTap: null,
                            ),
                            _StatCard(
                              label: 'Check-ins',
                              value: '$_totalCheckins',
                              icon: Icons.qr_code_rounded,
                              color:
                                  const Color(0xFFE65100),
                              onTap: null,
                            ),
                            _StatCard(
                              label: 'Faculty',
                              value: '$_totalTeachers',
                              icon: Icons.school_rounded,
                              color:
                                  const Color(0xFF00838F),
                              onTap: () => _showUserList(
                                context,
                                'Faculty',
                                _teachers,
                                const Color(0xFF00838F),
                                FirebaseAuth.instance.currentUser?.uid ?? '',
                              ),
                            ),
                            _StatCard(
                              label: 'Attendance rate',
                              value: _totalRsvps > 0
                                  ? '${((_totalCheckins / _totalRsvps) * 100).clamp(0.0, 100.0).toStringAsFixed(0)}%'
                                  : '0%',
                              icon:
                                  Icons.bar_chart_rounded,
                              color:
                                  const Color(0xFF1565C0),
                              onTap: null,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        Text('Top events by RSVPs',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                        const SizedBox(height: 12),

                        if (_topEvents.isEmpty)
                          const Text('No events yet')
                        else
                          ..._topEvents
                              .asMap()
                              .entries
                              .map((entry) {
                            final i = entry.key;
                            final event = entry.value;
                            final rsvpCount =
                                event['rsvpCount'] ?? 0;
                            final capacity =
                                event['capacity'] ?? 1;
                            final pct =
                                (rsvpCount / capacity)
                                    .clamp(0.0, 1.0);

                            return Container(
                              margin: const EdgeInsets
                                  .only(bottom: 10),
                              padding:
                                  const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                borderRadius:
                                    BorderRadius.circular(
                                        12),
                                border: Border.all(
                                    color: const Color(
                                        0xFFE2E8F0),
                                    width: 0.5),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration:
                                            BoxDecoration(
                                          color: AppConfig
                                              .primaryColor
                                              .withOpacity(
                                                  0.1),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(
                                                      12),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${i + 1}',
                                            style:
                                                const TextStyle(
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight
                                                      .w700,
                                              color: AppConfig
                                                  .primaryColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                          width: 10),
                                      Expanded(
                                        child: Text(
                                          event['title'] ??
                                              '',
                                          style:
                                              const TextStyle(
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                          ),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '$rsvpCount/$capacity',
                                        style:
                                            const TextStyle(
                                          fontSize: 13,
                                          fontWeight:
                                              FontWeight
                                                  .w600,
                                          color: AppConfig
                                              .primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius
                                            .circular(4),
                                    child:
                                        LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor:
                                          Colors
                                              .grey.shade200,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        pct >= 1.0
                                            ? Colors.orange
                                            : AppConfig
                                                .primaryColor,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppConfig.primaryColor
                                .withOpacity(0.06),
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: AppConfig.primaryColor
                                  .withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color:
                                      AppConfig.primaryColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    const Text(
                                      'Counts out of sync?',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight:
                                            FontWeight.w600,
                                        color: AppConfig
                                            .primaryColor,
                                      ),
                                    ),
                                    Text(
                                      'Tap sync ↑ to fix counts. Tap archive ↑ to move ended events to Past Events.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppConfig
                                            .primaryColor
                                            .withOpacity(
                                                0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          // Tab 2 — Past Events
          _loadingPast
              ? const Center(
                  child: CircularProgressIndicator())
              : _archivedEvents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Icon(Icons.archive_outlined,
                              size: 64,
                              color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('No past events yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the archive button to move ended events here',
                            style: TextStyle(
                                color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _archiveEndedEvents,
                            icon: const Icon(
                                Icons.archive_rounded),
                            label: const Text(
                                'Archive ended events'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadArchivedEvents,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _archivedEvents.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final event =
                              _archivedEvents[index];
                          final checkedIn =
                              event['actualCheckedIn'] ?? 0;
                          final rsvpCount =
                              event['actualRsvpCount'] ?? 0;
                          final rate = (event[
                                      'attendanceRate'] ??
                                  0.0)
                              .toDouble();
                          final startTime = (event[
                                      'startTime']
                                  as Timestamp?)
                              ?.toDate();

                          return GestureDetector(
                            onTap: () =>
                                _showEventAttendees(
                                    context, event),
                            child: Container(
                              padding:
                                  const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                borderRadius:
                                    BorderRadius.circular(
                                        14),
                                border: Border.all(
                                    color: const Color(
                                        0xFFE2E8F0),
                                    width: 0.5),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          event['title'] ??
                                              '',
                                          style:
                                              const TextStyle(
                                            fontSize: 15,
                                            fontWeight:
                                                FontWeight
                                                    .w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                            horizontal: 8,
                                            vertical: 3),
                                        decoration:
                                            BoxDecoration(
                                          color: Colors
                                              .grey.shade100,
                                          borderRadius:
                                              BorderRadius
                                                  .circular(
                                                      6),
                                        ),
                                        child: const Text(
                                          'Archived',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color:
                                                Colors.grey,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (startTime != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat(
                                              'MMM d, yyyy · h:mm a')
                                          .format(startTime),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color:
                                            Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      _MiniStat(
                                        label: 'RSVPs',
                                        value: '$rsvpCount',
                                        color: AppConfig
                                            .primaryColor,
                                      ),
                                      const SizedBox(
                                          width: 12),
                                      _MiniStat(
                                        label: 'Checked in',
                                        value: '$checkedIn',
                                        color: Colors
                                            .green.shade700,
                                      ),
                                      const SizedBox(
                                          width: 12),
                                      _MiniStat(
                                        label: 'Attendance',
                                        value:
                                            '${(rate * 100).clamp(0.0, 100.0).toStringAsFixed(0)}%',
                                        color: Colors.orange,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius:
                                        BorderRadius
                                            .circular(4),
                                    child:
                                        LinearProgressIndicator(
                                      value: rate.clamp(
                                          0.0, 1.0),
                                      backgroundColor:
                                          Colors.grey.shade200,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        rate >= 0.8
                                            ? Colors.green
                                            : rate >= 0.5
                                                ? Colors.orange
                                                : Colors.red,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment
                                            .end,
                                    children: [
                                      Text(
                                        'Tap to see attendees',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppConfig
                                              .primaryColor,
                                          fontWeight:
                                              FontWeight.w500,
                                        ),
                                      ),
                                      const Icon(
                                        Icons
                                            .chevron_right_rounded,
                                        size: 16,
                                        color: AppConfig
                                            .primaryColor,
                                      ),
                                    ],
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

// Past event attendees bottom sheet
class _PastEventDetailSheet extends StatefulWidget {
  final String eventId;
  const _PastEventDetailSheet({required this.eventId});

  @override
  State<_PastEventDetailSheet> createState() =>
      _PastEventDetailSheetState();
}

class _PastEventDetailSheetState
    extends State<_PastEventDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _attendees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAttendees();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendees() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: widget.eventId)
          .where('status',
              isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      final attendees = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection(AppConfig.usersCol)
              .doc(data['userId'])
              .get();
          attendees.add({
            'id': doc.id,
            ...data,
            'userName': userDoc['name'] ?? 'Unknown',
            'studentId': userDoc['studentId'] ?? 'N/A',
            'email': userDoc['email'] ?? '',
          });
        } catch (e) {
          attendees.add({
            'id': doc.id,
            ...data,
            'userName': 'Unknown',
          });
        }
      }

      if (mounted) {
        setState(() {
          _attendees = attendees;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _checkedIn =>
      _attendees
          .where((a) => a['checkedIn'] == true)
          .toList();

  List<Map<String, dynamic>> get _notCheckedIn =>
      _attendees
          .where((a) => a['checkedIn'] != true)
          .toList();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Event Attendees',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceAround,
              children: [
                _MiniStat(
                  label: 'Total RSVP\'d',
                  value: '${_attendees.length}',
                  color: AppConfig.primaryColor,
                ),
                _MiniStat(
                  label: 'Attended',
                  value: '${_checkedIn.length}',
                  color: Colors.green.shade700,
                ),
                _MiniStat(
                  label: 'No show',
                  value: '${_notCheckedIn.length}',
                  color: Colors.grey,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            labelColor: AppConfig.primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppConfig.primaryColor,
            tabs: [
              Tab(
                  text:
                      'Attended (${_checkedIn.length})'),
              Tab(
                  text:
                      'No show (${_notCheckedIn.length})'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _AttendeesList(
                          attendees: _checkedIn,
                          attended: true),
                      _AttendeesList(
                          attendees: _notCheckedIn,
                          attended: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AttendeesList extends StatelessWidget {
  final List<Map<String, dynamic>> attendees;
  final bool attended;

  const _AttendeesList({
    required this.attendees,
    required this.attended,
  });

  @override
  Widget build(BuildContext context) {
    if (attendees.isEmpty) {
      return Center(
        child: Text(
          attended ? 'No attendees' : 'Everyone showed up!',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: attendees.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final a = attendees[index];
        final isManual = a['manualCheckIn'] == true;
        final isWeb = a['checkedInViaWeb'] == true;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: attended
                ? Colors.green.shade50
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: attended
                  ? Colors.green.shade200
                  : Colors.grey.shade200,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: attended
                      ? Colors.green.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  attended
                      ? Icons.check_circle_rounded
                      : Icons.person_outline_rounded,
                  color: attended
                      ? Colors.green.shade700
                      : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      a['userName'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'ID: ${a['studentId'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (attended)
                      Text(
                        isWeb
                            ? 'QR scan'
                            : isManual
                                ? 'Manual'
                                : 'App',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      color: color.withOpacity(0.5),
                      size: 16),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}