package appwrite

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
)

// UploadFile uploads a file to an Appwrite storage bucket using the server API key.
func (c *Client) UploadFile(bucketID, filename, contentType string, content []byte) (map[string]interface{}, error) {
	return c.UploadFileCtx(context.Background(), bucketID, filename, contentType, content)
}

// UploadFileCtx uploads a file to an Appwrite storage bucket with context support.
func (c *Client) UploadFileCtx(ctx context.Context, bucketID, filename, contentType string, content []byte) (map[string]interface{}, error) {
	if bucketID == "" {
		return nil, fmt.Errorf("bucket id is required")
	}
	if filename == "" {
		filename = "upload"
	}

	var body bytes.Buffer
	writer := multipart.NewWriter(&body)

	if err := writer.WriteField("fileId", "unique()"); err != nil {
		return nil, fmt.Errorf("write fileId field: %w", err)
	}

	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return nil, fmt.Errorf("create multipart file part: %w", err)
	}
	if _, err := part.Write(content); err != nil {
		return nil, fmt.Errorf("write multipart file body: %w", err)
	}

	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("close multipart writer: %w", err)
	}

	path := fmt.Sprintf("%s/storage/buckets/%s/files", c.endpoint, bucketID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, path, &body)
	if err != nil {
		return nil, fmt.Errorf("create upload request: %w", err)
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("X-Appwrite-Project", c.projectID)
	req.Header.Set("X-Appwrite-Key", c.apiKey)
	if contentType != "" {
		req.Header.Set("X-File-Content-Type", contentType)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("execute upload request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read upload response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("appwrite upload error %d: %s", resp.StatusCode, string(respBody))
	}

	var result map[string]interface{}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, fmt.Errorf("unmarshal upload response: %w", err)
	}

	if fileID, _ := result["$id"].(string); fileID != "" {
		result["view_url"] = fmt.Sprintf("%s/storage/buckets/%s/files/%s/view?project=%s", c.endpoint, bucketID, fileID, c.projectID)
	}

	return result, nil
}
