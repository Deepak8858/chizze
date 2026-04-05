package handlers_test

import (
	"testing"
	"time"

	"github.com/chizze/backend/internal/handlers"
	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/testutil"
)

func registerReviewRoutes(te *testutil.TestEnv) {
	te.T.Helper()

	reviewHandler := handlers.NewReviewHandler(te.AWService)
	restaurantHandler := handlers.NewRestaurantHandler(te.AWService, te.GeoService, te.CacheService)
	adminHandler := handlers.NewAdminHandler(te.AWService, te.RedisClient, te.Hub)

	v1 := te.Router.Group("/api/v1")

	restaurants := v1.Group("/restaurants")
	{
		restaurants.GET("/:id/reviews", restaurantHandler.GetReviews)
	}

	authenticated := v1.Group("")
	authenticated.Use(middleware.Auth(te.Config, te.RedisClient))
	{
		orders := authenticated.Group("/orders")
		orders.POST("/:id/review", reviewHandler.CreateReview)
	}

	admin := v1.Group("/admin")
	admin.Use(middleware.Auth(te.Config, te.RedisClient))
	admin.Use(middleware.RequireRole("admin", "super_admin"))
	{
		admin.GET("/reviews", adminHandler.ListReviews)
		admin.PUT("/reviews/:id", adminHandler.UpdateReview)
	}
}

func reviewListFromResponse(t *testing.T, te *testutil.TestEnv, recCode int, bodyMap map[string]interface{}) []map[string]interface{} {
	t.Helper()

	if recCode != 200 {
		t.Fatalf("expected 200, got %d: %#v", recCode, bodyMap)
	}

	rawData, ok := bodyMap["data"].([]interface{})
	if !ok {
		t.Fatalf("expected data array, got %#v", bodyMap["data"])
	}

	out := make([]map[string]interface{}, 0, len(rawData))
	for _, item := range rawData {
		review, ok := item.(map[string]interface{})
		if !ok {
			t.Fatalf("expected review object, got %#v", item)
		}
		out = append(out, review)
	}

	return out
}

func containsReviewID(items []map[string]interface{}, wantID string) bool {
	for _, item := range items {
		id, _ := item["$id"].(string)
		if id == wantID {
			return true
		}
	}
	return false
}

