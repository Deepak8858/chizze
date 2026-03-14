package handlers_test

import (
	"strings"
	"testing"

	"github.com/chizze/backend/internal/testutil"
)

// ─── Exchange ───

func TestExchange_NewUser(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Register an Appwrite JWT → account mapping
	te.FakeAW.RegisterJWT("valid-appwrite-jwt", map[string]interface{}{
		"$id":   "user_abc",
		"phone": "+919876543210",
		"name":  "Test User",
		"email": "test@example.com",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt":  "valid-appwrite-jwt",
		"role": "customer",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["token"] == nil || data["token"] == "" {
		t.Fatal("expected a token in response")
	}
	if data["user_id"] != "user_abc" {
		t.Errorf("expected user_id=user_abc, got %v", data["user_id"])
	}
	if data["role"] != "customer" {
		t.Errorf("expected role=customer, got %v", data["role"])
	}
	if data["is_new"] != true {
		t.Errorf("expected is_new=true, got %v", data["is_new"])
	}

	// Verify user doc was created
	userDoc := te.FakeAW.GetDocument("users", "user_abc")
	if userDoc == nil {
		t.Fatal("expected user doc to be created")
	}
	if userDoc["phone"] != "+919876543210" {
		t.Errorf("expected phone=+919876543210, got %v", userDoc["phone"])
	}
}

func TestExchange_ExistingUser(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("valid-jwt", map[string]interface{}{
		"$id":   "user_existing",
		"phone": "+919876543210",
	})
	te.SeedUser("user_existing", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Existing User",
		"role":  "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt": "valid-jwt",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["is_new"] != false {
		t.Errorf("expected is_new=false for existing user, got %v", data["is_new"])
	}
	if data["role"] != "customer" {
		t.Errorf("expected role=customer, got %v", data["role"])
	}
}

func TestExchange_CrossRoleGuard(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("valid-jwt", map[string]interface{}{
		"$id":   "user_cross",
		"phone": "+919876543210",
	})
	te.SeedUser("user_cross", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Cross User",
		"role":  "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt":  "valid-jwt",
		"role": "delivery_partner",
	})

	if rec.Code != 409 {
		t.Fatalf("expected 409 for cross-role, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestExchange_InvalidJWT(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt": "bad-jwt-token",
	})

	if rec.Code != 401 {
		t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestExchange_MissingJWTField(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"role": "customer",
	})

	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing jwt, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestExchange_EmptyBody(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{})

	if rec.Code != 400 {
		t.Fatalf("expected 400 for empty body, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestExchange_RestaurantOwnerNewNeedsOnboard(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("rest-jwt", map[string]interface{}{
		"$id":   "owner_user",
		"phone": "+919876543210",
		"name":  "Owner",
	})
	// Existing user with restaurant_owner role but no restaurant record
	te.SeedUser("owner_user", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Owner",
		"role":  "restaurant_owner",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt":  "rest-jwt",
		"role": "restaurant_owner",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	// Should be marked as new since restaurant doesn't exist
	if data["is_new"] != true {
		t.Errorf("expected is_new=true (no restaurant record), got %v", data["is_new"])
	}
}

func TestExchange_DeliveryPartnerNeedsOnboardWithoutProfile(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("dp-jwt", map[string]interface{}{
		"$id":   "dp_user_99",
		"phone": "+919876543210",
		"name":  "Rider",
	})
	te.SeedUser("dp_user_99", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Rider",
		"role":  "delivery_partner",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt":  "dp-jwt",
		"role": "delivery_partner",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["is_new"] != true {
		t.Errorf("expected is_new=true (no DP profile), got %v", data["is_new"])
	}
}

func TestExchange_DefaultsToCustomerIfNoRole(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("no-role-jwt", map[string]interface{}{
		"$id":   "user_norole",
		"phone": "+919876543210",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt": "no-role-jwt",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["role"] != "customer" {
		t.Errorf("expected default role=customer, got %v", data["role"])
	}
}

func TestExchange_ClearsBlacklistOnLogin(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Blacklist user before exchange
	te.MiniRedis.Set("token_blacklist:user_bl2", "1")

	te.FakeAW.RegisterJWT("bl-jwt", map[string]interface{}{
		"$id":   "user_bl2",
		"phone": "+919876543210",
	})
	te.SeedUser("user_bl2", map[string]interface{}{
		"phone": "+919876543210", "role": "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt": "bl-jwt",
	})
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Blacklist should be cleared
	if te.MiniRedis.Exists("token_blacklist:user_bl2") {
		t.Error("expected blacklist key to be cleared after exchange")
	}
}

// ─── Refresh ───

func TestRefresh_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest("POST", "/api/v1/auth/refresh", nil, "user_refresh", "customer")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["token"] == nil || data["token"] == "" {
		t.Fatal("expected a new token in response")
	}
	if data["user_id"] != "user_refresh" {
		t.Errorf("expected user_id=user_refresh, got %v", data["user_id"])
	}
}

func TestRefresh_Blacklisted(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Blacklist the user
	te.MiniRedis.Set("token_blacklist:user_bl", "1")

	rec := te.AuthRequest("POST", "/api/v1/auth/refresh", nil, "user_bl", "customer")

	if rec.Code != 401 {
		t.Fatalf("expected 401 for blacklisted token, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRefresh_NoAuth(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/refresh", nil)
	if rec.Code != 401 {
		t.Fatalf("expected 401 for unauthenticated refresh, got %d", rec.Code)
	}
}

func TestRefresh_PreservesRole(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest("POST", "/api/v1/auth/refresh", nil, "user_r", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["role"] != "restaurant_owner" {
		t.Errorf("expected role=restaurant_owner, got %v", data["role"])
	}
}

// ─── Logout ───

func TestLogout_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest("DELETE", "/api/v1/auth/logout", nil, "user_logout", "customer")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify blacklist key was set in Redis
	if !te.MiniRedis.Exists("token_blacklist:user_logout") {
		t.Fatal("expected token_blacklist key to exist in Redis")
	}
}

func TestLogout_ThenRefreshFails(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Logout first
	rec := te.AuthRequest("DELETE", "/api/v1/auth/logout", nil, "user_lr", "customer")
	if rec.Code != 200 {
		t.Fatalf("logout: expected 200, got %d", rec.Code)
	}

	// Refresh should now fail
	rec = te.AuthRequest("POST", "/api/v1/auth/refresh", nil, "user_lr", "customer")
	if rec.Code != 401 {
		t.Fatalf("expected 401 after logout, got %d", rec.Code)
	}
}

// ─── CheckPhone ───

func TestCheckPhone_Exists(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("user_phone", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Phone User",
		"role":  "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/check-phone", map[string]interface{}{
		"phone": "+919876543210",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["exists"] != true {
		t.Errorf("expected exists=true, got %v", data["exists"])
	}
	if data["user_name"] != "Phone User" {
		t.Errorf("expected user_name=Phone User, got %v", data["user_name"])
	}
}

func TestCheckPhone_NotFound(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/check-phone", map[string]interface{}{
		"phone": "+919999999999",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	if data["exists"] != false {
		t.Errorf("expected exists=false, got %v", data["exists"])
	}
}

func TestCheckPhone_InvalidPhone(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/check-phone", map[string]interface{}{
		"phone": "1234",
	})
	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid phone, got %d", rec.Code)
	}
}

func TestCheckPhone_MissingPhone(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/check-phone", map[string]interface{}{})
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing phone, got %d", rec.Code)
	}
}

func TestCheckPhone_ReturnsRole(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("user_dp", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Rider",
		"role":  "delivery_partner",
	})

	rec := te.Request("POST", "/api/v1/auth/check-phone", map[string]interface{}{
		"phone": "+919876543210",
	})
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["role"] != "delivery_partner" {
		t.Errorf("expected role=delivery_partner, got %v", data["role"])
	}
}

// ─── SendOTP ───

func TestSendOTP_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{
		"phone": "+919876543210",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSendOTP_InvalidPhone(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{
		"phone": "1234",
	})

	if rec.Code != 400 {
		t.Fatalf("expected 400 for invalid phone, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSendOTP_MissingPhone(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{})
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing phone, got %d", rec.Code)
	}
}

func TestSendOTP_RateLimit(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	body := map[string]interface{}{"phone": "+919876543210"}

	// Send 3 requests (within limit)
	for i := 0; i < 3; i++ {
		rec := te.Request("POST", "/api/v1/auth/send-otp", body)
		if rec.Code != 200 {
			t.Fatalf("request %d: expected 200, got %d", i+1, rec.Code)
		}
	}

	// 4th should be rate limited
	rec := te.Request("POST", "/api/v1/auth/send-otp", body)
	if rec.Code != 429 {
		t.Fatalf("expected 429 for rate limited, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestSendOTP_DifferentPhonesOwnLimits(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Exhaust phone A
	for i := 0; i < 3; i++ {
		te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{"phone": "+919876543210"})
	}

	// Phone B should still work
	rec := te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{"phone": "+919876543211"})
	if rec.Code != 200 {
		t.Fatalf("different phone should not be rate limited, got %d", rec.Code)
	}
}

// ─── VerifyOTP ───

func TestVerifyOTP_Success(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("otp-jwt", map[string]interface{}{
		"$id":   "otp_user",
		"phone": "+919876543210",
	})
	te.SeedUser("otp_user", map[string]interface{}{
		"phone": "+919876543210", "role": "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone":        "+919876543210",
		"otp":          "123456",
		"appwrite_jwt": "otp-jwt",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["token"] == nil || data["token"] == "" {
		t.Fatal("expected token in response")
	}
	if data["user_id"] != "otp_user" {
		t.Errorf("expected user_id=otp_user, got %v", data["user_id"])
	}
}

func TestVerifyOTP_CreatesNewUser(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("new-otp-jwt", map[string]interface{}{
		"$id":   "brand_new_user",
		"phone": "+919876543210",
	})

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone":        "+919876543210",
		"otp":          "123456",
		"appwrite_jwt": "new-otp-jwt",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["role"] != "customer" {
		t.Errorf("expected default role=customer for new user, got %v", data["role"])
	}
}

func TestVerifyOTP_InvalidAppwriteJWT(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone":        "+919876543210",
		"otp":          "123456",
		"appwrite_jwt": "invalid-jwt",
	})

	if rec.Code != 401 {
		t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestVerifyOTP_PhoneMismatch(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.FakeAW.RegisterJWT("mismatch-jwt", map[string]interface{}{
		"$id":   "user_mm",
		"phone": "+919876543210",
	})

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone":        "+919999999999", // different from account
		"otp":          "123456",
		"appwrite_jwt": "mismatch-jwt",
	})

	if rec.Code != 400 {
		t.Fatalf("expected 400 for phone mismatch, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestVerifyOTP_MissingFields(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone": "+919876543210",
	})
	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing otp/jwt, got %d", rec.Code)
	}
}

// ─── Onboard ───

func TestOnboard_CustomerSuccess(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("onb_cust", map[string]interface{}{
		"phone": "+919876543210", "role": "customer",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":  "Test Customer",
		"email": "test@example.com",
	}, "onb_cust", "customer")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})
	if data["role"] != "customer" {
		t.Errorf("expected role=customer, got %v", data["role"])
	}

	// Verify user name was updated
	userDoc := te.FakeAW.GetDocument("users", "onb_cust")
	if userDoc["name"] != "Test Customer" {
		t.Errorf("expected name updated, got %v", userDoc["name"])
	}
}

