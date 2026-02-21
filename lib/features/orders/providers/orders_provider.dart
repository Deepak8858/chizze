import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/realtime_service.dart';
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
  StreamSubscription? _realtimeSub;

  OrdersNotifier(this._api, this._realtime) : super(const OrdersState()) {
    fetchOrders();
    _subscribeToRealtimeUpdates();
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

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Fetch orders from API, fallback to mock data
  Future<void> fetchOrders() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiConfig.orders);
      if (response.success && response.data != null) {
        // Parse orders from API response
        final ordersData = response.data as List<dynamic>;
        final orders = ordersData.map((d) {
          final m = d as Map<String, dynamic>;
          return Order(
            id: m['\$id'] ?? '',
            orderNumber: m['order_number'] ?? '',
            customerId: m['customer_id'] ?? '',
            restaurantId: m['restaurant_id'] ?? '',
            restaurantName: m['restaurant_name'] ?? '',
            deliveryAddressId: m['delivery_address_id'] ?? '',
            items: ((m['items'] ?? []) as List).map((i) {
              final item = i as Map<String, dynamic>;
              return OrderItem(
                id: item['id'] ?? '',
                name: item['name'] ?? '',
                quantity: item['quantity'] ?? 1,
                price: (item['price'] ?? 0).toDouble(),
                isVeg: item['is_veg'] ?? false,
              );
            }).toList(),
            itemTotal: (m['item_total'] ?? 0).toDouble(),
            deliveryFee: (m['delivery_fee'] ?? 0).toDouble(),
            platformFee: (m['platform_fee'] ?? 0).toDouble(),
            gst: (m['gst'] ?? 0).toDouble(),
            discount: (m['discount'] ?? 0).toDouble(),
            couponCode: m['coupon_code'],
            grandTotal: (m['grand_total'] ?? 0).toDouble(),
            paymentMethod: m['payment_method'] ?? 'razorpay',
            paymentStatus: m['payment_status'] ?? 'pending',
            paymentId: m['payment_id'],
            status: OrderStatus.fromString(m['status'] ?? 'placed'),
            specialInstructions: m['special_instructions'] ?? '',
            deliveryInstructions: m['delivery_instructions'] ?? '',
            estimatedDeliveryMin: m['estimated_delivery_min'] ?? 35,
            placedAt: DateTime.tryParse(m['placed_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
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
}

/// Global orders provider
final ordersProvider = StateNotifierProvider<OrdersNotifier, OrdersState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  final realtime = ref.watch(realtimeServiceProvider);
  return OrdersNotifier(api, realtime);
});
