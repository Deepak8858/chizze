package services

import (
	"context"
	"log"
	"sort"
	"time"

	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/pkg/appwrite"
)

// expectedCollectionAttrs lists the attribute keys the backend writes to each
// Appwrite collection. Updated as new denormalized fields are added. The
// validator logs a WARN at boot for any key the code expects but the schema
// does not have — that mismatch was the root cause of the 2026-04-14 ordering
// outage (missing customer_name/customer_phone), so we fail loud at boot now.
var expectedCollectionAttrs = map[string][]string{
	models.CollectionOrders: {
		"order_number", "customer_id", "customer_name", "customer_phone",
		"restaurant_id", "restaurant_name", "restaurant_latitude", "restaurant_longitude",
		"delivery_partner_id", "delivery_partner_name", "delivery_partner_phone",
		"delivery_address_id", "delivery_address", "delivery_landmark",
		"delivery_latitude", "delivery_longitude",
		"items", "item_total", "delivery_type", "delivery_fee", "platform_fee",
		"gst", "discount", "coupon_code", "tip", "grand_total",
		"payment_method", "payment_status", "payment_id", "razorpay_order_id",
		"status", "special_instructions", "delivery_instructions",
		"estimated_delivery_min", "placed_at", "confirmed_at", "preparing_at",
		"prepared_at", "accepted_at", "picked_up_at", "delivered_at", "cancelled_at",
		"cancellation_reason", "cancelled_by",
	},
	// reviews: every attribute CreateReview writes. Added after customers
	// reported they couldn't submit reviews — silent schema drift here produced
	// the same 400 document_invalid_structure that hit the orders collection.
	models.CollectionReviews: {
		"order_id", "customer_id", "restaurant_id", "delivery_partner_id",
		"food_rating", "delivery_rating", "review_text", "tags",
		"is_visible", "created_at", "restaurant_reply",
	},
}

// ValidateCollectionSchemas fetches each tracked collection's attributes from
// Appwrite and logs a WARN for any expected attribute missing from the schema.
// Non-fatal: we never block boot on a network blip. Any expected-attribute
// check that fails to read the collection is logged and skipped.
func ValidateCollectionSchemas(client *appwrite.Client) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	total := 0
	missing := 0
	for collectionID, expected := range expectedCollectionAttrs {
		attrs, err := client.ListCollectionAttributes(ctx, collectionID)
		if err != nil {
			log.Printf("[schema-check] WARN: could not list attributes for %q: %v", collectionID, err)
			continue
		}
		have := make(map[string]struct{}, len(attrs))
		for _, a := range attrs {
			if key, _ := a["key"].(string); key != "" {
				have[key] = struct{}{}
			}
		}
		var missingForCollection []string
		for _, k := range expected {
			if _, ok := have[k]; !ok {
				missingForCollection = append(missingForCollection, k)
			}
		}
		total += len(expected)
		missing += len(missingForCollection)
		if len(missingForCollection) > 0 {
			sort.Strings(missingForCollection)
			log.Printf("[schema-check] WARN: collection %q missing attributes: %v — writes touching these keys will fail with 400 document_invalid_structure", collectionID, missingForCollection)
		}
	}
	if missing == 0 {
		log.Printf("[schema-check] OK: %d expected attributes verified across %d collection(s)", total, len(expectedCollectionAttrs))
	} else {
		log.Printf("[schema-check] %d/%d expected attributes missing — see warnings above", missing, total)
	}
}
