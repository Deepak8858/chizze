import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/services/websocket_service.dart';

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

/// Rider location notifier — real-time updates from Appwrite + Go WebSocket
class RiderLocationNotifier extends StateNotifier<RiderLocation?> {
  final RealtimeService _realtime;
  final WebSocketService _ws;
  StreamSubscription? _realtimeSubscription;
  StreamSubscription? _wsSubscription;

  RiderLocationNotifier(this._realtime, this._ws) : super(null);

  /// Start tracking a specific rider (for customer view)
  void trackRider(String riderId) {
    // Cancel any existing subscription
    stopTracking();

    // Appwrite Realtime channel
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
            onError: (_) {},
          );
    } catch (_) {}

    // Go WebSocket — delivery_location events (higher frequency from rider app)
    _wsSubscription = _ws.deliveryLocations.listen((event) {
      if (event.latitude != null && event.longitude != null) {
        state = RiderLocation(
          riderId: riderId,
          latitude: event.latitude!,
          longitude: event.longitude!,
          heading: event.bearing ?? 0,
          speed: 0,
          updatedAt: event.timestamp,
        );
      }
    });
  }

  /// Stop tracking
  void stopTracking() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
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
      final ws = ref.watch(webSocketServiceProvider);
      return RiderLocationNotifier(realtime, ws);
    });
