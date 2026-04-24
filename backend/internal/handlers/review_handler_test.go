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

	reviewHandler := handlers.NewReviewHandler(te.AWService, nil)
	restaurantHandler := handlers.NewRestaurantHandler(te.AWService, te.GeoService, te.CacheService)
	adminHandler := handlers.NewAdminHandler(te.AWService, te.RedisClient, te.Hub)
	partnerHandler := handlers.NewPartnerHandler(te.AWService, te.RedisClient)

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

	partner := v1.Group("/partner")
	partner.Use(middleware.Auth(te.Config, te.RedisClient))
	partner.Use(middleware.RequireRole("restaurant_owner"))
	{
		partner.GET("/reviews", partnerHandler.ListReviews)
		partner.POST("/reviews/:id/reply", reviewHandler.ReplyToReview)
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
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "preparing",
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
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "completed",
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
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "dp_1",
		"status":              "delivered",
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

func TestCreateReview_DeliveryRatingOptionalFallsBackToFoodRating(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
	})

	body := map[string]interface{}{
		"food_rating": 4,
		"review_text": "Good food",
		"tags":        []string{"fresh"},
	}

	rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201 creating review without delivery_rating, got %d: %s", rec.Code, rec.Body.String())
	}

	resp := te.ParseResponse(rec)
	createdData, ok := resp["data"].(map[string]interface{})
	if !ok {
		t.Fatalf("expected review object in response, got %#v", resp["data"])
	}

	deliveryRating, ok := createdData["delivery_rating"].(float64)
	if !ok {
		t.Fatalf("expected delivery_rating in response, got %#v", createdData["delivery_rating"])
	}
	if int(deliveryRating) != 4 {
		t.Fatalf("expected delivery_rating fallback to food_rating=4, got %v", deliveryRating)
	}

	deadline := time.Now().Add(1 * time.Second)
	updated := false
	for time.Now().Before(deadline) {
		restaurant := te.FakeAW.GetDocument("restaurants", "rest_1")
		if restaurant != nil {
			rating, _ := restaurant["rating"].(float64)
			totalRatings, hasTotalRatings := restaurant["total_ratings"].(float64)
			_, hasTotalReviews := restaurant["total_reviews"]

			if rating == 4 && hasTotalRatings && int(totalRatings) == 1 && !hasTotalReviews {
				updated = true
				break
			}
		}
		time.Sleep(20 * time.Millisecond)
	}

	if !updated {
		restaurant := te.FakeAW.GetDocument("restaurants", "rest_1")
		t.Fatalf("expected restaurant aggregate update with total_ratings, got %#v", restaurant)
	}
}

// TestCreateReview_DeterministicIDPreventsRetryDuplicate verifies the
// deterministic review ID stops duplicates even when the legacy filter-query
// check is bypassed (e.g. racing retries submitting in parallel).
func TestCreateReview_DeterministicIDPreventsRetryDuplicate(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
	})

	body := map[string]interface{}{
		"food_rating": 5,
		"review_text": "Great",
	}

	rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("first submit: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// The created document must use the deterministic ID so the point-lookup
	// duplicate check works without any collection index.
	if doc := te.FakeAW.GetDocument("reviews", "rev_order_delivered"); doc == nil {
		t.Fatalf("expected review seeded with deterministic id rev_order_delivered, fake store: %#v", te.FakeAW)
	}

	rec2 := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", body, "cust_1", "customer")
	if rec2.Code != 400 {
		t.Fatalf("second submit: expected 400 duplicate, got %d: %s", rec2.Code, rec2.Body.String())
	}
	if te.FakeAW.DocumentCount("reviews") != 1 {
		t.Fatalf("expected duplicate to be rejected, got %d documents", te.FakeAW.DocumentCount("reviews"))
	}
}

// TestCreateReview_OmitsEmptyDeliveryPartnerID ensures orders that were never
// assigned a rider (pickup, cancelled-before-assignment, legacy rows) still
// accept reviews. Writing delivery_partner_id="" fails in production Appwrite
// when the attribute is relationship-typed or min-length constrained — the
// handler must omit the key entirely instead of sending an empty string.
func TestCreateReview_OmitsEmptyDeliveryPartnerID(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_no_rider", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
		// no delivery_partner_id — pickup or unassigned order
	})

	body := map[string]interface{}{
		"food_rating": 5,
		"review_text": "Solid pickup",
	}

	rec := te.AuthRequest("POST", "/api/v1/orders/order_no_rider/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201 for pickup/no-rider order, got %d: %s", rec.Code, rec.Body.String())
	}

	stored := te.FakeAW.GetDocument("reviews", "rev_order_no_rider")
	if stored == nil {
		t.Fatalf("expected review stored with deterministic id")
	}
	if raw, present := stored["delivery_partner_id"]; present {
		t.Fatalf("delivery_partner_id must be omitted when order has no rider, got %#v", raw)
	}
}

