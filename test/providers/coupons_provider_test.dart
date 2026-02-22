import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/coupons/providers/coupons_provider.dart';

void main() {
  group('Coupon model', () {
    test('isExpired false for future date', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
      );
      expect(coupon.isExpired, isFalse);
    });

    test('isExpired true for past date', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(coupon.isExpired, isTrue);
    });

    test('isUsable when active, not expired, usage available', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        usageLimit: 3,
        usageCount: 1,
        isActive: true,
      );
      expect(coupon.isUsable, isTrue);
    });

    test('isUsable false when inactive', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        isActive: false,
      );
      expect(coupon.isUsable, isFalse);
    });

    test('isUsable false when expired', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(coupon.isUsable, isFalse);
    });

    test('isUsable false when usage limit reached', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 7)),
        usageLimit: 2,
        usageCount: 2,
      );
      expect(coupon.isUsable, isFalse);
    });

    test('daysRemaining positive for future expiry', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 10)),
      );
      expect(coupon.daysRemaining, greaterThanOrEqualTo(9));
      expect(coupon.daysRemaining, lessThanOrEqualTo(10));
    });

    test('daysRemaining 0 for past expiry', () {
      final coupon = Coupon(
        id: '1',
        code: 'TEST',
        title: 'Test',
        description: 'desc',
        discountPercent: 10,
        expiresAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      expect(coupon.daysRemaining, 0);
    });

    test('defaults: maxDiscount 0, minOrder 0, usageLimit 1, usageCount 0, isActive true', () {
      final coupon = Coupon(
        id: '1',
        code: 'X',
        title: 'T',
        description: 'd',
        discountPercent: 5,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(coupon.maxDiscount, 0);
      expect(coupon.minOrder, 0);
      expect(coupon.usageLimit, 1);
      expect(coupon.usageCount, 0);
      expect(coupon.isActive, isTrue);
      expect(coupon.restaurantId, isNull);
    });
  });

  group('CouponsState', () {
    test('default state', () {
      const state = CouponsState();
      expect(state.available, isEmpty);
      expect(state.appliedCouponId, isNull);
      expect(state.isLoading, isFalse);
      expect(state.appliedCoupon, isNull);
    });

    test('appliedCoupon returns matching coupon', () {
      final coupon = Coupon(
        id: 'c1',
        code: 'TEST',
        title: 'T',
        description: 'd',
        discountPercent: 10,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final state = CouponsState(available: [coupon], appliedCouponId: 'c1');
      expect(state.appliedCoupon, isNotNull);
      expect(state.appliedCoupon!.code, 'TEST');
    });

    test('appliedCoupon null when ID not found', () {
      final state = CouponsState(available: [], appliedCouponId: 'c99');
      expect(state.appliedCoupon, isNull);
    });

    test('appliedCoupon null when no coupon applied', () {
      final coupon = Coupon(
        id: 'c1',
        code: 'X',
        title: 'T',
        description: 'd',
        discountPercent: 5,
        expiresAt: DateTime.now(),
      );
      final state = CouponsState(available: [coupon]);
      expect(state.appliedCoupon, isNull);
    });
  });
}
