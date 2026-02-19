import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
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
  final bool isSuccess;

  const PaymentState({
    this.isProcessing = false,
    this.error,
    this.paymentId,
    this.orderId,
    this.isSuccess = false,
  });

  PaymentState copyWith({
    bool? isProcessing,
    String? error,
    String? paymentId,
    String? orderId,
    bool? isSuccess,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      paymentId: paymentId ?? this.paymentId,
      orderId: orderId ?? this.orderId,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }
}

/// Payment notifier — manages Razorpay payment flow
class PaymentNotifier extends StateNotifier<PaymentState> {
  final Razorpay _razorpay;
  final Ref _ref;
  VoidCallback? _onSuccess;

  PaymentNotifier(this._ref)
    : _razorpay = Razorpay(),
      super(const PaymentState()) {
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  /// Start payment for the current cart
  void startPayment({
    required double amount,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
    String? description,
    VoidCallback? onSuccess,
  }) {
    _onSuccess = onSuccess;
    state = state.copyWith(isProcessing: true, error: null);

    // Generate a temporary order ID (in production, get from Go backend)
    final orderId = 'order_${DateTime.now().millisecondsSinceEpoch}';

    final options = {
      'key': RazorpayConfig.keyId,
      'amount': (amount * 100).toInt(), // Razorpay expects amount in paise
      'name': 'Chizze',
      'description': description ?? 'Food Delivery Order',
      'order_id':
          '', // In production, get from Razorpay Orders API via Go backend
      'prefill': {
        'contact': customerPhone,
        'email': customerEmail,
        'name': customerName,
      },
      'theme': {
        'color': '#F49D25', // Chizze primary color
      },
      'notes': {'order_id': orderId},
      'modal': {'confirm_close': true},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Failed to open payment: $e',
      );
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
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
  return PaymentNotifier(ref);
});
