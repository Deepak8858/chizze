import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/restaurant/models/menu_item.dart';

void main() {
  group('CustomizationOption', () {
    test('fromMap parses name and price', () {
      final opt = CustomizationOption.fromMap({'name': 'Large', 'price': 100});
      expect(opt.name, 'Large');
      expect(opt.price, 100.0);
    });

    test('fromMap defaults price to 0', () {
      final opt = CustomizationOption.fromMap({'name': 'Regular'});
      expect(opt.price, 0.0);
    });

    test('toMap round-trips', () {
      const opt = CustomizationOption(name: 'Extra Cheese', price: 50);
      final map = opt.toMap();
      final restored = CustomizationOption.fromMap(map);
      expect(restored.name, 'Extra Cheese');
      expect(restored.price, 50.0);
    });
  });

  group('CustomizationGroup', () {
    test('fromMap with "group" key', () {
      final g = CustomizationGroup.fromMap({
        'group': 'Portion',
        'options': [
          {'name': 'Regular', 'price': 0},
          {'name': 'Large', 'price': 100},
        ],
        'is_required': true,
        'max_selections': 1,
      });
      expect(g.name, 'Portion');
      expect(g.options.length, 2);
      expect(g.isRequired, isTrue);
      expect(g.maxSelections, 1);
    });

    test('fromMap with "name" key fallback', () {
      final g = CustomizationGroup.fromMap({
        'name': 'Toppings',
        'options': [],
      });
      expect(g.name, 'Toppings');
    });

    test('toMap round-trips', () {
      final g = CustomizationGroup(
        name: 'Size',
        options: const [
          CustomizationOption(name: 'S', price: 0),
          CustomizationOption(name: 'L', price: 50),
        ],
        isRequired: true,
        maxSelections: 1,
      );
      final map = g.toMap();
      expect(map['group'], 'Size');
      expect((map['options'] as List).length, 2);
      expect(map['is_required'], true);
      expect(map['max_selections'], 1);
    });
  });

  group('MenuCategory', () {
    test('fromMap parses all fields', () {
      final c = MenuCategory.fromMap({
        '\$id': 'cat1',
        'restaurant_id': 'r1',
        'name': 'Starters',
        'sort_order': 2,
        'is_active': true,
      });
      expect(c.id, 'cat1');
      expect(c.restaurantId, 'r1');
      expect(c.name, 'Starters');
      expect(c.sortOrder, 2);
      expect(c.isActive, isTrue);
    });

    test('fromMap defaults', () {
      final c = MenuCategory.fromMap({});
      expect(c.id, '');
      expect(c.name, '');
      expect(c.sortOrder, 0);
      expect(c.isActive, isTrue);
    });
  });

  group('MenuItem.fromMap', () {
    test('parses all fields', () {
      final map = {
        '\$id': 'm1',
        'restaurant_id': 'r1',
        'category_id': 'c1',
        'name': 'Chicken Biryani',
        'description': 'Fragrant rice',
        'price': 299,
        'image_url': 'https://img.com/b.jpg',
        'is_veg': false,
        'is_available': true,
        'is_bestseller': true,
        'is_must_try': false,
        'spice_level': 'medium',
        'preparation_time_min': 25,
        'calories': 650,
        'allergens': ['dairy', 'nuts'],
        'sort_order': 1,
        'customizations': [
          {
            'group': 'Portion',
            'options': [
              {'name': 'Regular', 'price': 0},
              {'name': 'Large', 'price': 100},
            ],
            'is_required': true,
            'max_selections': 1,
          },
        ],
      };
      final item = MenuItem.fromMap(map);
      expect(item.id, 'm1');
      expect(item.restaurantId, 'r1');
      expect(item.categoryId, 'c1');
      expect(item.name, 'Chicken Biryani');
      expect(item.price, 299.0);
      expect(item.isVeg, isFalse);
      expect(item.isAvailable, isTrue);
      expect(item.isBestseller, isTrue);
      expect(item.isMustTry, isFalse);
      expect(item.spiceLevel, 'medium');
      expect(item.preparationTimeMin, 25);
      expect(item.calories, 650);
      expect(item.allergens, ['dairy', 'nuts']);
      expect(item.sortOrder, 1);
      expect(item.customizations.length, 1);
      expect(item.customizations[0].name, 'Portion');
      expect(item.customizations[0].options.length, 2);
    });

    test('parses customizations from JSON string', () {
      final customizations = [
        {
          'group': 'Size',
          'options': [{'name': 'Regular', 'price': 0}],
        },
      ];
      final map = {
        'name': 'Pizza',
        'price': 399,
        'is_veg': true,
        'customizations': jsonEncode(customizations),
      };
      final item = MenuItem.fromMap(map);
      expect(item.customizations.length, 1);
      expect(item.customizations[0].name, 'Size');
    });

    test('handles invalid customizations JSON gracefully', () {
      final map = {
        'name': 'Pizza',
        'price': 399,
        'is_veg': true,
        'customizations': 'not-valid-json{{{',
      };
      final item = MenuItem.fromMap(map);
      expect(item.customizations, isEmpty);
    });

    test('handles empty map with defaults', () {
      final item = MenuItem.fromMap({});
      expect(item.id, '');
      expect(item.name, '');
      expect(item.price, 0.0);
      expect(item.isVeg, isFalse);
      expect(item.isAvailable, isTrue);
      expect(item.isBestseller, isFalse);
      expect(item.spiceLevel, 'mild');
      expect(item.preparationTimeMin, 20);
      expect(item.customizations, isEmpty);
      expect(item.calories, 0);
      expect(item.allergens, isEmpty);
    });
  });

  group('MenuItem.mockListForRestaurant', () {
    test('returns items for given restaurant', () {
      final items = MenuItem.mockListForRestaurant('r1');
      expect(items.isNotEmpty, isTrue);
      expect(items.every((i) => i.restaurantId == 'r1'), isTrue);
    });

    test('has both veg and non-veg items', () {
      final items = MenuItem.mockListForRestaurant('r1');
      expect(items.any((i) => i.isVeg), isTrue);
      expect(items.any((i) => !i.isVeg), isTrue);
    });

    test('has at least one item with customizations', () {
      final items = MenuItem.mockListForRestaurant('r1');
      expect(items.any((i) => i.customizations.isNotEmpty), isTrue);
    });
  });

  group('MenuItem.mockCategoriesForRestaurant', () {
    test('returns categories with correct restaurant', () {
      final cats = MenuItem.mockCategoriesForRestaurant('r2');
      expect(cats.isNotEmpty, isTrue);
      expect(cats.every((c) => c.restaurantId == 'r2'), isTrue);
    });

    test('categories are sorted', () {
      final cats = MenuItem.mockCategoriesForRestaurant('r1');
      for (int i = 1; i < cats.length; i++) {
        expect(cats[i].sortOrder, greaterThanOrEqualTo(cats[i - 1].sortOrder));
      }
    });
  });
}
