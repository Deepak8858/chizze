package handlers

import (
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
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

// List returns user's notifications with pagination
// GET /api/v1/notifications
func (h *NotificationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	pg := models.ParsePagination(c)
	_ = pg // ListNotifications uses its own query currently

	result, err := h.appwrite.ListNotifications(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch notifications")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// MarkRead marks a notification as read with ownership check
// PUT /api/v1/notifications/:id/read
func (h *NotificationHandler) MarkRead(c *gin.Context) {
	userID := middleware.GetUserID(c)
	notifID := c.Param("id")

	// Fetch notification to verify ownership
	notif, err := h.appwrite.GetNotification(notifID)
	if err != nil {
		utils.NotFound(c, "Notification not found")
		return
	}
	notifUserID, _ := notif["user_id"].(string)
	if notifUserID != userID {
		utils.Forbidden(c, "Access denied")
		return
	}

	updated, err := h.appwrite.UpdateNotification(notifID, map[string]interface{}{
		"is_read": true,
	})
	if err != nil {
		utils.InternalError(c, "Failed to mark notification as read")
		return
	}
	utils.Success(c, updated)
}

// MarkAllRead marks all user's notifications as read
// PUT /api/v1/notifications/read-all
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListNotifications(userID)
	if err != nil {
		utils.InternalError(c, "Failed to fetch notifications")
		return
	}

	updated := 0
	for _, doc := range result.Documents {
		id, _ := doc["$id"].(string)
		isRead, _ := doc["is_read"].(bool)
		if !isRead {
			_, err := h.appwrite.UpdateNotification(id, map[string]interface{}{
				"is_read": true,
			})
			if err == nil {
				updated++
			}
		}
	}
	utils.Success(c, gin.H{"message": "Notifications marked as read", "updated": updated})
}