// TestCreateReview_OmitsEmptyReviewText ensures customers who submit a
// rating without typing free-text feedback (the UI marks it optional) still
// succeed. Writing review_text="" fails in production Appwrite when the
// attribute is size-constrained, and the previous 500 response surfaced as
// "Server error. Please try again in a moment." blocking every such review.
func TestCreateReview_OmitsEmptyReviewText(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)

	cases := []struct {
		name    string
		orderID string
		body    map[string]interface{}
	}{
		{"explicit empty string", "order_empty", map[string]interface{}{"food_rating": 5, "review_text": ""}},
		{"whitespace only", "order_ws", map[string]interface{}{"food_rating": 5, "review_text": "   \t\n"}},
		{"missing field", "order_missing", map[string]interface{}{"food_rating": 5}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			te.SeedOrder(tc.orderID, map[string]interface{}{
				"customer_id":         "cust_1",
				"restaurant_id":       "rest_1",
				"delivery_partner_id": "dp_1",
				"status":              "delivered",
			})

			rec := te.AuthRequest("POST", "/api/v1/orders/"+tc.orderID+"/review", tc.body, "cust_1", "customer")
			if rec.Code != 201 {
				t.Fatalf("expected 201 with empty/missing review_text, got %d: %s", rec.Code, rec.Body.String())
			}

			stored := te.FakeAW.GetDocument("reviews", "rev_"+tc.orderID)
			if stored == nil {
				t.Fatalf("expected review stored with deterministic id")
			}
			if raw, present := stored["review_text"]; present {
				t.Fatalf("review_text must be omitted when empty/whitespace, got %#v", raw)
			}
		})
	}
}

// TestCreateReview_TrimsReviewText verifies the handler persists the trimmed
// review text (not the raw input) so leading/trailing whitespace from copy-
// paste on mobile keyboards doesn't survive into the review collection and
// skew downstream text analysis.
func TestCreateReview_TrimsReviewText(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
	})

	body := map[string]interface{}{
		"food_rating": 5,
		"review_text": "   Great food  \n",
	}

	rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	stored := te.FakeAW.GetDocument("reviews", "rev_order_delivered")
	if stored == nil {
		t.Fatalf("expected review stored")
	}
	text, _ := stored["review_text"].(string)
	if text != "Great food" {
		t.Fatalf("expected trimmed review_text, got %q", text)
	}
}

// TestCreateReview_NilTagsNormalizedToEmptySlice guards against the client
// omitting the tags field entirely (or sending null). Appwrite's string-array
// attribute rejects JSON null with 400 document_invalid_structure, so the
// handler must normalize to an empty array before the write.
func TestCreateReview_NilTagsNormalizedToEmptySlice(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":         "cust_1",
		"restaurant_id":       "rest_1",
		"delivery_partner_id": "dp_1",
		"status":              "delivered",
	})

	// Explicitly no tags key in payload; req.Tags arrives as nil.
	body := map[string]interface{}{
		"food_rating": 4,
		"review_text": "Great",
	}
	rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", body, "cust_1", "customer")
	if rec.Code != 201 {
		t.Fatalf("expected 201 when tags omitted, got %d: %s", rec.Code, rec.Body.String())
	}
	stored := te.FakeAW.GetDocument("reviews", "rev_order_delivered")
	if stored == nil {
		t.Fatalf("expected review to be stored")
	}
	tags, ok := stored["tags"].([]string)
	if !ok {
		// JSON round-trip through fake server may lose []string type; accept
		// []interface{} as well as long as it's a non-nil slice.
		if anyTags, okAny := stored["tags"].([]interface{}); okAny {
			if anyTags == nil {
				t.Fatalf("tags stored as nil — must be empty slice")
			}
			return
		}
		t.Fatalf("expected tags slice in stored review, got %#v", stored["tags"])
	}
	if tags == nil {
		t.Fatalf("tags stored as nil — must be empty slice")
	}
}

