import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/orders/models/order.dart';
import '../models/partner_order.dart';

/// Partner dashboard state
class PartnerState {
  final bool isOnline;
  final PartnerMetrics metrics;
  final List<PartnerOrder> orders;
  final bool isLoading;

  const PartnerState({
    this.isOnline = true,
    this.metrics = const PartnerMetrics(),
    this.orders = const [],
    this.isLoading = false,
  });

  PartnerState copyWith({
    bool? isOnline,
    PartnerMetrics? metrics,
    List<PartnerOrder>? orders,
    bool? isLoading,
  }) {
    return PartnerState(
      isOnline: isOnline ?? this.isOnline,
      metrics: metrics ?? this.metrics,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<PartnerOrder> get newOrders => orders
      .where((o) => o.isNew && o.order.status == OrderStatus.placed)
      .toList();

  List<PartnerOrder> get preparingOrders =>
      orders.where((o) => o.order.status == OrderStatus.preparing).toList();

  List<PartnerOrder> get readyOrders =>
      orders.where((o) => o.order.status == OrderStatus.ready).toList();

  List<PartnerOrder> get completedOrders => orders
      .where(
        (o) =>
            o.order.status == OrderStatus.delivered ||
            o.order.status == OrderStatus.pickedUp ||
            o.order.status == OrderStatus.outForDelivery,
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

/// Partner notifier
class PartnerNotifier extends StateNotifier<PartnerState> {
  PartnerNotifier() : super(const PartnerState()) {
    _loadMockData();
  }

  void _loadMockData() {
    state = state.copyWith(
      metrics: PartnerMetrics.mock,
      orders: PartnerOrder.mockList,
    );
  }

  /// Toggle restaurant online/offline
  void toggleOnline() {
    state = state.copyWith(isOnline: !state.isOnline);
  }

  /// Accept an order
  void acceptOrder(String orderId) {
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
  }

  /// Reject an order
  void rejectOrder(String orderId, String reason) {
    final updatedOrders = state.orders
        .where((po) => po.order.id != orderId)
        .toList();
    state = state.copyWith(orders: updatedOrders);
  }

  /// Mark order as preparing
  void markPreparing(String orderId) {
    _updateOrderStatus(orderId, OrderStatus.preparing);
  }

  /// Mark order as ready for pickup
  void markReady(String orderId) {
    _updateOrderStatus(orderId, OrderStatus.ready);
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
  return PartnerNotifier();
});
