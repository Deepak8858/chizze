import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/facebook_service.dart';
import '../../cart/providers/cart_provider.dart';

/// Razorpay configuration
class RazorpayConfig {
  // Key injected via --dart-define=RAZORPAY_KEY=...
  // MUST be set for production builds — empty default prevents test key leaking
  static const String keyId = String.fromEnvironment(
    'RAZORPAY_KEY',
    defaultValue: '',
  );
  static const String keySecret =
      ''; // Keep empty in client — verify on Go backend
}

/// Payment state
class PaymentState {
  final bool isProcessing;
  final String? error;
  final String? paymentId;
  final String? orderId;
  final String? razorpayOrderId;
  final bool isSuccess;
  final int amountPaise; // retained across Razorpay callback for FB Purchase event

  const PaymentState({
    this.isProcessing = false,
    this.error,
    this.paymentId,
    this.orderId,
    this.razorpayOrderId,
    this.isSuccess = false,
    this.amountPaise = 0,
  });

  PaymentState copyWith({
    bool? isProcessing,
    String? error,
    String? paymentId,
    String? orderId,
    String? razorpayOrderId,
    bool? isSuccess,
    int? amountPaise,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      paymentId: paymentId ?? this.paymentId,
      orderId: orderId ?? this.orderId,
      razorpayOrderId: razorpayOrderId ?? this.razorpayOrderId,
      isSuccess: isSuccess ?? this.isSuccess,
      amountPaise: amountPaise ?? this.amountPaise,
    );
  }
}

/// Payment notifier — manages Razorpay flow via Go backend
class PaymentNotifier extends StateNotifier<PaymentState> {
  final Razorpay _razorpay;
  final Ref _ref;
  final ApiClient _api;
  VoidCallback? _onSuccess;

