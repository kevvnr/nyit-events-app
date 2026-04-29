import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../config/mapbox_config.dart';
import '../../providers/event_provider.dart';
import '../../models/event_model.dart';
import '../../services/walking_route_service.dart';
import '../../utils/event_dedup.dart';
import '../../utils/map_directions.dart';
import '../feed/event_detail_screen.dart';

class _CampusBuilding {
  final String name;
  final double lat;
  final double lng;
  final IconData icon;
  final bool isParking;
  const _CampusBuilding(
    this.name,
    this.lat,
    this.lng,
    this.icon, {
    this.isParking = false,
  });
}

const List<_CampusBuilding> _buildings = [
  _CampusBuilding('Harry J. Schure Hall', 40.8137454431403,
      -73.60428057454216, Icons.school_rounded),
  _CampusBuilding('Salten Hall', 40.81388718396957,
      -73.60554079556253, Icons.business_rounded),
  _CampusBuilding('Anna Rubin Hall', 40.81335623621106,
      -73.60512680468784, Icons.apartment_rounded),
  _CampusBuilding('Theobald Science Center',
      40.812987847738235, -73.6043594492205,
      Icons.science_rounded),
  _CampusBuilding('Student Activity Center',
      40.8115533674869, -73.60153555356345,
      Icons.sports_basketball_rounded),
  _CampusBuilding('Rockefeller Hall', 40.81035934543809,
      -73.60628186591558, Icons.domain_rounded),
  _CampusBuilding('Riland Building', 40.80945159674424,
      -73.60550682952751, Icons.medical_services_rounded),
  _CampusBuilding('Biomedical Research Center',
      40.80982839959638, -73.60658169751095,
      Icons.biotech_rounded),
  _CampusBuilding('de Seversky Mansion',
      40.80925376204674, -73.61414943761697,
      Icons.villa_rounded),
  _CampusBuilding('Parking Lot 1', 40.814044359963994,
      -73.60745596524471, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 2', 40.813726026287085,
      -73.60889635873157, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 3', 40.81368398210138,
      -73.6100014540554, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 5', 40.8079097913687,
      -73.61485143505948, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 7', 40.80896546751834,
      -73.60430644356249, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 8', 40.8101357424386,
      -73.6034829398403, Icons.local_parking_rounded,
      isParking: true),
  _CampusBuilding('Parking Lot 9', 40.800583754241366,
      -73.59806421409746, Icons.local_parking_rounded,
      isParking: true),
  // ── Residential & Additional Buildings ──────────────────────
  _CampusBuilding('Simonson House', 40.81485147876463,
      -73.6098192844773, Icons.house_rounded),
  _CampusBuilding('North House', 40.81433710113313,
      -73.60603076564036, Icons.house_rounded),
  _CampusBuilding('Whitney Lane House', 40.81157820702483,
      -73.60052622567554, Icons.house_rounded),
  _CampusBuilding('Education Hall', 40.799738800306706,
      -73.59644669912416, Icons.menu_book_rounded),
  _CampusBuilding('Midge Karr Art & Design Center',
      40.80213827709307, -73.59811143296241,
      Icons.palette_rounded),
  _CampusBuilding('Tower House', 40.81108287767998,
      -73.60710866827468, Icons.house_rounded),
  _CampusBuilding('Gerry House', 40.81243536463496,
      -73.60753737447423, Icons.house_rounded),
  _CampusBuilding('Parking', 40.80057157183352,
      -73.59796114547753, Icons.local_parking_rounded,
      isParking: true),
];

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() =>
      _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  EventModel? _selectedEvent;
  _CampusBuilding? _selectedBuilding;
  bool _showParking = false;
  String _filter = 'All';
  LatLng? _userLatLng;
  StreamSubscription<Position>? _positionSub;
  bool _liveLocationOn = false;
  List<LatLng>? _walkingRoutePoints;
  bool _walkingRouteLoading = false;

  static const LatLng _campusCenter =
      LatLng(40.8095, -73.6045);

  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        ref.read(eventsNotifierProvider.notifier).loadEvents());
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleLiveLocation() async {
    if (_liveLocationOn) {
      await _positionSub?.cancel();
      _positionSub = null;
      setState(() {
        _liveLocationOn = false;
        _userLatLng = null;
      });
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required to show your position on the map.',
          ),
        ),
      );
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please turn on location services.'),
        ),
      );
      return;
    }

    setState(() => _liveLocationOn = true);

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((position) {
      final ll = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _userLatLng = ll);
      if (_liveLocationOn) {
        _mapController.move(ll, 16.2);
      }
    });
  }

  void _clearWalkingRoute() {
    setState(() => _walkingRoutePoints = null);
  }

  Future<void> _openDirectionsForEvent(EventModel event) async {
    if (event.locationLat == 0.0 && event.locationLng == 0.0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No coordinates for this event.'),
        ),
      );
      return;
    }
    await openWalkingDirections(
      context: context,
      destinationLat: event.locationLat,
      destinationLng: event.locationLng,
      destinationTitle: event.title,
    );
  }

  Future<void> _loadWalkingRouteToEvent(EventModel event) async {
    if (event.locationLat == 0.0 && event.locationLng == 0.0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No coordinates for this event.'),
        ),
      );
      return;
    }
    final start = _userLatLng ?? _campusCenter;
    setState(() {
      _walkingRouteLoading = true;
      _walkingRoutePoints = null;
    });
    try {
      final pts = await WalkingRouteService.fetchWalkingRoute(
        startLat: start.latitude,
        startLng: start.longitude,
        endLat: event.locationLat,
        endLng: event.locationLng,
      );
      if (!mounted) return;
      if (pts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not build a walking route. Try enabling GPS or pick another event.',
            ),
          ),
        );
        setState(() => _walkingRouteLoading = false);
        return;
      }
      setState(() {
        _walkingRoutePoints = pts;
        _walkingRouteLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.fromLTRB(36, 80, 36, 220),
            maxZoom: 17,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Route error: $e')),
        );
        setState(() => _walkingRouteLoading = false);
      }
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

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventsStreamProvider);
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: eventsState.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rawAllEvents) {
          // Same dedup contract as the feed so counts stay consistent across
          // tabs — one event = one marker/card everywhere.
          final allEvents = dedupeEvents(rawAllEvents);
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));
          final weekEnd = today.add(const Duration(days: 7));

          // Today's events (for map markers and filter chips)
          final events = allEvents.where((e) {
            if (e.isCancelled) return false;
            // Show events that start today OR are currently happening today
            return e.startTime.isBefore(tomorrow) && e.endTime.isAfter(today);
          }).toList();

          // This week's events for the bottom preview panel
          final weekEvents = allEvents.where((e) {
            if (e.isCancelled) return false;
            return e.endTime.isAfter(now) && e.startTime.isBefore(weekEnd);
          }).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

          final filteredEvents = _filter == 'Now'
              ? events.where((e) => e.isHappeningNow).toList()
              : events;

          final visibleBuildings = _showParking
              ? _buildings
              : _buildings
                  .where((b) => !b.isParking)
                  .toList();

          return Column(
            children: [
              // Header
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1A3A6B),
                      Color(0xFF1565C0),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 12, 16, 0),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Text(
                              'Campus Map',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Filter chips — Today, Live Now, Parking sit on a
                        // single row with even spacing. Each event filter
                        // expands to share the row equally so the pair always
                        // looks balanced; Parking is a compact toggle that
                        // hugs the right edge so it reads as an option, not
                        // a fourth filter.
                        Row(
                          children: [
                            Expanded(
                              child: _FilterChip(
                                label: 'Today',
                                count: events.length,
                                selected: _filter == 'All',
                                color: const Color(0xFF1565C0),
                                onTap: () =>
                                    setState(() => _filter = 'All'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterChip(
                                label: 'Live Now',
                                count: events
                                    .where((e) => e.isHappeningNow)
                                    .length,
                                selected: _filter == 'Now',
                                color: Colors.green.shade700,
                                onTap: () =>
                                    setState(() => _filter = 'Now'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'Parking',
                              icon: Icons.local_parking_rounded,
                              selected: _showParking,
                              color: const Color(0xFF455A64),
                              onTap: () => setState(
                                  () => _showParking = !_showParking),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
              ),

              // Map
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                  FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _campusCenter,
                    initialZoom: 14.8,
                    onTap: (_, __) => setState(() {
                      _selectedEvent = null;
                      _selectedBuilding = null;
                      _walkingRoutePoints = null;
                    }),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: MapboxConfig.streetsUrl,
                      userAgentPackageName:
                          'edu.nyit.campusevents',
                    ),

                    if (_walkingRoutePoints != null &&
                        _walkingRoutePoints!.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _walkingRoutePoints!,
                            strokeWidth: 5,
                            color: const Color(0xFF1565C0),
                            borderStrokeWidth: 2,
                            borderColor: Colors.white,
                          ),
                        ],
                      ),

                    // Building markers
                    MarkerLayer(
                      markers: visibleBuildings
                          .map((b) => Marker(
                                point: LatLng(b.lat, b.lng),
                                width: 36,
                                height: 36,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedBuilding = b;
                                    _selectedEvent = null;
                                    _walkingRoutePoints = null;
                                  }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: b.isParking
                                          ? Colors
                                              .grey.shade600
                                          : (_selectedBuilding ==
                                                  b
                                              ? const Color(
                                                  0xFF1a3a6b)
                                              : const Color(
                                                  0xFF1565C0)),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(
                                                  0.2),
                                          blurRadius: 4,
                                          offset:
                                              const Offset(
                                                  0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      b.icon,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),

                    if (_userLatLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _userLatLng!,
                            width: 28,
                            height: 28,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white,
                                    width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withOpacity(0.25),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                    // Event markers
                    MarkerLayer(
                      markers: filteredEvents
                          .where((e) =>
                              e.locationLat != 0.0 &&
                              e.locationLng != 0.0)
                          .map((e) => Marker(
                                point: LatLng(e.locationLat,
                                    e.locationLng),
                                width: 44,
                                height: 44,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedEvent = e;
                                    _selectedBuilding = null;
                                    _walkingRoutePoints = null;
                                  }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: e.isHappeningNow
                                          ? Colors
                                              .green.shade600
                                          : _categoryColor(
                                              e.category),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white,
                                          width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(
                                                  0.25),
                                          blurRadius: 6,
                                          offset:
                                              const Offset(
                                                  0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.event_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
                  // Live now glass pill
                  Positioned(
                    left: 12,
                    top: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 0.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade500,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.shade400
                                          .withValues(alpha: 0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                '${filteredEvents.where((e) => e.isHappeningNow).length} live now',
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Zoom controls
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Column(
                      children: [
                        _ZoomButton(
                          icon: Icons.add,
                          onTap: () {
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              (zoom + 1).clamp(10.0, 19.0),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _ZoomButton(
                          icon: Icons.remove,
                          onTap: () {
                            final zoom = _mapController.camera.zoom;
                            _mapController.move(
                              _mapController.camera.center,
                              (zoom - 1).clamp(10.0, 19.0),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        _ZoomButton(
                          icon: Icons.my_location_rounded,
                          onTap: () => _mapController.move(
                            _campusCenter,
                            14.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ZoomButton(
                          icon: Icons.near_me_rounded,
                          active: _liveLocationOn,
                          onTap: _toggleLiveLocation,
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
              ),

              // Bottom sheet
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),

                    if (_selectedEvent != null)
                      _EventInfoCard(
                        event: _selectedEvent!,
                        walkingRouteLoading: _walkingRouteLoading,
                        walkingRouteDrawn: _walkingRoutePoints != null,
                        onDirections: () =>
                            _openDirectionsForEvent(_selectedEvent!),
                        onWalkingRoute: () =>
                            _loadWalkingRouteToEvent(_selectedEvent!),
                        onClearRoute: _clearWalkingRoute,
                      )
                    else if (_selectedBuilding != null)
                      _BuildingInfoCard(
                          building: _selectedBuilding!)
                    else
                      _EventListPreview(
                          events: weekEvents),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _ZoomButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF1565C0)
                  : Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.6),
                width: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Colors.white : const Color(0xFF1565C0),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int? count;
  final IconData? icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.count,
    this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? color : Colors.white.withValues(alpha: 0.18);
    final fg = selected ? Colors.white : Colors.white.withValues(alpha: 0.92);
    final borderColor = selected
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.28);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: fg,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventInfoCard extends StatelessWidget {
  final EventModel event;
  final bool walkingRouteLoading;
  final bool walkingRouteDrawn;
  final VoidCallback onDirections;
  final VoidCallback onWalkingRoute;
  final VoidCallback onClearRoute;

  const _EventInfoCard({
    required this.event,
    required this.walkingRouteLoading,
    required this.walkingRouteDrawn,
    required this.onDirections,
    required this.onWalkingRoute,
    required this.onClearRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    EventDetailScreen(eventId: event.id),
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: event.isHappeningNow
                        ? Colors.green.shade50
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.event_rounded,
                    color: event.isHappeningNow
                        ? Colors.green.shade700
                        : const Color(0xFF1565C0),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      if (event.isHappeningNow)
                        Container(
                          margin: const EdgeInsets.only(
                              bottom: 4),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Happening now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.locationName,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${event.rsvpCount} going · ${event.spotsLeft} spots left',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MapActionButton(
                  icon: Icons.directions_walk_rounded,
                  label: 'Maps app',
                  filled: false,
                  onTap: onDirections,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MapActionButton(
                  icon: Icons.route_rounded,
                  label: walkingRouteLoading ? 'Routing…' : 'Walk route',
                  filled: true,
                  loading: walkingRouteLoading,
                  onTap: walkingRouteLoading ? null : onWalkingRoute,
                ),
              ),
            ],
          ),
          if (walkingRouteDrawn)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClearRoute,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Clear route'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  const _MapActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1565C0);
    final disabled = onTap == null;
    final bg = filled
        ? (disabled ? primary.withValues(alpha: 0.5) : primary)
        : Colors.white;
    final fg = filled ? Colors.white : primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            else
              Icon(icon, size: 17, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuildingInfoCard extends StatelessWidget {
  final _CampusBuilding building;
  const _BuildingInfoCard({required this.building});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: building.isParking
                  ? Colors.grey.shade100
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              building.icon,
              color: building.isParking
                  ? Colors.grey.shade600
                  : const Color(0xFF1565C0),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  building.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  building.isParking
                      ? 'Parking area'
                      : 'Campus building · NYIT Old Westbury',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
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

class _EventListPreview extends StatelessWidget {
  final List<EventModel> events;
  const _EventListPreview({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded,
                size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No events on map',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'This week · ${events.length} event${events.length != 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return TweenAnimationBuilder<double>(
                duration: Duration(
                  milliseconds: 280 + (index * 55).clamp(0, 360),
                ),
                curve: Curves.easeOutCubic,
                tween: Tween(begin: 0, end: 1),
                builder: (context, t, child) => Transform.translate(
                  offset: Offset((1 - t) * 16, 0),
                  child: Opacity(opacity: t, child: child),
                ),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EventDetailScreen(eventId: event.id),
                    ),
                  ),
                  child: Container(
                    width: 210,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: event.isHappeningNow
                          ? Colors.green.shade50
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: event.isHappeningNow
                            ? Colors.green.shade200
                            : const Color(0xFFEEF2F7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (event.isHappeningNow)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.locationName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          '${event.rsvpCount} going',
                          style: TextStyle(
                            fontSize: 11,
                            color: event.isHappeningNow
                                ? Colors.green.shade700
                                : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}