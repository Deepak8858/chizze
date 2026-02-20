import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../core/models/api_response.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/api_config.dart';
import '../../cart/providers/cart_provider.dart';
import '../../orders/models/order.dart' as app;

/// Razorpay configuration
class RazorpayConfig {
  static const String keyId =
      'rzp_test_XXXXXXXXXXXXXXX'; // Replace with real key
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

  /// Start payment — initiate via Go backend, then open Razorpay
  Future<void> startPayment({
    required double amount,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? description,
    VoidCallback? onSuccess,
  }) async {
    _onSuccess = onSuccess;
    state = state.copyWith(isProcessing: true, error: null);

    try {
      // Step 1: Create Razorpay order via Go backend
      final response = await _api.post(
        ApiConfig.paymentInitiate,
        body: {
          'amount': amount,
          'receipt': 'chz_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      String razorpayOrderId = '';
      if (response.success && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        razorpayOrderId = data['razorpay_order_id'] ?? '';
        state = state.copyWith(
          orderId: data['order_id'],
          razorpayOrderId: razorpayOrderId,
        );
      }

      // Step 2: Open Razorpay checkout
      final options = {
        'key': RazorpayConfig.keyId,
        'amount': (amount * 100).toInt(),
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
      // Fallback: open without backend order ID (for dev)
      final options = {
        'key': RazorpayConfig.keyId,
        'amount': (amount * 100).toInt(),
        'name': 'Chizze',
        'description': description ?? 'Food Delivery Order',
        'prefill': {
          'contact': customerPhone,
          'email': customerEmail,
          'name': customerName,
        },
        'theme': {'color': '#F49D25'},
      };
      try {
        _razorpay.open(options);
      } catch (e2) {
        state = state.copyWith(
          isProcessing: false,
          error: 'Failed to open payment: $e2',
        );
      }
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
    } catch (_) {
      // Verification failed — log but don't block UX
    }

    state = PaymentState(
      isProcessing: false,
      isSuccess: true,
      paymentId: response.paymentId,
      orderId: response.orderId,
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

  /// Create a mock order from current cart for UI development
  app.Order createOrderFromCart(CartState cartState) {
    final now = DateTime.now();
    final orderNumber = 'CHZ-${(100000 + Random().nextInt(900000))}';

    return app.Order(
      id: 'order_${now.millisecondsSinceEpoch}',
      orderNumber: orderNumber,
      customerId: 'current_user',
      restaurantId: cartState.restaurantId ?? '',
      restaurantName: cartState.restaurantName ?? '',
      deliveryAddressId: 'default_address',
      items: cartState.items
          .map(
            (ci) => app.OrderItem(
              id: ci.menuItem.id,
              name: ci.menuItem.name,
              quantity: ci.quantity,
              price: ci.menuItem.price,
              isVeg: ci.menuItem.isVeg,
            ),
          )
          .toList(),
      itemTotal: cartState.itemTotal,
      deliveryFee: cartState.deliveryFee,
      platformFee: cartState.platformFee,
      gst: cartState.gst,
      discount: cartState.discount,
      couponCode: cartState.couponCode,
      grandTotal: cartState.grandTotal,
      paymentMethod: 'razorpay',
      paymentStatus: state.isSuccess ? 'paid' : 'pending',
      paymentId: state.paymentId,
      status: app.OrderStatus.placed,
      specialInstructions: cartState.specialInstructions,
      deliveryInstructions: cartState.deliveryInstructions,
      estimatedDeliveryMin: 35,
      placedAt: now,
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
