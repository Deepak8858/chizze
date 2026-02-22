package utils

import (
	"strings"
	"testing"
)

func TestValidatePhone(t *testing.T) {
	tests := []struct {
		name  string
		phone string
		want  bool
	}{
		{"valid starting with 9", "+919876543210", true},
		{"valid starting with 8", "+918876543210", true},
		{"valid starting with 7", "+917876543210", true},
		{"valid starting with 6", "+916876543210", true},
		{"invalid starting with 5", "+915876543210", false},
		{"missing country code", "9876543210", false},
		{"wrong country code", "+929876543210", false},
		{"too short", "+91987654321", false},
		{"too long", "+9198765432101", false},
		{"empty string", "", false},
		{"with spaces", "+91 9876543210", false},
		{"with dashes", "+91-9876543210", false},
		{"letters mixed", "+91987654abc0", false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ValidatePhone(tc.phone)
			if got != tc.want {
				t.Errorf("ValidatePhone(%q) = %v, want %v", tc.phone, got, tc.want)
			}
		})
	}
}

func TestValidateEmail(t *testing.T) {
	tests := []struct {
		name  string
		email string
		want  bool
	}{
		{"simple valid", "user@example.com", true},
		{"with dots", "user.name@example.com", true},
		{"with plus", "user+tag@example.com", true},
		{"subdomain", "user@mail.example.com", true},
		{"short TLD", "user@example.co", true},
		{"missing @", "userexample.com", false},
		{"missing domain", "user@", false},
		{"missing local", "@example.com", false},
		{"empty string", "", false},
		{"double @", "user@@example.com", false},
		{"space in middle", "user @example.com", false},
		{"single char TLD", "user@example.c", false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ValidateEmail(tc.email)
			if got != tc.want {
				t.Errorf("ValidateEmail(%q) = %v, want %v", tc.email, got, tc.want)
			}
		})
	}
}

func TestValidatePincode(t *testing.T) {
	tests := []struct {
		name string
		pin  string
		want bool
	}{
		{"valid 6 digits", "560001", true},
		{"valid all zeros", "000000", true},
		{"too short", "56000", false},
		{"too long", "5600011", false},
		{"with letters", "56000a", false},
		{"empty", "", false},
		{"with space", "560 001", false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ValidatePincode(tc.pin)
			if got != tc.want {
				t.Errorf("ValidatePincode(%q) = %v, want %v", tc.pin, got, tc.want)
			}
		})
	}
}

func TestValidateRole(t *testing.T) {
	validRoles := []string{"customer", "restaurant_owner", "delivery_partner", "admin"}
	for _, role := range validRoles {
		t.Run("valid_"+role, func(t *testing.T) {
			if !ValidateRole(role) {
				t.Errorf("ValidateRole(%q) should be true", role)
			}
		})
	}

	invalidRoles := []string{"", "superadmin", "CUSTOMER", "Customer", "user", "manager"}
	for _, role := range invalidRoles {
		t.Run("invalid_"+role, func(t *testing.T) {
			if ValidateRole(role) {
				t.Errorf("ValidateRole(%q) should be false", role)
			}
		})
	}
}

func TestSanitizeString(t *testing.T) {
	tests := []struct {
		name   string
		input  string
		maxLen int
		want   string
	}{
		{"no change needed", "hello", 10, "hello"},
		{"trims whitespace", "  hello  ", 10, "hello"},
		{"truncates", "hello world", 5, "hello"},
		{"trim then truncate", "  hello world  ", 5, "hello"},
		{"empty string", "", 10, ""},
		{"max 0", "hello", 0, ""},
		{"exact length", "hello", 5, "hello"},
		{"unicode characters", "  café  ", 20, "café"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := SanitizeString(tc.input, tc.maxLen)
			if got != tc.want {
				t.Errorf("SanitizeString(%q, %d) = %q, want %q", tc.input, tc.maxLen, got, tc.want)
			}
		})
	}
}

func TestSanitizeString_TrimBeforeTruncate(t *testing.T) {
	// Ensure trimming happens before truncation
	result := SanitizeString("   abc   ", 3)
	if result != "abc" {
		t.Errorf("Expected trim before truncate: got %q", result)
	}
}

func TestSanitizeString_LongString(t *testing.T) {
	long := strings.Repeat("a", 1000)
	result := SanitizeString(long, 100)
	if len(result) != 100 {
		t.Errorf("Expected length 100, got %d", len(result))
	}
}
