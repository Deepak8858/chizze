import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Orders notifier
class OrdersNotifier extends StateNotifier<OrdersState> {
  OrdersNotifier() : super(const OrdersState()) {
    _loadMockOrders();
  }

  void _loadMockOrders() {
    state = state.copyWith(orders: Order.mockList);
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
  return OrdersNotifier();
});
