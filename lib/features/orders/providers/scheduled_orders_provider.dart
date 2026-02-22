import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Scheduled order model
class ScheduledOrder {
  final String id;
  final String restaurantId;
  final String restaurantName;
  final DateTime scheduledTime;
  final String status; // pending, confirmed, cancelled
  final double totalAmount;
  final int itemCount;
  final DateTime createdAt;

  const ScheduledOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.scheduledTime,
    required this.status,
    required this.totalAmount,
    this.itemCount = 0,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isCancelled => status == 'cancelled';
}

/// Scheduled orders state
class ScheduledOrdersState {
  final List<ScheduledOrder> orders;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const ScheduledOrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  ScheduledOrdersState copyWith({
    List<ScheduledOrder>? orders,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return ScheduledOrdersState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Scheduled orders notifier
class ScheduledOrdersNotifier extends StateNotifier<ScheduledOrdersState> {
  final ApiClient _api;

  ScheduledOrdersNotifier(this._api) : super(const ScheduledOrdersState()) {
    fetch();
  }

  /// Fetch scheduled orders
  Future<void> fetch() async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await _api.get(ApiConfig.scheduledOrders);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        final orders = list.map((d) {
          final m = d as Map<String, dynamic>;
          return ScheduledOrder(
            id: m['\$id'] ?? '',
            restaurantId: m['restaurant_id'] ?? '',
            restaurantName: m['restaurant_name'] ?? 'Restaurant',
            scheduledTime:
                DateTime.tryParse(m['scheduled_time'] ?? '') ?? DateTime.now(),
            status: m['status'] ?? 'pending',
            totalAmount: (m['total_amount'] ?? 0).toDouble(),
            itemCount: m['item_count'] ?? 0,
            createdAt:
                DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
        state = state.copyWith(orders: orders, isLoading: false);
      }
    } on ApiException {
      state = state.copyWith(isLoading: false);
    } catch (_) {
      // Mock fallback
      state = state.copyWith(
        orders: [
          ScheduledOrder(
            id: 'so1',
            restaurantId: 'r1',
            restaurantName: 'Biryani Express',
            scheduledTime: DateTime.now().add(const Duration(hours: 4)),
            status: 'pending',
            totalAmount: 450,
            itemCount: 3,
            createdAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
          ScheduledOrder(
            id: 'so2',
            restaurantId: 'r2',
            restaurantName: 'Pizza Paradise',
            scheduledTime: DateTime.now().add(const Duration(days: 1, hours: 12)),
            status: 'confirmed',
            totalAmount: 780,
            itemCount: 2,
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ],
        isLoading: false,
      );
    }
  }

  /// Cancel a scheduled order
  Future<void> cancel(String orderId) async {
    state = state.copyWith(error: null, successMessage: null);
    try {
      final response = await _api.put(
        '${ApiConfig.scheduledOrders}/$orderId/cancel',
      );
      if (response.success) {
        state = state.copyWith(
          orders: state.orders
              .map((o) {
                if (o.id == orderId) {
                  return ScheduledOrder(
                    id: o.id,
                    restaurantId: o.restaurantId,
                    restaurantName: o.restaurantName,
                    scheduledTime: o.scheduledTime,
                    status: 'cancelled',
                    totalAmount: o.totalAmount,
                    itemCount: o.itemCount,
                    createdAt: o.createdAt,
                  );
                }
                return o;
              })
              .toList(),
          successMessage: 'Order cancelled',
        );
      } else {
        state = state.copyWith(error: response.error ?? 'Failed to cancel');
      }
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (_) {
      state = state.copyWith(error: 'Something went wrong');
    }
  }
}

final scheduledOrdersProvider =
    StateNotifierProvider<ScheduledOrdersNotifier, ScheduledOrdersState>((ref) {
      final api = ref.watch(apiClientProvider);
      return ScheduledOrdersNotifier(api);
    });
