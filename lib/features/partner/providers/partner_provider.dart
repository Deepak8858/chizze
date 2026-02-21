import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/realtime_service.dart';
import '../../../features/orders/models/order.dart';
import '../models/partner_order.dart';

/// Partner dashboard state
class PartnerState {
  final bool isOnline;
  final PartnerMetrics metrics;
  final List<PartnerOrder> orders;
  final bool isLoading;
  final String? restaurantName;

  const PartnerState({
    this.isOnline = true,
    this.metrics = const PartnerMetrics(),
    this.orders = const [],
    this.isLoading = false,
    this.restaurantName,
  });

  PartnerState copyWith({
    bool? isOnline,
    PartnerMetrics? metrics,
    List<PartnerOrder>? orders,
    bool? isLoading,
    String? restaurantName,
  }) {
    return PartnerState(
      isOnline: isOnline ?? this.isOnline,
      metrics: metrics ?? this.metrics,
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      restaurantName: restaurantName ?? this.restaurantName,
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

/// Partner notifier — API-backed with mock fallback + Realtime
class PartnerNotifier extends StateNotifier<PartnerState> {
  final ApiClient _api;
  final RealtimeService _realtime;
  StreamSubscription? _realtimeSub;

  PartnerNotifier(this._api, this._realtime) : super(const PartnerState()) {
    _loadData();
    _subscribeToRealtime();
  }

  /// Listen for new/updated orders in real-time
  void _subscribeToRealtime() {
    try {
      final channel = RealtimeChannels.allOrdersChannel();
      _realtimeSub = _realtime.subscribe(channel).listen((event) {
        if (event.type == RealtimeEventType.create ||
            event.type == RealtimeEventType.update) {
          // Refresh orders when any order changes
          refresh();
        }
      });
    } catch (_) {} // Realtime not available
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      // Fetch dashboard metrics + active orders in parallel
      final results = await Future.wait([
        _api.get(ApiConfig.partnerDashboard),
        _api.get(ApiConfig.partnerOrders, queryParams: {'per_page': 50}),
      ]);

      final dashboardResponse = results[0];
      final ordersResponse = results[1];

      if (dashboardResponse.success && dashboardResponse.data != null) {
        final d = dashboardResponse.data as Map<String, dynamic>;
        final metrics = PartnerMetrics(
          todayRevenue: (d['today_revenue'] ?? 0).toDouble(),
          todayOrders: d['today_orders'] ?? 0,
          avgRating: (d['avg_rating'] ?? 0).toDouble(),
          pendingOrders: d['pending_orders'] ?? 0,
        );

        final isOnline = d['is_online'] ?? true;
        final restaurantName = d['restaurant_name'] as String?;

        List<PartnerOrder> orders = [];
        if (ordersResponse.success && ordersResponse.data != null) {
          orders = _parseOrders(ordersResponse.data);
        }

        state = state.copyWith(
          metrics: metrics,
          orders: orders,
          isOnline: isOnline,
          restaurantName: restaurantName,
          isLoading: false,
        );
        return;
      }
    } catch (_) {}

    // Fallback to mock data
    state = state.copyWith(
      metrics: PartnerMetrics.mock,
      orders: PartnerOrder.mockList,
      isLoading: false,
    );
  }

  /// Parse orders from API response
  List<PartnerOrder> _parseOrders(dynamic data) {
    if (data is! List) return [];
    return data.map<PartnerOrder>((item) {
      final map = item as Map<String, dynamic>;

      // Parse items JSON if stored as string
      if (map['items'] is String) {
        try {
          map['items'] = jsonDecode(map['items'] as String);
        } catch (_) {
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
  Future<void> refresh() => _loadData();

  /// Toggle restaurant online/offline
  Future<void> toggleOnline() async {
    final newState = !state.isOnline;
    state = state.copyWith(isOnline: newState);
    try {
      await _api.put(
        ApiConfig.partnerRestaurantStatus,
        body: {'is_online': newState},
      );
    } catch (_) {
      // Revert on failure
      state = state.copyWith(isOnline: !newState);
    }
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

    // Push status update to API
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'confirmed'},
        )
        .ignore();
  }

  /// Reject an order
  void rejectOrder(String orderId, String reason) {
    final updatedOrders = state.orders
        .where((po) => po.order.id != orderId)
        .toList();
    state = state.copyWith(orders: updatedOrders);

    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'cancelled', 'reason': reason},
        )
        .ignore();
  }

  /// Mark order as preparing
  void markPreparing(String orderId) {
    _updateOrderStatus(orderId, OrderStatus.preparing);
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'preparing'},
        )
        .ignore();
  }

  /// Mark order as ready for pickup
  void markReady(String orderId) {
    _updateOrderStatus(orderId, OrderStatus.ready);
    _api
        .put(
          '${ApiConfig.partnerOrders}/$orderId/status',
          body: {'status': 'ready'},
        )
        .ignore();
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
  return PartnerNotifier(api, realtime);
});
