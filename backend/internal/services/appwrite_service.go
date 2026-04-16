package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/pkg/appwrite"
	"github.com/chizze/backend/pkg/fcm"
)

// AppwriteService wraps Appwrite client with domain-specific methods
type AppwriteService struct {
	client *appwrite.Client
	fcm    *fcm.Client
}

// NewAppwriteService creates an Appwrite service
func NewAppwriteService(client *appwrite.Client) *AppwriteService {
	return &AppwriteService{client: client}
}

// SetFCMClient wires the FCM client so CreateNotification can also push to
// the user's device. Called once at startup from main after the FCM client
// is constructed. Safe to pass nil — pushes become a no-op.
func (s *AppwriteService) SetFCMClient(client *fcm.Client) {
	s.fcm = client
}

// sendPushToUser fetches the user's fcm_token and sends a push. Best-effort;
// logs failures so a bad token doesn't block the caller.
func (s *AppwriteService) sendPushToUser(userID, title, body, notifType string, data map[string]interface{}) {
	if s.fcm == nil || userID == "" {
		return
	}
	user, err := s.GetUser(userID)
	if err != nil || user == nil {
		return
	}
	token, _ := user["fcm_token"].(string)
	if token == "" {
		return
	}
	pushData := map[string]string{
		"type":               notifType,
		"click_action":       "FLUTTER_NOTIFICATION_CLICK",
		"android_channel_id": "chizze_main",
	}
	for k, v := range data {
		if v == nil {
			continue
		}
		switch val := v.(type) {
		case string:
			pushData[k] = val
		case bool, int, int32, int64, float32, float64:
			pushData[k] = fmt.Sprint(val)
		default:
			if b, err := json.Marshal(val); err == nil {
				pushData[k] = string(b)
			}
		}
	}
	if err := s.fcm.SendPush(context.Background(), token, title, body, pushData); err != nil {
		log.Printf("[AppwriteService] FCM push to %s failed: %v", userID, err)
	}
}

// Client exposes the underlying Appwrite client (for JWT verification, etc.)
func (s *AppwriteService) Client() *appwrite.Client {
	return s.client
}

// ─── Payments ───

func (s *AppwriteService) CreatePayment(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionPayments, id, data)
}

func (s *AppwriteService) UpdatePayment(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionPayments, id, data)
}

func (s *AppwriteService) GetPaymentByRazorpayOrder(razorpayOrderID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionPayments, []string{
		appwrite.QueryEqual("razorpay_order_id", razorpayOrderID),
	})
}

// ─── Users ───

func (s *AppwriteService) GetUser(userID string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionUsers, userID)
}

func (s *AppwriteService) ListUsers(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionUsers, queries)
}

// ListUsersByIDs batch-fetches users by their document IDs (avoids N+1).
// Returns an empty list when ids is empty.
func (s *AppwriteService) ListUsersByIDs(ids []string) (*appwrite.DocumentList, error) {
	if len(ids) == 0 {
		return &appwrite.DocumentList{Total: 0, Documents: nil}, nil
	}
	ifaces := make([]interface{}, len(ids))
	for i, v := range ids {
		ifaces[i] = v
	}
	return s.client.ListDocuments(models.CollectionUsers, []string{
		appwrite.QueryEqual("$id", ifaces...),
		appwrite.QueryLimit(len(ids)),
	})
}

func (s *AppwriteService) UpdateUser(userID string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionUsers, userID, data)
}

func (s *AppwriteService) DeleteUser(userID string) error {
	return s.client.DeleteDocument(models.CollectionUsers, userID)
}

// ─── Addresses ───

func (s *AppwriteService) ListAddresses(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionAddresses, []string{
		appwrite.QueryEqual("user_id", userID),
	})
}

func (s *AppwriteService) CreateAddress(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionAddresses, id, data)
}

func (s *AppwriteService) UpdateAddress(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionAddresses, id, data)
}

func (s *AppwriteService) DeleteAddress(id string) error {
	return s.client.DeleteDocument(models.CollectionAddresses, id)
}

// ─── Restaurants ───

func (s *AppwriteService) ListRestaurants(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionRestaurants, queries)
}

