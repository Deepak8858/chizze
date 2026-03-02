import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../features/orders/models/order.dart';
import '../models/partner_order.dart';
import '../services/order_notification_service.dart';

/// Connection status for realtime updates
enum RealtimeConnectionStatus {
  connected,
  polling,
  disconnected,
}

/// Partner dashboard state
class PartnerState {
  final bool isOnline;
  final PartnerMetrics metrics;
  final List<PartnerOrder> orders;
  final bool isLoading;
  final String? restaurantName;
  final String? restaurantImageUrl;
  final RealtimeConnectionStatus connectionStatus;
  final int unacknowledgedNewOrders;

  const PartnerState({
    this.isOnline = true,
    this.metrics = const PartnerMetrics(),
    this.orders = const [],
    this.isLoading = false,
    this.restaurantName,
    this.restaurantImageUrl,
    this.connectionStatus = RealtimeConnectionStatus.disconnected,
    this.unacknowledgedNewOrders = 0,
  });

  PartnerState copyWith({
    bool? isOnline,
    PartnerMetrics? metrics,
    List<PartnerOrder>? orders,
    bool? isLoading,
    String? restaurantName,
    String? restaurantImageUrl,
    RealtimeConnectionStatus? connectionStatus,
    int? unacknowledgedNewOrders,
  }) {
    return PartnerState(
      isOnline: isOnline ?? this.isOnline,
      metrics: metrics ?? this.metrics,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      restaurantName: restaurantName ?? this.restaurantName,
      restaurantImageUrl: restaurantImageUrl ?? this.restaurantImageUrl,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      unacknowledgedNewOrders:
          unacknowledgedNewOrders ?? this.unacknowledgedNewOrders,
    );
  }

  List<PartnerOrder> get newOrders => orders
      .where((o) => o.isNew && o.order.status == OrderStatus.placed)
      .toList();

  List<PartnerOrder> get preparingOrders =>
      orders.where((o) =>
          o.order.status == OrderStatus.confirmed ||
          o.order.status == OrderStatus.preparing).toList();

  List<PartnerOrder> get readyOrders =>
      orders.where((o) => o.order.status == OrderStatus.ready).toList();

  List<PartnerOrder> get completedOrders => orders
      .where(
        (o) =>
            o.order.status == OrderStatus.delivered ||
            o.order.status == OrderStatus.cancelled,
      )
      .toList();

  List<PartnerOrder> get activeOrders => orders
      .where(
        (o) =>
            o.order.status != OrderStatus.delivered &&
            o.order.status != OrderStatus.cancelled,
      )
      .toList();
}

/// Partner notifier — API-backed with Realtime + WebSocket + polling fallback + notifications
class PartnerNotifier extends StateNotifier<PartnerState> {
  final ApiClient _api;
  final RealtimeService _realtime;
  final WebSocketService _ws;
  final OrderNotificationService _notificationService;
  StreamSubscription? _realtimeSub;
  StreamSubscription? _wsSub;
  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  Set<String> _knownOrderIds = {};
  bool _realtimeConnected = false;
  bool _isLoadingGuard = false;
  bool _pendingReload = false; // queue a reload if one is skipped due to guard
  int _reconnectAttempts = 0;
  bool _disposed = false;

  PartnerNotifier(this._api, this._realtime, this._ws, this._notificationService)
      : super(const PartnerState()) {
    _initNotifications();
    _loadData();
    _subscribeToRealtime();
    _subscribeToWebSocket();
  }

  Future<void> _initNotifications() async {
    await _notificationService.initialize();
  }

