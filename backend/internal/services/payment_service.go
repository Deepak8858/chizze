package services

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/chizze/backend/internal/config"
)

// PaymentService handles Razorpay operations
type PaymentService struct {
	keyID         string
	keySecret     string
	webhookSecret string
	httpClient    *http.Client
}

// NewPaymentService creates a payment service
func NewPaymentService(cfg *config.Config) *PaymentService {
	webhookSec := cfg.RazorpayWebhookSecret
	if webhookSec == "" {
		webhookSec = cfg.RazorpayKeySecret // fallback for dev
	}
	return &PaymentService{
		keyID:         cfg.RazorpayKeyID,
		keySecret:     cfg.RazorpayKeySecret,
		webhookSecret: webhookSec,
		httpClient:    &http.Client{Timeout: 15 * time.Second},
	}
}

// GetKeyID returns the Razorpay key ID (for client-side checkout)
func (s *PaymentService) GetKeyID() string {
	return s.keyID
}

// RazorpayOrderResponse is the response from Razorpay order creation
type RazorpayOrderResponse struct {
	ID       string `json:"id"`
	Entity   string `json:"entity"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Status   string `json:"status"`
	Receipt  string `json:"receipt"`
}

// CreateRazorpayOrder creates an order on Razorpay
func (s *PaymentService) CreateRazorpayOrder(amountPaise int64, currency, receipt string) (*RazorpayOrderResponse, error) {
	payload := map[string]interface{}{
		"amount":   amountPaise,
		"currency": currency,
		"receipt":  receipt,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", "https://api.razorpay.com/v1/orders", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(s.keyID, s.keySecret)

	client := s.httpClient
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("razorpay request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("razorpay error %d: %s", resp.StatusCode, string(respBody))
	}

	var order RazorpayOrderResponse
	if err := json.Unmarshal(respBody, &order); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}
	return &order, nil
}

// VerifySignature validates Razorpay payment callback
func (s *PaymentService) VerifySignature(orderID, paymentID, signature string) bool {
	message := fmt.Sprintf("%s|%s", orderID, paymentID)

	mac := hmac.New(sha256.New, []byte(s.keySecret))
	mac.Write([]byte(message))
	expectedSignature := hex.EncodeToString(mac.Sum(nil))

	return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

// VerifyWebhookSignature validates Razorpay webhook signature using dedicated webhook secret
func (s *PaymentService) VerifyWebhookSignature(body []byte, signature string) bool {
	mac := hmac.New(sha256.New, []byte(s.webhookSecret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(signature))
}

// VerifyPaymentRequest is the body for POST /payments/verify
type VerifyPaymentRequest struct {
	RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
	RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
	RazorpaySignature string `json:"razorpay_signature" binding:"required"`
}
