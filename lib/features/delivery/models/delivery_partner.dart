import '../../../features/orders/models/order.dart';

/// Delivery partner profile model
class DeliveryPartner {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String vehicleType; // bike | scooter | bicycle | car
  final String vehicleNumber;
  final bool isOnline;
  final bool isOnDelivery;
  final double rating;
  final int totalDeliveries;
  final double totalEarnings;
  final double currentLatitude;
  final double currentLongitude;

  const DeliveryPartner({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    this.vehicleType = 'bike',
    this.vehicleNumber = '',
    this.isOnline = false,
    this.isOnDelivery = false,
    this.rating = 4.5,
    this.totalDeliveries = 0,
    this.totalEarnings = 0,
    this.currentLatitude = 0,
    this.currentLongitude = 0,
  });

  DeliveryPartner copyWith({
    bool? isOnline,
    bool? isOnDelivery,
    double? currentLatitude,
    double? currentLongitude,
  }) {
    return DeliveryPartner(
      id: id,
      userId: userId,
      name: name,
      phone: phone,
      vehicleType: vehicleType,
      vehicleNumber: vehicleNumber,
      isOnline: isOnline ?? this.isOnline,
      isOnDelivery: isOnDelivery ?? this.isOnDelivery,
      rating: rating,
      totalDeliveries: totalDeliveries,
      totalEarnings: totalEarnings,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
    );
  }

  /// Parse from dashboard API response
  factory DeliveryPartner.fromDashboard(Map<String, dynamic> json) {
    return DeliveryPartner(
      id: json['\$id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Driver',
      phone: json['phone'] as String? ?? '',
      vehicleType: json['vehicle_type'] as String? ?? 'bike',
      vehicleNumber: json['vehicle_number'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      isOnDelivery: json['is_on_delivery'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      totalDeliveries: (json['total_deliveries'] as num?)?.toInt() ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      currentLatitude: (json['current_latitude'] as num?)?.toDouble() ?? 0,
      currentLongitude: (json['current_longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  static const empty = DeliveryPartner(
    id: '',
    userId: '',
    name: '',
    phone: '',
    vehicleType: 'bike',
    vehicleNumber: '',
    isOnline: false,
    rating: 0,
    totalDeliveries: 0,
    totalEarnings: 0,
    currentLatitude: 0,
    currentLongitude: 0,
  );
}

/// Incoming delivery request
class DeliveryRequest {
  final String id;
  final Order order;
  final String restaurantName;
  final String restaurantAddress;
  final double restaurantLatitude;
  final double restaurantLongitude;
  final String customerAddress;
  final double customerLatitude;
  final double customerLongitude;
  final double distanceKm;
  final double estimatedEarning;
  final DateTime expiresAt; // countdown deadline

  const DeliveryRequest({
    required this.id,
    required this.order,
    required this.restaurantName,
    this.restaurantAddress = '',
    this.restaurantLatitude = 17.4486,
    this.restaurantLongitude = 78.3810,
    this.customerAddress = '',
    this.customerLatitude = 17.4401,
    this.customerLongitude = 78.3911,
    this.distanceKm = 0,
    this.estimatedEarning = 0,
    required this.expiresAt,
  });

  int get secondsRemaining {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get hasExpired => secondsRemaining <= 0;

  static DeliveryRequest mock() {
    final now = DateTime.now();
    return DeliveryRequest(
      id: 'req1',
      order: Order(
        id: 'do1',
        orderNumber: 'CHZ-500001',
        customerId: 'c1',
        restaurantId: 'r1',
        restaurantName: 'Biryani Blues',
        deliveryAddressId: 'a1',
        items: const [
          OrderItem(
            id: 'm1',
            name: 'Chicken Biryani',
            quantity: 2,
            price: 299,
            isVeg: false,
          ),
          OrderItem(
            id: 'm4',
            name: 'Raita',
            quantity: 1,
            price: 49,
            isVeg: true,
          ),
        ],
        itemTotal: 647,
        deliveryFee: 0,
        platformFee: 5,
        gst: 32.35,
        discount: 0,
        grandTotal: 684.35,
        paymentMethod: 'upi',
        paymentStatus: 'paid',
        status: OrderStatus.ready,
        estimatedDeliveryMin: 25,
        placedAt: now.subtract(const Duration(minutes: 15)),
      ),
      restaurantName: 'Biryani Blues',
      restaurantAddress: '12, Jubilee Hills, Hyderabad',
      restaurantLatitude: 17.4486,
      restaurantLongitude: 78.3810,
      customerAddress: '45, Madhapur, Hyderabad',
      customerLatitude: 17.4401,
      customerLongitude: 78.3911,
      distanceKm: 4.2,
      estimatedEarning: 65,
      expiresAt: now.add(const Duration(seconds: 30)),
    );
  }
}

/// Delivery metrics for dashboard
class DeliveryMetrics {
  final double todayEarnings;
  final int todayDeliveries;
  final double todayDistanceKm;
  final int weeklyGoal; // target deliveries for the week
  final int weeklyCompleted;

  const DeliveryMetrics({
    this.todayEarnings = 0,
    this.todayDeliveries = 0,
    this.todayDistanceKm = 0,
    this.weeklyGoal = 50,
    this.weeklyCompleted = 0,
  });

  double get weeklyProgress =>
      weeklyGoal > 0 ? (weeklyCompleted / weeklyGoal).clamp(0.0, 1.0) : 0;

  /// Parse from dashboard API response
  factory DeliveryMetrics.fromDashboard(Map<String, dynamic> json) {
    return DeliveryMetrics(
      todayEarnings: (json['today_earnings'] as num?)?.toDouble() ?? 0,
      todayDeliveries: (json['today_deliveries'] as num?)?.toInt() ?? 0,
      todayDistanceKm: (json['today_distance_km'] as num?)?.toDouble() ?? 0,
      weeklyGoal: (json['weekly_goal'] as num?)?.toInt() ?? 50,
      weeklyCompleted: (json['weekly_completed'] as num?)?.toInt() ?? 0,
    );
  }

  static const mock = DeliveryMetrics(
    todayEarnings: 850,
    todayDeliveries: 12,
    todayDistanceKm: 38.5,
    weeklyGoal: 50,
    weeklyCompleted: 34,
  );
}

/// Active delivery step
enum DeliveryStep {
  goToRestaurant('Go to Restaurant', '🏪'),
  pickUp('Pick Up Order', '📦'),
  goToCustomer('Go to Customer', '🏠'),
  deliver('Deliver Order', '✅');

  final String label;
  final String emoji;
  const DeliveryStep(this.label, this.emoji);
}

/// Active delivery state
class ActiveDelivery {
  final DeliveryRequest request;
  final DeliveryStep currentStep;
  final DateTime acceptedAt;

  const ActiveDelivery({
    required this.request,
    this.currentStep = DeliveryStep.goToRestaurant,
    required this.acceptedAt,
  });

  ActiveDelivery copyWith({DeliveryStep? currentStep}) {
    return ActiveDelivery(
      request: request,
      currentStep: currentStep ?? this.currentStep,
      acceptedAt: acceptedAt,
    );
  }

  bool get isComplete => currentStep == DeliveryStep.deliver;

  DeliveryStep? get nextStep {
    final idx = DeliveryStep.values.indexOf(currentStep);
    if (idx < DeliveryStep.values.length - 1) {
      return DeliveryStep.values[idx + 1];
    }
    return null;
  }
}
