package handlers_test

import (
	"encoding/json"
	"testing"

	"github.com/chizze/backend/internal/testutil"
)

// ─── helpers ───

func seedPartnerRestaurant(te *testutil.TestEnv, id, ownerID string, data map[string]interface{}) {
	base := map[string]interface{}{
		"owner_id":       ownerID,
		"name":           "Partner Cafe",
		"address":        "1 Main St",
		"city":           "Bangalore",
		"latitude":       12.97,
		"longitude":      77.59,
		"is_online":      true,
		"rating":         4.5,
		"total_earnings": 0.0,
	}
	for k, v := range data {
		base[k] = v
	}
	te.FakeAW.SeedDocument("restaurants", id, base)
}

// ─── GetBankDetails ───

func TestPartnerGetBankDetails_ReturnsSavedFields(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"bank_account_id":     "123456789012",
		"bank_account_holder": "Ada Lovelace",
		"ifsc":                "SBIN0001234",
		"upi_id":              "ada@upi",
		"total_earnings":      540.0,
	})

	rec := te.AuthRequest("GET", "/api/v1/partner/bank-details", nil, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	body := te.ParseResponse(rec)
	data := body["data"].(map[string]interface{})
	if data["bank_account_id"] != "123456789012" {
		t.Errorf("bank_account_id mismatch: %v", data["bank_account_id"])
	}
	if data["ifsc"] != "SBIN0001234" {
		t.Errorf("ifsc mismatch: %v", data["ifsc"])
	}
	if data["total_earnings"].(float64) != 540 {
		t.Errorf("total_earnings mismatch: %v", data["total_earnings"])
	}
}

func TestPartnerGetBankDetails_NoRestaurant_Forbidden(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	rec := te.AuthRequest("GET", "/api/v1/partner/bank-details", nil, "owner_1", "restaurant_owner")
	if rec.Code != 403 {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerGetBankDetails_WrongRole_Forbidden(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"role": "customer"})
	rec := te.AuthRequest("GET", "/api/v1/partner/bank-details", nil, "cust_1", "customer")
	if rec.Code != 403 {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── UpdateBankDetails ───

func TestPartnerUpdateBankDetails_Success_NormalizesIFSC(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	body := map[string]interface{}{
		"bank_account_id":     "555666777888",
		"bank_account_holder": "Grace Hopper",
		"ifsc":                " sbin0005678 ",
		"upi_id":              "grace@okicici",
	}
	rec := te.AuthRequest("PUT", "/api/v1/partner/bank-details", body, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	doc := te.FakeAW.GetDocument("restaurants", "rest_1")
	if doc["ifsc"] != "SBIN0005678" {
		t.Errorf("ifsc not normalized: %v", doc["ifsc"])
	}
	if doc["bank_account_id"] != "555666777888" {
		t.Errorf("bank_account_id not saved: %v", doc["bank_account_id"])
	}
	if doc["upi_id"] != "grace@okicici" {
		t.Errorf("upi_id not saved: %v", doc["upi_id"])
	}
}

func TestPartnerUpdateBankDetails_InvalidIFSC_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	cases := []string{"BADFORMAT", "SBIN1001234", "SB1N0001234", "SBIN0001234X"}
	for _, ifsc := range cases {
		body := map[string]interface{}{"ifsc": ifsc}
		rec := te.AuthRequest("PUT", "/api/v1/partner/bank-details", body, "owner_1", "restaurant_owner")
		if rec.Code != 400 {
			t.Errorf("IFSC %q expected 400, got %d", ifsc, rec.Code)
		}
	}
}

func TestPartnerUpdateBankDetails_ShortAccountNumber_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	body := map[string]interface{}{"bank_account_id": "12345"}
	rec := te.AuthRequest("PUT", "/api/v1/partner/bank-details", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerUpdateBankDetails_EmptyBody_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	rec := te.AuthRequest("PUT", "/api/v1/partner/bank-details", map[string]interface{}{}, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 for empty body, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerUpdateBankDetails_PartialUpdatePreservesOthers(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"bank_account_id":     "111111111111",
		"bank_account_holder": "Original Holder",
		"ifsc":                "SBIN0001111",
	})

	body := map[string]interface{}{"upi_id": "new@upi"}
	rec := te.AuthRequest("PUT", "/api/v1/partner/bank-details", body, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	doc := te.FakeAW.GetDocument("restaurants", "rest_1")
	if doc["bank_account_id"] != "111111111111" {
		t.Errorf("bank_account_id was clobbered: %v", doc["bank_account_id"])
	}
	if doc["upi_id"] != "new@upi" {
		t.Errorf("upi_id not updated: %v", doc["upi_id"])
	}
}

// ─── RequestPayout ───

func TestPartnerRequestPayout_Success_UPI(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"upi_id":         "owner@upi",
		"total_earnings": 500.0,
	})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// payout created
	if te.FakeAW.DocumentCount("payouts") != 1 {
		t.Fatalf("expected 1 payout, got %d", te.FakeAW.DocumentCount("payouts"))
	}

	// balance deducted
	doc := te.FakeAW.GetDocument("restaurants", "rest_1")
	if got, _ := doc["total_earnings"].(float64); got != 300 {
		t.Errorf("expected balance 300 after 500-200, got %v", got)
	}

	// notification created
	if te.FakeAW.DocumentCount("notifications") == 0 {
		t.Error("expected notification to be created")
	}
}

func TestPartnerRequestPayout_Success_BankTransfer(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"bank_account_id":     "123456789012",
		"bank_account_holder": "Owner One",
		"ifsc":                "SBIN0001234",
		"total_earnings":      1000.0,
	})

	body := map[string]interface{}{"amount": 750.0, "method": "bank_transfer"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_BelowMinimum_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"upi_id":         "owner@upi",
		"total_earnings": 500.0,
	})

	body := map[string]interface{}{"amount": 50.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	if te.FakeAW.DocumentCount("payouts") != 0 {
		t.Error("payout should not be created for below-minimum request")
	}
}

