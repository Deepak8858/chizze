import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Gold plan model
class GoldPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final int durationDays;
  final List<String> benefits;

  const GoldPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationDays,
    this.benefits = const [],
  });

  String get durationLabel {
    if (durationDays <= 31) return 'month';
    if (durationDays <= 92) return '3 months';
    return 'year';
  }
}

/// Gold subscription status
class GoldSubscription {
  final String id;
  final String planId;
  final String planName;
  final String status; // active, cancelled, expired
  final DateTime startsAt;
  final DateTime expiresAt;

  const GoldSubscription({
    required this.id,
    required this.planId,
    required this.planName,
    required this.status,
    required this.startsAt,
    required this.expiresAt,
  });

  bool get isActive => status == 'active' && DateTime.now().isBefore(expiresAt);
  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays;
}

/// Gold state
class GoldState {
  final List<GoldPlan> plans;
  final GoldSubscription? subscription;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const GoldState({
    this.plans = const [],
    this.subscription,
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  bool get isGoldMember => subscription?.isActive ?? false;

  GoldState copyWith({
    List<GoldPlan>? plans,
    GoldSubscription? subscription,
    bool clearSubscription = false,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return GoldState(
      plans: plans ?? this.plans,
      subscription: clearSubscription ? null : (subscription ?? this.subscription),
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

/// Gold notifier — manages plans, subscription, and membership
class GoldNotifier extends StateNotifier<GoldState> {
  final ApiClient _api;

  GoldNotifier(this._api) : super(const GoldState()) {
    fetchPlans();
    fetchStatus();
  }

  /// Fetch available gold plans
  Future<void> fetchPlans() async {
    try {
      final response = await _api.get(ApiConfig.goldPlans);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        final plans = list.map((d) {
          final m = d as Map<String, dynamic>;
          return GoldPlan(
            id: m['id'] ?? '',
            name: m['name'] ?? '',
            description: m['description'] ?? '',
            price: (m['price'] ?? 0).toDouble(),
            durationDays: m['duration_days'] ?? 30,
            benefits: (m['benefits'] as List<dynamic>?)
                    ?.map((b) => b.toString())
                    .toList() ??
                [],
          );
        }).toList();
        state = state.copyWith(plans: plans);
      }
    } on ApiException {
      // Keep current state
    } catch (_) {
      // Mock fallback
      state = state.copyWith(plans: _mockPlans);
    }
  }

  /// Fetch current subscription status
  Future<void> fetchStatus() async {
    try {
      final response = await _api.get(ApiConfig.goldStatus);
      if (response.success && response.data != null) {
        final m = response.data as Map<String, dynamic>;
        if (m['subscription'] != null) {
          final s = m['subscription'] as Map<String, dynamic>;
          state = state.copyWith(
            subscription: GoldSubscription(
              id: s['\$id'] ?? '',
              planId: s['plan_id'] ?? '',
              planName: s['plan_name'] ?? '',
              status: s['status'] ?? 'active',
              startsAt:
                  DateTime.tryParse(s['starts_at'] ?? '') ?? DateTime.now(),
              expiresAt: DateTime.tryParse(s['expires_at'] ?? '') ??
                  DateTime.now().add(const Duration(days: 30)),
            ),
          );
        }
      }
    } on ApiException {
      // Not subscribed
    } catch (_) {}
  }

  /// Subscribe to a Gold plan
  Future<void> subscribe(String planId) async {
    state = state.copyWith(isLoading: true, error: null, successMessage: null);
    try {
      final response = await _api.post(
        ApiConfig.goldSubscribe,
        body: {'plan_id': planId},
      );
      if (response.success) {
        state = state.copyWith(
          isLoading: false,
          successMessage: 'Welcome to Chizze Gold! 👑',
        );
        fetchStatus(); // Refresh subscription
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.error ?? 'Subscription failed',
        );
      }
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Something went wrong. Try again.',
      );
    }
  }

  /// Cancel Gold subscription
  Future<void> cancel() async {
    state = state.copyWith(isLoading: true, error: null, successMessage: null);
    try {
      final response = await _api.put(ApiConfig.goldCancel);
      if (response.success) {
        state = state.copyWith(
          isLoading: false,
          clearSubscription: true,
          successMessage: 'Membership cancelled',
        );
      }
    } on ApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  static const _mockPlans = [
    GoldPlan(
      id: 'monthly',
      name: 'Gold Monthly',
      description: 'Perfect to try Gold benefits',
      price: 149,
      durationDays: 30,
      benefits: [
        'Free delivery on all orders',
        'Extra 10% off on every order',
        'Priority customer support',
      ],
    ),
    GoldPlan(
      id: 'quarterly',
      name: 'Gold Quarterly',
      description: 'Best value for regulars',
      price: 349,
      durationDays: 90,
      benefits: [
        'All Monthly benefits',
        'Exclusive Gold-only deals',
        'Early access to new restaurants',
      ],
    ),
    GoldPlan(
      id: 'annual',
      name: 'Gold Annual',
      description: 'Maximum savings',
      price: 999,
      durationDays: 365,
      benefits: [
        'All Quarterly benefits',
        'Birthday month special offers',
        'VIP event invitations',
      ],
    ),
  ];
}

final goldProvider =
    StateNotifierProvider<GoldNotifier, GoldState>((ref) {
      final api = ref.watch(apiClientProvider);
      return GoldNotifier(api);
    });
