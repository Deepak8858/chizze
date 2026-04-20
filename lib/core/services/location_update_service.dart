import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'api_client.dart';
import 'api_config.dart';
import 'location_service.dart';

/// Result of a location-update operation driven by the "update your location"
/// push notification (or any equivalent trigger).
enum LocationUpdateOutcome {
  success,
  permissionDenied,
  serviceDisabled,
  gpsTimeout,
  networkError,
}

/// High-level service that captures the user's current GPS, reverse-geocodes it,
/// and persists it to both the user profile and the default saved address.
class LocationUpdateService {
  LocationUpdateService(this._api, this._location);

  final ApiClient _api;
  final LocationService _location;

  /// Run the full update flow. Safe to call from any screen / notification tap.
  Future<LocationUpdateOutcome> updateFromCurrentLocation() async {
    final permStatus = await _location.permissionStatus();
    if (permStatus == LocationPermissionStatus.serviceDisabled) {
      return LocationUpdateOutcome.serviceDisabled;
    }
    if (permStatus != LocationPermissionStatus.granted) {
      return LocationUpdateOutcome.permissionDenied;
    }

    final position = await _location.getFastCurrentPosition();
    if (position == null) return LocationUpdateOutcome.gpsTimeout;

    // Reverse-geocode best-effort. If it fails we still save coords so the
    // backend/profile has the latest fix — the address string can be refined later.
    String addressStr = '';
    try {
      final placemarks = await geo.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.subLocality?.isNotEmpty == true) p.subLocality!,
          if (p.locality?.isNotEmpty == true) p.locality!,
          if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
          if (p.postalCode?.isNotEmpty == true) p.postalCode!,
        ];
        addressStr = parts.join(', ');
      }
    } catch (_) {}

    try {
      // 1) Update the user record with the latest coords + address string.
      await _api.put(ApiConfig.profile, body: {
        'latitude': position.latitude,
        'longitude': position.longitude,
        if (addressStr.isNotEmpty) 'address': addressStr,
      });

      // 2) Upsert the default "Home" saved address so it appears in profile.
      await _api.post(ApiConfig.addresses, body: {
        'label': 'Home',
        'full_address': addressStr.isNotEmpty ? addressStr : 'Current location',
        'landmark': '',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'is_default': true,
      });
      return LocationUpdateOutcome.success;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationUpdate] network error: $e');
      return LocationUpdateOutcome.networkError;
    }
  }
}

final locationUpdateServiceProvider = Provider<LocationUpdateService>((ref) {
  final api = ref.watch(apiClientProvider);
  final loc = ref.watch(locationServiceProvider);
  return LocationUpdateService(api, loc);
});