  PaymentNotifier(this._ref, this._api)
    : _razorpay = Razorpay(),
      super(const PaymentState()) {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// Place order on Go backend (POST /orders) — returns the created order document
  /// Used by both COD and Razorpay flows to create the real order first
  Future<Map<String, dynamic>?> placeBackendOrder({
    required CartState cartState,
    required String paymentMethod,
    required String deliveryAddressId,
    double tip = 0,
    String? idempotencyKey,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);
    try {
      final items = cartState.items
          .map((ci) => {
                'item_id': ci.menuItem.id,
                'name': ci.menuItem.name,
                'quantity': ci.quantity,
                'price': ci.menuItem.price,
              })
          .toList();

      final body = <String, dynamic>{
        'restaurant_id': cartState.restaurantId ?? '',
        'delivery_address_id': deliveryAddressId,
        'items': items,
        'payment_method': paymentMethod,
        'tip': tip,
        'delivery_type': cartState.deliveryType,
        'special_instructions': cartState.specialInstructions,
        'delivery_instructions': cartState.deliveryInstructions,
      };
      if (cartState.couponCode != null) {
        body['coupon_code'] = cartState.couponCode;
      }

      final Map<String, String> headers = {};
      if (idempotencyKey != null) {
        headers['X-Idempotency-Key'] = idempotencyKey;
      }

      final response = await _api.post(
        ApiConfig.orders,
        body: body,
        headers: headers.isNotEmpty ? headers : null,
      );

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final orderId = data['\$id'] as String? ?? '';
        state = state.copyWith(orderId: orderId, isProcessing: false);
        // FB App Events: Purchase + InitiatedCheckout for Ads attribution.
        // We fire Purchase here for COD (which completes immediately on order
        // creation) and InitiatedCheckout for online methods (Razorpay fires
        // Purchase again on verified payment — see _handlePaymentSuccess).
        final total = (data['grand_total'] as num?)?.toDouble() ?? 0;
        final itemCount = items.length;
        if (paymentMethod == 'cod') {
          unawaited(FacebookService.instance.logPurchase(
            amount: total,
            orderId: orderId,
            itemCount: itemCount,
          ));
        } else {
          unawaited(FacebookService.instance.logInitiatedCheckout(
            totalAmount: total,
            itemCount: itemCount,
          ));
        }
        return data;
      } else {
        state = state.copyWith(
          isProcessing: false,
          error: response.error ?? 'Failed to create order',
        );
        return null;
      }
    } on ApiException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Order failed: ${e.message}',
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Failed to place order: $e',
      );
      return null;
    }
  }

  /// Start payment — initiate via Go backend, then open Razorpay
  ///
  /// Flow: POST /payments/initiate (with order_id) → get razorpay_order_id
  ///       → open Razorpay checkout → on success → POST /payments/verify
  Future<void> startPayment({
    required String orderId,
    required double amount,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? description,
    VoidCallback? onSuccess,
  }) async {
    _onSuccess = onSuccess;
    state = state.copyWith(isProcessing: true, error: null, orderId: orderId);

    try {
      // Step 1: Create Razorpay order via Go backend
      final response = await _api.post(
        ApiConfig.paymentInitiate,
        body: {'order_id': orderId},
      );

      String razorpayOrderId = '';
      String razorpayKeyId = RazorpayConfig.keyId;
      // `.round()` — not `.toInt()` — so a floating-point itemTotal×0.05 GST
      // that lands at e.g. 14999.999 becomes 15000 paise. Razorpay rejects the
      // checkout if the client amount doesn't exactly match the order amount.
      int amountPaise = (amount * 100).round();

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        razorpayOrderId = data['razorpay_order_id'] ?? '';
        razorpayKeyId = data['razorpay_key_id'] ?? RazorpayConfig.keyId;
        // Always trust the backend amount: it's the authoritative value used
        // when the Razorpay order was created. Any client-side computation is
        // advisory only.
        final backendAmount = data['amount'];
        if (backendAmount is num) {
          amountPaise = backendAmount.toInt();
        }
        state = state.copyWith(
          razorpayOrderId: razorpayOrderId,
          amountPaise: amountPaise,
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          error: response.error ?? 'Failed to create payment order',
        );
        return;
      }

      if (razorpayOrderId.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          error: 'Failed to create payment order',
        );
        return;
      }

      if (razorpayKeyId.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          error: 'Payment is unavailable right now. Please try again soon.',
        );
        return;
      }

      if (kReleaseMode && razorpayKeyId.startsWith('rzp_test_')) {
        state = state.copyWith(
          isProcessing: false,
          error:
              'Production payment is misconfigured. Live Razorpay key is required.',
        );
        return;
      }

      // Step 2: Open Razorpay checkout
      final options = {
        'key': razorpayKeyId,
        'amount': amountPaise,
        'name': 'Chizze',
        'description': description ?? 'Food Delivery Order',
        'order_id': razorpayOrderId,
        'prefill': {
          'contact': customerPhone,
          'email': customerEmail,
          'name': customerName,
        },
        'theme': {'color': '#F49D25'},
        'modal': {'confirm_close': true},
      };

      _razorpay.open(options);
    } on ApiException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Payment initiation failed: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Failed to start payment: $e',
      );
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    // Verify payment signature on Go backend
    try {
      await _api.post(
        ApiConfig.paymentVerify,
        body: {
          'razorpay_order_id': response.orderId ?? state.razorpayOrderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature': response.signature,
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Payment] Backend verification failed: $e');
      // Non-fatal — webhook will catch it server-side
    }

    // FB Purchase event fires now (after signature verified) for online
    // payments. Amount is in paise from Razorpay; convert to INR.
    if (state.orderId != null && state.orderId!.isNotEmpty) {
      unawaited(FacebookService.instance.logPurchase(
        amount: state.amountPaise / 100.0,
        orderId: state.orderId!,
      ));
    }

    state = PaymentState(
      isProcessing: false,
      isSuccess: true,
      paymentId: response.paymentId,
      orderId: state.orderId,
    );

    // Clear cart after successful payment
    _ref.read(cartProvider.notifier).clearCart();
    _onSuccess?.call();
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    // Razorpay's `response.message` is unreliable for user display: on some
    // SDK/platform combos it's a JSON-encoded error payload, a pass-through of
    // the gateway's raw string ("undefined" when the callback fires before a
    // payment attempt), or null. Translate the numeric `code` to a stable,
    // professional message and only fall back to raw text as a last resort.
    final code = response.code;
    final wasCancelled = code == Razorpay.PAYMENT_CANCELLED;
    final friendly = _mapPaymentFailureToMessage(code, response.message);

    // An abandoned online-pay order sits in status=placed/payment_status=pending
    // and would otherwise be picked up by restaurant/rider workers before the
    // webhook fired. Best-effort cancel so nobody starts cooking a meal the
    // customer hasn't paid for.
    final orderId = state.orderId;
    if (orderId != null && orderId.isNotEmpty) {
      unawaited(_cancelPendingOrder(orderId, wasCancelled));
    }

    if (kDebugMode) {
      debugPrint('[Payment] error code=$code message=${response.message}');
    }

    state = PaymentState(
      isProcessing: false,
      error: friendly,
      orderId: orderId,
    );
  }

  /// Maps a Razorpay [PaymentFailureResponse.code] + [raw] message into a
  /// professional, user-facing string. Visible for testing.
  @visibleForTesting
  static String mapPaymentFailureToMessage(int? code, String? raw) =>
      _mapPaymentFailureToMessage(code, raw);

  static String _mapPaymentFailureToMessage(int? code, String? raw) {
    switch (code) {
      case Razorpay.PAYMENT_CANCELLED:
        return 'Payment cancelled. Your order has not been placed — try again when you\'re ready.';
      case Razorpay.NETWORK_ERROR:
        return 'Payment failed: no internet connection. Check your network and try again.';
      case Razorpay.INVALID_OPTIONS:
        return 'Payment could not start due to a configuration issue. Please try again in a moment.';
      case Razorpay.TLS_ERROR:
        return 'Secure connection to the payment gateway failed. Update your device and try again.';
      case Razorpay.UNKNOWN_ERROR:
      default:
        final desc = _extractRazorpayDescription(raw);
        if (desc != null) {
          return 'Payment failed: $desc';
        }
        return 'Payment could not be completed. No amount has been charged — please try again.';
    }
  }

  static String? _extractRazorpayDescription(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'undefined' || trimmed.toLowerCase() == 'null') {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map) {
          final desc = err['description'];
          if (desc is String && desc.trim().isNotEmpty) return desc.trim();
          final reason = err['reason'];
          if (reason is String && reason.trim().isNotEmpty) {
            return reason.trim().replaceAll('_', ' ');
          }
        }
        final desc = decoded['description'];
        if (desc is String && desc.trim().isNotEmpty) return desc.trim();
      }
    } catch (_) {
      // Not JSON — fall through to plain-text handling.
    }
    return trimmed;
  }

  Future<void> _cancelPendingOrder(String orderId, bool userCancelled) async {
    try {
      await _api.put(
        '${ApiConfig.orders}/$orderId/cancel',
        body: {
          'reason': userCancelled
              ? 'Payment cancelled by customer'
              : 'Payment failed',
        },
      );
    } catch (e) {
      // Best-effort — Razorpay webhook (payment.failed) + order-timeout
      // worker are the authoritative safety nets. Keep the UI responsive
      // regardless of network outcome.
      if (kDebugMode) {
        debugPrint('[Payment] best-effort order-cancel failed: $e');
      }
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    state = state.copyWith(
      isProcessing: false,
      error:
          'External wallet: ${response.walletName}. Please complete payment.',
    );
  }

  void reset() {
    state = const PaymentState();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }
}

/// Payment provider
final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return PaymentNotifier(ref, api);
});
