import 'dart:async';
import 'package:flutter/foundation.dart';
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

/// Orders notifier — API-backed with Realtime updates
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
      _realtimeSub = _realtime
          .subscribe(channel)
          .listen(
            (event) {
              if (event.type == RealtimeEventType.update) {
                final data = event.data;
                final orderId = event.documentId;
                // Use tryFromString to avoid reverting status to 'placed'
                // when Appwrite sends an update with an unrecognised or null status.
                final statusStr = data['status'] as String?;
                if (statusStr == null) return;
                final newStatus = OrderStatus.tryFromString(statusStr);
                if (newStatus == null) return;

                updateOrderStatus(
                  orderId,
                  newStatus,
                  deliveryPartnerId: data['delivery_partner_id'] as String?,
                  deliveryPartnerName: data['delivery_partner_name'] as String?,
                  deliveryPartnerPhone:
                      data['delivery_partner_phone'] as String?,
                );
              } else if (event.type == RealtimeEventType.create) {
                // New order placed — refresh list
                fetchOrders();
              }
            },
            onError: (error, stack) {
              debugPrint('[Orders] realtime stream error: $error');
              _realtimeSub?.cancel();
              _realtimeSub = null;
            },
            onDone: () {
              _realtimeSub?.cancel();
              _realtimeSub = null;
            },
          );
    } catch (e) {
      // Realtime not available — rely on polling/manual refresh
      debugPrint('[Orders] realtime subscription error: $e');
    }
  }

  /// Listen for WebSocket order_update events from Go backend
  void _subscribeToWsUpdates() {
    _wsSub = _ws.orderUpdates.listen(
      (event) {
        final orderId = event.orderId;
        final statusStr = event.status;
        if (orderId != null && statusStr != null) {
          // Only process known order statuses — unknown values (e.g. "rider_assigned")
          // would fall back to OrderStatus.placed and incorrectly revert the order status.
          final newStatus = OrderStatus.tryFromString(statusStr);
          if (newStatus != null) {
            updateOrderStatus(
              orderId,
              newStatus,
              deliveryPartnerId:
                  event.payload['delivery_partner_id'] as String?,
              deliveryPartnerName:
                  event.payload['delivery_partner_name'] as String?,
              deliveryPartnerPhone:
                  event.payload['delivery_partner_phone'] as String?,
            );
          }
        }
      },
      onError: (error, stack) {
        debugPrint('[Orders] WebSocket stream error: $error');
        _wsSub?.cancel();
        _wsSub = null;
      },
      onDone: () {
        _wsSub?.cancel();
        _wsSub = null;
      },
    );
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  /// Fetch orders from API.
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
      // Show the real error to the user
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

  /// Update order status (from Appwrite Realtime or WebSocket)
  void updateOrderStatus(
    String orderId,
    OrderStatus newStatus, {
    String? deliveryPartnerId,
    String? deliveryPartnerName,
    String? deliveryPartnerPhone,
  }) {
    final updatedOrders = state.orders.map((order) {
      if (order.id == orderId) {
        return order.copyWith(
          status: newStatus,
          deliveryPartnerId:
              deliveryPartnerId ?? order.deliveryPartnerId,
          deliveryPartnerName:
              deliveryPartnerName ?? order.deliveryPartnerName,
          deliveryPartnerPhone:
              deliveryPartnerPhone ?? order.deliveryPartnerPhone,
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
    } catch (e) {
      debugPrint('[Orders] fetchOrderById error: $e');
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
