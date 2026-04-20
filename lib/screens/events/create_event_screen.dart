import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../../config/app_config.dart';
import '../../config/campus_locations.dart';
import '../../providers/event_provider.dart';
import '../../providers/auth_provider.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  @override
  ConsumerState<CreateEventScreen> createState() =>
      _CreateEventScreenState();
}

class _CreateEventScreenState
    extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _capacityController = TextEditingController();
  String _selectedCategory =
      AppConfig.defaultCategories.first;
  DateTime _startTime =
      DateTime.now().add(const Duration(hours: 1));
  DateTime _endTime =
      DateTime.now().add(const Duration(hours: 2));
  bool _isLoading = false;
  double _lat = 0.0;
  double _lng = 0.0;
  final List<String> _vibeTags = [];
  bool _showParking = false;
  String? _selectedLocationKey;
  Set<String> _unavailableLocationKeys = {};
  bool _loadingAvailability = false;
  Map<String, int> _capacityLimits = {};
  File? _selectedImage;
  String? _uploadedImageUrl;
  bool _isUploadingImage = false;

  List<CampusLocation> get _buildingLocations =>
      CampusLocations.all.where((l) => !l.isParking).toList();

  List<CampusLocation> get _parkingLocations =>
      CampusLocations.all.where((l) => l.isParking).toList();

  static const List<String> _vibeOptions = [
    '🍕 Free Food',
    '🤝 Networking',
    '😎 Chill',
    '⚡ High Energy',
    '🎓 Academic',
    '🎉 Party',
    '💼 Professional',
    '🏃 Active',
  ];

  @override
  void initState() {
    super.initState();
    _loadCapacityLimits();
    _refreshLocationAvailability();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
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
              'Choose image source',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppConfig.primaryColor
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: AppConfig.primaryColor,
                ),
              ),
              title: const Text('Photo Library'),
              subtitle:
                  const Text('Choose from your photos'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.green.shade700,
                ),
              ),
              title: const Text('Camera'),
              subtitle: const Text('Take a new photo'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final image = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() {
      _selectedImage = File(image.path);
      _isUploadingImage = true;
    });

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('event_images')
          .child(
              '${DateTime.now().millisecondsSinceEpoch}.jpg');

      await ref.putFile(_selectedImage!);
      final url = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _uploadedImageUrl = url;
          _isUploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickDateTime(
      {required bool isStart}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startTime : _endTime,
      firstDate: DateTime.now(),
      lastDate:
          DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          isStart ? _startTime : _endTime),
    );
    if (time == null) return;

    final dt = DateTime(date.year, date.month, date.day,
        time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startTime = dt;
        if (_endTime.isBefore(_startTime)) {
          _endTime =
              _startTime.add(const Duration(hours: 1));
        }
      } else {
        _endTime = dt;
      }
    });
    await _refreshLocationAvailability();
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

  Widget _buildLocationChip(CampusLocation loc,
      {bool isParking = false}) {
    final cap = int.tryParse(_capacityController.text.trim()) ?? 0;
    final maxCap = _maxFor(loc);
    final tooSmall = cap > 0 && maxCap < cap;
    final unavailable = _unavailableLocationKeys.contains(loc.id);
    final disabled = tooSmall || unavailable;
    final selected =
        _locationController.text == loc.name;
    return GestureDetector(
      onTap: disabled ? null : () => _selectLocation(loc),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppConfig.primaryColor
              : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppConfig.primaryColor
                : const Color(0xFFBFD1F5),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppConfig.primaryColor
                        .withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isParking
                  ? Icons.local_parking_rounded
                  : Icons.location_on_rounded,
              size: 14,
              color: selected
                  ? Colors.white
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              loc.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : (disabled ? Colors.grey.shade400 : const Color(0xFF1A3A6B)),
                decoration: disabled ? TextDecoration.lineThrough : null,
              ),
            ),
            if (tooSmall) ...[
              const SizedBox(width: 6),
              Text('max $maxCap',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red.shade400,
                  )),
            ] else if (unavailable) ...[
              const SizedBox(width: 6),
              Text('busy',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade500,
                  )),
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    var trimmedLoc = _locationController.text.trim();
    final cap = int.parse(_capacityController.text.trim());
    var locationKey = CampusLocations.effectiveKeyFor(
        _selectedLocationKey, trimmedLoc);
    final campusLoc = CampusLocations.byId(locationKey);
    final roomMax = campusLoc == null ? null : _maxFor(campusLoc);

    if (roomMax != null && cap > roomMax) {
      if (!mounted) return;
      final roomName = campusLoc?.name ?? 'selected room';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Capacity cannot exceed $roomMax for $roomName. '
            'Pick a larger venue or lower the count.',
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
      );
      if (conflict == null) break;
      final suggestions = await eventService.suggestFreeLocations(
        capacity: cap,
        start: _startTime,
        end: _endTime,
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
              '“${CampusLocations.byId(locationKey)?.name ?? trimmedLoc}” overlaps with “${conflict.title}” '
              '(${DateFormat('MMM d, h:mm a').format(conflict.startTime)}–${DateFormat('h:mm a').format(conflict.endTime)}).\n\n$altText',
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
      trimmedLoc = picked.name;
      locationKey = picked.id;
    }

    setState(() => _isLoading = true);
    try {
      final user =
          ref.read(userModelProvider).asData?.value;
      if (user == null) return;

      final event = await ref
          .read(eventsNotifierProvider.notifier)
          .createEvent(
            title: _titleController.text.trim(),
            description:
                _descriptionController.text.trim(),
            hostId: user.uid,
            hostName: user.name,
            category: _selectedCategory,
            startTime: _startTime,
            endTime: _endTime,
            locationName: _locationController.text.trim(),
            locationKey: locationKey,
            locationLat: _lat,
            locationLng: _lng,
            capacity: cap,
            vibeTags: _vibeTags,
            imageUrl: _uploadedImageUrl,
          );

      if (event != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Event',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _submit,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  )
                : const Text(
                    'Post',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image picker
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedImage != null
                        ? AppConfig.primaryColor
                        : Colors.grey.shade300,
                    width: _selectedImage != null ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _isUploadingImage
                    ? const Center(
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Uploading image...'),
                          ],
                        ),
                      )
                    : _selectedImage != null
                        ? ClipRRect(
                            borderRadius:
                                BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 10,
                                        vertical: 6),
                                    decoration:
                                        BoxDecoration(
                                      color: Colors.black
                                          .withOpacity(0.6),
                                      borderRadius:
                                          BorderRadius
                                              .circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize:
                                          MainAxisSize.min,
                                      children: [
                                        Icon(
                                            Icons
                                                .edit_rounded,
                                            color:
                                                Colors.white,
                                            size: 12),
                                        SizedBox(width: 4),
                                        Text(
                                          'Change',
                                          style: TextStyle(
                                            color:
                                                Colors.white,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppConfig
                                      .primaryColor
                                      .withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(
                                          28),
                                ),
                                child: const Icon(
                                  Icons
                                      .add_photo_alternate_rounded,
                                  color:
                                      AppConfig.primaryColor,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Add Event Photo',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppConfig
                                      .primaryColor,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to upload from library or camera',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            _buildCard(
              child: TextFormField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  labelText: 'Event title',
                  hintText: 'Give your event a name',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.title_rounded,
                    color: AppConfig.primaryColor,
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty
                        ? 'Title is required'
                        : null,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            _buildCard(
              child: TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'What\'s this event about?',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Icon(
                      Icons.description_rounded,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty
                        ? 'Description is required'
                        : null,
              ),
            ),
            const SizedBox(height: 12),

            // Category
            _buildCard(
              child: DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.category_rounded,
                    color: AppConfig.primaryColor,
                  ),
                ),
                items: AppConfig.defaultCategories
                    .map((cat) => DropdownMenuItem(
                          value: cat,
                          child: Text(cat),
                        ))
                    .toList(),
                onChanged: (val) => setState(
                    () => _selectedCategory = val!),
              ),
            ),
            const SizedBox(height: 12),

            // Date/Time
            _buildCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.calendar_today_rounded,
                        color: AppConfig.primaryColor),
                    title: const Text('Start time',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey)),
                    subtitle: Text(
                      DateFormat('EEE, MMM d · h:mm a')
                          .format(_startTime),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    onTap: () =>
                        _pickDateTime(isStart: true),
                  ),
                  Divider(
                      height: 0,
                      color: Colors.grey.shade200),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        Icons.calendar_today_outlined,
                        color: AppConfig.primaryColor),
                    title: const Text('End time',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey)),
                    subtitle: Text(
                      DateFormat('EEE, MMM d · h:mm a')
                          .format(_endTime),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    onTap: () =>
                        _pickDateTime(isStart: false),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 4),
            ),
            const SizedBox(height: 12),

            // Location
            _buildCard(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
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
                    decoration: InputDecoration(
                      labelText: 'Location',
                      hintText: 'Select or type location',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      prefixIcon: Icon(
                          Icons.location_on_rounded,
                          color: AppConfig.primaryColor),
                    ),
                    validator: (val) =>
                        val == null || val.trim().isEmpty
                            ? 'Location is required'
                            : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Campus buildings',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          children: _buildingLocations
                              .map((b) =>
                                  _buildLocationChip(b))
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
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => setState(() =>
                              _showParking = !_showParking),
                          child: Row(
                            children: [
                              Icon(
                                _showParking
                                    ? Icons
                                        .keyboard_arrow_up_rounded
                                    : Icons
                                        .keyboard_arrow_down_rounded,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Show parking lots',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_showParking) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            children: _parkingLocations
                                .map((p) =>
                                    _buildLocationChip(p,
                                        isParking: true))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),

            // Capacity
            _buildCard(
              child: TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Capacity',
                  hintText: 'Max attendees',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: Icon(Icons.people_rounded,
                      color: AppConfig.primaryColor),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Capacity is required';
                  }
                  final n = int.tryParse(val.trim());
                  if (n == null) {
                    return 'Must be a number';
                  }
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
            ),
            const SizedBox(height: 12),

            // Vibe tags
            _buildCard(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 14, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.local_offer_rounded,
                            color: AppConfig.primaryColor,
                            size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Vibe tags',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 0, 16, 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          _vibeOptions.map((vibe) {
                        final selected =
                            _vibeTags.contains(vibe);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _vibeTags.remove(vibe);
                            } else {
                              _vibeTags.add(vibe);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(
                                milliseconds: 150),
                            padding:
                                const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppConfig.primaryColor
                                  : const Color(0xFFF1F5F9),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: Text(
                              vibe,
                              style: TextStyle(
                                fontSize: 13,
                                color: selected
                                    ? Colors.white
                                    : const Color(
                                        0xFF475569),
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 28),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      vertical: 16),
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
                    : const Text('Create Event'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
    EdgeInsets padding =
        const EdgeInsets.symmetric(horizontal: 4),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}