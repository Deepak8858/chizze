import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'map_config.dart';

/// Service to fetch driving routes from Mapbox Directions API v5.
/// Returns a list of [lng, lat] coordinate pairs for the route polyline.
class RouteService {
  RouteService._()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ));
  static final RouteService instance = RouteService._();

  final Dio _dio;
  static const _baseUrl = 'https://api.mapbox.com/directions/v5/mapbox/driving';

  /// Fetch a driving route between two points.
  /// Returns list of [longitude, latitude] pairs, or null on failure.
  Future<List<List<double>>?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    // Mapbox expects coordinates as lng,lat
    final url = '$_baseUrl/$originLng,$originLat;$destLng,$destLat'
        '?geometries=geojson&overview=full&access_token=${MapConfig.accessToken}';

    try {
      final response = await _dio.get(url);
      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[RouteService] HTTP ${response.statusCode}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final geometry = routes[0]['geometry'] as Map<String, dynamic>?;
      if (geometry == null) return null;

      final coords = geometry['coordinates'] as List;
      return coords
          .map<List<double>>((c) => [
                (c[0] as num).toDouble(), // longitude
                (c[1] as num).toDouble(), // latitude
              ])
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[RouteService] Error fetching route: $e');
      return null;
    }
  }
}
