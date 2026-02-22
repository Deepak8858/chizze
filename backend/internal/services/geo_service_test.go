package services

import (
	"math"
	"testing"
)

func almostEqual(a, b, tolerance float64) bool {
	return math.Abs(a-b) < tolerance
}

func TestGeoService_Distance(t *testing.T) {
	svc := NewGeoService()

	// Mumbai to Pune (~120 km)
	d := svc.Distance(19.0760, 72.8777, 18.5204, 73.8567)
	if !almostEqual(d, 120, 5) {
		t.Errorf("Distance Mumbai→Pune = %.2f, want ~120", d)
	}

	// Same point = 0
	d = svc.Distance(12.9716, 77.5946, 12.9716, 77.5946)
	if d != 0 {
		t.Errorf("Distance same point should be 0, got %.4f", d)
	}
}

func TestGeoService_EstimateDeliveryTime(t *testing.T) {
	svc := NewGeoService()

	tests := []struct {
		name        string
		distanceKm  float64
		prepTimeMin int
		wantMin     int
	}{
		{"short distance, low prep", 2, 10, 20},  // ETA(2) = ceil(2/25*60)+5 = 10, +10 prep = 20
		{"zero distance", 0, 15, 20},               // ETA(0)=5, +15 = 20
		{"5km with 20min prep", 5, 20, 37},          // ETA(5)=17, +20 = 37
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := svc.EstimateDeliveryTime(tc.distanceKm, tc.prepTimeMin)
			if got != tc.wantMin {
				t.Errorf("EstimateDeliveryTime(%.1f, %d) = %d, want %d", tc.distanceKm, tc.prepTimeMin, got, tc.wantMin)
			}
		})
	}
}

func TestGeoService_EstimateDeliveryTime_Additive(t *testing.T) {
	svc := NewGeoService()

	// Prep time should add directly to travel time
	base := svc.EstimateDeliveryTime(5, 0)
	withPrep := svc.EstimateDeliveryTime(5, 10)
	if withPrep != base+10 {
		t.Errorf("Prep time should add directly: base=%d, withPrep=%d, expected %d", base, withPrep, base+10)
	}
}

func TestGeoService_NearbyBounds(t *testing.T) {
	svc := NewGeoService()
	lat, lng, radius := 12.9716, 77.5946, 5.0

	minLat, maxLat, minLng, maxLng := svc.NearbyBounds(lat, lng, radius)

	if minLat >= maxLat {
		t.Errorf("minLat (%f) should be < maxLat (%f)", minLat, maxLat)
	}
	if minLng >= maxLng {
		t.Errorf("minLng (%f) should be < maxLng (%f)", minLng, maxLng)
	}
	if lat < minLat || lat > maxLat {
		t.Errorf("Center lat should be inside bounds")
	}
}
