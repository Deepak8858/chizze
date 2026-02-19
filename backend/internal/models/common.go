package models

// Pagination holds page/limit query params
type Pagination struct {
	Page    int `json:"page"`
	PerPage int `json:"per_page"`
}

// DefaultPagination returns default pagination (page 1, 20 per page)
func DefaultPagination() Pagination {
	return Pagination{Page: 1, PerPage: 20}
}

// Offset calculates the offset for DB queries
func (p Pagination) Offset() int {
	return (p.Page - 1) * p.PerPage
}

// CollectionIDs are Appwrite collection identifiers
const (
	CollectionUsers            = "users"
	CollectionAddresses        = "addresses"
	CollectionRestaurants      = "restaurants"
	CollectionMenuCategories   = "menu_categories"
	CollectionMenuItems        = "menu_items"
	CollectionOrders           = "orders"
	CollectionDeliveryPartners = "delivery_partners"
	CollectionDeliveryLocations = "delivery_locations"
	CollectionReviews          = "reviews"
	CollectionCoupons          = "coupons"
	CollectionPayouts          = "payouts"
	CollectionNotifications    = "notifications"
)

// AppError is a structured error for API responses
type AppError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *AppError) Error() string {
	return e.Message
}

// NewAppError creates a new AppError
func NewAppError(code int, message string) *AppError {
	return &AppError{Code: code, Message: message}
}
