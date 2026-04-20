class MapboxConfig {
  /// Public (read-only) token — safe to ship in the app binary.
  static const publicToken =
      'pk.eyJ1Ijoia2V2dm5yIiwiYSI6ImNtbzBzbmo5djBibDcycnBzdmhsZGwzeGQifQ.rNhRepESvmc-6sQ-pwqNSg';

  /// Mapbox Streets v12 — raster tile URL template for flutter_map.
  static String get streetsUrl =>
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token=$publicToken';
}
