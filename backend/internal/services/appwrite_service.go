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

// ─── Users ───

func (s *AppwriteService) GetUser(userID string) (map[string]interface{}, error) {
	return s.client.GetDocument(models.CollectionUsers, userID)
}

func (s *AppwriteService) UpdateUser(userID string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionUsers, userID, data)
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

func (s *AppwriteService) UpdateRestaurant(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionRestaurants, id, data)
}

// ─── Menu ───

func (s *AppwriteService) ListMenuItems(restaurantID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionMenuItems, []string{
		appwrite.QueryEqual("restaurant_id", restaurantID),
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

func (s *AppwriteService) ListNotifications(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionNotifications, []string{
		appwrite.QueryEqual("user_id", userID),
		appwrite.QueryOrderDesc("created_at"),
	})
}

func (s *AppwriteService) UpdateNotification(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionNotifications, id, data)
}

// ─── Delivery Partners ───

func (s *AppwriteService) GetDeliveryPartner(userID string) (*appwrite.DocumentList, error) {
	return s.client.ListDocuments(models.CollectionDeliveryRequests, []string{
		appwrite.QueryEqual("user_id", userID),
	})
}

func (s *AppwriteService) UpdateDeliveryPartner(id string, data map[string]interface{}) (map[string]interface{}, error) {
	return s.client.UpdateDocument(models.CollectionDeliveryRequests, id, data)
}
