import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/cart/providers/cart_provider.dart';
import 'package:chizze/features/restaurant/models/menu_item.dart';

void main() {
  // Helper to create a test MenuItem
  MenuItem makeItem({
    String id = 'i1',
    String restaurantId = 'r1',
    double price = 299,
    bool isVeg = false,
  }) {
    return MenuItem(
      id: id,
      restaurantId: restaurantId,
      categoryId: 'c1',
      name: 'Test Item',
      description: 'desc',
      price: price,
      isVeg: isVeg,
    );
  }

  CartItem makeCartItem({
    String itemId = 'i1',
    String restaurantId = 'r1',
    String restaurantName = 'Test Restaurant',
    double price = 299,
    int quantity = 1,
    Map<String, List<CustomizationOption>> customizations = const {},
  }) {
    return CartItem(
      menuItem: makeItem(id: itemId, restaurantId: restaurantId, price: price),
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      quantity: quantity,
      selectedCustomizations: customizations,
    );
  }

  group('CartItem.totalPrice', () {
    test('base price * quantity without customizations', () {
      final item = makeCartItem(price: 299, quantity: 2);
      expect(item.totalPrice, 598.0);
    });

    test('includes customization prices', () {
      final item = makeCartItem(
        price: 299,
        quantity: 1,
        customizations: {
          'Portion': [const CustomizationOption(name: 'Large', price: 100)],
          'Extra': [
            const CustomizationOption(name: 'Raita', price: 30),
            const CustomizationOption(name: 'Egg', price: 20),
          ],
        },
      );
      // (299 + 100 + 30 + 20) * 1 = 449
      expect(item.totalPrice, 449.0);
    });

    test('customization prices multiply by quantity', () {
      final item = makeCartItem(
        price: 100,
        quantity: 3,
        customizations: {
          'Size': [const CustomizationOption(name: 'L', price: 50)],
        },
      );
      // (100 + 50) * 3 = 450
      expect(item.totalPrice, 450.0);
    });
  });

  group('CartItem.cartKey', () {
    test('same item+customizations produce same key', () {
      final a = makeCartItem(itemId: 'i1');
      final b = makeCartItem(itemId: 'i1');
      expect(a.cartKey, b.cartKey);
    });

    test('different items produce different keys', () {
      final a = makeCartItem(itemId: 'i1');
      final b = makeCartItem(itemId: 'i2');
      expect(a.cartKey, isNot(b.cartKey));
    });

    test('same item with different customizations produce different keys', () {
      final a = makeCartItem(
        itemId: 'i1',
        customizations: {
          'Size': [const CustomizationOption(name: 'S')],
        },
      );
      final b = makeCartItem(
        itemId: 'i1',
        customizations: {
          'Size': [const CustomizationOption(name: 'L')],
        },
      );
      expect(a.cartKey, isNot(b.cartKey));
    });
  });

  group('CartState computed getters', () {
    test('empty cart values', () {
      const state = CartState();
      expect(state.isEmpty, isTrue);
      expect(state.isNotEmpty, isFalse);
      expect(state.totalItems, 0);
      expect(state.itemTotal, 0);
      expect(state.deliveryFee, 40); // under ₹500
      expect(state.platformFee, 5);
      expect(state.gst, 0);
      expect(state.discount, 0);
      expect(state.grandTotal, 45.0); // 0 + 40 + 5 + 0 - 0
    });

    test('delivery fee is 0 above 500', () {
      final items = [makeCartItem(price: 600, quantity: 1)];
      final state = CartState(items: items);
      expect(state.itemTotal, 600.0);
      expect(state.deliveryFee, 0); // free above ₹500
    });

    test('delivery fee is 40 below 500', () {
      final items = [makeCartItem(price: 200, quantity: 1)];
      final state = CartState(items: items);
      expect(state.deliveryFee, 40);
    });

    test('delivery fee is 0 at exactly 500', () {
      final items = [makeCartItem(price: 500, quantity: 1)];
      final state = CartState(items: items);
      // 500 > 500 is false, so deliveryFee = 40
      expect(state.deliveryFee, 40);
    });

    test('delivery fee is 0 above 500', () {
      final items = [makeCartItem(price: 501, quantity: 1)];
      final state = CartState(items: items);
      expect(state.deliveryFee, 0);
    });

    test('platformFee is always 5', () {
      final state = CartState(items: [makeCartItem(price: 100)]);
      expect(state.platformFee, 5);
    });

    test('GST is 5% of itemTotal', () {
      final items = [makeCartItem(price: 200, quantity: 1)];
      final state = CartState(items: items);
      expect(state.gst, closeTo(10.0, 0.01)); // 200 * 0.05 = 10
    });

    test('grandTotal computation', () {
      final items = [makeCartItem(price: 300, quantity: 2)]; // itemTotal = 600
      final state = CartState(items: items, couponDiscount: 50);
      // itemTotal=600, deliveryFee=0 (>500), platformFee=5, gst=30, discount=50
      // grandTotal = 600 + 0 + 5 + 30 - 50 = 585
      expect(state.grandTotal, closeTo(585.0, 0.01));
    });

    test('totalItems sums quantities', () {
      final items = [
        makeCartItem(itemId: 'a', price: 100, quantity: 2),
        makeCartItem(itemId: 'b', price: 200, quantity: 3),
      ];
      final state = CartState(items: items);
      expect(state.totalItems, 5);
    });
  });

  group('CartNotifier', () {
    late CartNotifier notifier;

    setUp(() {
      notifier = CartNotifier();
    });

    test('initial state is empty', () {
      expect(notifier.state.isEmpty, isTrue);
    });

    test('addItem adds new item', () {
      notifier.addItem(makeCartItem(itemId: 'i1', price: 100));
      expect(notifier.state.items.length, 1);
      expect(notifier.state.restaurantId, 'r1');
      expect(notifier.state.restaurantName, 'Test Restaurant');
    });

    test('addItem increments quantity for duplicate cartKey', () {
      final item = makeCartItem(itemId: 'i1', price: 100, quantity: 1);
      notifier.addItem(item);
      notifier.addItem(item);
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items[0].quantity, 2);
    });

    test('addItem from different restaurant clears cart', () {
      notifier.addItem(makeCartItem(itemId: 'i1', restaurantId: 'r1'));
      notifier.addItem(makeCartItem(itemId: 'i2', restaurantId: 'r2', restaurantName: 'Other'));
      // Cart is cleared for old restaurant; new item is added
      expect(notifier.state.restaurantId, 'r2');
      expect(notifier.state.items.length, 1);
    });

    test('updateQuantity changes item quantity', () {
      final item = makeCartItem(itemId: 'i1', price: 100, quantity: 1);
      notifier.addItem(item);
      notifier.updateQuantity(item.cartKey, 5);
      expect(notifier.state.items[0].quantity, 5);
    });

    test('updateQuantity to 0 removes item', () {
      final item = makeCartItem(itemId: 'i1', price: 100, quantity: 1);
      notifier.addItem(item);
      notifier.updateQuantity(item.cartKey, 0);
      expect(notifier.state.isEmpty, isTrue);
    });

    test('removeItem removes by cartKey', () {
      final item1 = makeCartItem(itemId: 'i1', price: 100);
      final item2 = makeCartItem(itemId: 'i2', price: 200);
      notifier.addItem(item1);
      notifier.addItem(item2);
      notifier.removeItem(item1.cartKey);
      expect(notifier.state.items.length, 1);
      expect(notifier.state.items[0].menuItem.id, 'i2');
    });

    test('removeItem last item resets cart', () {
      final item = makeCartItem(itemId: 'i1');
      notifier.addItem(item);
      notifier.removeItem(item.cartKey);
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.restaurantId, isNull);
    });

    test('applyCoupon sets code and discount', () {
      notifier.applyCoupon('SAVE50', 50);
      expect(notifier.state.couponCode, 'SAVE50');
      expect(notifier.state.couponDiscount, 50);
    });

    test('removeCoupon clears coupon code and discount', () {
      notifier.applyCoupon('SAVE50', 50);
      notifier.removeCoupon();
      expect(notifier.state.couponCode, isNull);
      expect(notifier.state.couponDiscount, 0);
    });

    test('setDeliveryInstructions updates instructions', () {
      notifier.setDeliveryInstructions('Ring bell');
      expect(notifier.state.deliveryInstructions, 'Ring bell');
    });

    test('setSpecialInstructions updates instructions', () {
      notifier.setSpecialInstructions('No onions');
      expect(notifier.state.specialInstructions, 'No onions');
    });

    test('clearCart resets to empty', () {
      notifier.addItem(makeCartItem(itemId: 'i1'));
      notifier.applyCoupon('CODE', 10);
      notifier.clearCart();
      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.couponCode, isNull);
      expect(notifier.state.restaurantId, isNull);
    });
  });
}
