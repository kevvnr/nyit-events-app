import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_config.dart';
import '../../models/event_model.dart';

class AttendeeListScreen extends ConsumerStatefulWidget {
  final EventModel event;
  const AttendeeListScreen({super.key, required this.event});

  @override
  ConsumerState<AttendeeListScreen> createState() => _AttendeeListScreenState();
}

class _AttendeeListScreenState extends ConsumerState<AttendeeListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _rsvps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAttendees();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAttendees() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: widget.event.id)
          .get();

      final rsvps = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Get user info
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection(AppConfig.usersCol)
              .doc(data['userId'])
              .get();
          rsvps.add({
            'id': doc.id,
            ...data,
            'userName': userDoc['name'] ?? 'Unknown',
            'studentId': userDoc['studentId'] ?? '',
            'email': userDoc['email'] ?? '',
          });
        } catch (e) {
          rsvps.add({'id': doc.id, ...data, 'userName': 'Unknown'});
        }
      }

      if (mounted)
        setState(() {
          _rsvps = rsvps;
          _isLoading = false;
        });
    } catch (e) {
      print('loadAttendees error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _checkedIn => _rsvps
      .where(
        (r) => r['status'] == AppConfig.rsvpConfirmed && r['checkedIn'] == true,
      )
      .toList();

  List<Map<String, dynamic>> get _confirmed => _rsvps
      .where(
        (r) => r['status'] == AppConfig.rsvpConfirmed && r['checkedIn'] != true,
      )
      .toList();

  List<Map<String, dynamic>> get _waitlist =>
      _rsvps.where((r) => r['status'] == AppConfig.rsvpWaitlist).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Attendees'),
            Text(
              widget.event.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Checked in (${_checkedIn.length})'),
            Tab(text: 'RSVP\'d (${_confirmed.length})'),
            Tab(text: 'Waitlist (${_waitlist.length})'),
          ],
          labelStyle: const TextStyle(fontSize: 12),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _AttendeeList(attendees: _checkedIn, showCheckedIn: true),
                _AttendeeList(attendees: _confirmed, showCheckedIn: false),
                _AttendeeList(attendees: _waitlist, showCheckedIn: false),
              ],
            ),
    );
  }
}

class _AttendeeList extends StatelessWidget {
  final List<Map<String, dynamic>> attendees;
  final bool showCheckedIn;

  const _AttendeeList({required this.attendees, required this.showCheckedIn});

  @override
  Widget build(BuildContext context) {
    if (attendees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Nobody here yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: attendees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final attendee = attendees[index];
        final checkedIn = attendee['checkedIn'] == true;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: checkedIn
                  ? Colors.green.shade200
                  : const Color(0xFFE2E8F0),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: checkedIn
                      ? Colors.green.withOpacity(0.1)
                      : AppConfig.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  checkedIn ? Icons.check_circle_rounded : Icons.person_rounded,
                  color: checkedIn
                      ? Colors.green.shade700
                      : AppConfig.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attendee['userName'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'ID: ${attendee['studentId'] ?? 'N/A'} • ${attendee['email'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (checkedIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Present',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