func TestCreateReview_GatesAndLegacyCompletedStatus(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)

	te.SeedOrder("order_preparing", map[string]interface{}{
		"customer_id":  "cust_1",
		"restaurant_id": "rest_1",
		"status":       "preparing",
	})

	body := map[string]interface{}{
		"food_rating":     5,
		"delivery_rating": 4,
		"review_text":     "Great order",
		"tags":            []string{"fast", "tasty"},
	}

	rec := te.AuthRequest("POST", "/api/v1/orders/order_preparing/review", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for non-delivered order, got %d: %s", rec.Code, rec.Body.String())
	}

	te.SeedOrder("order_completed", map[string]interface{}{
		"customer_id":  "cust_1",
		"restaurant_id": "rest_1",
		"status":       "completed",
	})

	rec = te.AuthRequest("POST", "/api/v1/orders/order_completed/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201 for legacy completed status, got %d: %s", rec.Code, rec.Body.String())
	}

	if te.FakeAW.DocumentCount("reviews") != 1 {
		t.Fatalf("expected one review document, got %d", te.FakeAW.DocumentCount("reviews"))
	}

	rec = te.AuthRequest("POST", "/api/v1/orders/order_completed/review", body, "cust_1", "customer")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for duplicate review, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRestaurantGetReviews_ReturnsOnlyVisible(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	now := time.Now().UTC()
	te.FakeAW.SeedDocument("reviews", "rev_visible_new", map[string]interface{}{
		"restaurant_id": "rest_1",
		"is_visible":    true,
		"created_at":    now.Add(-1 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_hidden", map[string]interface{}{
		"restaurant_id": "rest_1",
		"is_visible":    false,
		"created_at":    now.Add(-2 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_visible_old", map[string]interface{}{
		"restaurant_id": "rest_1",
		"is_visible":    true,
		"created_at":    now.Add(-3 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_other_rest", map[string]interface{}{
		"restaurant_id": "rest_2",
		"is_visible":    true,
		"created_at":    now.Format(time.RFC3339),
	})

	rec := te.Request("GET", "/api/v1/restaurants/rest_1/reviews?per_page=20&page=1", nil)
	resp := te.ParseResponse(rec)
	items := reviewListFromResponse(t, te, rec.Code, resp)

	if len(items) != 2 {
		t.Fatalf("expected 2 visible reviews, got %d", len(items))
	}
	if !containsReviewID(items, "rev_visible_new") || !containsReviewID(items, "rev_visible_old") {
		t.Fatalf("expected visible reviews in payload, got %#v", items)
	}
	if containsReviewID(items, "rev_hidden") || containsReviewID(items, "rev_other_rest") {
		t.Fatalf("did not expect hidden/other restaurant reviews in payload: %#v", items)
	}

	firstID, _ := items[0]["$id"].(string)
	if firstID != "rev_visible_new" {
		t.Fatalf("expected newest visible review first, got %q", firstID)
	}
}

func TestAdminListReviews_StatusFilters(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	now := time.Now().UTC()
	te.FakeAW.SeedDocument("reviews", "rev_approved", map[string]interface{}{
		"restaurant_id": "rest_1",
		"is_visible":    true,
		"created_at":    now.Add(-1 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_rejected", map[string]interface{}{
		"restaurant_id": "rest_1",
		"is_visible":    false,
		"created_at":    now.Add(-2 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_pending", map[string]interface{}{
		"restaurant_id": "rest_1",
		"status":        "pending",
		"is_visible":    true,
		"created_at":    now.Add(-3 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_flagged", map[string]interface{}{
		"restaurant_id": "rest_1",
		"status":        "flagged",
		"is_visible":    false,
		"created_at":    now.Add(-4 * time.Minute).Format(time.RFC3339),
	})

	recApproved := te.AuthRequest("GET", "/api/v1/admin/reviews?status=approved&per_page=200", nil, "admin_1", "admin")
	approved := reviewListFromResponse(t, te, recApproved.Code, te.ParseResponse(recApproved))
	if !containsReviewID(approved, "rev_approved") {
		t.Fatalf("expected approved filter to include rev_approved, got %#v", approved)
	}
	if containsReviewID(approved, "rev_rejected") {
		t.Fatalf("did not expect approved filter to include rev_rejected, got %#v", approved)
	}

	recRejected := te.AuthRequest("GET", "/api/v1/admin/reviews?status=rejected&per_page=200", nil, "admin_1", "admin")
	rejected := reviewListFromResponse(t, te, recRejected.Code, te.ParseResponse(recRejected))
	if !containsReviewID(rejected, "rev_rejected") {
		t.Fatalf("expected rejected filter to include rev_rejected, got %#v", rejected)
	}

	recPending := te.AuthRequest("GET", "/api/v1/admin/reviews?status=pending&per_page=200", nil, "admin_1", "admin")
	pending := reviewListFromResponse(t, te, recPending.Code, te.ParseResponse(recPending))
	if !containsReviewID(pending, "rev_pending") {
		t.Fatalf("expected pending filter to include rev_pending, got %#v", pending)
	}
	if containsReviewID(pending, "rev_approved") {
		t.Fatalf("did not expect pending filter to include rev_approved, got %#v", pending)
	}

	recFlagged := te.AuthRequest("GET", "/api/v1/admin/reviews?status=flagged&per_page=200", nil, "admin_1", "admin")
	flagged := reviewListFromResponse(t, te, recFlagged.Code, te.ParseResponse(recFlagged))
	if !containsReviewID(flagged, "rev_flagged") {
		t.Fatalf("expected flagged filter to include rev_flagged, got %#v", flagged)
	}

	recInvalid := te.AuthRequest("GET", "/api/v1/admin/reviews?status=unknown&per_page=200", nil, "admin_1", "admin")
	if recInvalid.Code != 400 {
		t.Fatalf("expected 400 for invalid status filter, got %d: %s", recInvalid.Code, recInvalid.Body.String())
	}
}

func TestReviewVisibilityFlow_CustomerToAdminModeration(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":       "cust_1",
		"restaurant_id":     "rest_1",
		"delivery_partner_id": "dp_1",
		"status":            "delivered",
	})

	createBody := map[string]interface{}{
		"food_rating":     5,
		"delivery_rating": 5,
		"review_text":     "Excellent service",
		"tags":            []string{"fast"},
	}

	createRec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", createBody, "cust_1", "customer")
	if createRec.Code != 201 {
		t.Fatalf("expected 201 creating review, got %d: %s", createRec.Code, createRec.Body.String())
	}
	createResp := te.ParseResponse(createRec)
	createdData, ok := createResp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected review object in create response, got %#v", createResp["data"])
	}
	reviewID, _ := createdData["$id"].(string)
	if reviewID == "" {
		t.Fatalf("expected created review id, got %#v", createdData)
	}

	publicRecBefore := te.Request("GET", "/api/v1/restaurants/rest_1/reviews?per_page=50", nil)
	publicBefore := reviewListFromResponse(t, te, publicRecBefore.Code, te.ParseResponse(publicRecBefore))
	if !containsReviewID(publicBefore, reviewID) {
		t.Fatalf("expected public list to include new review before moderation, got %#v", publicBefore)
	}

	adminApprovedRec := te.AuthRequest("GET", "/api/v1/admin/reviews?status=approved&per_page=50", nil, "admin_1", "admin")
	adminApproved := reviewListFromResponse(t, te, adminApprovedRec.Code, te.ParseResponse(adminApprovedRec))
	if !containsReviewID(adminApproved, reviewID) {
		t.Fatalf("expected admin approved list to include new review, got %#v", adminApproved)
	}

	moderateRec := te.AuthRequest("PUT", "/api/v1/admin/reviews/"+reviewID, map[string]interface{}{"is_visible": false}, "admin_1", "admin")
	if moderateRec.Code != 200 {
		t.Fatalf("expected 200 moderating review, got %d: %s", moderateRec.Code, moderateRec.Body.String())
	}

	adminRejectedRec := te.AuthRequest("GET", "/api/v1/admin/reviews?status=rejected&per_page=50", nil, "admin_1", "admin")
	adminRejected := reviewListFromResponse(t, te, adminRejectedRec.Code, te.ParseResponse(adminRejectedRec))
	if !containsReviewID(adminRejected, reviewID) {
		t.Fatalf("expected admin rejected list to include hidden review, got %#v", adminRejected)
	}

	publicRecAfter := te.Request("GET", "/api/v1/restaurants/rest_1/reviews?per_page=50", nil)
	publicAfter := reviewListFromResponse(t, te, publicRecAfter.Code, te.ParseResponse(publicRecAfter))
	if containsReviewID(publicAfter, reviewID) {
		t.Fatalf("did not expect public list to include hidden review, got %#v", publicAfter)
	}
}