func (s *AppwriteService) GetRestaurant(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionRestaurants, id)
}

func (s *AppwriteService) CreateRestaurant(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionRestaurants, id, data)
}

func (s *AppwriteService) UpdateRestaurant(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionRestaurants, id, data)
}

// ─── Menu ───

func (s *AppwriteService) ListMenuItems(restaurantID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionMenuItems, []string{
		appwrite.QueryEqual("restaurant_id", restaurantID),
		appwrite.QueryLimit(500),
	})
}

func (s *AppwriteService) CreateMenuItem(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionMenuItems, id, data)
}

func (s *AppwriteService) UpdateMenuItem(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionMenuItems, id, data)
}

func (s *AppwriteService) DeleteMenuItem(id string) error {
	return s.client.DeleteDocument(models.CollectionMenuItems, id)
}

// ─── Orders ───

func (s *AppwriteService) CreateOrder(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionOrders, id, data)
}

func (s *AppwriteService) GetOrder(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionOrders, id)
}

func (s *AppwriteService) UpdateOrder(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionOrders, id, data)
}

func (s *AppwriteService) ListOrders(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionOrders, queries)
}

func (s *AppwriteService) DeleteOrder(id string) error {
	return s.client.DeleteDocument(models.CollectionOrders, id)
}

// ─── Reviews ───

func (s *AppwriteService) CreateReview(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionReviews, id, data)
}

func (s *AppwriteService) ListReviews(restaurantID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionReviews, []string{
		appwrite.QueryEqual("restaurant_id", restaurantID),
	})
}

func (s *AppwriteService) ListReviewsByQuery(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionReviews, queries)
}

func (s *AppwriteService) GetReview(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionReviews, id)
}

func (s *AppwriteService) UpdateReview(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionReviews, id, data)
}

// ─── Coupons ───

func (s *AppwriteService) ListCoupons(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionCoupons, queries)
}

func (s *AppwriteService) GetCoupon(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionCoupons, id)
}

// ─── Notifications ───

func (s *AppwriteService) ListNotifications(userID string, limit, offset int) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionNotifications, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(limit),
		appwrite.QueryOffset(offset),
	})
}

func (s *AppwriteService) GetNotification(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionNotifications, id)
}

func (s *AppwriteService) UpdateNotification(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionNotifications, id, data)
}

// ─── Delivery Partners ───

func (s *AppwriteService) GetDeliveryPartner(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionDeliveryPartners, []string{
		appwrite.QueryEqual("user_id", userID),
	})
}

func (s *AppwriteService) UpdateDeliveryPartner(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionDeliveryPartners, id, data)
}

func (s *AppwriteService) ListDeliveryPartners(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionDeliveryPartners, queries)
}

// ListDeliveryPartnersByUserIDs batch-fetches delivery_partner docs by their user_id
// field (avoids N+1 when enriching a list of orders with partner details).
func (s *AppwriteService) ListDeliveryPartnersByUserIDs(userIDs []string) (*appwrite.DocumentList, error) {
	if len(userIDs) == 0 {
		return &appwrite.DocumentList{Total: 0, Documents: nil}, nil
	}
	ifaces := make([]interface{}, len(userIDs))
	for i, v := range userIDs {
		ifaces[i] = v
	}
	return s.client.ListDocuments(models.CollectionDeliveryPartners, []string{
		appwrite.QueryEqual("user_id", ifaces...),
		appwrite.QueryLimit(len(userIDs)),
	})
}

func (s *AppwriteService) CreateDeliveryPartner(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionDeliveryPartners, id, data)
}

// ─── Delivery Requests (order assignments) ───

func (s *AppwriteService) CreateDeliveryRequest(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionDeliveryRequests, id, data)
}

// ─── Users (create) ───

func (s *AppwriteService) CreateUser(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionUsers, id, data)
}

// ─── Notifications (create) ───

