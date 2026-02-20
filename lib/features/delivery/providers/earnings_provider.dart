import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';

/// A single completed trip
class TripEarning {
  final String orderId;
  final String orderNumber;
  final String restaurantName;
  final double amount;
  final double distanceKm;
  final int durationMin;
  final DateTime completedAt;
  final double tipAmount;
  final bool hasSurge;

  const TripEarning({
    required this.orderId,
    required this.orderNumber,
    required this.restaurantName,
    required this.amount,
    required this.distanceKm,
    required this.durationMin,
    required this.completedAt,
    this.tipAmount = 0,
    this.hasSurge = false,
  });
}

/// Daily earnings summary
class DailyEarning {
  final String day; // "Mon", "Tue", etc.
  final double amount;
  final int trips;
  const DailyEarning({
    required this.day,
    required this.amount,
    required this.trips,
  });
}

/// Payout record
class PayoutRecord {
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amount;
  final String status; // pending | processing | completed
  final int orderCount;

  const PayoutRecord({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.status,
    required this.orderCount,
  });
}

/// Earnings state
class EarningsState {
  final List<DailyEarning> weeklyData;
  final List<TripEarning> recentTrips;
  final List<PayoutRecord> payouts;
  final double weeklyTotal;
  final double monthlyTotal;
  final double incentiveEarned;
  final double surgeEarned;
  final bool isLoading;

  const EarningsState({
    this.weeklyData = const [],
    this.recentTrips = const [],
    this.payouts = const [],
    this.weeklyTotal = 0,
    this.monthlyTotal = 0,
    this.incentiveEarned = 0,
    this.surgeEarned = 0,
    this.isLoading = false,
  });
}

/// Earnings notifier — API-backed with mock fallback
class EarningsNotifier extends StateNotifier<EarningsState> {
  final ApiClient _api;

  EarningsNotifier(this._api) : super(const EarningsState()) {
    fetchEarnings();
  }

  Future<void> fetchEarnings() async {
    state = const EarningsState(isLoading: true);
    try {
      // Attempt API fetch
      final response = await _api.get('/delivery/earnings');
      if (response.success && response.data != null) {
        state = const EarningsState(isLoading: false);
        return;
      }
    } catch (_) {}

    // Fallback to mock data
    final now = DateTime.now();
    state = EarningsState(
      weeklyTotal: 5840,
      monthlyTotal: 22350,
      incentiveEarned: 1200,
      surgeEarned: 650,
      weeklyData: const [
        DailyEarning(day: 'Mon', amount: 720, trips: 10),
        DailyEarning(day: 'Tue', amount: 650, trips: 9),
        DailyEarning(day: 'Wed', amount: 880, trips: 12),
        DailyEarning(day: 'Thu', amount: 790, trips: 11),
        DailyEarning(day: 'Fri', amount: 1050, trips: 15),
        DailyEarning(day: 'Sat', amount: 1100, trips: 16),
        DailyEarning(day: 'Sun', amount: 650, trips: 9),
      ],
      recentTrips: [
        TripEarning(
          orderId: 'o1',
          orderNumber: 'CHZ-500010',
          restaurantName: 'Biryani Blues',
          amount: 65,
          distanceKm: 3.8,
          durationMin: 22,
          completedAt: now.subtract(const Duration(minutes: 30)),
          tipAmount: 20,
        ),
        TripEarning(
          orderId: 'o2',
          orderNumber: 'CHZ-500009',
          restaurantName: 'Pizza Paradise',
          amount: 55,
          distanceKm: 2.5,
          durationMin: 15,
          completedAt: now.subtract(const Duration(hours: 1)),
          hasSurge: true,
        ),
        TripEarning(
          orderId: 'o3',
          orderNumber: 'CHZ-500008',
          restaurantName: 'Dosa Corner',
          amount: 45,
          distanceKm: 1.8,
          durationMin: 12,
          completedAt: now.subtract(const Duration(hours: 2)),
        ),
        TripEarning(
          orderId: 'o4',
          orderNumber: 'CHZ-500007',
          restaurantName: 'Tandoori Nights',
          amount: 75,
          distanceKm: 5.2,
          durationMin: 28,
          completedAt: now.subtract(const Duration(hours: 3)),
          tipAmount: 30,
          hasSurge: true,
        ),
        TripEarning(
          orderId: 'o5',
          orderNumber: 'CHZ-500006',
          restaurantName: 'Chat House',
          amount: 40,
          distanceKm: 1.5,
          durationMin: 10,
          completedAt: now.subtract(const Duration(hours: 4)),
        ),
      ],
      payouts: [
        PayoutRecord(
          id: 'pay1',
          periodStart: now.subtract(const Duration(days: 14)),
          periodEnd: now.subtract(const Duration(days: 7)),
          amount: 5200,
          status: 'completed',
          orderCount: 68,
        ),
        PayoutRecord(
          id: 'pay2',
          periodStart: now.subtract(const Duration(days: 7)),
          periodEnd: now,
          amount: 5840,
          status: 'processing',
          orderCount: 82,
        ),
      ],
    );
  }
}

/// Earnings provider — now StateNotifier for async fetching
final earningsProvider = StateNotifierProvider<EarningsNotifier, EarningsState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    return EarningsNotifier(api);
  },
);
