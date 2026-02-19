import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notification types
enum NotificationType {
  order('Order', '📦'),
  promo('Promotion', '🎁'),
  system('System', '⚙️');

  final String label;
  final String emoji;
  const NotificationType(this.label, this.emoji);
}

/// App notification model
class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final bool isRead;
  final DateTime createdAt;
  final String? actionRoute; // e.g. /order-detail/o1

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    required this.createdAt,
    this.actionRoute,
  });

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      actionRoute: actionRoute,
    );
  }
}

/// Notifications notifier
class NotificationsNotifier extends StateNotifier<List<AppNotification>> {
  NotificationsNotifier() : super(_mockNotifications);

  void markRead(String id) {
    state = state
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
  }

  void markAllRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
  }

  void clear() => state = [];

  int get unreadCount => state.where((n) => !n.isRead).length;

  static final _mockNotifications = [
    AppNotification(
      id: 'n1',
      title: 'Order Delivered! 🎉',
      body: 'Your order CHZ-240001 from Biryani Blues has been delivered.',
      type: NotificationType.order,
      createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      actionRoute: '/order-detail/o1',
    ),
    AppNotification(
      id: 'n2',
      title: 'Flat 40% OFF!',
      body:
          'Use code CHIZZE40 to get 40% off on your next order. Valid till midnight!',
      type: NotificationType.promo,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      id: 'n3',
      title: 'Order Confirmed',
      body: 'Your order CHZ-240002 from Pizza Paradise has been confirmed.',
      type: NotificationType.order,
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      actionRoute: '/order-detail/o2',
    ),
    AppNotification(
      id: 'n4',
      title: 'Weekend Special 🍕',
      body: 'Free delivery on all orders above ₹299 this weekend!',
      type: NotificationType.promo,
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    AppNotification(
      id: 'n5',
      title: 'App Update Available',
      body:
          'A new version of Chizze is available with bug fixes and performance improvements.',
      type: NotificationType.system,
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    AppNotification(
      id: 'n6',
      title: 'Rate your last order',
      body:
          'How was your Chicken Biryani from Biryani Blues? Share your feedback!',
      type: NotificationType.order,
      createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
      actionRoute: '/review/o1',
    ),
  ];
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<AppNotification>>((ref) {
      return NotificationsNotifier();
    });
