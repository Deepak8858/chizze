package handlers_test

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/testutil"
)

// Covers the Razorpay payment flow edge cases that would otherwise silently
// corrupt orders or let attackers inflate payment amounts. Each test wires
// through the real PaymentHandler in testutil so we exercise the signature
// verification, ownership checks, and order/payment state updates end-to-end.

func hmacHexBytes(secret string, body []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return hex.EncodeToString(mac.Sum(nil))
}

func sendWebhook(te *testutil.TestEnv, body []byte, signature string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/webhook", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if signature != "" {
		req.Header.Set("X-Razorpay-Signature", signature)
	}
	rec := httptest.NewRecorder()
	te.Router.ServeHTTP(rec, req)
	return rec
}

// ─── Webhook signature verification ───

func TestWebhook_RejectsMissingSignature(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	body := []byte(`{"event":"payment.captured"}`)
	rec := sendWebhook(te, body, "")

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing signature, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestWebhook_RejectsBadSignature(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	body := []byte(`{"event":"payment.captured"}`)
	rec := sendWebhook(te, body, "not-a-real-signature")

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for bad signature, got %d", rec.Code)
	}
}

func TestWebhook_RejectsTamperedBody(t *testing.T) {
	// Classic amount-inflation attack: attacker intercepts webhook, replaces
	// amount, but keeps the original signature. Must fail.
	te := testutil.NewTestEnv(t)
	defer te.Close()

	original := []byte(`{"event":"payment.captured","payload":{"payment":{"entity":{"amount":100}}}}`)
	tampered := []byte(`{"event":"payment.captured","payload":{"payment":{"entity":{"amount":999999999}}}}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, original)

	rec := sendWebhook(te, tampered, sig)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tampered body must return 401, got %d", rec.Code)
	}
}

// ─── payment.captured flow ───

func seedPendingPayment(te *testutil.TestEnv, orderID, rzpOrderID string, amountRupees float64, status string) string {
	te.T.Helper()
	paymentDocID := "pay_doc_" + orderID
	te.FakeAW.SeedDocument(models.CollectionPayments, paymentDocID, map[string]interface{}{
		"order_id":          orderID,
		"user_id":           "user_1",
		"razorpay_order_id": rzpOrderID,
		"amount":            amountRupees,
		"status":            status,
		"method":            "online",
	})
	return paymentDocID
}

func seedPlacedOrder(te *testutil.TestEnv, orderID string) {
	te.T.Helper()
	te.FakeAW.SeedDocument("orders", orderID, map[string]interface{}{
		"customer_id":    "user_1",
		"status":         models.OrderStatusPlaced,
		"payment_status": models.PaymentPending,
		"grand_total":    500.0,
	})
}

func TestWebhook_PaymentCaptured_MarksOrderPaid(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "pending")
	seedPlacedOrder(te, "order_1")

	body := []byte(`{
		"event":"payment.captured",
		"payload":{"payment":{"entity":{"id":"pay_123","order_id":"rzp_order_1","amount":50000,"status":"captured"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Order should be marked paid
	order := te.FakeAW.GetDocument("orders", "order_1")
	if got, _ := order["payment_status"].(string); got != models.PaymentPaid {
		t.Errorf("expected payment_status=paid, got %q", got)
	}
	if got, _ := order["payment_id"].(string); got != "pay_123" {
		t.Errorf("expected payment_id=pay_123, got %q", got)
	}
}

func TestWebhook_PaymentCaptured_AmountMismatch_Ignored(t *testing.T) {
	// Critical security test: Razorpay captured amount ≠ the amount our order
	// was created with. Must NOT mark order paid — otherwise a malicious/broken
	// flow pays ₹1 for a ₹500 order.
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "pending")
	seedPlacedOrder(te, "order_1")

	// Attacker captures 1 paise for a 50000-paise order
	body := []byte(`{
		"event":"payment.captured",
		"payload":{"payment":{"entity":{"id":"pay_evil","order_id":"rzp_order_1","amount":1,"status":"captured"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("webhook still returns 200 (log-and-continue), got %d", rec.Code)
	}

	order := te.FakeAW.GetDocument("orders", "order_1")
	if got, _ := order["payment_status"].(string); got == models.PaymentPaid {
		t.Error("SECURITY: order marked paid despite amount mismatch")
	}
}

func TestWebhook_PaymentCaptured_DuplicateIsIdempotent(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Start with payment already marked success (as if Verify() ran first)
	paymentDocID := seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "success")
	te.FakeAW.SeedDocument(models.CollectionPayments, paymentDocID, map[string]interface{}{
		"order_id":            "order_1",
		"user_id":             "user_1",
		"razorpay_order_id":   "rzp_order_1",
		"razorpay_payment_id": "pay_123",
		"amount":              500.0,
		"status":              "success",
		"method":              "online",
	})
	te.FakeAW.SeedDocument("orders", "order_1", map[string]interface{}{
		"customer_id":    "user_1",
		"status":         models.OrderStatusConfirmed,
		"payment_status": models.PaymentPaid,
		"payment_id":     "pay_123",
		"grand_total":    500.0,
	})

	// Razorpay retries the webhook — payment.captured with same payment_id
	body := []byte(`{
		"event":"payment.captured",
		"payload":{"payment":{"entity":{"id":"pay_123","order_id":"rzp_order_1","amount":50000,"status":"captured"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	// Order status must not regress from confirmed → placed or anything else
	order := te.FakeAW.GetDocument("orders", "order_1")
	if got, _ := order["status"].(string); got != models.OrderStatusConfirmed {
		t.Errorf("duplicate captured webhook must not change order status; got %q", got)
	}
}

// ─── payment.failed flow ───

func TestWebhook_PaymentFailed_CancelsPlacedOrder(t *testing.T) {
	// Root-cause regression guard: before this handler cancelled the order
	// on payment.failed, restaurants and the matcher kept working on orders
	// the customer never paid for. Validate the cancellation fires.
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "pending")
	seedPlacedOrder(te, "order_1")

	body := []byte(`{
		"event":"payment.failed",
		"payload":{"payment":{"entity":{"id":"pay_fail","order_id":"rzp_order_1","amount":50000,"status":"failed"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	order := te.FakeAW.GetDocument("orders", "order_1")
	if got, _ := order["status"].(string); got != models.OrderStatusCancelled {
		t.Errorf("expected order status=cancelled after payment.failed, got %q", got)
	}
	if got, _ := order["payment_status"].(string); got != models.PaymentFailed {
		t.Errorf("expected payment_status=failed, got %q", got)
	}
	if reason, _ := order["cancellation_reason"].(string); reason != "Payment failed" {
		t.Errorf("expected cancellation_reason='Payment failed', got %q", reason)
	}
}

func TestWebhook_PaymentFailed_DoesNotCancelConfirmedOrder(t *testing.T) {
	// A delayed/late payment.failed arriving after the restaurant has already
	// accepted and prepared the order must not retroactively cancel it; those
	// are handled by refund flows, not status flips.
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "pending")
	te.FakeAW.SeedDocument("orders", "order_1", map[string]interface{}{
		"customer_id":    "user_1",
		"status":         models.OrderStatusPreparing,
		"payment_status": models.PaymentPending,
		"grand_total":    500.0,
	})

	body := []byte(`{
		"event":"payment.failed",
		"payload":{"payment":{"entity":{"id":"pay_fail","order_id":"rzp_order_1","status":"failed"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	order := te.FakeAW.GetDocument("orders", "order_1")
	if got, _ := order["status"].(string); got != models.OrderStatusPreparing {
		t.Errorf("preparing order must NOT be cancelled by late payment.failed; got %q", got)
	}
	if got, _ := order["payment_status"].(string); got != models.PaymentFailed {
		t.Errorf("payment_status should still flip to failed, got %q", got)
	}
}

func TestWebhook_PaymentFailed_AfterSuccessIgnored(t *testing.T) {
	// Attacker replays an old payment.failed event after the payment has
	// already succeeded — must not downgrade payment_status from paid to failed.
	te := testutil.NewTestEnv(t)
	defer te.Close()

	paymentDocID := seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "success")
	_ = paymentDocID
	te.FakeAW.SeedDocument("orders", "order_1", map[string]interface{}{
		"customer_id":    "user_1",
		"status":         models.OrderStatusConfirmed,
		"payment_status": models.PaymentPaid,
		"payment_id":     "pay_123",
		"grand_total":    500.0,
	})

	body := []byte(`{
		"event":"payment.failed",
		"payload":{"payment":{"entity":{"id":"pay_fail","order_id":"rzp_order_1","status":"failed"}}}
	}`)
	sig := hmacHexBytes(te.Config.RazorpayWebhookSecret, body)

	rec := sendWebhook(te, body, sig)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	payment := te.FakeAW.GetDocument(models.CollectionPayments, paymentDocID)
	if got, _ := payment["status"].(string); got != "success" {
		t.Errorf("SECURITY: replayed payment.failed downgraded payment status to %q", got)
	}
}

// ─── Verify endpoint ───

func TestPaymentVerify_InvalidSignatureRejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	body := map[string]string{
		"razorpay_order_id":   "rzp_order_1",
		"razorpay_payment_id": "pay_123",
		"razorpay_signature":  "not-valid",
	}
	rec := te.AuthRequest(http.MethodPost, "/api/v1/payments/verify", body, "user_1", "customer")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for bad signature, got %d: %s", rec.Code, rec.Body.String())
	}

	var parsed map[string]interface{}
	_ = json.Unmarshal(rec.Body.Bytes(), &parsed)
	if errMsg, _ := parsed["error"].(string); errMsg == "" {
		t.Error("response must include an error message")
	}
}

func TestPaymentVerify_WrongOwnerForbidden(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPendingPayment(te, "order_1", "rzp_order_1", 500.0, "pending")
	seedPlacedOrder(te, "order_1")

	// Build a valid signature so we get past VerifySignature and reach the
	// ownership check.
	message := "rzp_order_1|pay_123"
	sig := hmacHexBytes(te.Config.RazorpayKeySecret, []byte(message))

	body := map[string]string{
		"razorpay_order_id":   "rzp_order_1",
		"razorpay_payment_id": "pay_123",
		"razorpay_signature":  sig,
	}
	rec := te.AuthRequest(http.MethodPost, "/api/v1/payments/verify", body, "attacker_user", "customer")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when another user tries to verify, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── Initiate endpoint ───

func TestPaymentInitiate_RejectsOtherUsersOrder(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	seedPlacedOrder(te, "order_1")

	body := map[string]string{"order_id": "order_1"}
	rec := te.AuthRequest(http.MethodPost, "/api/v1/payments/initiate", body, "not_owner", "customer")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when non-owner initiates payment, got %d", rec.Code)
	}
}

func TestPaymentInitiate_RejectsMissingOrderID(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest(http.MethodPost, "/api/v1/payments/initiate", map[string]string{}, "user_1", "customer")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing order_id, got %d", rec.Code)
	}
}

func TestPaymentInitiate_RejectsZeroAmountOrder(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.SeedDocument("orders", "order_zero", map[string]interface{}{
		"customer_id": "user_1",
		"grand_total": 0.0,
	})

	body := map[string]string{"order_id": "order_zero"}
	rec := te.AuthRequest(http.MethodPost, "/api/v1/payments/initiate", body, "user_1", "customer")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for zero-amount order, got %d: %s", rec.Code, rec.Body.String())
	}
}
