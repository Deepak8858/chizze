package appwrite

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"time"

	"github.com/chizze/backend/internal/config"
)

// Client wraps Appwrite REST API calls with production-grade HTTP settings
type Client struct {
	endpoint   string
	projectID  string
	apiKey     string
	databaseID string
	httpClient *http.Client
}

// NewClient creates an Appwrite client with optimized connection pooling
func NewClient(cfg *config.Config) *Client {
	transport := &http.Transport{
		// Connection pooling for high concurrency
		MaxIdleConns:        200,
		MaxIdleConnsPerHost: 100,
		MaxConnsPerHost:     200,
		IdleConnTimeout:     90 * time.Second,

		// Timeouts to prevent hanging connections
		DialContext: (&net.Dialer{
			Timeout:   5 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,

		// Enable HTTP/2
		ForceAttemptHTTP2: true,
	}

	return &Client{
		endpoint:   cfg.AppwriteEndpoint,
		projectID:  cfg.AppwriteProjectID,
		apiKey:     cfg.AppwriteAPIKey,
		databaseID: cfg.AppwriteDatabaseID,
		httpClient: &http.Client{
			Transport: transport,
			Timeout:   cfg.RequestTimeout,
		},
	}
}

// DocumentList is the response for list operations
type DocumentList struct {
	Total     int                      `json:"total"`
	Documents []map[string]interface{} `json:"documents"`
}

// request makes an authenticated HTTP request to Appwrite with retry
func (c *Client) request(ctx context.Context, method, path string, body interface{}) ([]byte, error) {
	var lastErr error

	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			// Exponential backoff with jitter: 100ms, 300ms
			backoff := time.Duration(100*(1<<attempt)) * time.Millisecond
			jitter := time.Duration(rand.Intn(50)) * time.Millisecond
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(backoff + jitter):
			}
		}

		data, err := c.doRequest(ctx, method, path, body)
		if err == nil {
			return data, nil
		}
		lastErr = err

		// Only retry on transient errors (5xx, timeout, connection reset)
		if !isRetryable(err) {
			return nil, err
		}
	}

	return nil, fmt.Errorf("after 3 retries: %w", lastErr)
}

func (c *Client) doRequest(ctx context.Context, method, path string, body interface{}) ([]byte, error) {
	var bodyReader io.Reader
	if body != nil {
		jsonBytes, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		bodyReader = bytes.NewReader(jsonBytes)
	}

	reqURL := fmt.Sprintf("%s%s", c.endpoint, path)
	req, err := http.NewRequestWithContext(ctx, method, reqURL, bodyReader)
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

	if resp.StatusCode >= 500 {
		return nil, &retryableError{
			statusCode: resp.StatusCode,
			body:       string(respBody),
		}
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("appwrite error %d: %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}

// ─── Database Operations ───

// ListDocuments lists documents in a collection with optional queries
func (c *Client) ListDocuments(collectionID string, queries []string) (*DocumentList, error) {
	return c.ListDocumentsCtx(context.Background(), collectionID, queries)
}

// ListDocumentsCtx lists documents with context support
func (c *Client) ListDocumentsCtx(ctx context.Context, collectionID string, queries []string) (*DocumentList, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents", c.databaseID, collectionID)

	if len(queries) > 0 {
		params := url.Values{}
		for _, q := range queries {
			params.Add("queries[]", q)
		}
		path += "?" + params.Encode()
	}

	data, err := c.request(ctx, "GET", path, nil)
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
	return c.GetDocumentCtx(context.Background(), collectionID, documentID)
}

// GetDocumentCtx retrieves a single document with context support
func (c *Client) GetDocumentCtx(ctx context.Context, collectionID, documentID string) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)

	data, err := c.request(ctx, "GET", path, nil)
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
	return c.CreateDocumentCtx(context.Background(), collectionID, documentID, body)
}

// CreateDocumentCtx creates a new document with context support
func (c *Client) CreateDocumentCtx(ctx context.Context, collectionID, documentID string, body map[string]interface{}) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents",
		c.databaseID, collectionID)

	payload := map[string]interface{}{
		"documentId": documentID,
		"data":       body,
	}

	data, err := c.request(ctx, "POST", path, payload)
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
	return c.UpdateDocumentCtx(context.Background(), collectionID, documentID, body)
}

// UpdateDocumentCtx updates an existing document with context support
func (c *Client) UpdateDocumentCtx(ctx context.Context, collectionID, documentID string, body map[string]interface{}) (map[string]interface{}, error) {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)

	payload := map[string]interface{}{
		"data": body,
	}

	data, err := c.request(ctx, "PATCH", path, payload)
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
	return c.DeleteDocumentCtx(context.Background(), collectionID, documentID)
}

// DeleteDocumentCtx deletes a document with context support
func (c *Client) DeleteDocumentCtx(ctx context.Context, collectionID, documentID string) error {
	path := fmt.Sprintf("/databases/%s/collections/%s/documents/%s",
		c.databaseID, collectionID, documentID)
	_, err := c.request(ctx, "DELETE", path, nil)
	return err
}

// ─── JWT Verification ───

// VerifyJWT validates an Appwrite client JWT by calling GET /account
// Returns the user account data if valid
func (c *Client) VerifyJWT(jwtToken string) (map[string]interface{}, error) {
	return c.VerifyJWTCtx(context.Background(), jwtToken)
}

// VerifyJWTCtx validates an Appwrite JWT with context
func (c *Client) VerifyJWTCtx(ctx context.Context, jwtToken string) (map[string]interface{}, error) {
	reqURL := fmt.Sprintf("%s/account", c.endpoint)
	req, err := http.NewRequestWithContext(ctx, "GET", reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Appwrite-Project", c.projectID)
	req.Header.Set("X-Appwrite-JWT", jwtToken)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("JWT verification failed (status %d): %s", resp.StatusCode, string(body))
	}

	var account map[string]interface{}
	if err := json.Unmarshal(body, &account); err != nil {
		return nil, fmt.Errorf("unmarshal account: %w", err)
	}
	return account, nil
}

// GetEndpoint returns the Appwrite endpoint URL
func (c *Client) GetEndpoint() string {
	return c.endpoint
}

// GetProjectID returns the Appwrite project ID
func (c *Client) GetProjectID() string {
	return c.projectID
}

// ─── Error helpers ───

type retryableError struct {
	statusCode int
	body       string
}

func (e *retryableError) Error() string {
	return fmt.Sprintf("appwrite error %d: %s", e.statusCode, e.body)
}

func isRetryable(err error) bool {
	if _, ok := err.(*retryableError); ok {
		return true
	}
	// Also retry on network errors (connection reset, timeout)
	if netErr, ok := err.(net.Error); ok {
		return netErr.Timeout()
	}
	return false
}
