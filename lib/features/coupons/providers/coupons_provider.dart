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

  const CouponsState({
    this.available = const [],
    this.appliedCouponId,
    this.isLoading = false,
  });

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
        state = CouponsState(
          available: coupons,
          appliedCouponId: state.appliedCouponId,
        );
      }
    } on ApiException {
      // Keep current state on error
    } catch (_) {}
  }

  /// Validate coupon via API before applying
  Future<bool> validateAndApply(String code, double orderTotal) async {
    try {
      final response = await _api.post(
        ApiConfig.validateCoupon,
        body: {'code': code, 'order_total': orderTotal},
      );
      if (response.success) {
        final coupon = state.available.where((c) => c.code == code).firstOrNull;
        if (coupon != null) {
          applyCoupon(coupon.id);
          return true;
        }
      }
    } on ApiException {
      // Validation failed
    } catch (_) {}
    return false;
  }

  void applyCoupon(String id) {
    state = CouponsState(available: state.available, appliedCouponId: id);
  }

  void removeCoupon() {
    state = CouponsState(available: state.available, appliedCouponId: null);
  }


}

final couponsProvider = StateNotifierProvider<CouponsNotifier, CouponsState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return CouponsNotifier(api);
});