func TestOnboard_RestaurantOwnerCreatesRestaurant(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("rest_owner_1", map[string]interface{}{
		"phone": "+919876543210", "role": "restaurant_owner",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":              "Owner Name",
		"restaurant_name":   "My Restaurant",
		"restaurant_address": "123 Main St",
		"city":              "Bangalore",
		"latitude":          12.97,
		"longitude":         77.59,
	}, "rest_owner_1", "restaurant_owner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify restaurant was created (ID = rest_ + first 8 chars of userID)
	restDoc := te.FakeAW.GetDocument("restaurants", "rest_res")
	if restDoc == nil {
		// Try the expected ID format
		restDoc = te.FakeAW.GetDocument("restaurants", "rest_rest_ow")
	}
	// Check that at least one restaurant exists
	if te.FakeAW.DocumentCount("restaurants") == 0 {
		t.Error("expected restaurant to be created")
	}
}

func TestOnboard_RestaurantOwnerMissingRestaurantName(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("rest_owner_2", map[string]interface{}{
		"phone": "+919876543210", "role": "restaurant_owner",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name": "Owner",
	}, "rest_owner_2", "restaurant_owner")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing restaurant_name, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestOnboard_DeliveryPartnerCreatesProfile(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_onb_user", map[string]interface{}{
		"phone": "+919876543210", "role": "delivery_partner",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":           "Rider Name",
		"vehicle_type":   "scooter",
		"vehicle_number": "KA01AB1234",
	}, "dp_onb_user", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if te.FakeAW.DocumentCount("delivery_partners") == 0 {
		t.Error("expected delivery partner profile to be created")
	}
}

func TestOnboard_DeliveryPartnerDefaultsVehicleToBike(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("dp_onb_def", map[string]interface{}{
		"phone": "+919876543210", "role": "delivery_partner",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name": "Rider",
	}, "dp_onb_def", "delivery_partner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Find the created delivery partner doc
	docs := te.FakeAW.AllDocuments("delivery_partners")
	if len(docs) == 0 {
		t.Fatal("expected delivery partner doc")
	}
	if docs[0]["vehicle_type"] != "bike" {
		t.Errorf("expected default vehicle_type=bike, got %v", docs[0]["vehicle_type"])
	}
}

func TestOnboard_MissingName(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"email": "test@example.com",
	}, "some_user", "customer")

	if rec.Code != 400 {
		t.Fatalf("expected 400 for missing name, got %d", rec.Code)
	}
}