  /// Listen for new/updated orders in real-time via Appwrite
  void _subscribeToRealtime() {
    try {
      final channel = RealtimeChannels.allOrdersChannel();
      _realtimeSub = _realtime.subscribe(channel).listen(
        (event) {
          _realtimeConnected = true;
          _reconnectAttempts = 0;
          _reconnectTimer?.cancel();
          state = state.copyWith(
            connectionStatus: RealtimeConnectionStatus.connected,
          );
          // Stop polling — realtime is working
          _stopPolling();

          if (event.type == RealtimeEventType.create) {
            // New order — refresh and notify
            _loadData(notifyNewOrders: true);
          } else if (event.type == RealtimeEventType.update) {
            // Order status changed — refresh silently
            _loadData(notifyNewOrders: false);
          }
        },
        onError: (_) {
          _realtimeConnected = false;
          _startPollingFallback();
          _scheduleRealtimeReconnect();
        },
        onDone: () {
          _realtimeConnected = false;
          _startPollingFallback();
          _scheduleRealtimeReconnect();
        },
      );

      // Also start polling as initial fallback — will be stopped once realtime connects
      Future.delayed(const Duration(seconds: 5), () {
        if (!_disposed && !_realtimeConnected) {
          _startPollingFallback();
        }
      });
    } catch (e) {
      debugPrint('[PartnerNotifier] Realtime subscribe error: $e');
      // Realtime not available — use polling only
      _startPollingFallback();
    }
  }

  /// Listen for order_update events via WebSocket (Go backend hub) as a
  /// redundant real-time channel. This ensures instant status updates even when
  /// Appwrite Realtime is slow or disconnected.
  void _subscribeToWebSocket() {
    try {
      _wsSub = _ws.orderUpdates.listen((event) {
        // An order status changed — reload data to refresh the dashboard.
        // The WS event is targeted at the restaurant owner by the backend.
        _loadData(notifyNewOrders: false);
      });
    } catch (e) {
      debugPrint('[PartnerNotifier] WS subscribe error: $e');
    }
  }

