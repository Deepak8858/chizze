package appwrite

import (
	"encoding/json"
	"fmt"
)

// Query builds Appwrite REST API query strings in JSON format.
// Appwrite Cloud 1.8+ requires queries as JSON objects.

// Equal creates an equality filter query
func QueryEqual(attribute string, values ...interface{}) string {
	q := map[string]interface{}{
		"method":    "equal",
		"attribute": attribute,
		"values":    values,
	}
	b, _ := json.Marshal(q)
	return string(b)
}

// Search creates a fulltext search query
func QuerySearch(attribute string, value string) string {
	q := map[string]interface{}{
		"method":    "search",
		"attribute": attribute,
		"values":    []string{value},
	}
	b, _ := json.Marshal(q)
	return string(b)
}

// OrderDesc creates a descending order query
func QueryOrderDesc(attribute string) string {
	q := map[string]interface{}{
		"method":    "orderDesc",
		"attribute": attribute,
	}
	b, _ := json.Marshal(q)
	return string(b)
}

// OrderAsc creates an ascending order query
func QueryOrderAsc(attribute string) string {
	q := map[string]interface{}{
		"method":    "orderAsc",
		"attribute": attribute,
	}
	b, _ := json.Marshal(q)
	return string(b)
}

// Limit creates a limit query
func QueryLimit(limit int) string {
	return fmt.Sprintf(`{"method":"limit","values":[%d]}`, limit)
}

// Offset creates an offset query
func QueryOffset(offset int) string {
	return fmt.Sprintf(`{"method":"offset","values":[%d]}`, offset)
}
