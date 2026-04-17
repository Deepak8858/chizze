import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// Centralised Facebook SDK wrapper.
///
/// Two jobs:
///   1. Native Facebook Login — returns an access token the backend can
///      verify against Graph API to issue our own JWT.
///   2. App Events analytics — fires conversion events (signup, purchase,
///      add-to-cart) that Facebook's Ads platform uses for attribution and
///      lookalike audiences.
///
/// All event names come from Facebook's standard event catalogue so Ads
/// Manager recognises them as optimisation targets (don't invent names —
/// Ads Manager can only optimise on standard ones).
class FacebookService {
  FacebookService._();
  static final FacebookService instance = FacebookService._();

  final FacebookAppEvents _events = FacebookAppEvents();
  final FacebookAuth _auth = FacebookAuth.instance;

  /// Call once at app startup (after runApp). Enables ATT prompt on iOS
  /// if needed. The SDK auto-logs the "app activated" event when auto events
  /// are enabled — no need to call it manually.
  Future<void> init() async {
    try {
      await _events.setAdvertiserTracking(enabled: true);
      await _events.setAutoLogAppEventsEnabled(true);
    } catch (e) {
      if (kDebugMode) debugPrint('[FB] init error: $e');
    }
  }

  // ────────────────────── Login ──────────────────────

  /// Native FB login. Returns the access token string, or null on cancel.
  /// Caller must forward this token to the backend for verification +
  /// JWT exchange — never trust client-side user data.
  Future<String?> signIn() async {
    try {
      final result = await _auth.login(
        permissions: const ['email', 'public_profile'],
        loginBehavior: LoginBehavior.nativeWithFallback,
      );
      if (result.status == LoginStatus.success) {
        return result.accessToken?.tokenString;
      }
      if (kDebugMode) debugPrint('[FB] login status=${result.status} msg=${result.message}');
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[FB] login error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.logOut();
    } catch (e) {
      if (kDebugMode) debugPrint('[FB] logout error: $e');
    }
  }

  // ────────────────────── App Events ──────────────────────

  /// Fire when a user completes signup (OTP verified / OAuth completed).
  Future<void> logCompletedRegistration({required String method}) async {
    await _safe(() => _events.logCompletedRegistration(registrationMethod: method));
  }

  /// Fire when the user successfully places an order. [amount] in INR.
  Future<void> logPurchase({
    required double amount,
    required String orderId,
    int itemCount = 0,
  }) async {
    await _safe(() => _events.logPurchase(
          amount: amount,
          currency: 'INR',
          parameters: {
            'fb_content_type': 'order',
            'fb_content_id': orderId,
            'fb_num_items': itemCount,
          },
        ));
  }

  /// Fire when the user adds an item to cart.
  Future<void> logAddToCart({
    required String itemId,
    required double price,
    String itemName = '',
  }) async {
    await _safe(() => _events.logAddToCart(
          id: itemId,
          type: 'product',
          currency: 'INR',
          price: price,
        ));
  }

  /// Fire when a user views a restaurant / menu item.
  Future<void> logViewContent({
    required String id,
    required String type, // "restaurant" | "menu_item"
    String name = '',
    double price = 0,
  }) async {
    await _safe(() => _events.logViewContent(
          id: id,
          type: type,
          currency: 'INR',
          price: price,
        ));
  }

  /// Initiate checkout (cart → payment screen).
  Future<void> logInitiatedCheckout({
    required double totalAmount,
    required int itemCount,
  }) async {
    await _safe(() => _events.logInitiatedCheckout(
          totalPrice: totalAmount,
          currency: 'INR',
          numItems: itemCount,
        ));
  }

  /// Search (search bar on home screen). FB standard event name.
  Future<void> logSearch(String query) async {
    await _safe(() => _events.logEvent(
          name: 'fb_mobile_search',
          parameters: {'fb_search_string': query},
        ));
  }

  Future<void> _safe(Future Function() op) async {
    try {
      await op();
    } catch (e) {
      if (kDebugMode) debugPrint('[FB] event error: $e');
    }
  }
}
