package testutil

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"time"
)

// FakeAppwrite is an in-memory Appwrite REST API server for testing.
type FakeAppwrite struct {
	Server *httptest.Server
	mu     sync.RWMutex
	// collections[collectionID][documentID] = document
	collections map[string]map[string]map[string]interface{}
	// jwtAccounts maps JWT tokens to account responses for GET /account
	jwtAccounts map[string]map[string]interface{}
	nextID      int
}

// NewFakeAppwrite creates and starts a fake Appwrite HTTP server.
func NewFakeAppwrite() *FakeAppwrite {
	fa := &FakeAppwrite{
		collections: make(map[string]map[string]map[string]interface{}),
		jwtAccounts: make(map[string]map[string]interface{}),
		nextID:      1000,
	}

	mux := http.NewServeMux()

	// GET /account — JWT verification
	mux.HandleFunc("GET /account", fa.handleGetAccount)

	// GET /health
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})

	// Document CRUD — use a catch-all for /databases/ paths
	mux.HandleFunc("/databases/", fa.handleDocuments)

	fa.Server = httptest.NewServer(mux)
	return fa
}

// Close stops the fake server.
func (fa *FakeAppwrite) Close() {
	fa.Server.Close()
}

// RegisterJWT maps a JWT token to an account response for GET /account.
func (fa *FakeAppwrite) RegisterJWT(jwtToken string, account map[string]interface{}) {
	fa.mu.Lock()
	defer fa.mu.Unlock()
	fa.jwtAccounts[jwtToken] = account
}

// SeedDocument pre-populates a document in the fake store.
func (fa *FakeAppwrite) SeedDocument(collectionID, docID string, data map[string]interface{}) {
	fa.mu.Lock()
	defer fa.mu.Unlock()
	if fa.collections[collectionID] == nil {
		fa.collections[collectionID] = make(map[string]map[string]interface{})
	}
	doc := make(map[string]interface{})
	for k, v := range data {
		doc[k] = v
	}
	doc["$id"] = docID
	now := time.Now().UTC().Format(time.RFC3339)
	if _, ok := doc["$createdAt"]; !ok {
		doc["$createdAt"] = now
	}
	doc["$updatedAt"] = now
	fa.collections[collectionID][docID] = doc
}

// GetDocument directly retrieves a document for assertions.
func (fa *FakeAppwrite) GetDocument(collectionID, docID string) map[string]interface{} {
	fa.mu.RLock()
	defer fa.mu.RUnlock()
	if coll, ok := fa.collections[collectionID]; ok {
		return coll[docID]
	}
	return nil
}

// DocumentCount returns the number of documents in a collection.
func (fa *FakeAppwrite) DocumentCount(collectionID string) int {
	fa.mu.RLock()
	defer fa.mu.RUnlock()
	return len(fa.collections[collectionID])
}

// AllDocuments returns all documents in a collection.
func (fa *FakeAppwrite) AllDocuments(collectionID string) []map[string]interface{} {
	fa.mu.RLock()
	defer fa.mu.RUnlock()
	var docs []map[string]interface{}
	for _, doc := range fa.collections[collectionID] {
		docs = append(docs, doc)
	}
	return docs
}

// ─── HTTP Handlers ───

