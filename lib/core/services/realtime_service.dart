import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appwrite_service.dart';

/// Appwrite collection/database IDs for realtime subscriptions
class RealtimeChannels {
  static const String databaseId = 'chizze_db';

  // Collection IDs
  static const String orders = 'orders';
  static const String notifications = 'notifications';
  static const String deliveryRequests = 'delivery_requests';
  static const String riderLocations = 'rider_locations';

  // Channel strings for Appwrite Realtime
  static String orderChannel(String orderId) =>
      'databases.$databaseId.collections.$orders.documents.$orderId';

  static String allOrdersChannel() =>
      'databases.$databaseId.collections.$orders.documents';

  static String notificationsChannel() =>
      'databases.$databaseId.collections.$notifications.documents';

  static String deliveryRequestsChannel() =>
      'databases.$databaseId.collections.$deliveryRequests.documents';

  static String riderLocationChannel(String riderId) =>
      'databases.$databaseId.collections.$riderLocations.documents.$riderId';
}

/// Realtime event types from Appwrite
enum RealtimeEventType {
  create,
  update,
  delete,
  unknown;

  static RealtimeEventType fromEvent(String event) {
    if (event.contains('.create')) return RealtimeEventType.create;
    if (event.contains('.update')) return RealtimeEventType.update;
    if (event.contains('.delete')) return RealtimeEventType.delete;
    return RealtimeEventType.unknown;
  }
}

/// Parsed realtime event
class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> data;
  final String documentId;
  final String collectionId;

  const RealtimeEvent({
    required this.type,
    required this.data,
    required this.documentId,
    required this.collectionId,
  });

  factory RealtimeEvent.fromMessage(RealtimeMessage message) {
    final payload = message.payload;
    final events = message.events;
    final eventType = events.isNotEmpty
        ? RealtimeEventType.fromEvent(events.first)
        : RealtimeEventType.unknown;

    return RealtimeEvent(
      type: eventType,
      data: payload,
      documentId: payload['\$id'] ?? '',
      collectionId: payload['\$collectionId'] ?? '',
    );
  }
}

/// Realtime service — manages Appwrite Realtime subscriptions
class RealtimeService {
  final Realtime _realtime;
  final Map<String, RealtimeSubscription> _subscriptions = {};
  final Map<String, StreamController<RealtimeEvent>> _controllers = {};

  RealtimeService(this._realtime);

  /// Subscribe to a channel and get a stream of events
  Stream<RealtimeEvent> subscribe(String channel) {
    // Return existing stream if already subscribed
    if (_controllers.containsKey(channel)) {
      return _controllers[channel]!.stream;
    }

    final controller = StreamController<RealtimeEvent>.broadcast();
    _controllers[channel] = controller;

    final subscription = _realtime.subscribe([channel]);
    _subscriptions[channel] = subscription;

    subscription.stream.listen(
      (message) {
        if (!controller.isClosed) {
          controller.add(RealtimeEvent.fromMessage(message));
        }
      },
      onError: (error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
    );

    return controller.stream;
  }

  /// Unsubscribe from a specific channel
  void unsubscribe(String channel) {
    _subscriptions[channel]?.close();
    _subscriptions.remove(channel);
    _controllers[channel]?.close();
    _controllers.remove(channel);
  }

  /// Unsubscribe from all channels
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.close();
    }
    _subscriptions.clear();
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

/// Realtime service provider
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final realtime = ref.watch(appwriteRealtimeProvider);
  final service = RealtimeService(realtime);
  ref.onDispose(() => service.dispose());
  return service;
});
