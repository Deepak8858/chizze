/// Order data model — maps to Appwrite `orders` collection
class Order {
  final String id;
  final String orderNumber;
  final String customerId;
  final String restaurantId;
  final String restaurantName;
  final String? deliveryPartnerId;
  final String? deliveryPartnerName;
  final String? deliveryPartnerPhone;
  final String deliveryAddressId;
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
  final DateTime placedAt;
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
    required this.restaurantId,
    required this.restaurantName,
    this.deliveryPartnerId,
    this.deliveryPartnerName,
    this.deliveryPartnerPhone,
    required this.deliveryAddressId,
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
    required this.placedAt,
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
      restaurantId: map['restaurant_id'] ?? '',
      restaurantName: map['restaurant_name'] ?? '',
      deliveryPartnerId: map['delivery_partner_id'],
      deliveryPartnerName: map['delivery_partner_name'],
      deliveryPartnerPhone: map['delivery_partner_phone'],
      deliveryAddressId: map['delivery_address_id'] ?? '',
      items:
          (map['items'] as List<dynamic>?)
              ?.map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
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
      placedAt: DateTime.tryParse(map['placed_at'] ?? '') ?? DateTime.now(),
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.tryParse(map['confirmed_at'])
          : null,
      preparedAt: map['prepared_at'] != null
          ? DateTime.tryParse(map['prepared_at'])
          : null,
      pickedUpAt: map['picked_up_at'] != null
          ? DateTime.tryParse(map['picked_up_at'])
          : null,
      deliveredAt: map['delivered_at'] != null
          ? DateTime.tryParse(map['delivered_at'])
          : null,
      cancelledAt: map['cancelled_at'] != null
          ? DateTime.tryParse(map['cancelled_at'])
          : null,
      cancellationReason: map['cancellation_reason'],
      cancelledBy: map['cancelled_by'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'order_number': orderNumber,
      'customer_id': customerId,
      'restaurant_id': restaurantId,
      'restaurant_name': restaurantName,
      'delivery_address_id': deliveryAddressId,
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
      'placed_at': placedAt.toIso8601String(),
    };
  }

  Order copyWith({
    OrderStatus? status,
    String? paymentStatus,
    String? paymentId,
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
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      deliveryPartnerId: deliveryPartnerId ?? this.deliveryPartnerId,
      deliveryPartnerName: deliveryPartnerName ?? this.deliveryPartnerName,
      deliveryPartnerPhone: deliveryPartnerPhone ?? this.deliveryPartnerPhone,
      deliveryAddressId: deliveryAddressId,
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
      placedAt: placedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      preparedAt: preparedAt ?? this.preparedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
      cancelledBy: cancelledBy,
    );
  }

  /// Mock orders for UI development
  static List<Order> get mockList => [
    Order(
      id: 'o1',
      orderNumber: 'CHZ-240001',
      customerId: 'u1',
      restaurantId: 'r1',
      restaurantName: 'Biryani Blues',
      deliveryAddressId: 'a1',
      items: [
        const OrderItem(
          id: 'm1',
          name: 'Chicken Biryani',
          quantity: 2,
          price: 299,
          isVeg: false,
        ),
        const OrderItem(
          id: 'm4',
          name: 'Dal Makhani',
          quantity: 1,
          price: 219,
          isVeg: true,
        ),
      ],
      itemTotal: 817,
      deliveryFee: 0,
      platformFee: 5,
      gst: 40.85,
      discount: 0,
      grandTotal: 862.85,
      paymentMethod: 'upi',
      paymentStatus: 'paid',
      paymentId: 'pay_test_001',
      status: OrderStatus.delivered,
      estimatedDeliveryMin: 35,
      placedAt: DateTime.now().subtract(const Duration(days: 2)),
      deliveredAt: DateTime.now().subtract(const Duration(days: 2, hours: -1)),
    ),
    Order(
      id: 'o2',
      orderNumber: 'CHZ-240002',
      customerId: 'u1',
      restaurantId: 'r2',
      restaurantName: 'Pizza Paradise',
      deliveryAddressId: 'a1',
      items: [
        const OrderItem(
          id: 'm1',
          name: 'Margherita Pizza',
          quantity: 1,
          price: 399,
          isVeg: true,
        ),
      ],
      itemTotal: 399,
      deliveryFee: 40,
      platformFee: 5,
      gst: 19.95,
      discount: 0,
      grandTotal: 463.95,
      paymentMethod: 'card',
      paymentStatus: 'paid',
      status: OrderStatus.outForDelivery,
      deliveryPartnerId: 'dp1',
      deliveryPartnerName: 'Ravi Kumar',
      deliveryPartnerPhone: '+919876543210',
      estimatedDeliveryMin: 15,
      placedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    ),
  ];
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
  pickedUp('picked_up', 'Picked Up', '🏍️'),
  outForDelivery('out_for_delivery', 'Out for Delivery', '🚀'),
  delivered('delivered', 'Delivered', '🎉'),
  cancelled('cancelled', 'Cancelled', '❌');

  final String value;
  final String label;
  final String emoji;
  const OrderStatus(this.value, this.label, this.emoji);

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => OrderStatus.placed,
    );
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
