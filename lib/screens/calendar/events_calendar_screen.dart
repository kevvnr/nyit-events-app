import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../feed/event_detail_screen.dart';

class _CalEvent {
  final String eventId;
  final String title;
  final DateTime start;
  final DateTime end;
  final String badge;

  const _CalEvent({
    required this.eventId,
    required this.title,
    required this.start,
    required this.end,
    required this.badge,
  });
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Week / month calendar of RSVP’d events and (for faculty) events you host.
class EventsCalendarScreen extends ConsumerStatefulWidget {
  const EventsCalendarScreen({super.key});

  @override
  ConsumerState<EventsCalendarScreen> createState() => _EventsCalendarScreenState();
}

class _EventsCalendarScreenState extends ConsumerState<EventsCalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loading = true;
  Map<DateTime, List<_CalEvent>> _eventsByDay = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _dayOnly(DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(userModelProvider).asData?.value;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      final db = FirebaseFirestore.instance;
      final byId = <String, _CalEvent>{};

      final rsvpSnap = await db
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: user.uid)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();

      final rsvpEventIds = <String>{};
      final rsvpStatusByEvent = <String, String>{};
      for (final doc in rsvpSnap.docs) {
        final data = doc.data();
        final eid = data['eventId']?.toString();
        if (eid == null || eid.isEmpty) continue;
        rsvpEventIds.add(eid);
        rsvpStatusByEvent[eid] = (data['status'] ?? '').toString();
      }

      if (user.canCreateEvents) {
        final hostedSnap = await db
            .collection(AppConfig.eventsCol)
            .where('hostId', isEqualTo: user.uid)
            .where('status', isEqualTo: AppConfig.eventPublished)
            .get();
        for (final doc in hostedSnap.docs) {
          rsvpEventIds.add(doc.id);
        }
      }

      final eventIds = rsvpEventIds.toList();
      final rawById = <String, Map<String, dynamic>>{};
      for (var i = 0; i < eventIds.length; i += 10) {
        final chunk = eventIds.sublist(
          i,
          (i + 10 > eventIds.length) ? eventIds.length : i + 10,
        );
        final snap = await db
            .collection(AppConfig.eventsCol)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          rawById[doc.id] = doc.data();
        }
      }

      for (final entry in rawById.entries) {
        final id = entry.key;
        final raw = entry.value;
        final status = (raw['status'] ?? '').toString();
        if (status == AppConfig.eventCancelled) continue;
        final startTs = raw['startTime'] as Timestamp?;
        final endTs = raw['endTime'] as Timestamp?;
        if (startTs == null || endTs == null) continue;
        final start = startTs.toDate();
        final end = endTs.toDate();
        final title = (raw['title'] ?? 'Event').toString();
        final hostId = (raw['hostId'] ?? '').toString();
        final isHost = hostId == user.uid;
        final rsvpSt = rsvpStatusByEvent[id];
        String badge;
        if (isHost && rsvpSt != null) {
          badge = 'Hosting · ${rsvpSt == AppConfig.rsvpWaitlist ? 'Waitlist' : 'RSVP’d'}';
        } else if (isHost) {
          badge = 'Hosting';
        } else if (rsvpSt == AppConfig.rsvpWaitlist) {
          badge = 'Waitlist';
        } else {
          badge = 'RSVP’d';
        }
        byId[id] = _CalEvent(
          eventId: id,
          title: title,
          start: start,
          end: end,
          badge: badge,
        );
      }

      final byDay = <DateTime, List<_CalEvent>>{};
      for (final e in byId.values) {
        var d = _dayOnly(e.start);
        final last = _dayOnly(e.end);
        while (!d.isAfter(last)) {
          byDay.putIfAbsent(d, () => []).add(e);
          d = d.add(const Duration(days: 1));
        }
      }
      for (final list in byDay.values) {
        list.sort((a, b) => a.start.compareTo(b.start));
      }

      if (mounted) {
        setState(() {
          _eventsByDay = byDay;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load calendar: $e')),
        );
      }
    }
  }

  List<_CalEvent> _eventsForDay(DateTime day) {
    return _eventsByDay[_dayOnly(day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedDay != null ? _eventsForDay(_selectedDay!) : <_CalEvent>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text('Event calendar'),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<CalendarFormat>(
                          segments: const [
                            ButtonSegment(
                              value: CalendarFormat.week,
                              label: Text('Week'),
                              icon: Icon(Icons.view_week_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: CalendarFormat.month,
                              label: Text('Month'),
                              icon: Icon(Icons.calendar_month_rounded, size: 18),
                            ),
                          ],
                          selected: {_calendarFormat},
                          onSelectionChanged: (s) {
                            setState(() {
                              _calendarFormat = s.first;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TableCalendar<_CalEvent>(
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2035, 12, 31),
                        focusedDay: _focusedDay,
                        calendarFormat: _calendarFormat,
                        eventLoader: _eventsForDay,
                        startingDayOfWeek: StartingDayOfWeek.sunday,
                        selectedDayPredicate: (day) =>
                            _selectedDay != null && isSameDay(_selectedDay!, day),
                        onDaySelected: (selected, focused) {
                          setState(() {
                            _selectedDay = _dayOnly(selected);
                            _focusedDay = focused;
                          });
                        },
                        onPageChanged: (focused) {
                          setState(() => _focusedDay = focused);
                        },
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: _calendarFormat == CalendarFormat.month,
                          markersMaxCount: 3,
                          markerDecoration: const BoxDecoration(
                            color: Color(0xFF1565C0),
                            shape: BoxShape.circle,
                          ),
                        ),
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        calendarBuilders: CalendarBuilders(
                          markerBuilder: (context, day, events) {
                            if (events.isEmpty) return null;
                            return Positioned(
                              bottom: 1,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  events.length > 3 ? 3 : events.length,
                                  (i) => Container(
                                    width: 5,
                                    height: 5,
                                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1565C0),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _selectedDay == null
                        ? 'Select a day'
                        : DateFormat('EEEE, MMM d').format(_selectedDay!),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  if (selected.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No events on this day',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    ...selected.map((e) => _EventListTile(event: e)),
                ],
              ),
            ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final _CalEvent event;

  const _EventListTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EventDetailScreen(eventId: event.eventId),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppConfig.primaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('h:mm a').format(event.start)} – ${DateFormat('h:mm a').format(event.end)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.badge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
