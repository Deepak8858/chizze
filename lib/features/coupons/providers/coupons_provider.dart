import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  const CouponsState({this.available = const [], this.appliedCouponId});

  Coupon? get appliedCoupon => appliedCouponId != null
      ? available.where((c) => c.id == appliedCouponId).firstOrNull
      : null;
}

/// Coupons notifier
class CouponsNotifier extends StateNotifier<CouponsState> {
  CouponsNotifier() : super(CouponsState(available: _mockCoupons));

  void applyCoupon(String id) {
    state = CouponsState(available: state.available, appliedCouponId: id);
  }

  void removeCoupon() {
    state = CouponsState(available: state.available, appliedCouponId: null);
  }

  static final _mockCoupons = [
    Coupon(
      id: 'c1',
      code: 'CHIZZE40',
      title: '40% OFF',
      description: 'Get 40% off on your first order',
      discountPercent: 40,
      maxDiscount: 150,
      minOrder: 199,
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      usageLimit: 1,
    ),
    Coupon(
      id: 'c2',
      code: 'FREEDEL',
      title: 'Free Delivery',
      description: 'Free delivery on orders above ₹299',
      discountPercent: 100,
      maxDiscount: 60,
      minOrder: 299,
      expiresAt: DateTime.now().add(const Duration(days: 3)),
      usageLimit: 3,
      usageCount: 1,
    ),
    Coupon(
      id: 'c3',
      code: 'WEEKEND25',
      title: '25% OFF',
      description: 'Weekend special — 25% off on all restaurants',
      discountPercent: 25,
      maxDiscount: 100,
      minOrder: 249,
      expiresAt: DateTime.now().add(const Duration(days: 2)),
      usageLimit: 2,
    ),
    Coupon(
      id: 'c4',
      code: 'BIRYANI50',
      title: '50% OFF Biryani',
      description: 'Flat 50% off on Biryani Blues orders',
      discountPercent: 50,
      maxDiscount: 200,
      minOrder: 399,
      expiresAt: DateTime.now().add(const Duration(days: 5)),
      restaurantId: 'r1',
    ),
    Coupon(
      id: 'c5',
      code: 'NEWUSER',
      title: 'New User Special',
      description: 'Flat ₹100 off for new users',
      discountPercent: 100,
      maxDiscount: 100,
      minOrder: 149,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      isActive: false, // already used
    ),
  ];
}

final couponsProvider = StateNotifierProvider<CouponsNotifier, CouponsState>((
  ref,
) {
  return CouponsNotifier();
});
