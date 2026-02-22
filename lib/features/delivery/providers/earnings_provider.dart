import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

// ─── Period selector ───────────────────────────────────────────────

/// Supported earnings period filters
enum EarningsPeriod {
  today('Today', 'day'),
  week('This Week', 'week'),
  month('This Month', 'month'),
  custom('Custom', 'custom');

  final String label;
  final String apiValue;
  const EarningsPeriod(this.label, this.apiValue);
}

// ─── Models ────────────────────────────────────────────────────────

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

  /// Parse from API response map
  factory TripEarning.fromMap(Map<String, dynamic> t) {
    return TripEarning(
      orderId: t['order_id']?.toString() ?? '',
      orderNumber: t['order_number']?.toString() ?? '',
      restaurantName: t['restaurant_id']?.toString() ?? '',
      amount: (t['amount'] as num?)?.toDouble() ?? 0,
      distanceKm: (t['distance_km'] as num?)?.toDouble() ?? 0,
      durationMin: (t['duration_min'] as num?)?.toInt() ?? 0,
      completedAt: DateTime.tryParse(
            t['completed_at']?.toString() ?? '',
          ) ??
          DateTime.now(),
      tipAmount: (t['tip'] as num?)?.toDouble() ?? 0,
      hasSurge: t['has_surge'] as bool? ?? false,
    );
  }
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

  /// Parse from API response map
  factory DailyEarning.fromMap(Map<String, dynamic> d) {
    return DailyEarning(
      day: d['day']?.toString() ?? '',
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      trips: (d['trips'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Payout record
class PayoutRecord {
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amount;
  final String status; // pending | processing | completed | failed
  final int orderCount;

  const PayoutRecord({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.status,
    required this.orderCount,
  });

  /// Parse from API response map
  factory PayoutRecord.fromMap(Map<String, dynamic> p) {
    return PayoutRecord(
      id: p['\$id']?.toString() ?? p['id']?.toString() ?? '',
      periodStart: DateTime.tryParse(
            p['period_start']?.toString() ?? '',
          ) ??
          DateTime.now(),
      periodEnd: DateTime.tryParse(
            p['period_end']?.toString() ?? '',
          ) ??
          DateTime.now(),
      amount: (p['amount'] as num?)?.toDouble() ?? 0,
      status: p['status']?.toString() ?? 'pending',
      orderCount: (p['order_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isProcessing => status == 'processing';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
}

// ─── State ─────────────────────────────────────────────────────────

/// Earnings state
class EarningsState {
  final EarningsPeriod selectedPeriod;
  final DateTime? customStart;
  final DateTime? customEnd;
  final List<DailyEarning> weeklyData;
  final List<TripEarning> recentTrips;
  final List<PayoutRecord> payouts;
  final double periodTotal; // earnings for selected period
  final double weeklyTotal;
  final double monthlyTotal;
  final double totalTips;
  final int totalTrips;
  final double incentiveEarned;
  final double surgeEarned;
  final bool isLoading;
  final bool isPayoutsLoading;
  final bool isRequestingPayout;
  final String? errorMessage;

  const EarningsState({
    this.selectedPeriod = EarningsPeriod.week,
    this.customStart,
    this.customEnd,
    this.weeklyData = const [],
    this.recentTrips = const [],
    this.payouts = const [],
    this.periodTotal = 0,
    this.weeklyTotal = 0,
    this.monthlyTotal = 0,
    this.totalTips = 0,
    this.totalTrips = 0,
    this.incentiveEarned = 0,
    this.surgeEarned = 0,
    this.isLoading = false,
    this.isPayoutsLoading = false,
    this.isRequestingPayout = false,
    this.errorMessage,
  });

  EarningsState copyWith({
    EarningsPeriod? selectedPeriod,
    DateTime? customStart,
    DateTime? customEnd,
    List<DailyEarning>? weeklyData,
    List<TripEarning>? recentTrips,
    List<PayoutRecord>? payouts,
    double? periodTotal,
    double? weeklyTotal,
    double? monthlyTotal,
    double? totalTips,
    int? totalTrips,
    double? incentiveEarned,
    double? surgeEarned,
    bool? isLoading,
    bool? isPayoutsLoading,
    bool? isRequestingPayout,
    String? errorMessage,
    bool clearError = false,
  }) {
    return EarningsState(
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      weeklyData: weeklyData ?? this.weeklyData,
      recentTrips: recentTrips ?? this.recentTrips,
      payouts: payouts ?? this.payouts,
      periodTotal: periodTotal ?? this.periodTotal,
      weeklyTotal: weeklyTotal ?? this.weeklyTotal,
      monthlyTotal: monthlyTotal ?? this.monthlyTotal,
      totalTips: totalTips ?? this.totalTips,
      totalTrips: totalTrips ?? this.totalTrips,
      incentiveEarned: incentiveEarned ?? this.incentiveEarned,
      surgeEarned: surgeEarned ?? this.surgeEarned,
      isLoading: isLoading ?? this.isLoading,
      isPayoutsLoading: isPayoutsLoading ?? this.isPayoutsLoading,
      isRequestingPayout: isRequestingPayout ?? this.isRequestingPayout,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Average earning per trip in the current period
  double get avgPerTrip => totalTrips > 0 ? periodTotal / totalTrips : 0;

  /// Average earning per trip for the week
  double get weeklyAvgPerTrip {
    final trips = weeklyData.fold<int>(0, (s, d) => s + d.trips);
    return trips > 0 ? weeklyTotal / trips : 0;
  }
}

// ─── Notifier ──────────────────────────────────────────────────────

/// Earnings notifier — API-backed with period selector + payout handling
class EarningsNotifier extends StateNotifier<EarningsState> {
  final ApiClient _api;
  bool _isLoadingGuard = false;

  EarningsNotifier(this._api) : super(const EarningsState()) {
    fetchEarnings();
    fetchPayouts();
  }

  // ─── Period selection ──────────────────────────────────────────

  /// Switch the earnings period and re-fetch
  void selectPeriod(EarningsPeriod period) {
    if (period == state.selectedPeriod) return;
    state = state.copyWith(selectedPeriod: period);
    fetchEarnings();
  }

  /// Set custom date range and fetch
  void setCustomRange(DateTime start, DateTime end) {
    state = state.copyWith(
      selectedPeriod: EarningsPeriod.custom,
      customStart: start,
      customEnd: end,
    );
    fetchEarnings();
  }

  // ─── Earnings fetch ────────────────────────────────────────────

  Future<void> fetchEarnings() async {
    if (_isLoadingGuard) return;
    _isLoadingGuard = true;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final queryParams = <String, String>{
        'period': state.selectedPeriod.apiValue,
      };
      // Attach custom range if applicable
      if (state.selectedPeriod == EarningsPeriod.custom &&
          state.customStart != null &&
          state.customEnd != null) {
        queryParams['from'] = state.customStart!.toIso8601String();
        queryParams['to'] = state.customEnd!.toIso8601String();
      }

      final response = await _api.get(
        ApiConfig.deliveryEarnings,
        queryParams: queryParams,
      );

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;

        // Parse weekly/daily data
        final weeklyRaw = data['weekly_data'] as List<dynamic>? ?? [];
        final weeklyData =
            weeklyRaw
                .map(
                  (d) =>
                      DailyEarning.fromMap(Map<String, dynamic>.from(d as Map)),
                )
                .toList();

        // Parse recent trips
        final tripsRaw = data['recent_trips'] as List<dynamic>? ?? [];
        final recentTrips =
            tripsRaw
                .map(
                  (t) =>
                      TripEarning.fromMap(Map<String, dynamic>.from(t as Map)),
                )
                .toList();

        final weeklyTotal =
            (data['weekly_total'] as num?)?.toDouble() ?? 0;
        final monthlyTotal =
            (data['monthly_total'] as num?)?.toDouble() ?? 0;
        final totalTips = (data['total_tips'] as num?)?.toDouble() ?? 0;
        final totalTrips = (data['total_trips'] as num?)?.toInt() ?? 0;

        // Determine period total based on selected period
        double periodTotal;
        switch (state.selectedPeriod) {
          case EarningsPeriod.today:
            periodTotal = weeklyData.isNotEmpty
                ? weeklyData.last.amount
                : weeklyTotal;
          case EarningsPeriod.month:
            periodTotal = monthlyTotal;
          default:
            periodTotal = weeklyTotal;
        }

        state = state.copyWith(
          weeklyData: weeklyData,
          recentTrips: recentTrips,
          periodTotal: periodTotal,
          weeklyTotal: weeklyTotal,
          monthlyTotal: monthlyTotal,
          totalTips: totalTips,
          totalTrips: totalTrips,
          isLoading: false,
        );
        _isLoadingGuard = false;
        return;
      }
    } catch (_) {}

    // Fallback — show empty state (no mock in production)
    state = state.copyWith(isLoading: false);
    _isLoadingGuard = false;
  }

  /// Pull-to-refresh
  Future<void> refresh() async {
    _isLoadingGuard = false;
    await Future.wait([fetchEarnings(), fetchPayouts()]);
  }

  // ─── Payouts ──────────────────────────────────────────────────

  /// Fetch payout history
  Future<void> fetchPayouts() async {
    state = state.copyWith(isPayoutsLoading: true);

    try {
      final response = await _api.get(ApiConfig.deliveryPayouts);
      if (response.success && response.data != null) {
        final rawList = response.data as List<dynamic>? ?? [];
        final payouts =
            rawList
                .map(
                  (p) =>
                      PayoutRecord.fromMap(Map<String, dynamic>.from(p as Map)),
                )
                .toList();
        state = state.copyWith(payouts: payouts, isPayoutsLoading: false);
        return;
      }
    } catch (_) {}

    state = state.copyWith(isPayoutsLoading: false);
  }

  /// Request a manual payout (instant withdrawal)
  Future<bool> requestPayout({double? amount}) async {
    if (state.isRequestingPayout) return false;
    state = state.copyWith(isRequestingPayout: true, clearError: true);

    try {
      final body = <String, dynamic>{};
      if (amount != null) body['amount'] = amount;
      body['method'] = 'bank_transfer'; // default method

      final response = await _api.post(
        ApiConfig.deliveryPayoutRequest,
        body: body,
      );
      if (response.success) {
        // Re-fetch payouts to show the new request
        await fetchPayouts();
        state = state.copyWith(isRequestingPayout: false);
        return true;
      }
      state = state.copyWith(
        isRequestingPayout: false,
        errorMessage: response.error ?? 'Payout request failed',
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isRequestingPayout: false,
        errorMessage: 'Network error — try again',
      );
      return false;
    }
  }

  /// Clear any error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ─── Provider ──────────────────────────────────────────────────────

/// Earnings provider — StateNotifier with period selector + payout handling
final earningsProvider = StateNotifierProvider<EarningsNotifier, EarningsState>(
  (ref) {
    final api = ref.watch(apiClientProvider);
    return EarningsNotifier(api);
  },
);
