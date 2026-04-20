package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"github.com/chizze/backend/internal/config"
)

// Trivial crypto helpers — repeated inline in tests so we aren't testing the
// implementation against itself. Any divergence between these and
// PaymentService means a genuine signature-logic regression.
func hmacHex(secret, message string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(message))
	return hex.EncodeToString(mac.Sum(nil))
}

func hmacHexBytes(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

func TestVerifySignature_Valid(t *testing.T) {
	svc := NewPaymentService(&config.Config{
		RazorpayKeyID:         "rzp_test_key",
		RazorpayKeySecret:     "secret123",
		RazorpayWebhookSecret: "webhook456",
	})

	orderID := "order_ABC"
	paymentID := "pay_XYZ"
	signature := hmacHex("secret123", orderID+"|"+paymentID)

	if !svc.VerifySignature(orderID, paymentID, signature) {
		t.Error("valid Razorpay signature must verify true")
	}
}

func TestVerifySignature_Invalid(t *testing.T) {
	svc := NewPaymentService(&config.Config{
		RazorpayKeyID:     "rzp_test_key",
		RazorpayKeySecret: "secret123",
	})

	if svc.VerifySignature("order_ABC", "pay_XYZ", "bogus") {
		t.Error("bogus signature must verify false")
	}
	if svc.VerifySignature("order_ABC", "pay_XYZ", "") {
		t.Error("empty signature must verify false")
	}
}

func TestVerifySignature_DifferentKey(t *testing.T) {
	// Swapping key_secret must invalidate an otherwise-correct signature —
	// protects against cross-environment signature replay (dev signature
	// accepted by prod, etc.).
	svcProd := NewPaymentService(&config.Config{
		RazorpayKeyID:     "rzp_live_key",
		RazorpayKeySecret: "prod_secret",
	})

	devSig := hmacHex("dev_secret", "order_ABC|pay_XYZ")
	if svcProd.VerifySignature("order_ABC", "pay_XYZ", devSig) {
		t.Error("signature signed by dev secret must fail against prod service")
	}
}

func TestVerifyWebhookSignature_UsesWebhookSecret(t *testing.T) {
	// Webhook verification must use the webhook secret, NOT the key_secret —
	// that mixup was a real production incident: webhook signatures silently
	// failing because the service fell back to key_secret instead of the
	// Razorpay dashboard-issued webhook secret.
	svc := NewPaymentService(&config.Config{
		RazorpayKeyID:         "rzp_test_key",
		RazorpayKeySecret:     "secret123",
		RazorpayWebhookSecret: "webhook456",
	})

	body := []byte(`{"event":"payment.captured","payload":{}}`)
	webhookSig := hmacHexBytes("webhook456", body)
	keySig := hmacHexBytes("secret123", body)

	if !svc.VerifyWebhookSignature(body, webhookSig) {
		t.Error("valid webhook signature must verify true")
	}
	if svc.VerifyWebhookSignature(body, keySig) {
		t.Error("key_secret-signed payload must NOT verify as webhook")
	}
}

func TestVerifyWebhookSignature_FallsBackToKeySecret(t *testing.T) {
	// If RazorpayWebhookSecret is unset (dev environments), the service
	// falls back to key_secret so local webhook testing works. Document that
	// behavior so we notice if it ever changes.
	svc := NewPaymentService(&config.Config{
		RazorpayKeyID:     "rzp_test_key",
		RazorpayKeySecret: "secret123",
		// RazorpayWebhookSecret intentionally empty
	})

	body := []byte(`{"event":"payment.failed"}`)
	sig := hmacHexBytes("secret123", body)

	if !svc.VerifyWebhookSignature(body, sig) {
		t.Error("with empty webhook secret, key_secret should verify as webhook (dev fallback)")
	}
}

func TestVerifyWebhookSignature_RejectsTamperedBody(t *testing.T) {
	svc := NewPaymentService(&config.Config{
		RazorpayKeyID:         "rzp_test_key",
		RazorpayKeySecret:     "secret123",
		RazorpayWebhookSecret: "webhook456",
	})

	original := []byte(`{"event":"payment.captured","amount":100}`)
	tampered := []byte(`{"event":"payment.captured","amount":999999}`)
	sig := hmacHexBytes("webhook456", original)

	if svc.VerifyWebhookSignature(tampered, sig) {
		t.Error("tampered webhook body must fail verification — otherwise attacker can inflate amounts")
	}
}
