package utils

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// APIResponse is the standard response wrapper
type APIResponse struct {
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
	Meta    *Meta       `json:"meta,omitempty"`
}

// Meta holds pagination info
type Meta struct {
	Page       int `json:"page"`
	PerPage    int `json:"perPage"`
	Total      int `json:"total"`
	TotalPages int `json:"totalPages"`
}

// Success sends a 200 JSON response
func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, APIResponse{
		Success: true,
		Data:    data,
	})
}

// Created sends a 201 JSON response
func Created(c *gin.Context, data interface{}) {
	c.JSON(http.StatusCreated, APIResponse{
		Success: true,
		Data:    data,
	})
}

// Paginated sends a paginated 200 JSON response
func Paginated(c *gin.Context, data interface{}, page, perPage, total int) {
	totalPages := total / perPage
	if total%perPage > 0 {
		totalPages++
	}
	c.JSON(http.StatusOK, APIResponse{
		Success: true,
		Data:    data,
		Meta: &Meta{
			Page:       page,
			PerPage:    perPage,
			Total:      total,
			TotalPages: totalPages,
		},
	})
}

// Error sends an error JSON response
func Error(c *gin.Context, status int, message string) {
	c.JSON(status, APIResponse{
		Success: false,
		Error:   message,
	})
}

// BadRequest sends 400
func BadRequest(c *gin.Context, message string) {
	Error(c, http.StatusBadRequest, message)
}

// Unauthorized sends 401
func Unauthorized(c *gin.Context, message string) {
	Error(c, http.StatusUnauthorized, message)
}

// Forbidden sends 403
func Forbidden(c *gin.Context, message string) {
	Error(c, http.StatusForbidden, message)
}

// NotFound sends 404
func NotFound(c *gin.Context, message string) {
	Error(c, http.StatusNotFound, message)
}

// InternalError sends 500
func InternalError(c *gin.Context, message string) {
	Error(c, http.StatusInternalServerError, message)
}
