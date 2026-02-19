package services

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"

	"github.com/chizze/backend/internal/config"
)

// PaymentService handles Razorpay operations
type PaymentService struct {
	keyID     string
	keySecret string
}

// NewPaymentService creates a payment service
func NewPaymentService(cfg *config.Config) *PaymentService {
	return &PaymentService{
		keyID:     cfg.RazorpayKeyID,
		keySecret: cfg.RazorpayKeySecret,
	}
}

// VerifySignature validates Razorpay payment callback
func (s *PaymentService) VerifySignature(orderID, paymentID, signature string) bool {
	message := fmt.Sprintf("%s|%s", orderID, paymentID)

	mac := hmac.New(sha256.New, []byte(s.keySecret))
	mac.Write([]byte(message))
	expectedSignature := hex.EncodeToString(mac.Sum(nil))

	return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

// VerifyPaymentRequest is the body for POST /payments/verify
type VerifyPaymentRequest struct {
	RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
	RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
	RazorpaySignature string `json:"razorpay_signature" binding:"required"`
}
