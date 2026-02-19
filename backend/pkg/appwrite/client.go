package appwrite

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/chizze/backend/internal/config"
)

// Client wraps Appwrite REST API calls
type Client struct {
	endpoint   string
	projectID  string
	apiKey     string
	databaseID string
	httpClient *http.Client
}

// NewClient creates an Appwrite client
func NewClient(cfg *config.Config) *Client {
	return &Client{
		endpoint:   cfg.AppwriteEndpoint,
		projectID:  cfg.AppwriteProjectID,
		apiKey:     cfg.AppwriteAPIKey,
		databaseID: cfg.AppwriteDatabaseID,
		httpClient: &http.Client{Timeout: 30 * time.Second},
	}
}

// DocumentList is the response for list operations
type DocumentList struct {
	Total     int                      `json:"total"`
	Documents []map[string]interface{} `json:"documents"`
}

// request makes an authenticated HTTP request to Appwrite
func (c *Client) request(method, path string, body interface{}) ([]byte, error) {
	var bodyReader io.Reader
	if body != nil {
		jsonBytes, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		bodyReader = bytes.NewReader(jsonBytes)
	}

	reqURL := fmt.Sprintf("%s%s", c.endpoint, path)
	req, err := http.NewRequest(method, reqURL, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Appwrite-Project", c.projectID)
	req.Header.Set("X-Appwrite-Key", c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("appwrite error %d: %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}

// ─── Database Operations ───

// ListDocuments lists documents in a collection with optional queries
func (c *Client) ListDocuments(collectionID string, queries []string) (*DocumentList, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents", c.databaseID, collectionID)

	if len(queries) > 0 {
		params := url.Values{}
		for _, q := range queries {
			params.Add("queries[]", q)
		}
		path += "?" + params.Encode()
	}

	data, err := c.request("GET", path, nil)
	if err != nil {
		return nil, err
	}

	var result DocumentList
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("unmarshal documents: %w", err)
	}
	return &result, nil
}

// GetDocument retrieves a single document
func (c *Client) GetDocument(collectionID, documentID string) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)

	data, err := c.request("GET", path, nil)
	if err != nil {
		return nil, err
	}

	var doc map[string]interface{}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("unmarshal document: %w", err)
	}
	return doc, nil
}

// CreateDocument creates a new document
func (c *Client) CreateDocument(collectionID, documentID string, body map[string]interface{}) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents",
		c.databaseID, collectionID)

	payload := map[string]interface{}{
		"documentId": documentID,
		"data":       body,
	}

	data, err := c.request("POST", path, payload)
	if err != nil {
		return nil, err
	}

	var doc map[string]interface{}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("unmarshal document: %w", err)
	}
	return doc, nil
}

// UpdateDocument updates an existing document
func (c *Client) UpdateDocument(collectionID, documentID string, body map[string]interface{}) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)

	payload := map[string]interface{}{
		"data": body,
	}

	data, err := c.request("PATCH", path, payload)
	if err != nil {
		return nil, err
	}

	var doc map[string]interface{}
	if err := json.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("unmarshal document: %w", err)
	}
	return doc, nil
}

// DeleteDocument deletes a document
func (c *Client) DeleteDocument(collectionID, documentID string) error {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)
	_, err := c.request("DELETE", path, nil)
	return err
}
