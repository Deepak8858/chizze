/// Restaurant data model — maps to Appwrite `restaurants` collection
class Restaurant {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String coverImageUrl;
  final String logoUrl;
  final List<String> cuisines;
  final String address;
  final double latitude;
  final double longitude;
  final String city;
  final double rating;
  final int totalRatings;
  final int priceForTwo;
  final int avgDeliveryTimeMin;
  final bool isVegOnly;
  final bool isOnline;
  final bool isFeatured;
  final bool isPromoted;
  final String openingTime;
  final String closingTime;
  final DateTime createdAt;

  const Restaurant({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.coverImageUrl,
    required this.logoUrl,
    required this.cuisines,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.rating,
    required this.totalRatings,
    required this.priceForTwo,
    required this.avgDeliveryTimeMin,
    required this.isVegOnly,
    required this.isOnline,
    this.isFeatured = false,
    this.isPromoted = false,
    required this.openingTime,
    required this.closingTime,
    required this.createdAt,
  });

  factory Restaurant.fromMap(Map<String, dynamic> map) {
    return Restaurant(
      id: map['\$id'] ?? '',
      ownerId: map['owner_id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      coverImageUrl: map['cover_image_url'] ?? '',
      logoUrl: map['logo_url'] ?? '',
      cuisines: List<String>.from(map['cuisines'] ?? []),
      address: map['address'] ?? '',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      city: map['city'] ?? '',
      rating: (map['rating'] ?? 0).toDouble(),
      totalRatings: map['total_ratings'] ?? 0,
      priceForTwo: map['price_for_two'] ?? 0,
      avgDeliveryTimeMin: map['avg_delivery_time_min'] ?? 30,
      isVegOnly: map['is_veg_only'] ?? false,
      isOnline: map['is_online'] ?? false,
      isFeatured: map['is_featured'] ?? false,
      isPromoted: map['is_promoted'] ?? false,
      openingTime: map['opening_time'] ?? '09:00',
      closingTime: map['closing_time'] ?? '23:00',
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'owner_id': ownerId,
      'name': name,
      'description': description,
      'cover_image_url': coverImageUrl,
      'logo_url': logoUrl,
      'cuisines': cuisines,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'rating': rating,
      'total_ratings': totalRatings,
      'price_for_two': priceForTwo,
      'avg_delivery_time_min': avgDeliveryTimeMin,
      'is_veg_only': isVegOnly,
      'is_online': isOnline,
      'is_featured': isFeatured,
      'is_promoted': isPromoted,
      'opening_time': openingTime,
      'closing_time': closingTime,
    };
  }


}