func TestOnboard_NoAuth(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name": "Test",
	})
	if rec.Code != 401 {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestOnboard_RestaurantOwnerUpdatesExisting(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("rest_upd_1", map[string]interface{}{
		"phone": "+919876543210", "role": "restaurant_owner",
	})
	te.SeedRestaurant("rest_existing", "rest_upd_1", 12.97, 77.59, false)

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":            "Owner",
		"restaurant_name": "Updated Restaurant",
		"city":            "Mumbai",
	}, "rest_upd_1", "restaurant_owner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	doc := te.FakeAW.GetDocument("restaurants", "rest_existing")
	if doc["name"] != "Updated Restaurant" {
		t.Errorf("expected name=Updated Restaurant, got %v", doc["name"])
	}
	if doc["city"] != "Mumbai" {
		t.Errorf("expected city=Mumbai, got %v", doc["city"])
	}
}

func TestOnboard_PreferencesStored(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("pref_user", map[string]interface{}{
		"phone": "+919876543210", "role": "customer",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":      "Pref User",
		"is_veg":    true,
		"dark_mode": true,
	}, "pref_user", "customer")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	doc := te.FakeAW.GetDocument("users", "pref_user")
	if doc["is_veg"] != true {
		t.Errorf("expected is_veg=true, got %v", doc["is_veg"])
	}
	if doc["dark_mode"] != true {
		t.Errorf("expected dark_mode=true, got %v", doc["dark_mode"])
	}
}

