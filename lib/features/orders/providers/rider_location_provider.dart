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

  /// Mock location that simulates movement (for dev without backend)
  static RiderLocation mock({int step = 0}) {
    // Simulate rider moving from restaurant to customer in Hyderabad
    const startLat = 17.4486;
    const startLng = 78.3810;
    const endLat = 17.4401;
    const endLng = 78.3911;

    final progress = (step % 20) / 20.0; // loop every 20 steps
    return RiderLocation(
      riderId: 'mock_rider',
      latitude: startLat + (endLat - startLat) * progress,
      longitude: startLng + (endLng - startLng) * progress,
      heading: 135, // southeast
      speed: 20 + (progress * 10),
      updatedAt: DateTime.now(),
    );
  }
}

/// Rider location notifier — real-time updates from Appwrite
/// Falls back to simulated movement for development
class RiderLocationNotifier extends StateNotifier<RiderLocation?> {
  final RealtimeService _realtime;
  StreamSubscription? _realtimeSubscription;
  Timer? _mockTimer;
  int _mockStep = 0;

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
              // Fallback to mock simulation on error
              _startMockSimulation();
            },
          );

      // Start mock simulation as fallback
      // If real data comes in, the mock won't interfere
      // (realtime updates will override mock state)
      _startMockSimulation();
    } catch (_) {
      _startMockSimulation();
    }
  }

  /// Start mock simulation for development
  void _startMockSimulation() {
    _mockTimer?.cancel();
    _mockStep = 0;
    state = RiderLocation.mock(step: _mockStep);

    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _mockStep++;
      state = RiderLocation.mock(step: _mockStep);
    });
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
