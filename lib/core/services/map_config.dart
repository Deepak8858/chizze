/// Mapbox configuration constants
class MapConfig {
  /// Mapbox public access token
  /// Replace with your own token from https://account.mapbox.com/access-tokens/
  static const String accessToken =
      'pk.eyJ1IjoiZGVlcGFrNzIzOCIsImEiOiJjbWxnZjAwMTMwOWo5M2xzaHF3eTd1eTd6In0.cNbgPuE749GMnCztExzPgg';

  /// Dark map style URL — matches Chizze dark theme
  static const String darkStyleUrl = 'mapbox://styles/mapbox/dark-v11';

  /// Default camera center — Hyderabad, India
  static const double defaultLatitude = 17.4401;
  static const double defaultLongitude = 78.3489;
  static const double defaultZoom = 14.0;

  /// Tracking zoom (closer)
  static const double trackingZoom = 15.5;

  /// Animation duration in milliseconds
  static const int markerAnimationMs = 1000;

  /// Route line color (Chizze primary orange)
  static const int routeLineColor = 0xFFF49D25; // #F49D25
  static const double routeLineWidth = 4.0;
}
