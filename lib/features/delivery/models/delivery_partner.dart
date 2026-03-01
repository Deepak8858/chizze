import 'package:flutter/foundation.dart';

import '../../../features/orders/models/order.dart';

/// Delivery partner profile model
class DeliveryPartner {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String avatarUrl;
  final String vehicleType; // bike | scooter | bicycle | car
  final String vehicleNumber;
  final bool isOnline;
  final bool isOnDelivery;
  final double rating;
  final int totalDeliveries;
  final double totalEarnings;
  final double currentLatitude;
  final double currentLongitude;
  final double hoursOnlineToday;
  final double tipsToday;

  const DeliveryPartner({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    this.avatarUrl = '',
    this.vehicleType = 'bike',
    this.vehicleNumber = '',
    this.isOnline = false,
    this.isOnDelivery = false,
    this.rating = 4.5,
    this.totalDeliveries = 0,
    this.totalEarnings = 0,
    this.currentLatitude = 0,
    this.currentLongitude = 0,
    this.hoursOnlineToday = 0,
    this.tipsToday = 0,
  });

  DeliveryPartner copyWith({
    String? vehicleType,
    String? vehicleNumber,
    bool? isOnline,
    bool? isOnDelivery,
    double? currentLatitude,
    double? currentLongitude,
    double? hoursOnlineToday,
    double? tipsToday,
    double? rating,
    int? totalDeliveries,
    double? totalEarnings,
  }) {
    return DeliveryPartner(
      id: id,
      userId: userId,
      name: name,
      phone: phone,
      avatarUrl: avatarUrl,
      vehicleType: vehicleType ?? this.vehicleType,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      isOnline: isOnline ?? this.isOnline,
      isOnDelivery: isOnDelivery ?? this.isOnDelivery,
      rating: rating ?? this.rating,
      totalDeliveries: totalDeliveries ?? this.totalDeliveries,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      hoursOnlineToday: hoursOnlineToday ?? this.hoursOnlineToday,
      tipsToday: tipsToday ?? this.tipsToday,
    );
  }

