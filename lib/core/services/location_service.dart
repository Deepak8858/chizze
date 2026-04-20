import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Location data model (only real GPS readings — no default fallbacks).
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
}

/// Why a location call failed — lets the UI show the right CTA.
enum LocationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  serviceDisabled,
}

/// Location service — real GPS only. Never returns a synthetic fallback.
class LocationService {
  /// Best known real GPS reading from any prior call. Null until we have one.
  LocationData? lastPosition;

  /// In-flight warm-up future so duplicate callers share one GPS acquisition.
  Future<LocationData?>? _warmingUp;

  /// Check the current permission + service state.
  Future<LocationPermissionStatus> permissionStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.permanentlyDenied;
    }
    return LocationPermissionStatus.granted;
  }

  /// Fast one-shot reading. Returns the last known position instantly when
  /// available and kicks off a fresh fix in the background to refresh
  /// [lastPosition]. Returns null on permission denied / services off / timeout.
  Future<LocationData?> getFastCurrentPosition() async {
    final status = await permissionStatus();
    if (status != LocationPermissionStatus.granted) return null;

    // 1) Try last-known (typically <100ms). Return immediately if present.
    try {
      final known = await Geolocator.getLastKnownPosition();
      if (known != null) {
        final data = _toData(known);
        lastPosition = data;
        // Refresh in background so the next caller gets an even fresher fix.
        unawaited(_freshFix(accuracy: LocationAccuracy.medium, timeoutSec: 6));
        return data;
      }
    } catch (_) {}

    // 2) No last-known — get a fresh fix with a snappy timeout.
    return _freshFix(accuracy: LocationAccuracy.medium, timeoutSec: 5);
  }

  /// Precise one-shot reading (higher accuracy, longer timeout).
  /// Returns null on failure — never a fallback.
  Future<LocationData?> getCurrentPosition() async {
    final status = await permissionStatus();
    if (status != LocationPermissionStatus.granted) return null;
    return _freshFix(accuracy: LocationAccuracy.high, timeoutSec: 10);
  }

  /// Fire-and-forget warm-up: requests permission and pre-fetches GPS so the
  /// next caller reads [lastPosition] instantly. Safe to call multiple times.
  Future<LocationData?> warmUp() {
    final existing = _warmingUp;
    if (existing != null) return existing;
    final future = _doWarmUp();
    _warmingUp = future;
    future.whenComplete(() => _warmingUp = null);
    return future;
  }

  Future<LocationData?> _doWarmUp() async {
    try {
      final status = await permissionStatus();
      if (status != LocationPermissionStatus.granted) return null;
      // Populate lastPosition from last-known first (instant),
      // then upgrade with a fresh fix.
      try {
        final known = await Geolocator.getLastKnownPosition();
        if (known != null) lastPosition = _toData(known);
      } catch (_) {}
      final fresh = await _freshFix(
        accuracy: LocationAccuracy.medium,
        timeoutSec: 8,
      );
      return fresh ?? lastPosition;
    } catch (e) {
      if (kDebugMode) debugPrint('[Location] warmUp error: $e');
      return lastPosition;
    }
  }

  Future<LocationData?> _freshFix({
    required LocationAccuracy accuracy,
    required int timeoutSec,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: Duration(seconds: timeoutSec),
        ),
      );
      final data = _toData(position);
      lastPosition = data;
      return data;
    } catch (e) {
      if (kDebugMode) debugPrint('[Location] _freshFix error: $e');
      return null;
    }
  }

  LocationData _toData(Position p) => LocationData(
        latitude: p.latitude,
        longitude: p.longitude,
        heading: p.heading,
        speed: p.speed,
        timestamp: p.timestamp,
      );

  /// Continuous stream (delivery partner). Error-safe: ends cleanly instead of
  /// throwing to PlatformDispatcher if permissions are denied mid-stream.
  Stream<LocationData> getPositionStream() async* {
    final status = await permissionStatus();
    if (status != LocationPermissionStatus.granted) return;

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).map((p) {
      final data = _toData(p);
      lastPosition = data;
      return data;
    }).handleError((error, _) {
      if (kDebugMode) debugPrint('[Location] stream error (handled): $error');
    });
  }

  void dispose() {}
}

/// Location service provider (singleton for app lifetime so lastPosition persists).
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Convenience provider — fetches current position on demand, refreshable.
/// Returns null on failure (caller decides how to surface that).
final currentPositionProvider = FutureProvider<LocationData?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  return service.getFastCurrentPosition();
});
