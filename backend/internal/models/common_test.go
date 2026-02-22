package models

import "testing"

func TestDefaultPagination(t *testing.T) {
	p := DefaultPagination()
	if p.Page != 1 {
		t.Errorf("DefaultPagination().Page = %d, want 1", p.Page)
	}
	if p.PerPage != 20 {
		t.Errorf("DefaultPagination().PerPage = %d, want 20", p.PerPage)
	}
}

func TestPagination_Offset(t *testing.T) {
	tests := []struct {
		name     string
		page     int
		perPage  int
		expected int
	}{
		{"page 1", 1, 20, 0},
		{"page 2", 2, 20, 20},
		{"page 3, 10 per page", 3, 10, 20},
		{"page 5, 50 per page", 5, 50, 200},
		{"page 1, 100 per page", 1, 100, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p := Pagination{Page: tc.page, PerPage: tc.perPage}
			got := p.Offset()
			if got != tc.expected {
				t.Errorf("Offset() = %d, want %d", got, tc.expected)
			}
		})
	}
}

func TestNewAppError(t *testing.T) {
	err := NewAppError(404, "not found")
	if err.Code != 404 {
		t.Errorf("Code = %d, want 404", err.Code)
	}
	if err.Message != "not found" {
		t.Errorf("Message = %q, want %q", err.Message, "not found")
	}
}

func TestAppError_Error(t *testing.T) {
	err := NewAppError(500, "internal error")
	if err.Error() != "internal error" {
		t.Errorf("Error() = %q, want %q", err.Error(), "internal error")
	}
}

func TestAppError_ImplementsErrorInterface(t *testing.T) {
	var _ error = &AppError{}
}

func TestCollectionConstants(t *testing.T) {
	// Verify key collection constants are non-empty
	collections := []string{
		CollectionUsers,
		CollectionOrders,
		CollectionRestaurants,
		CollectionMenuItems,
		CollectionMenuCategories,
	}
	for _, c := range collections {
		if c == "" {
			t.Errorf("Collection constant should not be empty")
		}
	}
}
