import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../router/app_router.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'location_update_service.dart';

/// Key under which the device push token is cached locally
const _kDeviceTokenKey = 'chizze_device_push_token';

/// Sentinel payload value used to signal that tapping a local notification
/// should trigger the "refresh my saved location" flow rather than navigate.
const _kUpdateLocationPayload = '__action:update_location__';

/// Top-level handler for background FCM messages.
/// Must be a top-level function (not a method or closure).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) debugPrint('[Push] Background message: ${message.messageId}');
}

/// Push-notification service backed by Firebase Cloud Messaging.
///
/// Falls back to a dev-mode placeholder token when Firebase is not
/// configured (e.g. missing google-services.json).
class PushNotificationService {
  PushNotificationService(this._api, this._ref);

  final ApiClient _api;
  final Ref _ref;

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
    if (kDebugMode) {
      debugPrint('[Push] Service initialised. Token: $_deviceToken');
    }
  }

  /// Set up Firebase Messaging listeners
  Future<void> _initFirebaseMessaging() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request visual + audible permission so heads-up notifications on iOS
      // and Android 13+ surface with sound by default.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (kDebugMode) {
        debugPrint('[Push] Permission status: ${settings.authorizationStatus}');
      }

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Foreground messages → show local notification + handle delivery_request
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint(
            '[Push] Foreground message: ${message.messageId} type=${message.data["type"]}',
          );
        }
        final msgType = message.data['type'] as String? ?? '';

        // Delivery request FCM — app is foreground, trigger in-app handling
        // without notification sound (silent notification policy).
        // The DeliveryNotifier's Appwrite Realtime subscription will handle
        // showing the actual request card.
        if (msgType == 'delivery_request') {
          _onDeliveryRequestPush(message.data);
          return;
        }

        // Location-refresh broadcast: show a tap-to-update notification.
        if (msgType == 'update_location') {
          final notif = message.notification;
          showLocalNotification(
            title:
                notif?.title ??
                (message.data['title'] as String? ?? 'Update your location'),
            body:
                notif?.body ??
                (message.data['body'] as String? ??
                    'Tap to refresh for faster delivery'),
            payload: _kUpdateLocationPayload,
          );
          return;
        }

        // Fall back to the data payload when the message has no notification
        // block (happens when backend sends data-only pushes). Ensures every
        // FCM that reaches a foregrounded app still surfaces in the tray.
        final notification = message.notification;
        final title =
            notification?.title ??
            (message.data['title'] as String? ?? 'Chizze');
        final body =
            notification?.body ?? (message.data['body'] as String? ?? '');
        if (title.isEmpty && body.isEmpty) return;
        showLocalNotification(
          title: title,
          body: body,
          payload: _extractRoute(message.data),
        );
      });

      // Handle notification taps (app was in background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('[Push] Notification opened: ${message.data}');
        }
        final msgType = message.data['type'] as String? ?? '';
        if (msgType == 'delivery_request') {
          _onDeliveryRequestPush(message.data);
        } else if (msgType == 'update_location') {
          _runLocationUpdate();
        } else {
          _handleNotificationRoute(_extractRoute(message.data));
        }
      });

      // Check if app was launched from a notification
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        if (kDebugMode) {
          debugPrint('[Push] App launched from notification: ${initial.data}');
        }
        // Delay to let the router initialise
        Future.delayed(const Duration(milliseconds: 500), () {
          final msgType = initial.data['type'] as String? ?? '';
          if (msgType == 'update_location') {
            _runLocationUpdate();
          } else {
            _handleNotificationRoute(_extractRoute(initial.data));
          }
        });
      }

      _firebaseAvailable = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] Firebase Messaging not available: $e');
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
        if (kDebugMode) {
          debugPrint('[Push] Local notification tapped: ${response.payload}');
        }
        _handleNotificationRoute(response.payload);
      },
    );

    // Create the main Android channel eagerly so that the very first FCM
    // message (which Firebase binds to `android_channel_id`) has a channel
    // configured with the correct importance — otherwise the OS falls back
    // to the low-importance default and the notification never pops up.
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'chizze_main',
          'Chizze Notifications',
          description: 'Order updates, offers & more',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      // Dedicated high-priority channel for restaurant owners. Backend's
      // FCM payload sets android_channel_id=new_orders (see order_handler.go
      // line 455); without this registration Android silently routes the push
      // to the fallback low-importance default — owners missed orders.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'new_orders',
          'New Orders',
          description: 'Incoming orders for restaurant partners',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      // Dedicated channel for delivery-partner assignment pushes (matcher →
      // fcm.DeliveryRequestPayload uses android_channel_id=delivery_requests).
      // Importance.max + vibration so riders see the 30s countdown even when
      // the screen is locked.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'delivery_requests',
          'Delivery Requests',
          description: 'New delivery assignments for partners',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin.requestNotificationsPermission();
    }
  }

  /// Handle an incoming delivery_request FCM push.
  /// Called both in foreground (onMessage) and on notification tap (onMessageOpenedApp).
  void _onDeliveryRequestPush(Map<String, dynamic> data) {
    final orderId = data['order_id'] as String? ?? '';
    if (kDebugMode) debugPrint('[Push] delivery_request FCM: orderId=$orderId');

    // Navigate to delivery dashboard so the rider sees the request
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).go('/delivery');
    }
  }

  /// Extract a navigation route from a notification's data payload.
  /// Backend uses `deep_link` for explicit routes (e.g. /review/{id} on
  /// delivered notifications). Falls back to `route` for legacy payloads,
  /// then derives a sensible default from `type` + `order_id`.
  String? _extractRoute(Map<String, dynamic> data) {
    final deepLink = data['deep_link'] as String?;
    if (deepLink != null && deepLink.isNotEmpty) return deepLink;
    final route = data['route'] as String?;
    if (route != null && route.isNotEmpty) return route;
    // Derive: order_status updates → tracking screen for that order
    final type = data['type'] as String? ?? '';
    final orderId = data['order_id'] as String? ?? '';
    if (orderId.isNotEmpty &&
        (type == 'order_status' || type == 'delivery_update')) {
      return '/order-tracking/$orderId';
    }
    return null;
  }

  /// Navigate to the route encoded in a notification payload.
  /// Supported routes: /order-tracking/:id, /review/:id, /orders, etc.
  /// Also recognises the `_kUpdateLocationPayload` sentinel used by the
  /// "refresh your location" broadcast.
  void _handleNotificationRoute(String? route) {
    if (route == null || route.isEmpty) return;
    if (route == _kUpdateLocationPayload) {
      _runLocationUpdate();
      return;
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      if (kDebugMode) {
        debugPrint('[Push] No navigator context — cannot route to $route');
      }
      return;
    }
    if (kDebugMode) debugPrint('[Push] Navigating to: $route');
    GoRouter.of(context).go(route);
  }

  /// Capture the device's current GPS, reverse-geocode it, and persist it
  /// to the user profile + default saved address. Invoked when the user
  /// taps the "update your location" push notification.
  Future<void> _runLocationUpdate() async {
    // Navigate to profile so the user sees the updated address when the
    // network call completes.
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null) GoRouter.of(navCtx).go('/profile');

    final outcome = await _ref
        .read(locationUpdateServiceProvider)
        .updateFromCurrentLocation();

    final message = switch (outcome) {
      LocationUpdateOutcome.success => 'Location updated',
      LocationUpdateOutcome.permissionDenied =>
        'Location permission required — enable it in settings',
      LocationUpdateOutcome.serviceDisabled =>
        'Please turn on GPS to update your location',
      LocationUpdateOutcome.gpsTimeout =>
        'Could not get your location — please try again',
      LocationUpdateOutcome.networkError => 'Network error — please try again',
    };

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Device Token ───

  /// Ensure we have a device token; generate one if needed and register it
  /// with the backend.
  Future<void> _ensureDeviceToken() async {
    // Try to get a real FCM token first
    if (_firebaseAvailable) {
      try {
        _deviceToken = await FirebaseMessaging.instance.getToken();
        if (kDebugMode) debugPrint('[Push] FCM token acquired');

        // Listen for token refreshes
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          _deviceToken = newToken;
          registerToken();
          if (kDebugMode) debugPrint('[Push] FCM token refreshed');
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[Push] Failed to get FCM token: $e');
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
      await _api.put(ApiConfig.fcmToken, body: {'token': _deviceToken});
      if (kDebugMode) debugPrint('[Push] Token registered with backend');
    } catch (e) {
      // Non-fatal — will retry on next app start
      if (kDebugMode) debugPrint('[Push] Failed to register token: $e');
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
      playSound: true,
      enableVibration: true,
      ticker: 'Chizze',
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
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
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return PushNotificationService(api, ref);
});