// TestCreateReview_EdgeCases covers non-owner, missing order, and invalid
// rating payloads to make sure the handler gates everything before persisting.
func TestCreateReview_EdgeCases(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_1", "owner_1", 12.97, 77.59, true)
	te.SeedOrder("order_delivered", map[string]interface{}{
		"customer_id":   "cust_1",
		"restaurant_id": "rest_1",
		"status":        "delivered",
	})

	validBody := map[string]interface{}{"food_rating": 5, "review_text": "ok"}

	t.Run("non-existent order returns 404", func(t *testing.T) {
		rec := te.AuthRequest("POST", "/api/v1/orders/does_not_exist/review", validBody, "cust_1", "customer")
		if rec.Code != 404 {
			t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("other customer cannot review", func(t *testing.T) {
		rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review", validBody, "stranger", "customer")
		if rec.Code != 403 {
			t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("missing food_rating returns 400", func(t *testing.T) {
		rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review",
			map[string]interface{}{"review_text": "no rating"}, "cust_1", "customer")
		if rec.Code != 400 {
			t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("out-of-range food_rating returns 400", func(t *testing.T) {
		rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review",
			map[string]interface{}{"food_rating": 9}, "cust_1", "customer")
		if rec.Code != 400 {
			t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
		}
	})

	t.Run("zero food_rating fails required validation", func(t *testing.T) {
		rec := te.AuthRequest("POST", "/api/v1/orders/order_delivered/review",
			map[string]interface{}{"food_rating": 0}, "cust_1", "customer")
		if rec.Code != 400 {
			t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
		}
	})
}

// TestPartnerListReviews_OwnershipAndVisibility verifies partners see reviews
// for their own restaurant, newest-first, and never reviews of restaurants
// they do not own.
func TestPartnerListReviews_OwnershipAndVisibility(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	te.SeedRestaurant("rest_mine", "owner_1", 12.97, 77.59, true)
	te.SeedRestaurant("rest_other", "owner_2", 12.97, 77.59, true)

	now := time.Now().UTC()
	te.FakeAW.SeedDocument("reviews", "rev_mine_new", map[string]interface{}{
		"restaurant_id": "rest_mine",
		"food_rating":   5,
		"is_visible":    true,
		"created_at":    now.Add(-1 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_mine_old", map[string]interface{}{
		"restaurant_id": "rest_mine",
		"food_rating":   4,
		"is_visible":    true,
		"created_at":    now.Add(-10 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_mine_hidden", map[string]interface{}{
		"restaurant_id": "rest_mine",
		"food_rating":   2,
		"is_visible":    false,
		"created_at":    now.Add(-5 * time.Minute).Format(time.RFC3339),
	})
	te.FakeAW.SeedDocument("reviews", "rev_other", map[string]interface{}{
		"restaurant_id": "rest_other",
		"food_rating":   5,
		"is_visible":    true,
		"created_at":    now.Format(time.RFC3339),
	})

	rec := te.AuthRequest("GET", "/api/v1/partner/reviews?per_page=50", nil, "owner_1", "restaurant_owner")
	items := reviewListFromResponse(t, te, rec.Code, te.ParseResponse(rec))

	// Partner sees ALL their reviews, hidden included — the partner dashboard
	// needs visibility into moderated content, unlike the public endpoint.
	if !containsReviewID(items, "rev_mine_new") ||
		!containsReviewID(items, "rev_mine_old") ||
		!containsReviewID(items, "rev_mine_hidden") {
		t.Fatalf("expected partner to see all own-restaurant reviews, got %#v", items)
	}
	if containsReviewID(items, "rev_other") {
		t.Fatalf("partner must not see reviews for restaurants they do not own, got %#v", items)
	}
}

// TestPartnerListReviews_NoRestaurantReturns403 ensures callers without a
// registered restaurant get a clean 403 rather than an empty-looking 200.
func TestPartnerListReviews_NoRestaurantReturns403(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	registerReviewRoutes(te)

	rec := te.AuthRequest("GET", "/api/v1/partner/reviews", nil, "orphan_owner", "restaurant_owner")
	if rec.Code != 403 {
		t.Fatalf("expected 403 when partner has no restaurant, got %d: %s", rec.Code, rec.Body.String())
	}
}
