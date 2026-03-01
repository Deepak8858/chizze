import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/orders/models/order.dart';

void main() {
  group('OrderStatus', () {
    test('fromString maps all known status values', () {
      expect(OrderStatus.fromString('placed'), OrderStatus.placed);
      expect(OrderStatus.fromString('confirmed'), OrderStatus.confirmed);
      expect(OrderStatus.fromString('preparing'), OrderStatus.preparing);
      expect(OrderStatus.fromString('ready'), OrderStatus.ready);
      expect(OrderStatus.fromString('pickedUp'), OrderStatus.pickedUp);
      expect(
        OrderStatus.fromString('outForDelivery'),
        OrderStatus.outForDelivery,
      );
      expect(OrderStatus.fromString('picked_up'), OrderStatus.pickedUp);
      expect(OrderStatus.fromString('out_for_delivery'), OrderStatus.outForDelivery);
      expect(OrderStatus.fromString('delivered'), OrderStatus.delivered);
      expect(OrderStatus.fromString('cancelled'), OrderStatus.cancelled);
    });

    test('fromString defaults to placed for unknown value', () {
      expect(OrderStatus.fromString('unknown'), OrderStatus.placed);
      expect(OrderStatus.fromString(''), OrderStatus.placed);
    });

    test('progress returns correct values', () {
      expect(OrderStatus.placed.progress, 0.0);
      expect(OrderStatus.confirmed.progress, 0.17);
      expect(OrderStatus.preparing.progress, 0.33);
      expect(OrderStatus.ready.progress, 0.50);
      expect(OrderStatus.pickedUp.progress, 0.67);
      expect(OrderStatus.outForDelivery.progress, 0.83);
      expect(OrderStatus.delivered.progress, 1.0);
      expect(OrderStatus.cancelled.progress, 0.0);
    });

    test('isActive is true for non-terminal statuses', () {
      expect(OrderStatus.placed.isActive, isTrue);
      expect(OrderStatus.confirmed.isActive, isTrue);
      expect(OrderStatus.preparing.isActive, isTrue);
      expect(OrderStatus.ready.isActive, isTrue);
      expect(OrderStatus.pickedUp.isActive, isTrue);
      expect(OrderStatus.outForDelivery.isActive, isTrue);
    });

    test('isActive is false for terminal statuses', () {
      expect(OrderStatus.delivered.isActive, isFalse);
      expect(OrderStatus.cancelled.isActive, isFalse);
    });

    test('value matches API status string', () {
      const expectedValues = {
        OrderStatus.placed: 'placed',
        OrderStatus.confirmed: 'confirmed',
        OrderStatus.preparing: 'preparing',
        OrderStatus.ready: 'ready',
        OrderStatus.pickedUp: 'pickedUp',
        OrderStatus.outForDelivery: 'outForDelivery',
        OrderStatus.delivered: 'delivered',
        OrderStatus.cancelled: 'cancelled',
      };
      // Ensure every enum member is covered
      expect(expectedValues.length, OrderStatus.values.length);
      for (final status in OrderStatus.values) {
        expect(
          status.value,
          expectedValues[status],
          reason: '${status.name}.value should be ${expectedValues[status]}',
        );
      }
    });

    test('label and emoji are non-empty', () {
      for (final status in OrderStatus.values) {
        expect(status.label.isNotEmpty, isTrue, reason: '${status.name} label');
        expect(status.emoji.isNotEmpty, isTrue, reason: '${status.name} emoji');
      }
    });
  });

  group('OrderItem', () {
    test('fromMap parses correctly', () {
      final map = {
        'item_id': 'i1',
        'name': 'Biryani',
        'quantity': 2,
        'price': 299,
        'is_veg': false,
        'customizations': 'Extra spicy',
      };
      final item = OrderItem.fromMap(map);
      expect(item.id, 'i1');
      expect(item.name, 'Biryani');
      expect(item.quantity, 2);
      expect(item.price, 299.0);
      expect(item.isVeg, isFalse);
      expect(item.customizations, 'Extra spicy');
    });

    test('fromMap handles missing fields', () {
      final item = OrderItem.fromMap({});
      expect(item.id, '');
      expect(item.name, '');
      expect(item.quantity, 1);
      expect(item.price, 0.0);
      expect(item.isVeg, isFalse);
      expect(item.customizations, isNull);
    });

    test('toMap round-trips correctly', () {
      const item = OrderItem(
        id: 'i1', name: 'Naan', quantity: 3,
        price: 59, isVeg: true, customizations: 'Butter',
      );
      final map = item.toMap();
      expect(map['item_id'], 'i1');
      expect(map['name'], 'Naan');
      expect(map['quantity'], 3);
      expect(map['price'], 59.0);
      expect(map['is_veg'], true);
      expect(map['customizations'], 'Butter');
    });

    test('fromMap uses "id" fallback if "item_id" absent', () {
      final item = OrderItem.fromMap({'id': 'fallback_id'});
      expect(item.id, 'fallback_id');
    });
  });

  group('Order.fromMap', () {
    final sampleMap = {
      '\$id': 'ord_1',
      'order_number': 'CHZ-240001',
      'customer_id': 'c1',
      'restaurant_id': 'r1',
      'restaurant_name': 'Biryani Blues',
      'delivery_partner_id': 'dp1',
      'delivery_address_id': 'a1',
      'items': [
        {'item_id': 'i1', 'name': 'Biryani', 'quantity': 1, 'price': 299, 'is_veg': false},
      ],
      'item_total': 299,
      'delivery_fee': 40,
      'platform_fee': 5,
      'gst': 14.95,
      'discount': 0,
      'coupon_code': null,
      'tip': 20,
      'grand_total': 378.95,
      'payment_method': 'upi',
      'payment_status': 'paid',
      'status': 'confirmed',
      'special_instructions': 'No onions',
      'delivery_instructions': 'Ring doorbell',
      'estimated_delivery_min': 25,
      'placed_at': '2024-01-15T10:30:00.000Z',
      'confirmed_at': '2024-01-15T10:32:00.000Z',
    };

    test('parses all top-level fields', () {
      final order = Order.fromMap(sampleMap);
      expect(order.id, 'ord_1');
      expect(order.orderNumber, 'CHZ-240001');
      expect(order.customerId, 'c1');
      expect(order.restaurantId, 'r1');
      expect(order.restaurantName, 'Biryani Blues');
      expect(order.deliveryPartnerId, 'dp1');
      expect(order.deliveryAddressId, 'a1');
      expect(order.itemTotal, 299.0);
      expect(order.deliveryFee, 40.0);
      expect(order.platformFee, 5.0);
      expect(order.gst, 14.95);
      expect(order.discount, 0.0);
      expect(order.tip, 20.0);
      expect(order.grandTotal, 378.95);
      expect(order.paymentMethod, 'upi');
      expect(order.paymentStatus, 'paid');
      expect(order.status, OrderStatus.confirmed);
      expect(order.specialInstructions, 'No onions');
      expect(order.deliveryInstructions, 'Ring doorbell');
      expect(order.estimatedDeliveryMin, 25);
    });

    test('parses items list', () {
      final order = Order.fromMap(sampleMap);
      expect(order.items.length, 1);
      expect(order.items[0].name, 'Biryani');
    });

    test('parses datetime fields', () {
      final order = Order.fromMap(sampleMap);
      expect(order.placedAt, isNotNull);
      expect(order.placedAt!.year, 2024);
      expect(order.confirmedAt, isNotNull);
      expect(order.preparedAt, isNull);
      expect(order.deliveredAt, isNull);
    });

    test('handles empty map with defaults', () {
      final order = Order.fromMap({});
      expect(order.id, '');
      expect(order.orderNumber, '');
      expect(order.items, isEmpty);
      expect(order.status, OrderStatus.placed);
      expect(order.paymentMethod, 'upi');
      expect(order.estimatedDeliveryMin, 30);
    });
  });

  group('Order.toMap', () {
    test('round-trip preserves key fields', () {
      final original = Order.fromMap({
        '\$id': 'ord_1',
        'order_number': 'CHZ-001',
        'customer_id': 'c1',
        'restaurant_id': 'r1',
        'restaurant_name': 'Test',
        'delivery_address_id': 'a1',
        'items': [],
        'item_total': 100,
        'delivery_fee': 40,
        'platform_fee': 5,
        'gst': 5,
        'discount': 0,
        'grand_total': 150,
        'payment_method': 'card',
        'payment_status': 'pending',
        'status': 'preparing',
        'placed_at': '2024-06-01T12:00:00.000Z',
      });
      final map = original.toMap();
      expect(map['order_number'], 'CHZ-001');
      expect(map['status'], 'preparing');
      expect(map['payment_method'], 'card');
      expect(map['item_total'], 100.0);
      expect(map['grand_total'], 150.0);
    });
  });

  group('Order.copyWith', () {
    test('copies with new status', () {
      final order = Order.fromMap({
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
        'status': 'placed',
        'placed_at': '2024-01-01T00:00:00.000Z',
      });
      final updated = order.copyWith(status: OrderStatus.confirmed);
      expect(updated.status, OrderStatus.confirmed);
      expect(updated.id, order.id);
      expect(updated.orderNumber, order.orderNumber);
    });

    test('preserves original when no arguments', () {
      final order = Order.fromMap({
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
        'status': 'placed',
        'placed_at': '2024-01-01T00:00:00.000Z',
      });
      final copy = order.copyWith();
      expect(copy.status, order.status);
      expect(copy.paymentStatus, order.paymentStatus);
    });
  });

}
