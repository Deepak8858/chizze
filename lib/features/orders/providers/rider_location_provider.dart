import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/realtime_service.dart';

/// Rider location model for map tracking
class RiderLocation {
  final String riderId;
  final double latitude;
  final double longitude;
  final double heading;
  final double speed;
  final DateTime updatedAt;

  const RiderLocation({
    required this.riderId,
    required this.latitude,
    required this.longitude,
    this.heading = 0,
    this.speed = 0,
    required this.updatedAt,
  });

  factory RiderLocation.fromRealtimeData(Map<String, dynamic> data) {
    return RiderLocation(
      riderId: data['rider_id'] ?? data['\$id'] ?? '',
      latitude: (data['latitude'] ?? 17.4401).toDouble(),
      longitude: (data['longitude'] ?? 78.3489).toDouble(),
      heading: (data['heading'] ?? 0).toDouble(),
      speed: (data['speed'] ?? 0).toDouble(),
      updatedAt: DateTime.tryParse(data['\$updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

}

/// Rider location notifier — real-time updates from Appwrite
class RiderLocationNotifier extends StateNotifier<RiderLocation?> {
  final RealtimeService _realtime;
  StreamSubscription? _realtimeSubscription;

  RiderLocationNotifier(this._realtime) : super(null);

  /// Start tracking a specific rider (for customer view)
  void trackRider(String riderId) {
    // Cancel any existing subscription
    stopTracking();

    try {
      final channel = RealtimeChannels.riderLocationChannel(riderId);
      _realtimeSubscription = _realtime
          .subscribe(channel)
          .listen(
            (event) {
              if (event.type == RealtimeEventType.update ||
                  event.type == RealtimeEventType.create) {
                state = RiderLocation.fromRealtimeData(event.data);
              }
            },
            onError: (_) {
              // No mock fallback — location stays null until real data arrives
            },
          );
    } catch (_) {
      // Realtime not available — location stays null
    }
  }

  /// Stop tracking
  void stopTracking() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _mockTimer?.cancel();
    _mockTimer = null;
    state = null;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}

/// Rider location provider — tracks a delivery partner's position
final riderLocationProvider =
    StateNotifierProvider<RiderLocationNotifier, RiderLocation?>((ref) {
      final realtime = ref.watch(realtimeServiceProvider);
      return RiderLocationNotifier(realtime);
    });
