import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/services/websocket_service.dart';
import '../models/order.dart';

/// Orders state
class OrdersState {
  final List<Order> orders;
  final bool isLoading;
  final String? error;

  const OrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.error,
  });

  OrdersState copyWith({List<Order>? orders, bool? isLoading, String? error}) {
    return OrdersState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<Order> get activeOrders =>
      orders.where((o) => o.status.isActive).toList();

  List<Order> get pastOrders =>
      orders.where((o) => !o.status.isActive).toList();
}

/// Orders notifier — fetches from API with mock fallback + Realtime updates
class OrdersNotifier extends StateNotifier<OrdersState> {
  final ApiClient _api;
  final RealtimeService _realtime;
  final WebSocketService _ws;
  StreamSubscription? _realtimeSub;
  StreamSubscription? _wsSub;

  OrdersNotifier(this._api, this._realtime, this._ws)
      : super(const OrdersState()) {
    fetchOrders();
    _subscribeToRealtimeUpdates();
    _subscribeToWsUpdates();
  }

  /// Listen for real-time order status changes from Appwrite
  void _subscribeToRealtimeUpdates() {
    try {
      final channel = RealtimeChannels.allOrdersChannel();
      _realtimeSub = _realtime.subscribe(channel).listen((event) {
        if (event.type == RealtimeEventType.update) {
          final data = event.data;
          final orderId = event.documentId;
          final newStatus = OrderStatus.fromString(data['status'] ?? 'placed');
          updateOrderStatus(orderId, newStatus);
        } else if (event.type == RealtimeEventType.create) {
          // New order placed — refresh list
          fetchOrders();
        }
      });
    } catch (_) {
      // Realtime not available — rely on polling/manual refresh
    }
  }

  /// Listen for WebSocket order_update events from Go backend
  void _subscribeToWsUpdates() {
    _wsSub = _ws.orderUpdates.listen((event) {
      final orderId = event.orderId;
      final statusStr = event.status;
      if (orderId != null && statusStr != null) {
        final newStatus = OrderStatus.fromString(statusStr);
        updateOrderStatus(orderId, newStatus);
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  /// Fetch orders from API, fallback to mock data
  Future<void> fetchOrders() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiConfig.orders);
      if (response.success && response.data != null) {
        // Parse orders from API response using Order.fromMap for full field coverage
        final ordersData = response.data as List<dynamic>;
        final orders = ordersData
            .map((d) => Order.fromMap(d as Map<String, dynamic>))
            .toList();
        state = state.copyWith(orders: orders, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false, error: response.error);
      }
    } on ApiException catch (e) {
      // No mock fallback — show the real error to the user
      state = state.copyWith(
        orders: [],
        isLoading: false,
        error: e.statusCode != 0 ? e.message : 'Unable to connect to server',
      );
    } catch (e) {
      state = state.copyWith(
        orders: [],
        isLoading: false,
        error: 'Failed to load orders',
      );
    }
  }

  /// Add a new order (after payment success)
  void addOrder(Order order) {
    state = state.copyWith(orders: [order, ...state.orders]);
  }

  /// Update order status (from Appwrite Realtime)
  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final updatedOrders = state.orders.map((order) {
      if (order.id == orderId) {
        return order.copyWith(
          status: newStatus,
          confirmedAt: newStatus == OrderStatus.confirmed
              ? DateTime.now()
              : null,
          preparedAt: newStatus == OrderStatus.ready ? DateTime.now() : null,
          pickedUpAt: newStatus == OrderStatus.pickedUp ? DateTime.now() : null,
          deliveredAt: newStatus == OrderStatus.delivered
              ? DateTime.now()
              : null,
        );
      }
      return order;
    }).toList();

    state = state.copyWith(orders: updatedOrders);
  }

  /// Get specific order by ID
  Order? getOrder(String orderId) {
    try {
      return state.orders.firstWhere((o) => o.id == orderId);
    } catch (_) {
      return null;
    }
  }

  /// Fetch a single order by ID from the API and merge into local state.
  /// Used as fallback when the order isn't in the provider yet.
  Future<Order?> fetchOrderById(String orderId) async {
    try {
      final response = await _api.get('${ApiConfig.orders}/$orderId');
      if (response.success && response.data != null) {
        final order = Order.fromMap(response.data as Map<String, dynamic>);
        // Merge into existing list (replace if exists, or prepend)
        final existing = state.orders.indexWhere((o) => o.id == orderId);
        final updatedOrders = [...state.orders];
        if (existing >= 0) {
          updatedOrders[existing] = order;
        } else {
          updatedOrders.insert(0, order);
        }
        state = state.copyWith(orders: updatedOrders);
        return order;
      }
    } catch (_) {
      // Silently fail — caller can handle null
    }
    return null;
  }
}

/// Global orders provider
final ordersProvider = StateNotifierProvider<OrdersNotifier, OrdersState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  final realtime = ref.watch(realtimeServiceProvider);
  final ws = ref.watch(webSocketServiceProvider);
  return OrdersNotifier(api, realtime, ws);
});
