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

    // Fallback to mock data
    state = _mockAnalytics;
  }

  static final _mockAnalytics = const AnalyticsState(
    totalRevenue: 87350,
    totalOrders: 196,
    avgOrderValue: 445.66,
    revenueData: [
      DailyRevenue(day: 'Mon', amount: 11200, orders: 24),
      DailyRevenue(day: 'Tue', amount: 9800, orders: 21),
      DailyRevenue(day: 'Wed', amount: 13500, orders: 29),
      DailyRevenue(day: 'Thu', amount: 10200, orders: 22),
      DailyRevenue(day: 'Fri', amount: 15800, orders: 34),
      DailyRevenue(day: 'Sat', amount: 16400, orders: 38),
      DailyRevenue(day: 'Sun', amount: 10450, orders: 28),
    ],
    topItems: [
      TopItem(
        name: 'Chicken Biryani',
        orderCount: 82,
        revenue: 24518,
        isVeg: false,
      ),
      TopItem(
        name: 'Mutton Biryani',
        orderCount: 45,
        revenue: 17955,
        isVeg: false,
      ),
      TopItem(name: 'Dal Makhani', orderCount: 38, revenue: 8322, isVeg: true),
      TopItem(name: 'Paneer Tikka', orderCount: 31, revenue: 7409, isVeg: true),
      TopItem(name: 'Gulab Jamun', orderCount: 56, revenue: 4424, isVeg: true),
    ],
    peakHours: [
      HourlyVolume(hour: 9, orders: 2),
      HourlyVolume(hour: 10, orders: 5),
      HourlyVolume(hour: 11, orders: 12),
      HourlyVolume(hour: 12, orders: 28),
      HourlyVolume(hour: 13, orders: 32),
      HourlyVolume(hour: 14, orders: 18),
      HourlyVolume(hour: 15, orders: 8),
      HourlyVolume(hour: 16, orders: 6),
      HourlyVolume(hour: 17, orders: 10),
      HourlyVolume(hour: 18, orders: 22),
      HourlyVolume(hour: 19, orders: 35),
      HourlyVolume(hour: 20, orders: 38),
      HourlyVolume(hour: 21, orders: 30),
      HourlyVolume(hour: 22, orders: 15),
      HourlyVolume(hour: 23, orders: 5),
    ],
  );
}

/// Analytics provider — now StateNotifier for async fetching
final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
      final api = ref.watch(apiClientProvider);
      return AnalyticsNotifier(api);
    });
