package utils

import (
	"regexp"
	"strings"
)

var (
	phoneRegex = regexp.MustCompile(`^\+91[6-9]\d{9}$`)
	emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)
	pinRegex   = regexp.MustCompile(`^\d{6}$`)
)

// ValidatePhone validates an Indian phone number
func ValidatePhone(phone string) bool {
	return phoneRegex.MatchString(phone)
}

// ValidateEmail validates an email address
func ValidateEmail(email string) bool {
	return emailRegex.MatchString(email)
}

// ValidatePincode validates a 6-digit Indian pincode
func ValidatePincode(pin string) bool {
	return pinRegex.MatchString(pin)
}

// ValidateRole checks if role is valid
func ValidateRole(role string) bool {
	validRoles := []string{"customer", "restaurant_owner", "delivery_partner", "admin"}
	for _, r := range validRoles {
		if r == role {
			return true
		}
	}
	return false
}

// SanitizeString trims and limits string length
func SanitizeString(s string, maxLen int) string {
	s = strings.TrimSpace(s)
	if len(s) > maxLen {
		return s[:maxLen]
	}
	return s
}