func TestPartnerRequestPayout_InsufficientBalance_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"upi_id":         "owner@upi",
		"total_earnings": 100.0,
	})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_MissingUPIDetails_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{"total_earnings": 500.0})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 without UPI, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_MissingBankDetails_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"total_earnings": 500.0,
		"ifsc":           "SBIN0001234",
		// missing bank_account_id / holder
	})

	body := map[string]interface{}{"amount": 200.0, "method": "bank_transfer"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_PendingExists_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"upi_id":         "owner@upi",
		"total_earnings": 500.0,
	})
	te.SeedPayout("prev_pending", map[string]interface{}{
		"partner_id": "rest_1",
		"user_id":    "owner_1",
		"amount":     150.0,
		"status":     "pending",
		"method":     "upi",
	})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 with pending payout, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_ProcessingExists_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{
		"upi_id":         "owner@upi",
		"total_earnings": 500.0,
	})
	te.SeedPayout("prev_proc", map[string]interface{}{
		"partner_id": "rest_1",
		"user_id":    "owner_1",
		"amount":     100.0,
		"status":     "processing",
		"method":     "upi",
	})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400 with processing payout, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_InvalidMethod_Rejected(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", map[string]interface{}{"total_earnings": 500.0})

	body := map[string]interface{}{"amount": 200.0, "method": "crypto"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "owner_1", "restaurant_owner")
	if rec.Code != 400 {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestPartnerRequestPayout_WrongRole_Forbidden(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("cust_1", map[string]interface{}{"role": "customer"})

	body := map[string]interface{}{"amount": 200.0, "method": "upi"}
	rec := te.AuthRequest("POST", "/api/v1/partner/payouts/request", body, "cust_1", "customer")
	if rec.Code != 403 {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
}

// ─── ListPayouts ───

func TestPartnerListPayouts_ReturnsOnlyOwnPayouts(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	// Own payouts
	te.SeedPayout("p1", map[string]interface{}{"partner_id": "rest_1", "user_id": "owner_1", "amount": 100.0, "status": "completed"})
	te.SeedPayout("p2", map[string]interface{}{"partner_id": "rest_1", "user_id": "owner_1", "amount": 250.0, "status": "pending"})
	// Someone else's payout
	te.SeedPayout("p3", map[string]interface{}{"partner_id": "rest_other", "user_id": "owner_other", "amount": 999.0, "status": "completed"})

	rec := te.AuthRequest("GET", "/api/v1/partner/payouts", nil, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var body map[string]interface{}
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	data := body["data"].([]interface{})
	if len(data) != 2 {
		t.Fatalf("expected 2 payouts for this partner, got %d", len(data))
	}
}

func TestPartnerListPayouts_Empty(t *testing.T) {
	te := testutil.NewTestEnv(t)
	defer te.Close()

	te.SeedUser("owner_1", map[string]interface{}{"role": "restaurant_owner"})
	seedPartnerRestaurant(te, "rest_1", "owner_1", nil)

	rec := te.AuthRequest("GET", "/api/v1/partner/payouts", nil, "owner_1", "restaurant_owner")
	if rec.Code != 200 {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}