// ─── Exchange with phone migration ───

func TestExchange_PhoneMigration(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Old user doc with the phone (different ID from Appwrite account)
	te.SeedUser("old_user_id", map[string]interface{}{
		"phone": "+919876543210",
		"name":  "Old Account",
		"role":  "customer",
	})

	// New Appwrite account referencing the same phone
	te.FakeAW.RegisterJWT("migrate-jwt", map[string]interface{}{
		"$id":   "new_aw_id",
		"phone": "+919876543210",
		"name":  "Old Account",
	})

	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt": "migrate-jwt",
	})

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	resp := te.ParseResponse(rec)
	data, _ := resp["data"].(map[string]interface{})

	// Should use new Appwrite user ID
	if data["user_id"] != "new_aw_id" {
		t.Errorf("expected user_id=new_aw_id, got %v", data["user_id"])
	}
	if data["is_new"] != false {
		t.Errorf("expected is_new=false for migrated user, got %v", data["is_new"])
	}
}

// ─── Timeout / Various edge cases ───

func TestSendOTP_NonIndianPhone(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	rec := te.Request("POST", "/api/v1/auth/send-otp", map[string]interface{}{
		"phone": "+14155551234",
	})
	if rec.Code != 400 {
		t.Fatalf("expected 400 for non-Indian phone, got %d", rec.Code)
	}
}

