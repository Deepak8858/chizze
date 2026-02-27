import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
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

  const PaymentState({
    this.isProcessing = false,
    this.error,
    this.paymentId,
    this.orderId,
    this.razorpayOrderId,
    this.isSuccess = false,
  });

  PaymentState copyWith({
    bool? isProcessing,
    String? error,
    String? paymentId,
    String? orderId,
    String? razorpayOrderId,
    bool? isSuccess,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      paymentId: paymentId ?? this.paymentId,
      orderId: orderId ?? this.orderId,
      razorpayOrderId: razorpayOrderId ?? this.razorpayOrderId,
      isSuccess: isSuccess ?? this.isSuccess,
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
      int amountPaise = (amount * 100).toInt();

      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        razorpayOrderId = data['razorpay_order_id'] ?? '';
        razorpayKeyId = data['razorpay_key_id'] ?? RazorpayConfig.keyId;
        amountPaise = data['amount'] ?? amountPaise;
        state = state.copyWith(razorpayOrderId: razorpayOrderId);
      }

      if (razorpayOrderId.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          error: 'Failed to create payment order',
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
      debugPrint('[Payment] Backend verification failed: $e');
      // Non-fatal — webhook will catch it server-side
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
    state = PaymentState(
      isProcessing: false,
      error: response.message ?? 'Payment failed',
    );
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