  /// Polling fallback: fetch orders every 15 seconds when Realtime is down
  void _startPollingFallback() {
    if (_pollingTimer?.isActive == true) return; // Already polling
    debugPrint('[PartnerNotifier] Starting polling fallback (15s interval)');
    state = state.copyWith(
      connectionStatus: RealtimeConnectionStatus.polling,
    );
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadData(notifyNewOrders: true);
    });
  }

  void _stopPolling() {
    if (_pollingTimer?.isActive == true) {
      debugPrint('[PartnerNotifier] Stopping polling — realtime connected');
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  /// Attempt to re-subscribe to Realtime with exponential backoff
  void _scheduleRealtimeReconnect() {
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= 5) {
      debugPrint('[PartnerNotifier] Max reconnect attempts reached, staying on polling');
      return;
    }
    final delay = Duration(seconds: 10 * (1 << _reconnectAttempts)); // 10s, 20s, 40s, 80s, 160s
    debugPrint('[PartnerNotifier] Scheduling realtime reconnect in ${delay.inSeconds}s (attempt ${_reconnectAttempts + 1})');
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _realtimeSub?.cancel();
      _subscribeToRealtime();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeSub?.cancel();
    _wsSub?.cancel();
    _pollingTimer?.cancel();
    _reconnectTimer?.cancel();
    _notificationService.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool notifyNewOrders = false}) async {
    if (_isLoadingGuard) {
      // A load is already in progress — queue a reload so we don't drop
      // realtime events that arrive during the current fetch.
      _pendingReload = true;
      return;
    }
    _isLoadingGuard = true;
    _pendingReload = false;
    state = state.copyWith(isLoading: true);
    try {
      // Fetch dashboard metrics + active orders in parallel
      final results = await Future.wait([
        _api.get(ApiConfig.partnerDashboard),
        _api.get(ApiConfig.partnerOrders, queryParams: {'per_page': 50}),
      ]);

      final dashboardResponse = results[0];
      final ordersResponse = results[1];

      // Parse dashboard independently
      PartnerMetrics metrics = state.metrics;
      bool isOnline = state.isOnline;
      String? restaurantName = state.restaurantName;
      String? restaurantImageUrl = state.restaurantImageUrl;

      if (dashboardResponse.success && dashboardResponse.data != null) {
        final d = dashboardResponse.data;
        if (d is Map<String, dynamic>) {
          metrics = PartnerMetrics(
            todayRevenue: (d['today_revenue'] ?? 0).toDouble(),
            todayOrders: d['today_orders'] ?? 0,
            avgRating: (d['avg_rating'] ?? 0).toDouble(),
            pendingOrders: d['pending_orders'] ?? 0,
          );
          isOnline = d['is_online'] ?? true;
          restaurantName = d['restaurant_name'] as String?;
          restaurantImageUrl = d['restaurant_image_url'] as String?;
        }
      }

      // Parse orders independently (even if dashboard fails)
      List<PartnerOrder> orders = state.orders;
      if (ordersResponse.success && ordersResponse.data != null) {
        orders = _parseOrders(ordersResponse.data);
      }

      // Detect genuinely new orders for notification
      if (notifyNewOrders && _knownOrderIds.isNotEmpty) {
        final currentIds = orders.map((o) => o.order.id).toSet();
        final brandNewIds = currentIds.difference(_knownOrderIds);
        for (final newId in brandNewIds) {
          final newOrder = orders.firstWhere((o) => o.order.id == newId);
          if (newOrder.isNew) {
            _notifyNewOrder(newOrder);
          }
        }
      }

      // Update known order IDs
      _knownOrderIds = orders.map((o) => o.order.id).toSet();

      // Count unacknowledged new orders
      final newCount = orders
          .where((o) => o.isNew && o.order.status == OrderStatus.placed)
          .length;

      // Manage repeated alert for unattended new orders
      if (newCount > 0) {
        _notificationService.startRepeatedAlert();
      } else {
        _notificationService.stopRepeatedAlert();
      }

      state = state.copyWith(
        metrics: metrics,
        orders: orders,
        isOnline: isOnline,
        restaurantName: restaurantName,
        restaurantImageUrl: restaurantImageUrl,
        isLoading: false,
        unacknowledgedNewOrders: newCount,
      );
    } catch (e) {
      debugPrint('[PartnerNotifier] _loadData error: $e');
      // On error, preserve existing data but stop loading
      state = state.copyWith(isLoading: false);
    } finally {
      _isLoadingGuard = false;
      // If a reload was requested while we were loading, do it now
      if (_pendingReload) {
        _pendingReload = false;
        _loadData(notifyNewOrders: notifyNewOrders);
      }
    }
  }

  /// Send notification for a newly detected order
  void _notifyNewOrder(PartnerOrder po) {
    final order = po.order;
    final itemsSummary =
        order.items.map((i) => '${i.name} × ${i.quantity}').join(', ');
    _notificationService.playNewOrderAlert(
      orderNumber: order.orderNumber,
      itemsSummary: itemsSummary,
      amount: order.grandTotal,
    );
  }

  /// Parse orders from API response
  List<PartnerOrder> _parseOrders(dynamic data) {
    if (data is! List) return [];
    return data.map<PartnerOrder>((item) {
      final map = Map<String, dynamic>.from(item as Map<String, dynamic>);

      // Parse items JSON if stored as string
      if (map['items'] is String) {
        try {
          map['items'] = jsonDecode(map['items'] as String);
        } catch (e) {
          debugPrint('[Partner] items JSON parse error: $e');
          map['items'] = [];
        }
      }

      final order = Order.fromMap(map);
      final isNew = map['is_new'] == true;
      final deadlineStr = map['accept_deadline'] as String?;
      DateTime? deadline;
      if (deadlineStr != null) {
        deadline = DateTime.tryParse(deadlineStr);
      }
      return PartnerOrder(
        order: order,
        acceptDeadline: deadline,
        isNew: isNew,
      );
    }).toList();
  }

  /// Refresh data from API
  Future<void> refresh() => _loadData(notifyNewOrders: true);

  /// Acknowledge new orders — clears badge count
  void acknowledgeNewOrders() {
    _notificationService.stopRepeatedAlert();
    state = state.copyWith(unacknowledgedNewOrders: 0);
  }

  /// Update restaurant image URL
  Future<bool> updateRestaurantImage(String imageUrl) async {
    final oldUrl = state.restaurantImageUrl;
    state = state.copyWith(restaurantImageUrl: imageUrl);
    try {
      final res = await _api.put(
        ApiConfig.partnerRestaurant,
        body: {'restaurant_image_url': imageUrl},
      );
      if (!res.success) {
        state = state.copyWith(restaurantImageUrl: oldUrl);
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[PartnerNotifier] updateRestaurantImage error: $e');
      state = state.copyWith(restaurantImageUrl: oldUrl);
      return false;
    }
  }

  /// Toggle restaurant online/offline
  Future<void> toggleOnline() async {
    final newState = !state.isOnline;
    state = state.copyWith(isOnline: newState);
    try {
      await _api.put(
        ApiConfig.partnerRestaurantStatus,
        body: {'is_online': newState},
      );
    } catch (e) {
      debugPrint('[PartnerNotifier] toggleOnline error: $e');
      // Revert on failure
      state = state.copyWith(isOnline: !newState);
    }
  }

  /// Accept an order with haptic feedback
  void acceptOrder(String orderId) {
    OrderNotificationService.hapticConfirm();
    final previousOrders = List<PartnerOrder>.from(state.orders);
    final updatedOrders = state.orders.map((po) {
      if (po.order.id == orderId) {
        return po.copyWith(
          order: po.order.copyWith(
            status: OrderStatus.confirmed,
            confirmedAt: DateTime.now(),
          ),
          isNew: false,
        );
      }
      return po;
    }).toList();
    state = state.copyWith(orders: updatedOrders);

    // Push status update to API with rollback on failure
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'confirmed'},
        )
        .catchError((e) {
          debugPrint('[PartnerNotifier] acceptOrder error: $e');
          state = state.copyWith(orders: previousOrders);
          return ApiResponse<dynamic>(success: false);
        });
  }

  /// Reject an order with haptic feedback
  void rejectOrder(String orderId, String reason) {
    OrderNotificationService.hapticReject();
    final previousOrders = List<PartnerOrder>.from(state.orders);
    final updatedOrders = state.orders
        .where((po) => po.order.id != orderId)
        .toList();
    state = state.copyWith(orders: updatedOrders);

    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'cancelled', 'reason': reason},
        )
        .catchError((e) {
          debugPrint('[PartnerNotifier] rejectOrder error: $e');
          state = state.copyWith(orders: previousOrders);
          return ApiResponse<dynamic>(success: false);
        });
  }

  /// Mark order as preparing
  void markPreparing(String orderId) {
    final previousOrders = List<PartnerOrder>.from(state.orders);
    _updateOrderStatus(orderId, OrderStatus.preparing);
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'preparing'},
        )
        .catchError((e) {
          debugPrint('[PartnerNotifier] markPreparing error: $e');
          state = state.copyWith(orders: previousOrders);
          return ApiResponse<dynamic>(success: false);
        });
  }

  /// Mark order as ready for pickup
  void markReady(String orderId) {
    final previousOrders = List<PartnerOrder>.from(state.orders);
    _updateOrderStatus(orderId, OrderStatus.ready);
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'ready'},
        )
        .catchError((e) {
          debugPrint('[PartnerNotifier] markReady error: $e');
          state = state.copyWith(orders: previousOrders);
          return ApiResponse<dynamic>(success: false);
        });
  }

  void _updateOrderStatus(String orderId, OrderStatus status) {
    final updatedOrders = state.orders.map((po) {
      if (po.order.id == orderId) {
        return po.copyWith(
          order: po.order.copyWith(
            status: status,
            preparedAt: status == OrderStatus.ready ? DateTime.now() : null,
          ),
          isNew: false,
        );
      }
      return po;
    }).toList();
    state = state.copyWith(orders: updatedOrders);
  }
}

/// Partner provider
final partnerProvider = StateNotifierProvider<PartnerNotifier, PartnerState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  final realtime = ref.watch(realtimeServiceProvider);
  final ws = ref.watch(webSocketServiceProvider);
  final notificationService = OrderNotificationService();
  return PartnerNotifier(api, realtime, ws, notificationService);
});
