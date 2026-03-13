import 'dart:async';
import 'package:flutter/foundation.dart';
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
      riderId: (data['rider_id'] ?? data['\$id'] ?? '').toString(),
      latitude: _safeDouble(data['latitude']),
      longitude: _safeDouble(data['longitude']),
      heading: _safeDouble(data['heading']),
      speed: _safeDouble(data['speed']),
      updatedAt: _safeDateTime(data['\$updatedAt']),
    );
  }

  /// Safely coerce a dynamic value to double.
  static double _safeDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Safely parse a DateTime from string or numeric timestamp.
  /// Numeric values are expected in milliseconds since epoch; values that
  /// appear to be seconds (< 1e12) are auto-promoted to milliseconds.
  static DateTime _safeDateTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is num) {
      final ms = value < 1e12 ? (value * 1000).toInt() : value.toInt();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.now();
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
            onError: (error, stack) {
              if (kDebugMode) {
                debugPrint(
                '[RiderLocation] realtime stream error for rider $riderId on $channel: $error',
              );
              }
              _realtimeSubscription?.cancel();
              _realtimeSubscription = null;
              state = null;
            },
            onDone: () {
              _realtimeSubscription?.cancel();
              _realtimeSubscription = null;
              state = null;
            },
          );
    } catch (e) {
      if (kDebugMode) debugPrint('[RiderLocation] realtime subscription error: $e');
    }

    // Go WebSocket — delivery_location events (higher frequency from rider app)
    try {
      _wsSubscription = _ws.deliveryLocations.listen(
        (event) {
          if (event.latitude != null && event.longitude != null) {
            state = RiderLocation(
              riderId: riderId,
              latitude: event.latitude!,
              longitude: event.longitude!,
              heading: event.bearing ?? 0,
              speed: event.speed ?? 0,
              updatedAt: event.timestamp,
            );
          }
        },
        onError: (error, stack) {
          if (kDebugMode) {
            debugPrint(
            '[RiderLocation] WebSocket stream error for rider $riderId: $error',
          );
          }
          _wsSubscription?.cancel();
          _wsSubscription = null;
          state = null;
        },
        onDone: () {
          _wsSubscription?.cancel();
          _wsSubscription = null;
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[RiderLocation] WebSocket subscription error for rider $riderId: $e');
      _wsSubscription?.cancel();
      _wsSubscription = null;
      state = null;
    }
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
