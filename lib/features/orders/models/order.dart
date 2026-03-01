import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Order data model — maps to Appwrite `orders` collection
class Order {
  final String id;
  final String orderNumber;
  final String customerId;
  final String? customerName;
  final String restaurantId;
  final String restaurantName;
  final String? deliveryPartnerId;
  final String? deliveryPartnerName;
  final String? deliveryPartnerPhone;
  final String deliveryAddressId;
  final String? deliveryAddress;
  final String? deliveryLandmark;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final double? restaurantLatitude;
  final double? restaurantLongitude;
  final List<OrderItem> items;
  final double itemTotal;
  final double deliveryFee;
  final double platformFee;
  final double gst;
  final double discount;
  final String? couponCode;
  final double tip;
  final double grandTotal;
  final String paymentMethod;
  final String paymentStatus;
  final String? paymentId;
  final String? razorpayOrderId;
  final OrderStatus status;
  final String specialInstructions;
  final String deliveryInstructions;
  final int estimatedDeliveryMin;
  final DateTime? placedAt;
  final DateTime? confirmedAt;
  final DateTime? preparedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? cancelledBy;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    this.customerName,
    required this.restaurantId,
    required this.restaurantName,
    this.deliveryPartnerId,
    this.deliveryPartnerName,
    this.deliveryPartnerPhone,
    required this.deliveryAddressId,
    this.deliveryAddress,
    this.deliveryLandmark,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.restaurantLatitude,
    this.restaurantLongitude,
    required this.items,
    required this.itemTotal,
    required this.deliveryFee,
    required this.platformFee,
    required this.gst,
    required this.discount,
    this.couponCode,
    this.tip = 0,
    required this.grandTotal,
    required this.paymentMethod,
    required this.paymentStatus,
    this.paymentId,
    this.razorpayOrderId,
    required this.status,
    this.specialInstructions = '',
    this.deliveryInstructions = '',
    this.estimatedDeliveryMin = 30,
    this.placedAt,
    this.confirmedAt,
    this.preparedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancellationReason,
    this.cancelledBy,
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['\$id'] ?? '',
      orderNumber: map['order_number'] ?? '',
      customerId: map['customer_id'] ?? '',
      customerName: map['customer_name'],
      restaurantId: map['restaurant_id'] ?? '',
      restaurantName: map['restaurant_name'] ?? '',
      deliveryPartnerId: map['delivery_partner_id'],
      deliveryPartnerName: map['delivery_partner_name'],
      deliveryPartnerPhone: map['delivery_partner_phone'],
      deliveryAddressId: map['delivery_address_id'] ?? '',
      deliveryAddress: map['delivery_address'],
      deliveryLandmark: map['delivery_landmark'],
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      restaurantLatitude: (map['restaurant_latitude'] as num?)?.toDouble(),
      restaurantLongitude: (map['restaurant_longitude'] as num?)?.toDouble(),
      items: _parseItems(map['items']),
      itemTotal: (map['item_total'] ?? 0).toDouble(),
      deliveryFee: (map['delivery_fee'] ?? 0).toDouble(),
      platformFee: (map['platform_fee'] ?? 0).toDouble(),
      gst: (map['gst'] ?? 0).toDouble(),
      discount: (map['discount'] ?? 0).toDouble(),
      couponCode: map['coupon_code'],
      tip: (map['tip'] ?? 0).toDouble(),
      grandTotal: (map['grand_total'] ?? 0).toDouble(),
      paymentMethod: map['payment_method'] ?? 'upi',
      paymentStatus: map['payment_status'] ?? 'pending',
      paymentId: map['payment_id'],
      razorpayOrderId: map['razorpay_order_id'],
      status: OrderStatus.fromString(map['status'] ?? 'placed'),
      specialInstructions: map['special_instructions'] ?? '',
      deliveryInstructions: map['delivery_instructions'] ?? '',
      estimatedDeliveryMin: map['estimated_delivery_min'] ?? 30,
      placedAt: _parsePlacedAt(map['placed_at']),
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.tryParse(map['confirmed_at'].toString())
          : null,
      preparedAt: map['prepared_at'] != null
          ? DateTime.tryParse(map['prepared_at'].toString())
          : null,
      pickedUpAt: map['picked_up_at'] != null
          ? DateTime.tryParse(map['picked_up_at'].toString())
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.tryParse(map['delivered_at'].toString())
          : null,
      cancelledAt: map['cancelled_at'] != null
          ? DateTime.tryParse(map['cancelled_at'].toString())
          : null,
      cancellationReason: map['cancellation_reason'],
      cancelledBy: map['cancelled_by'],
    );
  }

  /// Parse placed_at with explicit logging when missing/invalid.
  static DateTime? _parsePlacedAt(dynamic raw) {
    if (raw == null || (raw is String && raw.isEmpty)) {
      debugPrint('[Order] placed_at is missing or empty in API response');
      return null;
    }
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) {
      debugPrint('[Order] placed_at failed to parse: "$raw"');
    }
    return parsed;
  }

  /// Parse items field which may be a JSON string (from Appwrite) or a List
  static List<OrderItem> _parseItems(dynamic raw) {
    if (raw == null) return [];
    List<dynamic> itemsList;
    if (raw is String) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          itemsList = decoded;
        } else {
          return [];
        }
      } catch (_) {
        return [];
      }
    } else if (raw is List) {
      itemsList = raw;
    } else {
      return [];
    }
    return itemsList
        .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> toMap() {
    return {
      'order_number': orderNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName,
      'delivery_address_id': deliveryAddressId,
      'delivery_address': deliveryAddress,
      'delivery_landmark': deliveryLandmark,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'restaurant_latitude': restaurantLatitude,
      'restaurant_longitude': restaurantLongitude,
      'items': items.map((i) => i.toMap()).toList(),
      'item_total': itemTotal,
      'delivery_fee': deliveryFee,
      'platform_fee': platformFee,
      'gst': gst,
      'discount': discount,
      'coupon_code': couponCode,
      'tip': tip,
      'grand_total': grandTotal,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'payment_id': paymentId,
      'razorpay_order_id': razorpayOrderId,
      'status': status.value,
      'special_instructions': specialInstructions,
      'delivery_instructions': deliveryInstructions,
      'estimated_delivery_min': estimatedDeliveryMin,
      if (placedAt != null) 'placed_at': placedAt!.toIso8601String(),
    };
  }

  Order copyWith({
    OrderStatus? status,
    String? paymentStatus,
    String? paymentId,
    String? customerName,
    String? deliveryPartnerId,
    String? deliveryPartnerName,
    String? deliveryPartnerPhone,
    DateTime? confirmedAt,
    DateTime? preparedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
  }) {
    return Order(
      id: id,
      orderNumber: orderNumber,
      customerId: customerId,
      customerName: customerName ?? this.customerName,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      deliveryPartnerId: deliveryPartnerId ?? this.deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName ?? this.deliveryPartnerName,
      deliveryPartnerPhone: deliveryPartnerPhone ?? this.deliveryPartnerPhone,
      deliveryAddressId: deliveryAddressId,
      deliveryAddress: deliveryAddress,
      deliveryLandmark: deliveryLandmark,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
      restaurantLatitude: restaurantLatitude,
      restaurantLongitude: restaurantLongitude,
      items: items,
      itemTotal: itemTotal,
      deliveryFee: deliveryFee,
      platformFee: platformFee,
      gst: gst,
      discount: discount,
      couponCode: couponCode,
      tip: tip,
      grandTotal: grandTotal,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentId: paymentId ?? this.paymentId,
      razorpayOrderId: razorpayOrderId,
      status: status ?? this.status,
      specialInstructions: specialInstructions,
      deliveryInstructions: deliveryInstructions,
      estimatedDeliveryMin: estimatedDeliveryMin,
      placedAt: placedAt ?? this.placedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      preparedAt: preparedAt ?? this.preparedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
      cancelledBy: cancelledBy,
    );
  }


}

