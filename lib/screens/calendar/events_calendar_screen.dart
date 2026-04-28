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

class _EventsCalendarScreenState extends ConsumerState<EventsCalendarScreen>
    with WidgetsBindingObserver {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loading = true;
  Map<DateTime, List<_CalEvent>> _eventsByDay = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDay = _dayOnly(DateTime.now());
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

      // 1) User's RSVPs (so we can badge events as RSVP'd / Waitlist / Hosting)
      final rsvpStatusByEvent = <String, String>{};
      final rsvpSnap = await db
          .collection(AppConfig.rsvpsCol)
          .where('userId', isEqualTo: user.uid)
          .where(
            'status',
            whereIn: [AppConfig.rsvpConfirmed, AppConfig.rsvpWaitlist],
          )
          .get();
      for (final doc in rsvpSnap.docs) {
        final data = doc.data();
        final eid = data['eventId']?.toString();
        if (eid == null || eid.isEmpty) continue;
        rsvpStatusByEvent[eid] = (data['status'] ?? '').toString();
      }

      // 2) ALL published events — show every event on the calendar so it's
      // never blank. RSVP'd / hosted ones get a badge; the rest are shown as
      // "Open" so students can browse and RSVP from the calendar.
      final eventsSnap = await db
          .collection(AppConfig.eventsCol)
          .where('status', isEqualTo: AppConfig.eventPublished)
          .get();
      for (final doc in eventsSnap.docs) {
        final raw = doc.data();
        final startTs = raw['startTime'] as Timestamp?;
        final endTs = raw['endTime'] as Timestamp?;
        if (startTs == null || endTs == null) continue;
        final start = startTs.toDate();
        final end = endTs.toDate();
        final title = (raw['title'] ?? 'Event').toString();
        final hostId = (raw['hostId'] ?? '').toString();
        final isHost = hostId == user.uid;
        final rsvpSt = rsvpStatusByEvent[doc.id];
        String badge;
        if (isHost && rsvpSt != null) {
          badge = 'Hosting · ${rsvpSt == AppConfig.rsvpWaitlist ? 'Waitlist' : 'RSVP’d'}';
        } else if (isHost) {
          badge = 'Hosting';
        } else if (rsvpSt == AppConfig.rsvpWaitlist) {
          badge = 'Waitlist';
        } else if (rsvpSt == AppConfig.rsvpConfirmed) {
          badge = 'RSVP’d';
        } else {
          badge = 'Open';
        }
        byId[doc.id] = _CalEvent(
          eventId: doc.id,
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
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFEEF2F7)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: Color(0xFF0F172A),
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
                    ...selected.map((e) => _EventListTile(event: e, onReturn: _load)),
                ],
              ),
            ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  final _CalEvent event;
  final VoidCallback? onReturn;

  const _EventListTile({required this.event, this.onReturn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black.withValues(alpha: 0.05),
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEEF2F7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(eventId: event.eventId),
                ),
              );
              onReturn?.call();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E5BB8), Color(0xFF1565C0)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppConfig.primaryColor.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('MMM').format(event.start).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          DateFormat('d').format(event.start),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            letterSpacing: -0.3,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${DateFormat('h:mm a').format(event.start)} – ${DateFormat('h:mm a').format(event.end)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppConfig.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            event.badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: AppConfig.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
