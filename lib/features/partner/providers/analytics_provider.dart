import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Analytics data for restaurant partner
class AnalyticsState {
  final List<DailyRevenue> revenueData;
  final List<TopItem> topItems;
  final List<HourlyVolume> peakHours;
  final double totalRevenue;
  final int totalOrders;
  final double avgOrderValue;
  final bool isLoading;

  const AnalyticsState({
    this.revenueData = const [],
    this.topItems = const [],
    this.peakHours = const [],
    this.totalRevenue = 0,
    this.totalOrders = 0,
    this.avgOrderValue = 0,
    this.isLoading = false,
  });
}

class DailyRevenue {
  final String day; // "Mon", "Tue", etc.
  final double amount;
  final int orders;
  const DailyRevenue({
    required this.day,
    required this.amount,
    required this.orders,
  });
}

class TopItem {
  final String name;
  final int orderCount;
  final double revenue;
  final bool isVeg;
  const TopItem({
    required this.name,
    required this.orderCount,
    required this.revenue,
    required this.isVeg,
  });
}

class HourlyVolume {
  final int hour; // 0-23
  final int orders;
  const HourlyVolume({required this.hour, required this.orders});
}

/// Analytics notifier — API-backed with mock fallback
class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  final ApiClient _api;

  AnalyticsNotifier(this._api) : super(const AnalyticsState()) {
    fetchAnalytics();
  }

  Future<void> fetchAnalytics({String period = 'week'}) async {
    state = const AnalyticsState(isLoading: true);
    try {
      final response = await _api.get(
        ApiConfig.partnerAnalytics,
        queryParams: {'period': period},
      );
      if (response.success && response.data != null) {
        final d = response.data as Map<String, dynamic>;

        // Parse revenue data
        final revenueList = (d['revenue_data'] as List?)?.map((r) {
          final m = r as Map<String, dynamic>;
          return DailyRevenue(
            day: m['day'] ?? '',
            amount: (m['amount'] ?? 0).toDouble(),
            orders: m['orders'] ?? 0,
          );
        }).toList() ?? [];

        // Parse top items
        final topItemsList = (d['top_items'] as List?)?.map((t) {
          final m = t as Map<String, dynamic>;
          return TopItem(
            name: m['name'] ?? '',
            orderCount: m['order_count'] ?? m['Count'] ?? 0,
            revenue: (m['revenue'] ?? m['Rev'] ?? 0).toDouble(),
            isVeg: m['is_veg'] ?? m['IsVeg'] ?? false,
          );
        }).toList() ?? [];

        // Parse peak hours
        final peakHoursList = (d['peak_hours'] as List?)?.map((h) {
          final m = h as Map<String, dynamic>;
          return HourlyVolume(
            hour: m['hour'] ?? 0,
            orders: m['orders'] ?? 0,
          );
        }).toList() ?? [];

        state = AnalyticsState(
          totalRevenue: (d['total_revenue'] ?? 0).toDouble(),
          totalOrders: d['total_orders'] ?? 0,
          avgOrderValue: (d['avg_order_value'] ?? 0).toDouble(),
          revenueData: revenueList,
          topItems: topItemsList,
          peakHours: peakHoursList,
        );
        return;
      }
    } catch (_) {}

    // No mock fallback — show empty state
    state = const AnalyticsState();
  }
}

/// Analytics provider — now StateNotifier for async fetching
final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
      final api = ref.watch(apiClientProvider);
      return AnalyticsNotifier(api);
    });