// CreateNotification stores a notification and fires an FCM push asynchronously
// so the device's Android system tray shows it even when the app is backgrounded
// or the WS channel is down. FCM is best-effort; a failure never fails the create.
//
// The push extracts its payload from `data`:
//   - user_id → recipient (required for push)
//   - title, body, type → FCM notification header
//   - any nested `data` map is forwarded as FCM data (used for deep_link routing)
func (s *AppwriteService) CreateNotification(id string, data map[string]interface{}) (map[string]interface{}, error) {
	doc, err := s.client.CreateDocument(models.CollectionNotifications, id, data)
	if err != nil {
		return doc, err
	}

	userID, _ := data["user_id"].(string)
	title, _ := data["title"].(string)
	body, _ := data["body"].(string)
	notifType, _ := data["type"].(string)

	var pushData map[string]interface{}
	switch raw := data["data"].(type) {
	case map[string]interface{}:
		pushData = raw
	case string:
		if raw != "" {
			var parsed map[string]interface{}
			if jerr := json.Unmarshal([]byte(raw), &parsed); jerr == nil {
				pushData = parsed
			}
		}
	}

	if userID != "" && s.fcm != nil {
		go s.sendPushToUser(userID, title, body, notifType, pushData)
	}
	return doc, nil
}

func (s *AppwriteService) UploadFile(bucketID, filename, contentType string, data []byte) (map[string]interface{}, error) {
	return s.client.UploadFile(bucketID, filename, contentType, data)
}

// ─── Menu Categories ───

func (s *AppwriteService) ListMenuCategories(restaurantID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionMenuCategories, []string{
		appwrite.QueryEqual("restaurant_id", restaurantID),
		appwrite.QueryOrderAsc("sort_order"),
		appwrite.QueryLimit(100),
	})
}

func (s *AppwriteService) GetMenuCategory(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionMenuCategories, id)
}

func (s *AppwriteService) CreateMenuCategory(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionMenuCategories, id, data)
}

func (s *AppwriteService) UpdateMenuCategory(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionMenuCategories, id, data)
}

func (s *AppwriteService) DeleteMenuCategory(id string) error {
	return s.client.DeleteDocument(models.CollectionMenuCategories, id)
}

// ─── Coupons (update) ───

func (s *AppwriteService) UpdateCoupon(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionCoupons, id, data)
}

// ─── Delivery Locations ───

func (s *AppwriteService) CreateDeliveryLocation(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionRiderLocations, id, data)
}

func (s *AppwriteService) UpdateDeliveryLocation(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionRiderLocations, id, data)
}

func (s *AppwriteService) ListDeliveryLocations(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionRiderLocations, queries)
}

// ─── Payouts ───

func (s *AppwriteService) CreatePayout(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionPayouts, id, data)
}

func (s *AppwriteService) GetPayout(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionPayouts, id)
}

func (s *AppwriteService) UpdatePayout(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionPayouts, id, data)
}

func (s *AppwriteService) ListPayouts(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionPayouts, queries)
}

func (s *AppwriteService) DeletePayout(id string) error {
	return s.client.DeleteDocument(models.CollectionPayouts, id)
}

// ─── Addresses (single fetch) ───

func (s *AppwriteService) GetAddress(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionAddresses, id)
}

// ─── Menu Items (single fetch) ───

func (s *AppwriteService) GetMenuItem(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionMenuItems, id)
}

// ListMenuItemsByIDs batch-fetches menu items by their document IDs (avoids N+1).
func (s *AppwriteService) ListMenuItemsByIDs(ids []string) (*appwrite.DocumentList, error) {
	ifaces := make([]interface{}, len(ids))
	for i, v := range ids {
		ifaces[i] = v
	}
	return s.client.ListDocuments(models.CollectionMenuItems, []string{
		appwrite.QueryEqual("$id", ifaces...),
		appwrite.QueryLimit(len(ids)),
	})
}

// ─── Restaurants by owner ───

func (s *AppwriteService) GetRestaurantByOwner(ownerID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionRestaurants, []string{
		appwrite.QueryEqual("owner_id", ownerID),
	})
}

// ─── Favorites ───

func (s *AppwriteService) ListFavorites(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionFavorites, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryOrderDesc("created_at"),
	})
}