  /// Parse from dashboard API response
  factory DeliveryPartner.fromDashboard(Map<String, dynamic> json) {
    return DeliveryPartner(
      id: json['\$id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Driver',
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      vehicleType: json['vehicle_type'] as String? ?? 'bike',
      vehicleNumber: json['vehicle_number'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      isOnDelivery: json['is_on_delivery'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      totalDeliveries: (json['total_deliveries'] as num?)?.toInt() ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0,
      currentLatitude: (json['current_latitude'] as num?)?.toDouble() ?? 0,
      currentLongitude: (json['current_longitude'] as num?)?.toDouble() ?? 0,
      hoursOnlineToday: (json['hours_online_today'] as num?)?.toDouble() ?? 0,
      tipsToday: (json['tips_today'] as num?)?.toDouble() ?? 0,
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
  final String restaurantCuisine;
  final String restaurantAddress;
  final String restaurantPhone;
  final double restaurantLatitude;
  final double restaurantLongitude;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final double customerLatitude;
  final double customerLongitude;
  final double pickupDistanceKm;
  final double deliveryDistanceKm;
  final double distanceKm; // total
  final double estimatedEarning;
  final String specialInstructions;
  final DateTime expiresAt; // countdown deadline

  const DeliveryRequest({
    required this.id,
    required this.order,
    required this.restaurantName,
    this.restaurantCuisine = '',
    this.restaurantAddress = '',
    this.restaurantPhone = '',
    this.restaurantLatitude = 0,
    this.restaurantLongitude = 0,
    this.customerName = 'Customer',
    this.customerPhone = '',
    this.customerAddress = '',
    this.customerLatitude = 0,
    this.customerLongitude = 0,
    this.pickupDistanceKm = 0,
    this.deliveryDistanceKm = 0,
    this.distanceKm = 0,
    this.estimatedEarning = 0,
    this.specialInstructions = '',
    required this.expiresAt,
  });

  int get secondsRemaining {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Countdown fraction based on actual expiry window.
  /// Falls back to 60s if placedAt is missing or produces an invalid window.
  double get countdownFraction {
    if (secondsRemaining <= 0) return 0;
    final placed = order.placedAt;
    if (placed == null) {
      debugPrint('[DeliveryRequest] countdownFraction: order.placedAt is null '
          '(orderId=${order.id}), using 60s fallback denominator');
      return (secondsRemaining / 60).clamp(0.0, 1.0);
    }
    // Compute total window from order placement to expiry
    final totalWindow = expiresAt.difference(placed).inSeconds;
    final denominator = totalWindow > 0 ? totalWindow : 60;
    return (secondsRemaining / denominator).clamp(0.0, 1.0);
  }

  bool get hasExpired => secondsRemaining <= 0;

  /// Parse from API / realtime event
  factory DeliveryRequest.fromMap(Map<String, dynamic> json) {
    final orderMap = json['order'] as Map<String, dynamic>? ?? {};
    return DeliveryRequest(
      id: json['\$id'] as String? ?? json['id'] as String? ?? '',
      order: Order.fromMap(orderMap),
      restaurantName: json['restaurant_name'] as String? ?? '',
      restaurantCuisine: json['restaurant_cuisine'] as String? ?? '',
      restaurantAddress: json['restaurant_address'] as String? ?? '',
      restaurantPhone: json['restaurant_phone'] as String? ?? '',
      restaurantLatitude:
          (json['restaurant_latitude'] as num?)?.toDouble() ?? 0,
      restaurantLongitude:
          (json['restaurant_longitude'] as num?)?.toDouble() ?? 0,
      customerName: json['customer_name'] as String? ?? 'Customer',
      customerPhone: json['customer_phone'] as String? ?? '',
      customerAddress: json['customer_address'] as String? ?? '',
      customerLatitude:
          (json['customer_latitude'] as num?)?.toDouble() ?? 0,
      customerLongitude:
          (json['customer_longitude'] as num?)?.toDouble() ?? 0,
      pickupDistanceKm:
          (json['pickup_distance_km'] as num?)?.toDouble() ?? 0,
      deliveryDistanceKm:
          (json['delivery_distance_km'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      estimatedEarning:
          (json['estimated_earning'] as num?)?.toDouble() ?? 0,
      specialInstructions: json['special_instructions'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.now().add(const Duration(seconds: 30)),
    );
  }


}

/// Delivery metrics for dashboard
class DeliveryMetrics {
  final double todayEarnings;
  final int todayDeliveries;
  final double todayDistanceKm;
  final double hoursOnline;
  final double tipsEarned;
  final double weeklyEarningsGoal; // amount target
  final double weeklyEarningsCurrent;
  final int weeklyGoal; // delivery count target
  final int weeklyCompleted;

  const DeliveryMetrics({
    this.todayEarnings = 0,
    this.todayDeliveries = 0,
    this.todayDistanceKm = 0,
    this.hoursOnline = 0,
    this.tipsEarned = 0,
    this.weeklyEarningsGoal = 15000,
    this.weeklyEarningsCurrent = 0,
    this.weeklyGoal = 50,
    this.weeklyCompleted = 0,
  });

  double get weeklyProgress =>
      weeklyGoal > 0 ? (weeklyCompleted / weeklyGoal).clamp(0.0, 1.0) : 0;

  double get weeklyEarningsProgress =>
      weeklyEarningsGoal > 0
          ? (weeklyEarningsCurrent / weeklyEarningsGoal).clamp(0.0, 1.0)
          : 0;

  /// Parse from dashboard API response
  factory DeliveryMetrics.fromDashboard(Map<String, dynamic> json) {
    final hoursOnline =
      (json['hours_online_today'] as num?)?.toDouble() ??
      (json['hours_online'] as num?)?.toDouble() ??
      0;
    final tipsEarned =
      (json['tips_today'] as num?)?.toDouble() ??
      (json['tips_earned'] as num?)?.toDouble() ??
      0;

    return DeliveryMetrics(
      todayEarnings: (json['today_earnings'] as num?)?.toDouble() ?? 0,
      todayDeliveries: (json['today_deliveries'] as num?)?.toInt() ?? 0,
      todayDistanceKm: (json['today_distance_km'] as num?)?.toDouble() ?? 0,
      hoursOnline: hoursOnline,
      tipsEarned: tipsEarned,
      weeklyEarningsGoal:
          (json['weekly_earnings_goal'] as num?)?.toDouble() ?? 15000,
      weeklyEarningsCurrent:
          (json['weekly_earnings_current'] as num?)?.toDouble() ?? 0,
      weeklyGoal: (json['weekly_goal'] as num?)?.toInt() ?? 50,
      weeklyCompleted: (json['weekly_completed'] as num?)?.toInt() ?? 0,
    );
  }

  DeliveryMetrics copyWith({
    double? todayEarnings,
    int? todayDeliveries,
    double? todayDistanceKm,
    double? hoursOnline,
    double? tipsEarned,
    double? weeklyEarningsCurrent,
    int? weeklyCompleted,
  }) {
    return DeliveryMetrics(
      todayEarnings: todayEarnings ?? this.todayEarnings,
      todayDeliveries: todayDeliveries ?? this.todayDeliveries,
      todayDistanceKm: todayDistanceKm ?? this.todayDistanceKm,
      hoursOnline: hoursOnline ?? this.hoursOnline,
      tipsEarned: tipsEarned ?? this.tipsEarned,
      weeklyEarningsGoal: weeklyEarningsGoal,
      weeklyEarningsCurrent:
          weeklyEarningsCurrent ?? this.weeklyEarningsCurrent,
      weeklyGoal: weeklyGoal,
      weeklyCompleted: weeklyCompleted ?? this.weeklyCompleted,
    );
  }


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