/// Individual item in an order
class OrderItem {
  final String id;
  final String name;
  final int quantity;
  final double price;
  final bool isVeg;
  final String? customizations;

  const OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.isVeg,
    this.customizations,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['item_id'] ?? map['id'] ?? '',
      name: map['name'] ?? '',
      quantity: map['quantity'] ?? 1,
      price: (map['price'] ?? 0).toDouble(),
      isVeg: map['is_veg'] ?? false,
      customizations: map['customizations'],
    );
  }

  Map<String, dynamic> toMap() => {
    'item_id': id,
    'name': name,
    'quantity': quantity,
    'price': price,
    'is_veg': isVeg,
    'customizations': customizations,
  };
}

/// Order status enum with display labels
enum OrderStatus {
  placed('placed', 'Order Placed', '📋'),
  confirmed('confirmed', 'Confirmed', '✅'),
  preparing('preparing', 'Preparing', '👨‍🍳'),
  ready('ready', 'Ready for Pickup', '📦'),
  pickedUp('pickedUp', 'Picked Up', '🏍️'),
  outForDelivery('outForDelivery', 'Out for Delivery', '🚀'),
  delivered('delivered', 'Delivered', '🎉'),
  cancelled('cancelled', 'Cancelled', '❌');

  final String value;
  final String label;
  final String emoji;
  const OrderStatus(this.value, this.label, this.emoji);

  static String _normalizeStatus(String value) {
    switch (value) {
      case 'picked_up':
        return 'pickedUp';
      case 'out_for_delivery':
        return 'outForDelivery';
      default:
        return value;
    }
  }

  static OrderStatus fromString(String value) {
    final normalized = _normalizeStatus(value);
    return OrderStatus.values.firstWhere(
      (s) => s.value == normalized,
      orElse: () => OrderStatus.placed,
    );
  }

  /// Returns null for unknown values instead of falling back to [placed].
  /// Use this when processing WebSocket events to avoid reverting status.
  static OrderStatus? tryFromString(String value) {
    final normalized = _normalizeStatus(value);
    for (final s in OrderStatus.values) {
      if (s.value == normalized) return s;
    }
    return null;
  }

  /// Progress percentage (0.0 to 1.0)
  double get progress {
    switch (this) {
      case OrderStatus.placed:
        return 0.0;
      case OrderStatus.confirmed:
        return 0.17;
      case OrderStatus.preparing:
        return 0.33;
      case OrderStatus.ready:
        return 0.50;
      case OrderStatus.pickedUp:
        return 0.67;
      case OrderStatus.outForDelivery:
        return 0.83;
      case OrderStatus.delivered:
        return 1.0;
      case OrderStatus.cancelled:
        return 0.0;
    }
  }

  bool get isActive =>
      this != OrderStatus.delivered && this != OrderStatus.cancelled;
}
