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


}
