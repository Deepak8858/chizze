import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Key under which the device push token is cached locally
const _kDeviceTokenKey = 'chizze_device_push_token';

/// Lightweight push-notification service.
///
/// Handles:
/// * Generating / retrieving a device token (placeholder until Firebase is wired)
/// * Sending the token to the Go backend via `PUT /users/me/fcm-token`
/// * Initialising `flutter_local_notifications` for heads-up display
///
/// To integrate real FCM later:
/// 1. Add `firebase_messaging` to pubspec.yaml + Firebase project setup
/// 2. Replace [_generateDeviceToken] with `FirebaseMessaging.instance.getToken()`
/// 3. Listen to `FirebaseMessaging.onMessage` and call [showLocalNotification]
class PushNotificationService {
  PushNotificationService(this._api);

  final ApiClient _api;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Cached device token for the current session
  String? _deviceToken;

  // ─── Initialisation ───

  /// Call once at app startup (e.g., in main.dart after auth)
  Future<void> init() async {
    await _initLocalNotifications();
    await _ensureDeviceToken();
    debugPrint('[Push] Service initialised. Token: $_deviceToken');
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
    await _localNotifications.initialize(settings);
  }

  // ─── Device Token ───

  /// Ensure we have a device token; generate one if needed and register it
  /// with the backend.
  Future<void> _ensureDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceToken = prefs.getString(_kDeviceTokenKey);

    if (_deviceToken == null) {
      _deviceToken = _generateDeviceToken();
      await prefs.setString(_kDeviceTokenKey, _deviceToken!);
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

  /// Placeholder token generator.
  /// Replace with `FirebaseMessaging.instance.getToken()` when Firebase is set up.
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
