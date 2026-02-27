import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/delivery/models/delivery_partner.dart';
import 'package:chizze/features/orders/models/order.dart';

void main() {
  group('DeliveryPartner.fromDashboard', () {
    test('parses all fields', () {
      final json = {
        '\$id': 'dp1',
        'user_id': 'u1',
        'name': 'Ravi Kumar',
        'phone': '+919876543210',
        'avatar_url': 'https://example.com/avatar.jpg',
        'vehicle_type': 'scooter',
        'vehicle_number': 'KA-01-1234',
        'is_online': true,
        'is_on_delivery': false,
        'rating': 4.8,
        'total_deliveries': 250,
        'total_earnings': 45000.50,
        'current_latitude': 12.9141,
        'current_longitude': 77.6501,
        'hours_online_today': 6.5,
        'tips_today': 180.0,
      };
      final dp = DeliveryPartner.fromDashboard(json);
      expect(dp.id, 'dp1');
      expect(dp.userId, 'u1');
      expect(dp.name, 'Ravi Kumar');
      expect(dp.phone, '+919876543210');
      expect(dp.avatarUrl, 'https://example.com/avatar.jpg');
      expect(dp.vehicleType, 'scooter');
      expect(dp.vehicleNumber, 'KA-01-1234');
      expect(dp.isOnline, isTrue);
      expect(dp.isOnDelivery, isFalse);
      expect(dp.rating, 4.8);
      expect(dp.totalDeliveries, 250);
      expect(dp.totalEarnings, 45000.50);
      expect(dp.currentLatitude, 12.9141);
      expect(dp.currentLongitude, 77.6501);
      expect(dp.hoursOnlineToday, 6.5);
      expect(dp.tipsToday, 180.0);
    });

    test('handles empty map with defaults', () {
      final dp = DeliveryPartner.fromDashboard({});
      expect(dp.id, '');
      expect(dp.name, 'Driver');
      expect(dp.vehicleType, 'bike');
      expect(dp.isOnline, isFalse);
      expect(dp.rating, 4.5);
      expect(dp.totalDeliveries, 0);
      expect(dp.totalEarnings, 0);
    });
  });

  group('DeliveryPartner.copyWith', () {
    test('overrides specified fields', () {
      const dp = DeliveryPartner(
        id: 'dp1', userId: 'u1', name: 'Test', phone: '+91000',
        isOnline: false, currentLatitude: 0, currentLongitude: 0,
      );
      final updated = dp.copyWith(isOnline: true, currentLatitude: 12.0);
      expect(updated.isOnline, isTrue);
      expect(updated.currentLatitude, 12.0);
      expect(updated.name, 'Test');
      expect(updated.id, 'dp1');
    });
  });

  group('DeliveryPartner.empty', () {
    test('has empty id and name', () {
      expect(DeliveryPartner.empty.id, '');
      expect(DeliveryPartner.empty.name, '');
      expect(DeliveryPartner.empty.rating, 0);
    });
  });

  group('DeliveryRequest.fromMap', () {
    test('parses all fields including nested order', () {
      final json = {
        '\$id': 'req_1',
        'order': {
          '\$id': 'ord_1',
          'order_number': 'CHZ-001',
          'customer_id': 'c1',
          'restaurant_id': 'r1',
          'restaurant_name': 'Test',
          'delivery_address_id': 'a1',
          'items': [],
          'item_total': 299,
          'delivery_fee': 40,
          'platform_fee': 5,
          'gst': 15,
          'discount': 0,
          'grand_total': 359,
          'payment_method': 'upi',
          'payment_status': 'paid',
          'status': 'ready',
          'placed_at': '2024-01-15T10:00:00.000Z',
        },
        'restaurant_name': 'Biryani Blues',
        'restaurant_cuisine': 'Hyderabadi',
        'restaurant_address': 'Jubilee Hills',
        'restaurant_latitude': 17.45,
        'restaurant_longitude': 78.38,
        'customer_name': 'Rahul',
        'customer_address': '45, Madhapur',
        'customer_latitude': 17.44,
        'customer_longitude': 78.39,
        'pickup_distance_km': 1.5,
        'delivery_distance_km': 2.7,
        'distance_km': 4.2,
        'estimated_earning': 65.0,
        'special_instructions': 'Leave at gate',
        'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
      };
      final req = DeliveryRequest.fromMap(json);
      expect(req.id, 'req_1');
      expect(req.restaurantName, 'Biryani Blues');
      expect(req.restaurantCuisine, 'Hyderabadi');
      expect(req.customerName, 'Rahul');
      expect(req.pickupDistanceKm, 1.5);
      expect(req.deliveryDistanceKm, 2.7);
      expect(req.distanceKm, 4.2);
      expect(req.estimatedEarning, 65.0);
      expect(req.specialInstructions, 'Leave at gate');
      expect(req.order.id, 'ord_1');
      expect(req.order.status, OrderStatus.ready);
    });

    test('handles empty map', () {
      final req = DeliveryRequest.fromMap({});
      expect(req.id, '');
      expect(req.restaurantName, '');
      expect(req.customerName, 'Customer');
      expect(req.distanceKm, 0);
    });
  });

  group('DeliveryRequest computed properties', () {
    test('secondsRemaining is positive for future expiry', () {
      final req = DeliveryRequest.fromMap({
        'expires_at': DateTime.now().add(const Duration(seconds: 15)).toIso8601String(),
        'order': <String, dynamic>{},
      });
      expect(req.secondsRemaining, greaterThan(0));
      expect(req.secondsRemaining, lessThanOrEqualTo(15));
    });

    test('secondsRemaining is 0 for past expiry', () {
      final req = DeliveryRequest.fromMap({
        'expires_at': DateTime.now().subtract(const Duration(seconds: 5)).toIso8601String(),
        'order': <String, dynamic>{},
      });
      expect(req.secondsRemaining, 0);
    });

    test('hasExpired is true for past expiry', () {
      final req = DeliveryRequest.fromMap({
        'expires_at': DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String(),
        'order': <String, dynamic>{},
      });
      expect(req.hasExpired, isTrue);
    });

    test('countdownFraction between 0 and 1 for active request', () {
      final req = DeliveryRequest.fromMap({
        'expires_at': DateTime.now().add(const Duration(seconds: 15)).toIso8601String(),
        'order': <String, dynamic>{},
      });
      expect(req.countdownFraction, greaterThan(0));
      expect(req.countdownFraction, lessThanOrEqualTo(1.0));
    });
  });

  group('DeliveryMetrics', () {
    test('weeklyProgress clamps to 0..1', () {
      const metrics = DeliveryMetrics(weeklyGoal: 50, weeklyCompleted: 34);
      expect(metrics.weeklyProgress, closeTo(0.68, 0.01));

      const over = DeliveryMetrics(weeklyGoal: 10, weeklyCompleted: 15);
      expect(over.weeklyProgress, 1.0);

      const zero = DeliveryMetrics(weeklyGoal: 0, weeklyCompleted: 5);
      expect(zero.weeklyProgress, 0.0);
    });

    test('weeklyEarningsProgress clamps to 0..1', () {
      const metrics = DeliveryMetrics(
        weeklyEarningsGoal: 15000,
        weeklyEarningsCurrent: 8200,
      );
      expect(metrics.weeklyEarningsProgress, closeTo(0.5467, 0.01));

      const zero = DeliveryMetrics(
        weeklyEarningsGoal: 0,
        weeklyEarningsCurrent: 1000,
      );
      expect(zero.weeklyEarningsProgress, 0.0);
    });

    test('fromDashboard parses all fields', () {
      final metrics = DeliveryMetrics.fromDashboard({
        'today_earnings': 850,
        'today_deliveries': 12,
        'today_distance_km': 38.5,
        'hours_online': 6.5,
        'tips_earned': 180,
        'weekly_earnings_goal': 15000,
        'weekly_earnings_current': 8200,
        'weekly_goal': 50,
        'weekly_completed': 34,
      });
      expect(metrics.todayEarnings, 850.0);
      expect(metrics.todayDeliveries, 12);
      expect(metrics.todayDistanceKm, 38.5);
      expect(metrics.hoursOnline, 6.5);
      expect(metrics.tipsEarned, 180.0);
      expect(metrics.weeklyGoal, 50);
      expect(metrics.weeklyCompleted, 34);
    });

    test('non-zero fixture has non-zero values', () {
      const metrics = DeliveryMetrics(todayEarnings: 500, todayDeliveries: 8);
      expect(metrics.todayEarnings, greaterThan(0));
      expect(metrics.todayDeliveries, greaterThan(0));
    });

    test('copyWith overrides specified fields', () {
      const metrics = DeliveryMetrics(todayEarnings: 100, todayDeliveries: 5);
      final updated = metrics.copyWith(todayEarnings: 200);
      expect(updated.todayEarnings, 200);
      expect(updated.todayDeliveries, 5);
    });
  });

  group('DeliveryStep', () {
    test('has correct labels', () {
      expect(DeliveryStep.goToRestaurant.label, 'Go to Restaurant');
      expect(DeliveryStep.pickUp.label, 'Pick Up Order');
      expect(DeliveryStep.goToCustomer.label, 'Go to Customer');
      expect(DeliveryStep.deliver.label, 'Deliver Order');
    });

    test('has non-empty emoji', () {
      for (final step in DeliveryStep.values) {
        expect(step.emoji.isNotEmpty, isTrue);
      }
    });
  });

  group('ActiveDelivery', () {
    late DeliveryRequest mockReq;

    setUp(() {
      mockReq = DeliveryRequest.fromMap({
        'id': 'req_1',
        'order': {
          '\$id': 'o1',
          'order_number': 'CHZ-001',
          'customer_id': 'c1',
          'restaurant_id': 'r1',
          'restaurant_name': 'R',
          'delivery_address_id': 'a1',
          'items': [],
          'item_total': 100,
          'delivery_fee': 0,
          'platform_fee': 5,
          'gst': 5,
          'discount': 0,
          'grand_total': 110,
          'payment_method': 'upi',
          'payment_status': 'paid',
          'status': 'ready',
          'placed_at': '2024-01-01T00:00:00.000Z',
        },
        'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
      });
    });

    test('defaults to goToRestaurant step', () {
      final ad = ActiveDelivery(request: mockReq, acceptedAt: DateTime.now());
      expect(ad.currentStep, DeliveryStep.goToRestaurant);
      expect(ad.isComplete, isFalse);
    });

    test('isComplete is true only at deliver step', () {
      final ad = ActiveDelivery(
        request: mockReq,
        currentStep: DeliveryStep.deliver,
        acceptedAt: DateTime.now(),
      );
      expect(ad.isComplete, isTrue);
    });

    test('nextStep progresses through steps', () {
      final ad = ActiveDelivery(request: mockReq, acceptedAt: DateTime.now());
      expect(ad.nextStep, DeliveryStep.pickUp);

      final atPickup = ad.copyWith(currentStep: DeliveryStep.pickUp);
      expect(atPickup.nextStep, DeliveryStep.goToCustomer);

      final atCustomer = atPickup.copyWith(currentStep: DeliveryStep.goToCustomer);
      expect(atCustomer.nextStep, DeliveryStep.deliver);

      final atDeliver = atCustomer.copyWith(currentStep: DeliveryStep.deliver);
      expect(atDeliver.nextStep, isNull);
    });
  });
}
