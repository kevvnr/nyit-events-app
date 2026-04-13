import 'dart:convert';

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Walking routes via the public OSRM demo server (OpenStreetMap).
/// Encoded geometry is decoded with [flutter_polyline_points] for the map polyline.
class WalkingRouteService {
  WalkingRouteService._();

  static Future<List<LatLng>> fetchWalkingRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    // OSRM expects longitude,latitude pairs
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/walking/'
      '$startLng,$startLat;$endLng,$endLat'
      '?overview=full&geometries=polyline',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Route server returned ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      return [];
    }
    final encoded = routes.first['geometry'] as String?;
    if (encoded == null || encoded.isEmpty) {
      return [];
    }
    final decoded = PolylinePoints.decodePolyline(encoded);
    return decoded
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }
}
