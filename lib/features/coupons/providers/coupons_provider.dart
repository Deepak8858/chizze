import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';

/// Coupon model
class Coupon {
  final String id;
  final String code;
  final String title;
  final String description;
  final double discountPercent;
  final double maxDiscount;
  final double minOrder;
  final DateTime expiresAt;
  final int usageLimit;
  final int usageCount;
  final String? restaurantId; // null = all restaurants
  final bool isActive;

  const Coupon({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountPercent,
    this.maxDiscount = 0,
    this.minOrder = 0,
    required this.expiresAt,
    this.usageLimit = 1,
    this.usageCount = 0,
    this.restaurantId,
    this.isActive = true,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable => isActive && !isExpired && usageCount < usageLimit;

  int get daysRemaining {
    final diff = expiresAt.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }
}

/// Coupons state
class CouponsState {
  final List<Coupon> available;
  final String? appliedCouponId;
  final bool isLoading;
  final String? error;

  const CouponsState({
    this.available = const [],
    this.appliedCouponId,
    this.isLoading = false,
    this.error,
  });

  CouponsState copyWith({
    List<Coupon>? available,
    String? appliedCouponId,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearCoupon = false,
  }) {
    return CouponsState(
      available: available ?? this.available,
      appliedCouponId: clearCoupon
          ? null
          : (appliedCouponId ?? this.appliedCouponId),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Coupon? get appliedCoupon => appliedCouponId != null
      ? available.where((c) => c.id == appliedCouponId).firstOrNull
      : null;
}

/// Coupons notifier — API-backed
class CouponsNotifier extends StateNotifier<CouponsState> {
  final ApiClient _api;

  CouponsNotifier(this._api) : super(const CouponsState(available: [])) {
    fetchCoupons();
  }

  /// Fetch coupons from API
  Future<void> fetchCoupons() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _api.get(ApiConfig.coupons);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        final coupons = list.map((d) {
          final m = d as Map<String, dynamic>;
          return Coupon(
            id: m['\$id'] ?? '',
            code: m['code'] ?? '',
            title: m['description'] ?? '',
            description: m['description'] ?? '',
            discountPercent: (m['discount_value'] ?? 0).toDouble(),
            maxDiscount: (m['max_discount'] ?? 0).toDouble(),
            minOrder: (m['min_order_value'] ?? 0).toDouble(),
            expiresAt:
                DateTime.tryParse(m['valid_until'] ?? '') ??
                DateTime.now().add(const Duration(days: 7)),
            usageLimit: m['usage_limit'] ?? 1,
            usageCount: m['used_count'] ?? 0,
            restaurantId: m['restaurant_id'],
            isActive: m['is_active'] ?? true,
          );
        }).toList();
        state = state.copyWith(available: coupons, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: response.error ?? 'Failed to load coupons',
        );
      }
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[CouponsProvider] API error fetching coupons: ${e.message}',
        );
      }
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CouponsProvider] Unexpected error fetching coupons: $e');
      }
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Validate coupon via API before applying
  Future<bool> validateAndApply(String code, double orderTotal) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _api.post(
        ApiConfig.validateCoupon,
        body: {'code': code, 'order_total': orderTotal},
      );
      if (response.success) {
        final coupon = state.available.where((c) => c.code == code).firstOrNull;
        if (coupon != null) {
          state = state.copyWith(appliedCouponId: coupon.id, isLoading: false);
          return true;
        }
        state = state.copyWith(
          isLoading: false,
          error: 'Coupon validated by server but not available locally',
        );
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        error: response.error ?? 'Coupon validation failed',
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint(
        '[CouponsProvider] Validation error for code $code: ${e.message}',
      );
      }
      state = state.copyWith(isLoading: false, error: e.message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CouponsProvider] Unexpected validation error: $e');
      }
      state = state.copyWith(isLoading: false, error: e.toString());
    }
    return false;
  }

  void applyCoupon(String id) {
    state = state.copyWith(appliedCouponId: id, clearError: true);
  }

  void removeCoupon() {
    state = state.copyWith(clearCoupon: true, clearError: true);
  }


}

final couponsProvider = StateNotifierProvider<CouponsNotifier, CouponsState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return CouponsNotifier(api);
});