func (s *AppwriteService) CreateFavorite(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionFavorites, id, data)
}

func (s *AppwriteService) DeleteFavorite(id string) error {
	return s.client.DeleteDocument(models.CollectionFavorites, id)
}

func (s *AppwriteService) FindFavorite(userID, restaurantID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionFavorites, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryEqual("restaurant_id", restaurantID),
	})
}

// ─── Gold Subscriptions ───

func (s *AppwriteService) CreateGoldSubscription(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionGoldSubscriptions, id, data)
}

func (s *AppwriteService) GetActiveGoldSubscription(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionGoldSubscriptions, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryEqual("status", "active"),
		appwrite.QueryOrderDesc("created_at"),
	})
}

func (s *AppwriteService) UpdateGoldSubscription(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionGoldSubscriptions, id, data)
}

// ─── Referrals ───

func (s *AppwriteService) CreateReferral(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionReferrals, id, data)
}

func (s *AppwriteService) ListReferrals(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionReferrals, []string{
		appwrite.QueryEqual("referrer_user_id", userID),
		appwrite.QueryOrderDesc("created_at"),
	})
}

func (s *AppwriteService) FindReferralByCode(code string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionUsers, []string{
		appwrite.QueryEqual("referral_code", code),
	})
}

// ─── Scheduled Orders ───

func (s *AppwriteService) CreateScheduledOrder(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionScheduledOrders, id, data)
}

func (s *AppwriteService) ListScheduledOrders(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionScheduledOrders, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryOrderDesc("scheduled_for"),
	})
}

func (s *AppwriteService) UpdateScheduledOrder(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionScheduledOrders, id, data)
}

func (s *AppwriteService) DeleteScheduledOrder(id string) error {
	return s.client.DeleteDocument(models.CollectionScheduledOrders, id)
}

// ─── Delivery Issues ───

func (s *AppwriteService) CreateDeliveryIssue(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionDeliveryIssues, id, data)
}

func (s *AppwriteService) ListDeliveryIssues(orderID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionDeliveryIssues, []string{
		appwrite.QueryEqual("order_id", orderID),
		appwrite.QueryOrderDesc("created_at"),
	})
}

// ─── Admin-specific methods ───

func (s *AppwriteService) DeleteRestaurant(id string) error {
	return s.client.DeleteDocument(models.CollectionRestaurants, id)
}

func (s *AppwriteService) CreateCoupon(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionCoupons, id, data)
}

func (s *AppwriteService) DeleteCoupon(id string) error {
	return s.client.DeleteDocument(models.CollectionCoupons, id)
}

func (s *AppwriteService) DeleteReview(id string) error {
	return s.client.DeleteDocument(models.CollectionReviews, id)
}

func (s *AppwriteService) ListAllGoldSubscriptions(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionGoldSubscriptions, queries)
}

func (s *AppwriteService) ListAllReferrals(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionReferrals, queries)
}

func (s *AppwriteService) ListAllNotifications(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionNotifications, queries)
}

func (s *AppwriteService) GetDeliveryIssue(id string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionDeliveryIssues, id)
}

func (s *AppwriteService) UpdateDeliveryIssue(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionDeliveryIssues, id, data)
}

func (s *AppwriteService) ListDeliveryIssuesByQuery(queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionDeliveryIssues, queries)
}

func (s *AppwriteService) DeleteDeliveryPartner(id string) error {
	return s.client.DeleteDocument(models.CollectionDeliveryPartners, id)
}

// ─── New collection CRUD (audit_log, zones, surge_rules, feature_flags, support_issues, banners, settings) ───

func (s *AppwriteService) ListDocuments(collection string, queries []string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(collection, queries)
}

func (s *AppwriteService) GetDocument(collection, id string) (map[string]interface{}, error) {
	return s.client.GetDocument(collection, id)
}

func (s *AppwriteService) CreateDocument(collection, id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(collection, id, data)
}

func (s *AppwriteService) UpdateDocument(collection, id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(collection, id, data)
}

func (s *AppwriteService) DeleteDocument(collection, id string) error {
	return s.client.DeleteDocument(collection, id)
}
