import 'package:flutter_test/flutter_test.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:chizze/features/payment/providers/payment_provider.dart';

/// Unit tests for [PaymentNotifier.mapPaymentFailureToMessage].
///
/// These cover the cancellation/failure messages that used to surface
/// "undefined" to customers because the Razorpay SDK sometimes emits an
/// unparsed/null [PaymentFailureResponse.message]. Keep these tests aligned
/// with the Razorpay error code constants — if the SDK renumbers them, the
/// switch in payment_provider.dart must be updated alongside these tests.
void main() {
  group('mapPaymentFailureToMessage', () {
    test('PAYMENT_CANCELLED → professional customer-facing copy', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.PAYMENT_CANCELLED,
        null,
      );
      expect(msg.toLowerCase(), contains('cancelled'));
      expect(msg.toLowerCase(), contains('order has not been placed'));
      expect(msg.toLowerCase(), isNot(contains('undefined')));
    });

    test('PAYMENT_CANCELLED ignores raw "undefined" message', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.PAYMENT_CANCELLED,
        'undefined',
      );
      expect(msg.toLowerCase(), isNot(contains('undefined')));
      expect(msg.toLowerCase(), contains('cancelled'));
    });

    test('NETWORK_ERROR explains connectivity issue', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.NETWORK_ERROR,
        null,
      );
      expect(msg.toLowerCase(), contains('internet'));
      expect(msg.toLowerCase(), isNot(contains('undefined')));
    });

    test('TLS_ERROR mentions secure connection', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.TLS_ERROR,
        null,
      );
      expect(msg.toLowerCase(), contains('secure'));
    });

    test('INVALID_OPTIONS shows configuration fallback', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.INVALID_OPTIONS,
        null,
      );
      expect(msg.toLowerCase(), contains('try again'));
      expect(msg.toLowerCase(), isNot(contains('undefined')));
    });

    test('UNKNOWN_ERROR with null raw falls back to generic message', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        null,
      );
      expect(msg.toLowerCase(), contains('no amount has been charged'));
      expect(msg.toLowerCase(), isNot(contains('undefined')));
    });

    test('UNKNOWN_ERROR with raw "undefined" falls back to generic', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        'undefined',
      );
      expect(msg.toLowerCase(), isNot(contains('undefined')));
      expect(msg.toLowerCase(), contains('no amount has been charged'));
    });

    test('UNKNOWN_ERROR extracts description from nested JSON payload', () {
      const raw =
          '{"error":{"code":"BAD_REQUEST_ERROR","description":"Payment failed due to insufficient funds","source":"customer"}}';
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        raw,
      );
      expect(msg, contains('insufficient funds'));
    });

    test('UNKNOWN_ERROR extracts top-level description when no nested error',
        () {
      const raw = '{"description":"Card declined by issuing bank"}';
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        raw,
      );
      expect(msg, contains('Card declined by issuing bank'));
    });

    test('UNKNOWN_ERROR uses reason when description absent', () {
      const raw =
          '{"error":{"reason":"payment_timeout","metadata":{"payment_id":"pay_x"}}}';
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        raw,
      );
      // Underscore → space so "payment_timeout" reads as "payment timeout"
      expect(msg, contains('payment timeout'));
    });

    test('UNKNOWN_ERROR with non-JSON plain text passes text through', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        'Card declined',
      );
      expect(msg, contains('Card declined'));
    });

    test('UNKNOWN_ERROR with "null" literal falls back to generic', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        'null',
      );
      expect(msg.toLowerCase(), isNot(contains('null')));
      expect(msg.toLowerCase(), contains('no amount has been charged'));
    });

    test('null code (platform channel glitch) is treated as UNKNOWN_ERROR',
        () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(null, null);
      expect(msg.toLowerCase(), contains('no amount has been charged'));
      expect(msg.toLowerCase(), isNot(contains('undefined')));
    });

    test('empty-string raw message is treated as missing', () {
      final msg = PaymentNotifier.mapPaymentFailureToMessage(
        Razorpay.UNKNOWN_ERROR,
        '',
      );
      expect(msg.toLowerCase(), isNot(contains('undefined')));
      expect(msg.toLowerCase(), contains('no amount has been charged'));
    });
  });
}
