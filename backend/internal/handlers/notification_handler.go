package handlers

import (
	"log"

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
// @Summary      List notifications
// @Description  Returns the authenticated user's notifications with pagination
// @Tags         Notifications
// @Accept       json
// @Produce      json
// @Param        page      query     int  false  "Page number"
// @Param        per_page  query     int  false  "Items per page"
// @Success      200  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/notifications [get]
func (h *NotificationHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	pg := models.ParsePagination(c)

	result, err := h.appwrite.ListNotifications(userID, pg.PerPage, pg.Offset())
	if err != nil {
		log.Printf("[notifications] ListNotifications failed for user %s: %v", userID, err)
		utils.InternalError(c, "Failed to fetch notifications")
		return
	}
	utils.Paginated(c, result.Documents, pg.Page, pg.PerPage, result.Total)
}

// MarkRead marks a notification as read with ownership check
// @Summary      Mark notification as read
// @Description  Marks a single notification as read with ownership verification
// @Tags         Notifications
// @Accept       json
// @Produce      json
// @Param        id  path      string  true  "Notification ID"
// @Success      200  {object}  map[string]interface{}
// @Failure      403  {object}  map[string]interface{}
// @Failure      404  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/notifications/{id}/read [put]
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
// @Summary      Mark all notifications as read
// @Description  Marks all of the authenticated user's unread notifications as read
// @Tags         Notifications
// @Accept       json
// @Produce      json
// @Success      200  {object}  map[string]interface{}
// @Failure      500  {object}  map[string]interface{}
// @Security     BearerAuth
// @Router       /api/v1/notifications/read-all [put]
func (h *NotificationHandler) MarkAllRead(c *gin.Context) {
	userID := middleware.GetUserID(c)
	result, err := h.appwrite.ListNotifications(userID, 500, 0)
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
