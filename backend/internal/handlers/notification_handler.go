package handlers

import (
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
)

// NotificationHandler handles notification endpoints
type NotificationHandler struct {
	appwrite *services.AppwriteService
}

// NewNotificationHandler creates a notification handler
func NewNotificationHandler(aw *services.AppwriteService) *NotificationHandler {
	return &NotificationHandler{appwrite: aw}
}

// List returns user's notifications
// GET /api/v1/notifications
func (h *NotificationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListNotifications(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch notifications")
		return
	}
	utils.Success(c, result.Documents)
}

// MarkRead marks a notification as read
// PUT /api/v1/notifications/:id/read
func (h *NotificationHandler) MarkRead(c *gin.Context) {
	notifID := c.Param("id")
	updated, err := h.appwrite.UpdateNotification(notifID, map[string]interface{}{
		"is_read": true,
	})
	if err != nil {
		utils.InternalError(c, "Failed to mark notification as read")
		return
	}
	utils.Success(c, updated)
}

// MarkAllRead marks all notifications as read
// PUT /api/v1/notifications/read-all
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListNotifications(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch notifications")
		return
	}

	for _, doc := range result.Documents {
		id, _ := doc["$id"].(string)
		isRead, _ := doc["is_read"].(bool)
		if !isRead {
			_, _ = h.appwrite.UpdateNotification(id, map[string]interface{}{
				"is_read": true,
			})
		}
	}
	utils.Success(c, gin.H{"message": "All notifications marked as read"})
}
