import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'map_config.dart';

/// Location data model
class LocationData {
  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final DateTime timestamp;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.heading = 0,
    this.speed = 0,
    required this.timestamp,
  });

  static LocationData get fallback => LocationData(
    latitude: MapConfig.defaultLatitude,
    longitude: MapConfig.defaultLongitude,
    timestamp: DateTime.now(),
  );
}

/// Location service — wraps geolocator for GPS access
class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  /// Check and request location permissions
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Get current position (one-shot)
  Future<LocationData> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        return LocationData(
          latitude: MapConfig.defaultLatitude,
          longitude: MapConfig.defaultLongitude,
          timestamp: DateTime.now(),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        timestamp: position.timestamp,
      );
    } catch (_) {
      return LocationData(
        latitude: MapConfig.defaultLatitude,
        longitude: MapConfig.defaultLongitude,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Start continuous location updates (for delivery partner)
  Stream<LocationData> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update every 10 meters
      ),
    ).map(
      (position) => LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        heading: position.heading,
        speed: position.speed,
        timestamp: position.timestamp,
      ),
    );
  }

  void dispose() {
    _positionSubscription?.cancel();
  }
}

/// Location service provider
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current position provider (one-shot, refreshable)
final currentPositionProvider = FutureProvider<LocationData>((ref) async {
  final service = ref.watch(locationServiceProvider);
  return service.getCurrentPosition();
});
