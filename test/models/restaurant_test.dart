import 'package:flutter_test/flutter_test.dart';
import 'package:chizze/features/home/models/restaurant.dart';

void main() {
  group('Restaurant.fromMap', () {
    final sampleMap = {
      '\$id': 'r1',
      'owner_id': 'o1',
      'name': 'Biryani Blues',
      'description': 'Authentic Hyderabadi biryanis',
      'cover_image_url': 'https://example.com/cover.jpg',
      'logo_url': 'https://example.com/logo.jpg',
      'cuisines': ['biryani', 'north_indian'],
      'address': 'HSR Layout, Bengaluru',
      'latitude': 12.9141,
      'longitude': 77.6501,
      'city': 'Bengaluru',
      'rating': 4.5,
      'total_ratings': 2340,
      'price_for_two': 450,
      'avg_delivery_time_min': 35,
      'is_veg_only': false,
      'is_online': true,
      'is_featured': true,
      'is_promoted': false,
      'opening_time': '11:00',
      'closing_time': '23:00',
      'created_at': '2024-01-15T10:00:00.000Z',
    };

    test('parses all fields correctly', () {
      final r = Restaurant.fromMap(sampleMap);
      expect(r.id, 'r1');
      expect(r.ownerId, 'o1');
      expect(r.name, 'Biryani Blues');
      expect(r.description, 'Authentic Hyderabadi biryanis');
      expect(r.coverImageUrl, 'https://example.com/cover.jpg');
      expect(r.logoUrl, 'https://example.com/logo.jpg');
      expect(r.cuisines, ['biryani', 'north_indian']);
      expect(r.address, 'HSR Layout, Bengaluru');
      expect(r.latitude, 12.9141);
      expect(r.longitude, 77.6501);
      expect(r.city, 'Bengaluru');
      expect(r.rating, 4.5);
      expect(r.totalRatings, 2340);
      expect(r.priceForTwo, 450);
      expect(r.avgDeliveryTimeMin, 35);
      expect(r.isVegOnly, isFalse);
      expect(r.isOnline, isTrue);
      expect(r.isFeatured, isTrue);
      expect(r.isPromoted, isFalse);
      expect(r.openingTime, '11:00');
      expect(r.closingTime, '23:00');
      expect(r.createdAt.year, 2024);
    });

    test('handles empty map with defaults', () {
      final r = Restaurant.fromMap({});
      expect(r.id, '');
      expect(r.name, '');
      expect(r.cuisines, isEmpty);
      expect(r.latitude, 0.0);
      expect(r.longitude, 0.0);
      expect(r.rating, 0.0);
      expect(r.totalRatings, 0);
      expect(r.priceForTwo, 0);
      expect(r.avgDeliveryTimeMin, 30);
      expect(r.isVegOnly, isFalse);
      expect(r.isOnline, isFalse);
      expect(r.isFeatured, isFalse);
      expect(r.isPromoted, isFalse);
      expect(r.openingTime, '09:00');
      expect(r.closingTime, '23:00');
    });
  });

  group('Restaurant.toMap', () {
    test('round-trip preserves key fields', () {
      final original = Restaurant.fromMap({
        '\$id': 'r1',
        'owner_id': 'o1',
        'name': 'Test Restaurant',
        'description': 'Desc',
        'cover_image_url': '',
        'logo_url': '',
        'cuisines': ['pizza'],
        'address': 'Addr',
        'latitude': 12.0,
        'longitude': 77.0,
        'city': 'City',
        'rating': 4.0,
        'total_ratings': 100,
        'price_for_two': 300,
        'avg_delivery_time_min': 25,
        'is_veg_only': true,
        'is_online': true,
        'opening_time': '08:00',
        'closing_time': '22:00',
        'created_at': '2024-06-01T12:00:00.000Z',
      });
      final map = original.toMap();
      expect(map['name'], 'Test Restaurant');
      expect(map['cuisines'], ['pizza']);
      expect(map['latitude'], 12.0);
      expect(map['is_veg_only'], true);
      expect(map['is_online'], true);
      expect(map['price_for_two'], 300);
      // toMap does not include $id (server-assigned)
      expect(map.containsKey('\$id'), isFalse);
    });
  });

  group('Restaurant.mockList', () {
    test('returns non-empty list', () {
      expect(Restaurant.mockList.isNotEmpty, isTrue);
      expect(Restaurant.mockList.length, greaterThanOrEqualTo(3));
    });

    test('all mock restaurants have valid fields', () {
      for (final r in Restaurant.mockList) {
        expect(r.id.isNotEmpty, isTrue);
        expect(r.name.isNotEmpty, isTrue);
        expect(r.cuisines.isNotEmpty, isTrue);
        expect(r.latitude, isNot(0));
        expect(r.longitude, isNot(0));
        expect(r.priceForTwo, greaterThan(0));
      }
    });

    test('has at least one veg-only restaurant', () {
      expect(
        Restaurant.mockList.any((r) => r.isVegOnly),
        isTrue,
      );
    });
  });
}
