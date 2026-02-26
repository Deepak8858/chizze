package handlers

import (
	"encoding/json"
	"io"
	"log"
	"math"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
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

// Initiate creates a Razorpay order and stores payment record
// @Summary Initiate a payment
// @Description Creates a Razorpay order for the given order and stores a payment record
// @Tags Payments
// @Accept json
// @Produce json
// @Param request body object{order_id=string} true "Order ID to pay for"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/payments/initiate [post]
func (h *PaymentHandler) Initiate(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		OrderID string `json:"order_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Order ID is required")
		return
	}

	// Fetch order and verify ownership
	order, err := h.appwrite.GetOrder(req.OrderID)
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	customerID, _ := order["customer_id"].(string)
	if customerID != userID {
		utils.Forbidden(c, "Not your order")
		return
	}

	// Get amount from order (grand_total in rupees, Razorpay expects paise)
	grandTotal, _ := order["grand_total"].(float64)
	if grandTotal <= 0 {
		utils.BadRequest(c, "Invalid order amount")
		return
	}
	amountPaise := int64(math.Round(grandTotal * 100))

	// Create Razorpay order
	orderNumber, _ := order["order_number"].(string)
	rzpOrder, err := h.payments.CreateRazorpayOrder(amountPaise, "INR", orderNumber)
	if err != nil {
		log.Printf("[ERROR] Razorpay order creation failed for order=%s amount=%d user=%s: %v",
			req.OrderID, amountPaise, userID, err)
		utils.InternalError(c, "Failed to create payment order")
		return
	}

	// Store payment record in Appwrite
	paymentData := map[string]interface{}{
		"order_id":          req.OrderID,
		"user_id":           userID,
		"razorpay_order_id": rzpOrder.ID,
		"amount":            grandTotal,
		"status":            "pending",
		"method":            "online",
	}
	if _, err := h.appwrite.CreatePayment("unique()", paymentData); err != nil {
		log.Printf("[ERROR] CreatePayment record failed for order=%s: %v", req.OrderID, err)
		utils.InternalError(c, "Failed to create payment order")
		return
	}

	utils.Success(c, gin.H{
		"razorpay_order_id": rzpOrder.ID,
		"razorpay_key_id":   h.payments.GetKeyID(),
		"amount":            amountPaise,
		"currency":          "INR",
		"order_id":          req.OrderID,
	})
}

// Verify validates Razorpay payment callback and updates order
// @Summary Verify a payment
// @Description Validates Razorpay payment signature and updates order payment status to paid
// @Tags Payments
// @Accept json
// @Produce json
// @Param request body services.VerifyPaymentRequest true "Razorpay payment verification data"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Failure 403 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Security BearerAuth
// @Router /api/v1/payments/verify [post]
func (h *PaymentHandler) Verify(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req services.VerifyPaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "Missing payment verification data")
		return
	}

	if !h.payments.VerifySignature(req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature) {
		utils.BadRequest(c, "Payment verification failed — invalid signature")
		return
	}

	// Find payment record by razorpay_order_id
	paymentResult, err := h.appwrite.GetPaymentByRazorpayOrder(req.RazorpayOrderID)
	if err != nil || paymentResult.Total == 0 {
		utils.NotFound(c, "Payment record not found")
		return
	}

	paymentDoc := paymentResult.Documents[0]
	paymentID, _ := paymentDoc["$id"].(string)
	orderID, _ := paymentDoc["order_id"].(string)
	paymentOwnerID, _ := paymentDoc["user_id"].(string)

	// Verify ownership
	if paymentOwnerID != userID {
		utils.Forbidden(c, "Not your payment")
		return
	}

	// Update payment record
	if _, err := h.appwrite.UpdatePayment(paymentID, map[string]interface{}{
		"razorpay_payment_id": req.RazorpayPaymentID,
		"razorpay_signature":  req.RazorpaySignature,
		"status":              "success",
	}); err != nil {
		log.Printf("[ERROR] UpdatePayment failed for payment=%s order=%s: %v", paymentID, orderID, err)
		utils.InternalError(c, "Failed to update payment record")
		return
	}

	// Update order payment status
	if _, err := h.appwrite.UpdateOrder(orderID, map[string]interface{}{
		"payment_status": models.PaymentPaid,
		"payment_id":     req.RazorpayPaymentID,
	}); err != nil {
		log.Printf("[ERROR] UpdateOrder payment status failed for order=%s: %v", orderID, err)
		utils.InternalError(c, "Payment verified but failed to update order")
		return
	}

	utils.Success(c, gin.H{
		"verified":   true,
		"payment_id": req.RazorpayPaymentID,
		"order_id":   orderID,
	})
}

// Webhook handles Razorpay webhook events
// @Summary Razorpay webhook
// @Description Handles Razorpay webhook events for payment.captured, payment.failed, and refund.processed
// @Tags Payments
// @Accept json
// @Produce json
// @Param X-Razorpay-Signature header string true "Razorpay webhook signature"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 401 {object} map[string]string
// @Router /api/v1/payments/webhook [post]
func (h *PaymentHandler) Webhook(c *gin.Context) {
	// Read raw body for signature verification
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		utils.BadRequest(c, "Failed to read request body")
		return
	}

	// Verify webhook signature
	signature := c.GetHeader("X-Razorpay-Signature")
	if signature == "" || !h.payments.VerifyWebhookSignature(body, signature) {
		utils.Unauthorized(c, "Invalid webhook signature")
		return
	}

	// Parse webhook event
	var event struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct {
				Entity struct {
					ID      string  `json:"id"`
					OrderID string  `json:"order_id"`
					Amount  float64 `json:"amount"`
					Status  string  `json:"status"`
				} `json:"entity"`
			} `json:"payment"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(body, &event); err != nil {
		utils.BadRequest(c, "Invalid webhook payload")
		return
	}

	log.Printf("Razorpay webhook: event=%s payment_id=%s order_id=%s",
		event.Event, event.Payload.Payment.Entity.ID, event.Payload.Payment.Entity.OrderID)

	switch event.Event {
	case "payment.captured":
		// Payment successful — update order if not already updated via Verify()
		rzpOrderID := event.Payload.Payment.Entity.OrderID
		paymentResult, err := h.appwrite.GetPaymentByRazorpayOrder(rzpOrderID)
		if err == nil && paymentResult.Total > 0 {
			paymentDoc := paymentResult.Documents[0]
			paymentID, _ := paymentDoc["$id"].(string)
			orderID, _ := paymentDoc["order_id"].(string)

			h.appwrite.UpdatePayment(paymentID, map[string]interface{}{
				"razorpay_payment_id": event.Payload.Payment.Entity.ID,
				"status":              "success",
			})

			h.appwrite.UpdateOrder(orderID, map[string]interface{}{
				"payment_status": models.PaymentPaid,
				"payment_id":     event.Payload.Payment.Entity.ID,
			})
		}

	case "payment.failed":
		rzpOrderID := event.Payload.Payment.Entity.OrderID
		paymentResult, err := h.appwrite.GetPaymentByRazorpayOrder(rzpOrderID)
		if err == nil && paymentResult.Total > 0 {
			paymentDoc := paymentResult.Documents[0]
			paymentID, _ := paymentDoc["$id"].(string)
			orderID, _ := paymentDoc["order_id"].(string)

			h.appwrite.UpdatePayment(paymentID, map[string]interface{}{
				"status": "failed",
			})

			h.appwrite.UpdateOrder(orderID, map[string]interface{}{
				"payment_status": models.PaymentFailed,
			})
		}

	case "refund.processed":
		// Handle refund — mark order payment as refunded
		rzpOrderID := event.Payload.Payment.Entity.OrderID
		paymentResult, err := h.appwrite.GetPaymentByRazorpayOrder(rzpOrderID)
		if err == nil && paymentResult.Total > 0 {
			paymentDoc := paymentResult.Documents[0]
			orderID, _ := paymentDoc["order_id"].(string)
			h.appwrite.UpdateOrder(orderID, map[string]interface{}{
				"payment_status": models.PaymentRefunded,
			})
		}
	}

	utils.Success(c, gin.H{"received": true})
}
