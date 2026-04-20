import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/app_config.dart';
import '../../config/campus_locations.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import '../../services/notification_service.dart';

class EditEventScreen extends ConsumerStatefulWidget {
  final EventModel event;
  const EditEventScreen({super.key, required this.event});

  @override
  ConsumerState<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends ConsumerState<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late TextEditingController _capacityController;
  late String _selectedCategory;
  late DateTime _startTime;
  late DateTime _endTime;
  bool _isLoading = false;
  late double _lat;
  late double _lng;
  String? _selectedLocationKey;
  bool _showParking = false;
  Set<String> _unavailableLocationKeys = {};
  bool _loadingAvailability = false;
  Map<String, int> _capacityLimits = {};

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.event.title);
    _descriptionController =
        TextEditingController(text: widget.event.description);
    _locationController =
        TextEditingController(text: widget.event.locationName);
    _capacityController =
        TextEditingController(text: widget.event.capacity.toString());
    _selectedCategory = widget.event.category;
    _startTime = widget.event.startTime;
    _endTime = widget.event.endTime;
    _lat = widget.event.locationLat;
    _lng = widget.event.locationLng;
    _selectedLocationKey = widget.event.locationKey.isNotEmpty
        ? widget.event.locationKey
        : CampusLocations.matchByName(widget.event.locationName)?.id;
    _loadCapacityLimits();
    _refreshLocationAvailability();
  }

  Future<void> _loadCapacityLimits() async {
    try {
      final limits =
          await ref.read(eventServiceProvider).getEffectiveRoomCapacities();
      if (!mounted) return;
      setState(() => _capacityLimits = limits);
    } catch (_) {}
  }

  int _maxFor(CampusLocation loc) => _capacityLimits[loc.id] ?? loc.maxCapacity;

  List<CampusLocation> get _buildingLocations =>
      CampusLocations.all.where((l) => !l.isParking).toList();

  List<CampusLocation> get _parkingLocations =>
      CampusLocations.all.where((l) => l.isParking).toList();

  void _selectLocation(CampusLocation loc) {
    setState(() {
      _locationController.text = loc.name;
      _lat = loc.lat;
      _lng = loc.lng;
      _selectedLocationKey = loc.id;
      final cap = int.tryParse(_capacityController.text.trim());
      final maxCap = _maxFor(loc);
      if (cap == null || cap > maxCap) {
        _capacityController.text = '$maxCap';
      }
    });
  }

  Future<void> _refreshLocationAvailability() async {
    setState(() => _loadingAvailability = true);
    try {
      final blocked = await ref.read(eventServiceProvider).getUnavailableLocationKeys(
            start: _startTime,
            end: _endTime,
            excludeEventId: widget.event.id,
          );
      if (!mounted) return;
      setState(() {
        _unavailableLocationKeys = blocked;
        _loadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAvailability = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startTime : _endTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(isStart ? _startTime : _endTime),
    );
    if (time == null) return;

    final picked = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

    setState(() {
      if (isStart) {
        _startTime = picked;
        if (_endTime.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = picked;
      }
    });
    await _refreshLocationAvailability();
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final newCapacity = int.parse(_capacityController.text.trim());
    final trimmedLoc = _locationController.text.trim();
    var locationKey = CampusLocations.effectiveKeyFor(
        _selectedLocationKey, trimmedLoc);
    final campusLoc = CampusLocations.byId(locationKey);
    final roomMax = campusLoc == null ? null : _maxFor(campusLoc);
    if (roomMax != null && newCapacity > roomMax) {
      if (!mounted) return;
      final roomName = campusLoc?.name ?? 'selected room';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Capacity cannot exceed $roomMax for $roomName.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final eventService = ref.read(eventServiceProvider);
    while (locationKey.isNotEmpty) {
      final conflict = await eventService.findSchedulingConflict(
        locationKey: locationKey,
        start: _startTime,
        end: _endTime,
        excludeEventId: widget.event.id,
      );
      if (conflict == null) break;
      final suggestions = await eventService.suggestFreeLocations(
        capacity: newCapacity,
        start: _startTime,
        end: _endTime,
        excludeEventId: widget.event.id,
      );
      if (!mounted) return;
      final altText = suggestions.isEmpty
          ? 'No other campus venues are free for this time window.'
          : 'Suggestions:\n${suggestions.take(5).map((l) => '• ${l.name} (max ${l.maxCapacity})').join('\n')}';
      final picked = await showDialog<CampusLocation?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location already booked'),
          content: SingleChildScrollView(
            child: Text(
              '“${CampusLocations.byId(locationKey)?.name ?? trimmedLoc}” overlaps with “${conflict.title}”.\n\n$altText',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            if (suggestions.isNotEmpty)
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, suggestions.first),
                child: Text('Use ${suggestions.first.name}'),
              ),
          ],
        ),
      );
      if (picked == null) return;
      _selectLocation(picked);
      locationKey = picked.id;
    }

    final currentRsvpCount = widget.event.rsvpCount;

    // Guard: warn if new capacity is below current confirmed RSVP count
    if (newCapacity < currentRsvpCount) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Capacity too low'),
          content: Text(
            'This event already has $currentRsvpCount confirmed RSVPs. '
            'Setting capacity to $newCapacity would leave '
            '${currentRsvpCount - newCapacity} students over the limit.\n\n'
            'Set capacity to at least $currentRsvpCount, or proceed anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              child: const Text('Proceed anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(eventServiceProvider).updateEvent(widget.event.id, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'locationName': _locationController.text.trim(),
        'locationKey': locationKey,
        'locationLat': _lat,
        'locationLng': _lng,
        'capacity': int.parse(_capacityController.text.trim()),
        'category': _selectedCategory,
        'startTime': Timestamp.fromDate(_startTime),
        'endTime': Timestamp.fromDate(_endTime),
      });

      // Notify all RSVPs about the update
      final rsvps = await FirebaseFirestore.instance
          .collection(AppConfig.rsvpsCol)
          .where('eventId', isEqualTo: widget.event.id)
          .where('status', isEqualTo: AppConfig.rsvpConfirmed)
          .get();

      for (final rsvp in rsvps.docs) {
        await NotificationService.writeInAppNotification(
          userId: rsvp['userId'],
          type: AppConfig.notifUpdate,
          eventId: widget.event.id,
          message:
              '"${_titleController.text.trim()}" has been updated. Check the event for new details.',
        );
      }

      await ref.read(eventsNotifierProvider.notifier).loadEvents();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event updated and attendees notified!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Edit event'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Event title',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  validator: (val) => val == null || val.isEmpty
                      ? 'Required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  validator: (val) => val == null || val.isEmpty
                      ? 'Required'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: AppConfig.defaultCategories.map((cat) {
                    return DropdownMenuItem(
                        value: cat, child: Text(cat));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  onChanged: (_) {
                    final t = _locationController.text.trim();
                    final m = CampusLocations.matchByName(t);
                    setState(() {
                      if (m != null && m.name == t) {
                        _selectedLocationKey = m.id;
                        _lat = m.lat;
                        _lng = m.lng;
                      } else {
                        _selectedLocationKey = null;
                      }
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (val) => val == null || val.isEmpty
                      ? 'Required'
                      : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Campus venues',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _buildingLocations
                      .map((b) {
                        final cap = int.tryParse(_capacityController.text.trim()) ?? 0;
                        final maxCap = _maxFor(b);
                        final tooSmall = cap > 0 && maxCap < cap;
                        final unavailable = _unavailableLocationKeys.contains(b.id);
                        final disabled = tooSmall || unavailable;
                        final selected = _locationController.text == b.name;
                        return ActionChip(
                          backgroundColor: selected
                              ? AppConfig.primaryColor
                              : const Color(0xFFEEF2FF),
                          side: BorderSide(
                            color: selected
                                ? AppConfig.primaryColor
                                : const Color(0xFFBFD1F5),
                          ),
                          label: Text(
                            '${b.name}${tooSmall ? ' (max $maxCap)' : unavailable ? ' (busy)' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? Colors.white
                                  : (disabled ? Colors.grey : const Color(0xFF1A3A6B)),
                              decoration: disabled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          onPressed: disabled ? null : () => _selectLocation(b),
                        );
                      })
                      .toList(),
                ),
                if (_loadingAvailability)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showParking = !_showParking),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      children: [
                        Icon(_showParking
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded),
                        Text('Parking lots',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
                if (_showParking)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _parkingLocations
                        .map((p) {
                          final cap = int.tryParse(_capacityController.text.trim()) ?? 0;
                          final maxCap = _maxFor(p);
                          final tooSmall = cap > 0 && maxCap < cap;
                          final unavailable = _unavailableLocationKeys.contains(p.id);
                          final disabled = tooSmall || unavailable;
                          final selected = _locationController.text == p.name;
                          return ActionChip(
                            backgroundColor: selected
                                ? AppConfig.primaryColor
                                : const Color(0xFFEEF2FF),
                            side: BorderSide(
                              color: selected
                                  ? AppConfig.primaryColor
                                  : const Color(0xFFBFD1F5),
                            ),
                            label: Text(
                              '${p.name}${tooSmall ? ' (max $maxCap)' : unavailable ? ' (busy)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: selected
                                    ? Colors.white
                                    : (disabled ? Colors.grey : const Color(0xFF1A3A6B)),
                                decoration: disabled ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            onPressed: disabled ? null : () => _selectLocation(p),
                          );
                        })
                        .toList(),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Capacity',
                    prefixIcon: Icon(Icons.people_outline_rounded),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'Required';
                    final n = int.tryParse(val);
                    if (n == null) return 'Must be a number';
                    if (n < 1) return 'Must be at least 1';
                    final key = CampusLocations.effectiveKeyFor(
                        _selectedLocationKey,
                        _locationController.text.trim());
                    final loc = CampusLocations.byId(key);
                    final maxCap = loc == null ? null : _maxFor(loc);
                    if (loc != null && maxCap != null && n > maxCap) {
                      return 'Max $maxCap for ${loc.name}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text('Date & time',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _DateTimeTile(
                  label: 'Start',
                  dateTime: _startTime,
                  onTap: () => _pickDateTime(isStart: true),
                ),
                const SizedBox(height: 10),
                _DateTimeTile(
                  label: 'End',
                  dateTime: _endTime,
                  onTap: () => _pickDateTime(isStart: false),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveEvent,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final String label;
  final DateTime dateTime;
  final VoidCallback onTap;

  const _DateTimeTile({
    required this.label,
    required this.dateTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 18, color: AppConfig.primaryColor),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  DateFormat('EEE, MMM d yyyy • h:mm a').format(dateTime),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}