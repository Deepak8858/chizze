package handlers

import (
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// PaymentHandler handles payment endpoints
type PaymentHandler struct {
	appwrite *services.AppwriteService
	payments *services.PaymentService
}

// NewPaymentHandler creates a payment handler
func NewPaymentHandler(aw *services.AppwriteService, ps *services.PaymentService) *PaymentHandler {
	return &PaymentHandler{appwrite: aw, payments: ps}
}

// Initiate creates a Razorpay order
// POST /api/v1/payments/initiate
func (h *PaymentHandler) Initiate(c *gin.Context) {
	var req struct {
		OrderID string  `json:"order_id" binding:"required"`
		Amount  float64 `json:"amount" binding:"required,gt=0"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Order ID and amount are required")
		return
	}

	// TODO: Create Razorpay order via API, return order_id + key_id
	utils.Success(c, gin.H{
		"razorpay_order_id": "order_placeholder",
		"amount":            req.Amount * 100, // paise
		"currency":          "INR",
	})
}

// Verify validates Razorpay payment callback
// POST /api/v1/payments/verify
func (h *PaymentHandler) Verify(c *gin.Context) {
	var req services.VerifyPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Missing payment verification data")
		return
	}

	if !h.payments.VerifySignature(req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature) {
		utils.BadRequest(c, "Payment verification failed — invalid signature")
		return
	}

	// TODO: Update order payment_status to 'paid', store payment_id
	utils.Success(c, gin.H{
		"verified":   true,
		"payment_id": req.RazorpayPaymentID,
	})
}

// Webhook handles Razorpay webhook events
// POST /api/v1/payments/webhook
func (h *PaymentHandler) Webhook(c *gin.Context) {
	// TODO: Validate webhook signature, process events
	utils.Success(c, gin.H{"received": true})
}
