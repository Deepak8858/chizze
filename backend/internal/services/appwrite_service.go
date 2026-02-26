package services

import (
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/pkg/appwrite"
)

// AppwriteService wraps Appwrite client with domain-specific methods
type AppwriteService struct {
	client *appwrite.Client
}

// NewAppwriteService creates an Appwrite service
func NewAppwriteService(client *appwrite.Client) *AppwriteService {
	return &AppwriteService{client: client}
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
		appwrite.QueryOrderDesc("created_at"),
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

func (s *AppwriteService) CreateNotification(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.CreateDocument(models.CollectionNotifications, id, data)
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
