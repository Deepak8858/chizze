package main

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/chizze/backend/internal/config"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/pkg/appwrite"
)

func main() {
	cfg := config.Load()
	if cfg.AppwriteAPIKey == "" {
		log.Fatal("Need APPWRITE_API_KEY")
	}

	client := appwrite.NewClient(
		cfg,
	)

	// List orders matching order_id
	queries := []string{
		appwrite.QueryEqual("order_id", "CHZ-838777-229030"),
	}

	res, err := client.ListDocuments(models.CollectionOrders, queries)
	if err != nil {
		log.Fatalf("Error: %v", err)
	}

	if len(res.Documents) == 0 {
		log.Println("Order not found by order_id. Trying delivery requests...")
		res, err = client.ListDocuments(models.CollectionDeliveryRequests, []string{
			appwrite.QueryEqual("order_id", "CHZ-838777-229030"),
		})
		if err != nil {
			log.Fatalf("Error: %v", err)
		}
		if len(res.Documents) == 0 {
			log.Println("Not found in delivery requests either.")
			// Dump all users named "prince"
			res, _ = client.ListDocuments(models.CollectionUsers, []string{
				appwrite.QuerySearch("name", "prince"),
			})
			b, _ := json.MarshalIndent(res, "", "  ")
			fmt.Println("Users:", string(b))

			// Try delivery partners
			res, _ = client.ListDocuments(models.CollectionDeliveryPartners, []string{
				appwrite.QuerySearch("name", "prince"),
			})
			b, _ = json.MarshalIndent(res, "", "  ")
			fmt.Println("Partners:", string(b))
			return
		}
	}

	b, _ := json.MarshalIndent(res.Documents, "", "  ")
	fmt.Println(string(b))
}
