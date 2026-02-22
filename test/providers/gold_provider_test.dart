import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/gold/providers/gold_provider.dart';

void main() {
  group('GoldPlan', () {
    test('durationLabel "month" for ≤31 days', () {
      const plan = GoldPlan(
        id: 'p1',
        name: 'Monthly',
        description: 'd',
        price: 149,
        durationDays: 30,
      );
      expect(plan.durationLabel, 'month');
    });

    test('durationLabel "month" for exactly 31 days', () {
      const plan = GoldPlan(
        id: 'p1',
        name: 'Monthly',
        description: 'd',
        price: 149,
        durationDays: 31,
      );
      expect(plan.durationLabel, 'month');
    });

    test('durationLabel "3 months" for 32-92 days', () {
      const plan = GoldPlan(
        id: 'p2',
        name: 'Quarterly',
        description: 'd',
        price: 349,
        durationDays: 90,
      );
      expect(plan.durationLabel, '3 months');
    });

    test('durationLabel "3 months" for exactly 92 days', () {
      const plan = GoldPlan(
        id: 'p2',
        name: 'Quarterly',
        description: 'd',
        price: 349,
        durationDays: 92,
      );
      expect(plan.durationLabel, '3 months');
    });

    test('durationLabel "year" for >92 days', () {
      const plan = GoldPlan(
        id: 'p3',
        name: 'Annual',
        description: 'd',
        price: 999,
        durationDays: 365,
      );
      expect(plan.durationLabel, 'year');
    });

    test('default benefits is empty list', () {
      const plan = GoldPlan(
        id: 'p1',
        name: 'X',
        description: 'd',
        price: 100,
        durationDays: 30,
      );
      expect(plan.benefits, isEmpty);
    });

    test('benefits preserved', () {
      const plan = GoldPlan(
        id: 'p1',
        name: 'X',
        description: 'd',
        price: 100,
        durationDays: 30,
        benefits: ['Free delivery', 'Extra 10% off'],
      );
      expect(plan.benefits.length, 2);
      expect(plan.benefits[0], 'Free delivery');
    });
  });

  group('GoldSubscription', () {
    test('isActive when status=active and not expired', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Gold Monthly',
        status: 'active',
        startsAt: DateTime.now().subtract(const Duration(days: 10)),
        expiresAt: DateTime.now().add(const Duration(days: 20)),
      );
      expect(sub.isActive, isTrue);
    });

    test('isActive false when status=cancelled', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Gold Monthly',
        status: 'cancelled',
        startsAt: DateTime.now().subtract(const Duration(days: 10)),
        expiresAt: DateTime.now().add(const Duration(days: 20)),
      );
      expect(sub.isActive, isFalse);
    });

    test('isActive false when expired', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Gold Monthly',
        status: 'active',
        startsAt: DateTime.now().subtract(const Duration(days: 40)),
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(sub.isActive, isFalse);
    });

    test('daysRemaining positive for future expiry', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Gold Monthly',
        status: 'active',
        startsAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 15)),
      );
      expect(sub.daysRemaining, greaterThanOrEqualTo(14));
      expect(sub.daysRemaining, lessThanOrEqualTo(15));
    });

    test('daysRemaining negative for past expiry', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Gold Monthly',
        status: 'expired',
        startsAt: DateTime.now().subtract(const Duration(days: 40)),
        expiresAt: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(sub.daysRemaining, lessThan(0));
    });
  });

  group('GoldState', () {
    test('default state', () {
      const state = GoldState();
      expect(state.plans, isEmpty);
      expect(state.subscription, isNull);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.successMessage, isNull);
      expect(state.isGoldMember, isFalse);
    });

    test('isGoldMember true when active subscription', () {
      final state = GoldState(
        subscription: GoldSubscription(
          id: 's1',
          planId: 'p1',
          planName: 'Monthly',
          status: 'active',
          startsAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      );
      expect(state.isGoldMember, isTrue);
    });

    test('isGoldMember false when subscription expired', () {
      final state = GoldState(
        subscription: GoldSubscription(
          id: 's1',
          planId: 'p1',
          planName: 'Monthly',
          status: 'active',
          startsAt: DateTime.now().subtract(const Duration(days: 40)),
          expiresAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      );
      expect(state.isGoldMember, isFalse);
    });

    test('copyWith replaces fields', () {
      const state = GoldState();
      final updated = state.copyWith(
        isLoading: true,
        error: 'fail',
        successMessage: 'ok',
      );
      expect(updated.isLoading, isTrue);
      expect(updated.error, 'fail');
      expect(updated.successMessage, 'ok');
    });

    test('copyWith clearSubscription sets null', () {
      final state = GoldState(
        subscription: GoldSubscription(
          id: 's1',
          planId: 'p1',
          planName: 'Monthly',
          status: 'active',
          startsAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      );
      final updated = state.copyWith(clearSubscription: true);
      expect(updated.subscription, isNull);
      expect(updated.isGoldMember, isFalse);
    });

    test('copyWith preserves subscription when not clearing', () {
      final sub = GoldSubscription(
        id: 's1',
        planId: 'p1',
        planName: 'Monthly',
        status: 'active',
        startsAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      final state = GoldState(subscription: sub);
      final updated = state.copyWith(isLoading: true);
      expect(updated.subscription, isNotNull);
      expect(updated.subscription!.id, 's1');
    });

    test('copyWith with plans', () {
      const state = GoldState();
      final updated = state.copyWith(
        plans: [
          const GoldPlan(
            id: 'p1',
            name: 'Monthly',
            description: 'd',
            price: 149,
            durationDays: 30,
          ),
        ],
      );
      expect(updated.plans.length, 1);
      expect(updated.plans[0].name, 'Monthly');
    });
  });
}
