import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/realtime_service.dart';

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

/// Notifications notifier — API-backed with mock fallback + Realtime
class NotificationsNotifier extends StateNotifier<List<AppNotification>> {
  final ApiClient _api;
  final RealtimeService _realtime;
  StreamSubscription? _realtimeSub;

  NotificationsNotifier(this._api, this._realtime) : super(const []) {
    fetchNotifications();
    _subscribeToRealtime();
  }

  /// Listen for new notifications in real-time
  void _subscribeToRealtime() {
    try {
      final channel = RealtimeChannels.notificationsChannel();
      _realtimeSub = _realtime.subscribe(channel).listen((event) {
        if (event.type == RealtimeEventType.create) {
          final m = event.data;
          final notification = AppNotification(
            id: m['\$id'] ?? '',
            title: m['title'] ?? '',
            body: m['body'] ?? '',
            type: _parseType(m['type']),
            isRead: false,
            createdAt:
                DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
            actionRoute: m['data'] != null ? _extractRoute(m['data']) : null,
          );
          // Add to top of list
          state = [notification, ...state];
        }
      });
    } catch (_) {} // Realtime not available
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Fetch from API
  Future<void> fetchNotifications() async {
    try {
      final response = await _api.get(ApiConfig.notifications);
      if (response.success && response.data != null) {
        final list = response.data as List<dynamic>;
        state = list.map((d) {
          final m = d as Map<String, dynamic>;
          return AppNotification(
            id: m['\$id'] ?? '',
            title: m['title'] ?? '',
            body: m['body'] ?? '',
            type: _parseType(m['type']),
            isRead: m['is_read'] ?? false,
            createdAt:
                DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
            actionRoute: m['data'] != null ? _extractRoute(m['data']) : null,
          );
        }).toList();
      }
    } on ApiException {
      // Keep current state
    } catch (_) {}
  }

  NotificationType _parseType(String? type) {
    switch (type) {
      case 'order_update':
        return NotificationType.order;
      case 'promo':
        return NotificationType.promo;
      default:
        return NotificationType.system;
    }
  }

  String? _extractRoute(dynamic data) {
    if (data is Map && data['order_id'] != null) {
      return '/order-detail/${data['order_id']}';
    }
    return null;
  }

  void markRead(String id) {
    state = state
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
    _api.put('${ApiConfig.notifications}/$id/read').ignore();
  }

  void markAllRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
    _api.put('${ApiConfig.notifications}/read-all').ignore();
  }

  void clear() => state = [];

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<AppNotification>>((ref) {
      final api = ref.watch(apiClientProvider);
      final realtime = ref.watch(realtimeServiceProvider);
      return NotificationsNotifier(api, realtime);
    });