func (fa *FakeAppwrite) handleGetAccount(w http.ResponseWriter, r *http.Request) {
	jwtToken := r.Header.Get("X-Appwrite-JWT")
	fa.mu.RLock()
	account, ok := fa.jwtAccounts[jwtToken]
	fa.mu.RUnlock()

	if !ok || jwtToken == "" {
		w.WriteHeader(401)
		json.NewEncoder(w).Encode(map[string]string{"message": "Invalid JWT"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(account)
}

func (fa *FakeAppwrite) handleDocuments(w http.ResponseWriter, r *http.Request) {
	// Parse path: /databases/{dbID}/collections/{collID}/documents[/{docID}]
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	// Expected: databases / {db} / collections / {coll} / documents [/ {docID}]
	//           0           1      2              3        4            5
	if len(parts) < 5 || parts[0] != "databases" || parts[2] != "collections" || parts[4] != "documents" {
		http.Error(w, "invalid path", 400)
		return
	}
	collID := parts[3]
	docID := ""
	if len(parts) > 5 {
		docID = parts[5]
	}

	w.Header().Set("Content-Type", "application/json")

	switch r.Method {
	case "GET":
		if docID != "" {
			fa.handleGetDoc(w, collID, docID)
		} else {
			fa.handleListDocs(w, r, collID)
		}
	case "POST":
		fa.handleCreateDoc(w, r, collID)
	case "PATCH":
		fa.handleUpdateDoc(w, r, collID, docID)
	case "DELETE":
		fa.handleDeleteDoc(w, collID, docID)
	default:
		http.Error(w, "method not allowed", 405)
	}
}

func (fa *FakeAppwrite) handleGetDoc(w http.ResponseWriter, collID, docID string) {
	fa.mu.RLock()
	doc, ok := fa.collections[collID][docID]
	fa.mu.RUnlock()
	if !ok {
		w.WriteHeader(404)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"message": "Document not found",
			"code":    404,
		})
		return
	}
	json.NewEncoder(w).Encode(doc)
}

func (fa *FakeAppwrite) handleListDocs(w http.ResponseWriter, r *http.Request, collID string) {
	fa.mu.RLock()
	var docs []map[string]interface{}
	for _, doc := range fa.collections[collID] {
		docs = append(docs, doc)
	}
	fa.mu.RUnlock()

	// Parse queries
	rawQueries := r.URL.Query()["queries[]"]
	docs = fa.applyQueries(docs, rawQueries)

	json.NewEncoder(w).Encode(map[string]interface{}{
		"total":     len(docs),
		"documents": docs,
	})
}

func (fa *FakeAppwrite) handleCreateDoc(w http.ResponseWriter, r *http.Request, collID string) {
	body, _ := io.ReadAll(r.Body)
	var payload struct {
		DocumentID string                 `json:"documentId"`
		Data       map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		w.WriteHeader(400)
		json.NewEncoder(w).Encode(map[string]string{"message": "invalid JSON"})
		return
	}

	docID := payload.DocumentID
	if docID == "" || docID == "unique()" {
		fa.mu.Lock()
		docID = fmt.Sprintf("auto_%d", fa.nextID)
		fa.nextID++
		fa.mu.Unlock()
	}

	doc := make(map[string]interface{})
	for k, v := range payload.Data {
		doc[k] = v
	}
	doc["$id"] = docID
	now := time.Now().UTC().Format(time.RFC3339)
	doc["$createdAt"] = now
	doc["$updatedAt"] = now

	fa.mu.Lock()
	if fa.collections[collID] == nil {
		fa.collections[collID] = make(map[string]map[string]interface{})
	}
	fa.collections[collID][docID] = doc
	fa.mu.Unlock()

	w.WriteHeader(201)
	json.NewEncoder(w).Encode(doc)
}

func (fa *FakeAppwrite) handleUpdateDoc(w http.ResponseWriter, r *http.Request, collID, docID string) {
	body, _ := io.ReadAll(r.Body)
	var payload struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		w.WriteHeader(400)
		json.NewEncoder(w).Encode(map[string]string{"message": "invalid JSON"})
		return
	}

	fa.mu.Lock()
	defer fa.mu.Unlock()
	doc, ok := fa.collections[collID][docID]
	if !ok {
		w.WriteHeader(404)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"message": "Document not found",
			"code":    404,
		})
		return
	}

	for k, v := range payload.Data {
		doc[k] = v
	}
	doc["$updatedAt"] = time.Now().UTC().Format(time.RFC3339)
	fa.collections[collID][docID] = doc
	json.NewEncoder(w).Encode(doc)
}

func (fa *FakeAppwrite) handleDeleteDoc(w http.ResponseWriter, collID, docID string) {
	fa.mu.Lock()
	defer fa.mu.Unlock()
	delete(fa.collections[collID], docID)
	w.WriteHeader(204)
}

// ─── Query Engine ───

type parsedQuery struct {
	Method    string        `json:"method"`
	Attribute string        `json:"attribute"`
	Values    []interface{} `json:"values"`
}