func TestExchange_CrossRoleGuardMigration(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	// Old doc with restaurant_owner role
	te.SeedUser("old_cross_id", map[string]interface{}{
		"phone": "+919876543210",
		"role":  "restaurant_owner",
	})

	te.FakeAW.RegisterJWT("cross-mig-jwt", map[string]interface{}{
		"$id":   "new_cross_id",
		"phone": "+919876543210",
	})

	// Attempt to migrate as customer → should fail with cross-role guard
	rec := te.Request("POST", "/api/v1/auth/exchange", map[string]interface{}{
		"jwt":  "cross-mig-jwt",
		"role": "customer",
	})

	if rec.Code != 409 {
		t.Fatalf("expected 409 for cross-role during migration, got %d: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, "already registered") {
		t.Errorf("expected cross-role message, got %s", body)
	}
}

func TestVerifyOTP_ClearsBlacklist(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.MiniRedis.Set("token_blacklist:verify_user", "1")

	te.FakeAW.RegisterJWT("verify-bl-jwt", map[string]interface{}{
		"$id":   "verify_user",
		"phone": "+919876543210",
	})
	te.SeedUser("verify_user", map[string]interface{}{
		"phone": "+919876543210", "role": "customer",
	})

	rec := te.Request("POST", "/api/v1/auth/verify-otp", map[string]interface{}{
		"phone":        "+919876543210",
		"otp":          "999999",
		"appwrite_jwt": "verify-bl-jwt",
	})
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	if te.MiniRedis.Exists("token_blacklist:verify_user") {
		t.Error("expected blacklist to be cleared after verify-otp")
	}
}

func TestOnboard_RestaurantDefaultCity(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("rest_def_city", map[string]interface{}{
		"phone": "+919876543210", "role": "restaurant_owner",
	})

	rec := te.AuthRequest("POST", "/api/v1/auth/onboard", map[string]interface{}{
		"name":            "Owner",
		"restaurant_name": "No City Restaurant",
		// city intentionally omitted
	}, "rest_def_city", "restaurant_owner")

	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Check restaurant has default city
	docs := te.FakeAW.AllDocuments("restaurants")
	found := false
	for _, doc := range docs {
		if doc["name"] == "No City Restaurant" {
			found = true
			if doc["city"] != "Unknown" {
				t.Errorf("expected default city=Unknown, got %v", doc["city"])
			}
		}
	}
	if !found {
		t.Error("expected restaurant to be created")
	}
}
