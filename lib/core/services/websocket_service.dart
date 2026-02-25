import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/environment.dart';
import '../auth/auth_provider.dart';
import 'api_client.dart';

// ─── WebSocket Event Types (mirror Go backend events.go) ───

enum WsEventType {
  orderUpdate,
  deliveryRequest,
  deliveryLocation,
  newOrder,
  notification,
  riderStatusChange,
  restaurantUpdate,
  unknown;

  static WsEventType fromString(String s) {
    switch (s) {
      case 'order_update':
        return orderUpdate;
      case 'delivery_request':
        return deliveryRequest;
      case 'delivery_location':
        return deliveryLocation;
      case 'new_order':
        return newOrder;
      case 'notification':
        return notification;
      case 'rider_status_change':
        return riderStatusChange;
      case 'restaurant_update':
        return restaurantUpdate;
      default:
        return unknown;
    }
  }
}

/// Parsed WebSocket event from the Go backend
class WsEvent {
  final WsEventType type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const WsEvent({
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    return WsEvent(
      type: WsEventType.fromString(json['type'] ?? ''),
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      timestamp:
          DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }

  /// Convenience accessors for common payload fields
  String? get orderId => payload['order_id'] as String?;
  String? get status => payload['status'] as String?;
  String? get message => payload['message'] as String?;
  double? get latitude => (payload['lat'] as num?)?.toDouble();
  double? get longitude => (payload['lng'] as num?)?.toDouble();
  double? get bearing => (payload['bearing'] as num?)?.toDouble();
  double? get speed => (payload['speed'] as num?)?.toDouble();
}

// ─── Connection state ───

enum WsConnectionState { disconnected, connecting, connected }

/// WebSocket service — persistent connection to Go backend /ws endpoint
/// with auto-reconnect, exponential backoff, and typed event streams.
class WebSocketService {
  final ApiClient _apiClient;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectDelay = Duration(seconds: 30);

  // State
  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _state;

  // Event broadcast
  final _eventController = StreamController<WsEvent>.broadcast();
  final _stateController = StreamController<WsConnectionState>.broadcast();

  /// Stream of all incoming WebSocket events
  Stream<WsEvent> get events => _eventController.stream;

  /// Stream of connection state changes
  Stream<WsConnectionState> get stateChanges => _stateController.stream;

  /// Filtered streams by event type
  Stream<WsEvent> get orderUpdates =>
      events.where((e) => e.type == WsEventType.orderUpdate);

  Stream<WsEvent> get deliveryLocations =>
      events.where((e) => e.type == WsEventType.deliveryLocation);

  Stream<WsEvent> get deliveryRequests =>
      events.where((e) => e.type == WsEventType.deliveryRequest);

  Stream<WsEvent> get newOrders =>
      events.where((e) => e.type == WsEventType.newOrder);

  Stream<WsEvent> get notifications =>
      events.where((e) => e.type == WsEventType.notification);

  WebSocketService(this._apiClient);

  /// Derive the WebSocket URL from the REST API URL
  Uri _wsUri(String token) {
    final base = Environment.apiBaseUrl;
    final uri = Uri.parse(base);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: port,
      path: '${uri.path}/ws',
      queryParameters: {'token': token},
    );
  }

  /// Connect to the WebSocket endpoint (requires auth token)
  void connect() {
    final token = _apiClient.currentToken;
    if (token == null || token.isEmpty) {
      debugPrint('[WS] No auth token — skipping connect');
      return;
    }
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      return;
    }

    _setState(WsConnectionState.connecting);
    final wsUrl = _wsUri(token);
    debugPrint('[WS] Connecting to ${wsUrl.toString().replaceAll(RegExp(r'token=[^&]+'), 'token=***')}');

    try {
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _setState(WsConnectionState.connected);
      _startHeartbeat();
      debugPrint('[WS] Connected');
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Disconnect cleanly
  void disconnect() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
    _reconnectAttempts = 0;
    debugPrint('[WS] Disconnected');
  }

  /// Send a JSON message to the server
  void send(Map<String, dynamic> message) {
    if (_state != WsConnectionState.connected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      debugPrint('[WS] Send error: $e');
    }
  }

  // ─── Internal ───

  void _onMessage(dynamic raw) {
    _reconnectAttempts = 0; // Connection confirmed working
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final event = WsEvent.fromJson(json);
      if (!_eventController.isClosed) {
        _eventController.add(event);
      }
    } catch (e) {
      debugPrint('[WS] Parse error: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[WS] Error: $error');
    _setState(WsConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WS] Connection closed');
    _heartbeatTimer?.cancel();
    if (_state != WsConnectionState.disconnected) {
      _setState(WsConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _setState(WsConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Exponential backoff reconnect: 1s, 2s, 4s, 8s, ... max 30s
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(
      seconds: (1 << _reconnectAttempts).clamp(1, _maxReconnectDelay.inSeconds),
    );
    _reconnectAttempts++;
    debugPrint('[WS] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, connect);
  }

  /// Send periodic pings to keep the connection alive (server expects pongs)
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      send({'type': 'ping'});
    });
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _eventController.close();
    _stateController.close();
  }
}

// ─── Riverpod Provider ───

/// Global WebSocket service provider
final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = WebSocketService(apiClient);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for all WebSocket events
final wsEventsProvider = StreamProvider<WsEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.events;
});

/// Stream provider for order updates only
final wsOrderUpdatesProvider = StreamProvider<WsEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.orderUpdates;
});

/// Stream provider for delivery location updates
final wsDeliveryLocationProvider = StreamProvider<WsEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.deliveryLocations;
});

/// Stream provider for notification events
final wsNotificationsProvider = StreamProvider<WsEvent>((ref) {
  final ws = ref.watch(webSocketServiceProvider);
  return ws.notifications;
});

/// Auto-connect provider — watches auth state and connects/disconnects WS.
/// Must be watched once (e.g. in the root widget) to activate.
final wsAutoConnectProvider = Provider<void>((ref) {
  final authState = ref.watch(authProvider);
  final ws = ref.read(webSocketServiceProvider);

  if (authState.isAuthenticated) {
    ws.connect();
  } else if (authState.status == AuthStatus.unauthenticated) {
    ws.disconnect();
  }
});