func (fa *FakeAppwrite) applyQueries(docs []map[string]interface{}, rawQueries []string) []map[string]interface{} {
	var queries []parsedQuery
	for _, raw := range rawQueries {
		var q parsedQuery
		if err := json.Unmarshal([]byte(raw), &q); err != nil {
			continue
		}
		queries = append(queries, q)
	}

	// Apply filters
	for _, q := range queries {
		switch q.Method {
		case "equal":
			docs = filterEqual(docs, q.Attribute, q.Values)
		case "notEqual":
			docs = filterNotEqual(docs, q.Attribute, q.Values)
		case "isNull":
			docs = filterIsNull(docs, q.Attribute)
		case "greaterThan":
			if len(q.Values) > 0 {
				docs = filterCompare(docs, q.Attribute, q.Values[0], ">")
			}
		case "greaterThanEqual":
			if len(q.Values) > 0 {
				docs = filterCompare(docs, q.Attribute, q.Values[0], ">=")
			}
		case "lessThan":
			if len(q.Values) > 0 {
				docs = filterCompare(docs, q.Attribute, q.Values[0], "<")
			}
		case "lessThanEqual":
			if len(q.Values) > 0 {
				docs = filterCompare(docs, q.Attribute, q.Values[0], "<=")
			}
		case "search":
			if len(q.Values) > 0 {
				term, _ := q.Values[0].(string)
				docs = filterSearch(docs, q.Attribute, term)
			}
		case "orderDesc":
			sortDocs(docs, q.Attribute, true)
		case "orderAsc":
			sortDocs(docs, q.Attribute, false)
		}
	}

	// Apply offset and limit
	offset := extractQueryInt(queries, "offset")
	limit := extractQueryInt(queries, "limit")
	if offset > 0 && offset < len(docs) {
		docs = docs[offset:]
	} else if offset >= len(docs) {
		docs = nil
	}
	if limit > 0 && limit < len(docs) {
		docs = docs[:limit]
	}

	if docs == nil {
		docs = []map[string]interface{}{}
	}
	return docs
}

func filterEqual(docs []map[string]interface{}, attr string, values []interface{}) []map[string]interface{} {
	var result []map[string]interface{}
	for _, doc := range docs {
		val := doc[attr]
		for _, v := range values {
			if docValStr(val) == docValStr(v) {
				result = append(result, doc)
				break
			}
		}
	}
	return result
}

func filterNotEqual(docs []map[string]interface{}, attr string, values []interface{}) []map[string]interface{} {
	var result []map[string]interface{}
	for _, doc := range docs {
		val := doc[attr]
		match := false
		for _, v := range values {
			if docValStr(val) == docValStr(v) {
				match = true
				break
			}
		}
		if !match {
			result = append(result, doc)
		}
	}
	return result
}

func filterIsNull(docs []map[string]interface{}, attr string) []map[string]interface{} {
	var result []map[string]interface{}
	for _, doc := range docs {
		val, exists := doc[attr]
		if !exists || val == nil {
			result = append(result, doc)
		}
	}
	return result
}

func filterCompare(docs []map[string]interface{}, attr string, value interface{}, op string) []map[string]interface{} {
	var result []map[string]interface{}
	targetStr := docValStr(value)
	for _, doc := range docs {
		docStr := docValStr(doc[attr])
		var pass bool
		switch op {
		case ">":
			pass = docStr > targetStr
		case ">=":
			pass = docStr >= targetStr
		case "<":
			pass = docStr < targetStr
		case "<=":
			pass = docStr <= targetStr
		}
		if pass {
			result = append(result, doc)
		}
	}
	return result
}

func filterSearch(docs []map[string]interface{}, attr, term string) []map[string]interface{} {
	var result []map[string]interface{}
	termLower := strings.ToLower(term)
	for _, doc := range docs {
		val, _ := doc[attr].(string)
		if strings.Contains(strings.ToLower(val), termLower) {
			result = append(result, doc)
		}
	}
	return result
}

func sortDocs(docs []map[string]interface{}, attr string, desc bool) {
	sort.SliceStable(docs, func(i, j int) bool {
		a := docValStr(docs[i][attr])
		b := docValStr(docs[j][attr])
		if desc {
			return a > b
		}
		return a < b
	})
}

func extractQueryInt(queries []parsedQuery, method string) int {
	for _, q := range queries {
		if q.Method == method && len(q.Values) > 0 {
			switch v := q.Values[0].(type) {
			case float64:
				return int(v)
			case int:
				return v
			}
		}
	}
	return 0
}

// docValStr converts any value to a string for comparison.
func docValStr(v interface{}) string {
	if v == nil {
		return ""
	}
	return fmt.Sprintf("%v", v)
}
