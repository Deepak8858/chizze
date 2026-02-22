import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for partner order notification alerts (sound + haptic + local notification)
class OrderNotificationService {
  static final OrderNotificationService _instance =
      OrderNotificationService._internal();
  factory OrderNotificationService() => _instance;
  OrderNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _alertTimer;

  /// Initialize the notification plugin
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _notifications.initialize(settings);
      _initialized = true;
    } catch (e) {
      debugPrint('[OrderNotificationService] init error: $e');
    }
  }

  /// Play new order alert: haptic feedback + local notification
  Future<void> playNewOrderAlert({
    required String orderNumber,
    required String itemsSummary,
    required double amount,
  }) async {
    // Haptic feedback — heavy impact
    await HapticFeedback.heavyImpact();

    // Show local notification with sound
    if (_initialized) {
      try {
        final androidDetails = AndroidNotificationDetails(
          'partner_new_orders',
          'New Orders',
          channelDescription: 'Alerts for new incoming orders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
        );
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        );
        final details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _notifications.show(
          DateTime.now().millisecondsSinceEpoch % 100000,
          '🔔 New Order: $orderNumber',
          '$itemsSummary • ₹${amount.toInt()}',
          details,
        );
      } catch (e) {
        debugPrint('[OrderNotificationService] notification error: $e');
      }
    }
  }

  /// Start repeated alert for unattended orders (vibrate every 10s)
  void startRepeatedAlert() {
    stopRepeatedAlert();
    _alertTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  /// Stop repeated alerts
  void stopRepeatedAlert() {
    _alertTimer?.cancel();
    _alertTimer = null;
  }

  /// Quick haptic feedback for button actions
  static Future<void> hapticConfirm() => HapticFeedback.mediumImpact();
  static Future<void> hapticReject() => HapticFeedback.heavyImpact();
  static Future<void> hapticLight() => HapticFeedback.lightImpact();

  void dispose() {
    stopRepeatedAlert();
  }
}
