/// Canonical campus rooms/lots for scheduling, capacity, and map consistency.
class CampusLocation {
  final String id;
  final String name;
  final double lat;
  final double lng;
  /// Maximum event capacity for this space (room fire code / seating).
  final int maxCapacity;
  final bool isParking;

  const CampusLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.maxCapacity,
    this.isParking = false,
  });
}

abstract class CampusLocations {
  static const List<CampusLocation> all = [
    CampusLocation(
      id: 'schure_hall',
      name: 'Harry J. Schure Hall',
      lat: 40.8137454431403,
      lng: -73.60428057454216,
      maxCapacity: 150,
    ),
    CampusLocation(
      id: 'salten_hall',
      name: 'Salten Hall',
      lat: 40.81388718396957,
      lng: -73.60554079556253,
      maxCapacity: 100,
    ),
    CampusLocation(
      id: 'anna_rubin_hall',
      name: 'Anna Rubin Hall',
      lat: 40.81335623621106,
      lng: -73.60512680468784,
      maxCapacity: 80,
    ),
    CampusLocation(
      id: 'theobald_science',
      name: 'Theobald Science Center',
      lat: 40.812987847738235,
      lng: -73.6043594492205,
      maxCapacity: 120,
    ),
    CampusLocation(
      id: 'student_activity_center',
      name: 'Student Activity Center',
      lat: 40.8115533674869,
      lng: -73.60153555356345,
      maxCapacity: 250,
    ),
    CampusLocation(
      id: 'rockefeller_hall',
      name: 'Rockefeller Hall',
      lat: 40.81035934543809,
      lng: -73.60628186591558,
      maxCapacity: 100,
    ),
    CampusLocation(
      id: 'riland_building',
      name: 'Riland Building',
      lat: 40.80945159674424,
      lng: -73.60550682952751,
      maxCapacity: 60,
    ),
    CampusLocation(
      id: 'biomedical_research',
      name: 'Biomedical Research Center',
      lat: 40.80982839959638,
      lng: -73.60658169751095,
      maxCapacity: 80,
    ),
    CampusLocation(
      id: 'de_seversky_mansion',
      name: 'de Seversky Mansion',
      lat: 40.80925376204674,
      lng: -73.61414943761697,
      maxCapacity: 75,
    ),
    CampusLocation(
      id: 'parking_lot_1',
      name: 'Parking Lot 1',
      lat: 40.814044359963994,
      lng: -73.60745596524471,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_2',
      name: 'Parking Lot 2',
      lat: 40.813726026287085,
      lng: -73.60889635873157,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_3',
      name: 'Parking Lot 3',
      lat: 40.81368398210138,
      lng: -73.6100014540554,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_5',
      name: 'Parking Lot 5',
      lat: 40.8079097913687,
      lng: -73.61485143505948,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_7',
      name: 'Parking Lot 7',
      lat: 40.80896546751834,
      lng: -73.60430644356249,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_8',
      name: 'Parking Lot 8',
      lat: 40.8101357424386,
      lng: -73.6034829398403,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'parking_lot_9',
      name: 'Parking Lot 9',
      lat: 40.800583754241366,
      lng: -73.59806421409746,
      maxCapacity: 50,
      isParking: true,
    ),
    CampusLocation(
      id: 'simonson_house',
      name: 'Simonson House',
      lat: 40.81485147876463,
      lng: -73.6098192844773,
      maxCapacity: 40,
    ),
    CampusLocation(
      id: 'north_house',
      name: 'North House',
      lat: 40.81433710113313,
      lng: -73.60603076564036,
      maxCapacity: 40,
    ),
    CampusLocation(
      id: 'whitney_lane_house',
      name: 'Whitney Lane House',
      lat: 40.81157820702483,
      lng: -73.60052622567554,
      maxCapacity: 30,
    ),
    CampusLocation(
      id: 'education_hall',
      name: 'Education Hall',
      lat: 40.799738800306706,
      lng: -73.59644669912416,
      maxCapacity: 80,
    ),
    CampusLocation(
      id: 'midge_karr_art',
      name: 'Midge Karr Art & Design Center',
      lat: 40.80213827709307,
      lng: -73.59811143296241,
      maxCapacity: 50,
    ),
    CampusLocation(
      id: 'tower_house',
      name: 'Tower House',
      lat: 40.81108287767998,
      lng: -73.60710866827468,
      maxCapacity: 35,
    ),
    CampusLocation(
      id: 'gerry_house',
      name: 'Gerry House',
      lat: 40.81243536463496,
      lng: -73.60753737447423,
      maxCapacity: 35,
    ),
    CampusLocation(
      id: 'parking_generic',
      name: 'Parking',
      lat: 40.80057157183352,
      lng: -73.59796114547753,
      maxCapacity: 40,
      isParking: true,
    ),
  ];

  static CampusLocation? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final loc in all) {
      if (loc.id == id) return loc;
    }
    return null;
  }

  /// Match legacy events that only stored [locationName].
  static CampusLocation? matchByName(String name) {
    final t = name.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final loc in all) {
      if (loc.name.toLowerCase() == t) return loc;
    }
    return null;
  }

  /// Effective key for scheduling: stored key, or inferred from name.
  static String effectiveKeyFor(String? storedKey, String locationName) {
    if (storedKey != null && storedKey.isNotEmpty) return storedKey;
    return matchByName(locationName)?.id ?? '';
  }
}
