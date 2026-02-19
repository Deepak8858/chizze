import '../../../features/orders/models/order.dart';

/// Partner-specific order view with accept/reject timer
class PartnerOrder {
  final Order order;
  final DateTime? acceptDeadline; // 90 seconds from when order was placed
  final bool isNew;

  const PartnerOrder({
    required this.order,
    this.acceptDeadline,
    this.isNew = false,
  });

  /// Seconds remaining to accept/reject
  int get secondsRemaining {
    if (acceptDeadline == null) return 0;
    final diff = acceptDeadline!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get hasExpired => secondsRemaining <= 0 && isNew;

  PartnerOrder copyWith({Order? order, DateTime? acceptDeadline, bool? isNew}) {
    return PartnerOrder(
      order: order ?? this.order,
      acceptDeadline: acceptDeadline ?? this.acceptDeadline,
      isNew: isNew ?? this.isNew,
    );
  }

  /// Mock partner orders for UI development
  static List<PartnerOrder> get mockList {
    final now = DateTime.now();
    return [
      PartnerOrder(
        order: Order(
          id: 'po1',
          orderNumber: 'CHZ-300001',
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
          status: OrderStatus.placed,
          specialInstructions: 'Extra spicy',
          estimatedDeliveryMin: 35,
          placedAt: now.subtract(const Duration(seconds: 30)),
        ),
        acceptDeadline: now.add(const Duration(seconds: 60)),
        isNew: true,
      ),
      PartnerOrder(
        order: Order(
          id: 'po2',
          orderNumber: 'CHZ-300002',
          customerId: 'c2',
          restaurantId: 'r1',
          restaurantName: 'Biryani Blues',
          deliveryAddressId: 'a2',
          items: const [
            OrderItem(
              id: 'm2',
              name: 'Mutton Biryani',
              quantity: 1,
              price: 399,
              isVeg: false,
            ),
            OrderItem(
              id: 'm5',
              name: 'Gulab Jamun',
              quantity: 2,
              price: 79,
              isVeg: true,
            ),
          ],
          itemTotal: 557,
          deliveryFee: 40,
          platformFee: 5,
          gst: 27.85,
          discount: 0,
          grandTotal: 629.85,
          paymentMethod: 'card',
          paymentStatus: 'paid',
          status: OrderStatus.preparing,
          estimatedDeliveryMin: 30,
          placedAt: now.subtract(const Duration(minutes: 10)),
          confirmedAt: now.subtract(const Duration(minutes: 9)),
        ),
        isNew: false,
      ),
      PartnerOrder(
        order: Order(
          id: 'po3',
          orderNumber: 'CHZ-300003',
          customerId: 'c3',
          restaurantId: 'r1',
          restaurantName: 'Biryani Blues',
          deliveryAddressId: 'a3',
          items: const [
            OrderItem(
              id: 'm4',
              name: 'Dal Makhani',
              quantity: 1,
              price: 219,
              isVeg: true,
            ),
            OrderItem(
              id: 'm6',
              name: 'Naan',
              quantity: 3,
              price: 49,
              isVeg: true,
            ),
          ],
          itemTotal: 366,
          deliveryFee: 40,
          platformFee: 5,
          gst: 18.3,
          discount: 0,
          grandTotal: 429.3,
          paymentMethod: 'cod',
          paymentStatus: 'pending',
          status: OrderStatus.ready,
          estimatedDeliveryMin: 25,
          placedAt: now.subtract(const Duration(minutes: 20)),
          confirmedAt: now.subtract(const Duration(minutes: 19)),
          preparedAt: now.subtract(const Duration(minutes: 5)),
        ),
        isNew: false,
      ),
    ];
  }
}

/// Dashboard metrics
class PartnerMetrics {
  final double todayRevenue;
  final int todayOrders;
  final double avgRating;
  final int pendingOrders;

  const PartnerMetrics({
    this.todayRevenue = 0,
    this.todayOrders = 0,
    this.avgRating = 0,
    this.pendingOrders = 0,
  });

  static const mock = PartnerMetrics(
    todayRevenue: 12450,
    todayOrders: 28,
    avgRating: 4.3,
    pendingOrders: 3,
  );
}
