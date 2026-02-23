import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../router/app_router.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Key under which the device push token is cached locally
const _kDeviceTokenKey = 'chizze_device_push_token';

/// Top-level handler for background FCM messages.
/// Must be a top-level function (not a method or closure).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[Push] Background message: ${message.messageId}');
}

/// Push-notification service backed by Firebase Cloud Messaging.
///
/// Falls back to a dev-mode placeholder token when Firebase is not
/// configured (e.g. missing google-services.json).
class PushNotificationService {
  PushNotificationService(this._api);

  final ApiClient _api;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Cached device token for the current session
  String? _deviceToken;

  /// Whether Firebase Messaging initialised successfully
  bool _firebaseAvailable = false;

  // ─── Initialisation ───

  /// Call once at app startup (e.g., in main.dart after auth)
  Future<void> init() async {
    await _initLocalNotifications();
    await _initFirebaseMessaging();
    await _ensureDeviceToken();
    debugPrint('[Push] Service initialised. Token: $_deviceToken');
  }

  /// Set up Firebase Messaging listeners
  Future<void> _initFirebaseMessaging() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission (iOS + Android 13+)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[Push] Permission status: ${settings.authorizationStatus}');

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      // Foreground messages → show local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[Push] Foreground message: ${message.messageId}');
        final notification = message.notification;
        if (notification != null) {
          showLocalNotification(
            title: notification.title ?? 'Chizze',
            body: notification.body ?? '',
            payload: message.data['route'],
          );
        }
      });

      // Handle notification taps (app was in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[Push] Notification opened: ${message.data}');
        _handleNotificationRoute(message.data['route']);
      });

      // Check if app was launched from a notification
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        debugPrint('[Push] App launched from notification: ${initial.data}');
        // Delay to let the router initialise
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleNotificationRoute(initial.data['route']);
        });
      }

      _firebaseAvailable = true;
    } catch (e) {
      debugPrint('[Push] Firebase Messaging not available: $e');
      _firebaseAvailable = false;
    }
  }

  /// Initialise the flutter_local_notifications plugin
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[Push] Local notification tapped: ${response.payload}');
        _handleNotificationRoute(response.payload);
      },
    );
  }

  /// Navigate to the route encoded in a notification payload.
  /// Supported routes: /order-tracking/:id, /orders, /notifications, etc.
  void _handleNotificationRoute(String? route) {
    if (route == null || route.isEmpty) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      debugPrint('[Push] No navigator context — cannot route to $route');
      return;
    }
    debugPrint('[Push] Navigating to: $route');
    GoRouter.of(context).go(route);
  }

  // ─── Device Token ───

  /// Ensure we have a device token; generate one if needed and register it
  /// with the backend.
  Future<void> _ensureDeviceToken() async {
    // Try to get a real FCM token first
    if (_firebaseAvailable) {
      try {
        _deviceToken = await FirebaseMessaging.instance.getToken();
        debugPrint('[Push] FCM token acquired');

        // Listen for token refreshes
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          _deviceToken = newToken;
          registerToken();
          debugPrint('[Push] FCM token refreshed');
        });
      } catch (e) {
        debugPrint('[Push] Failed to get FCM token: $e');
      }
    }

    // Fallback to local dev token if FCM unavailable
    if (_deviceToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _deviceToken = prefs.getString(_kDeviceTokenKey);

      if (_deviceToken == null) {
        _deviceToken = _generateDeviceToken();
        await prefs.setString(_kDeviceTokenKey, _deviceToken!);
      }
    }

    await registerToken();
  }

  /// Register (or re-register) the current device token with the backend.
  /// Safe to call multiple times — the backend upserts.
  Future<void> registerToken() async {
    if (_deviceToken == null) return;
    try {
      await _api.put(
        ApiConfig.fcmToken,
        body: {'token': _deviceToken},
      );
      debugPrint('[Push] Token registered with backend');
    } catch (e) {
      // Non-fatal — will retry on next app start
      debugPrint('[Push] Failed to register token: $e');
    }
  }

  /// Dev-mode placeholder token generator.
  /// Used only when Firebase is not configured.
  String _generateDeviceToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    final token = List.generate(
      64,
      (_) => chars[rng.nextInt(chars.length)],
    ).join();
    return 'chizze_dev_$token';
  }

  // ─── Show notifications locally ───

  /// Display a heads-up notification on the device.
  /// Call this from a realtime listener or when an FCM message arrives.
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'chizze_main',
      'Chizze Notifications',
      channelDescription: 'Order updates, offers & more',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Current device token (may be null before [init] is called)
  String? get deviceToken => _deviceToken;
}

/// Global provider for the push notification service
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final api = ref.watch(apiClientProvider);
  return PushNotificationService(api);
});
