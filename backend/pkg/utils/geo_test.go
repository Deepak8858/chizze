package utils

import (
	"math"
	"testing"
)

func almostEqual(a, b, tolerance float64) bool {
	return math.Abs(a-b) < tolerance
}

func TestHaversine_KnownDistances(t *testing.T) {
	tests := []struct {
		name     string
		lat1     float64
		lng1     float64
		lat2     float64
		lng2     float64
		wantKm   float64
		tolerance float64
	}{
		{
			name: "Mumbai to Pune",
			lat1: 19.0760, lng1: 72.8777,
			lat2: 18.5204, lng2: 73.8567,
			wantKm: 120.0, tolerance: 5.0,
		},
		{
			name: "Same point",
			lat1: 12.9716, lng1: 77.5946,
			lat2: 12.9716, lng2: 77.5946,
			wantKm: 0.0, tolerance: 0.001,
		},
		{
			name: "Delhi to Noida (short distance)",
			lat1: 28.6139, lng1: 77.2090,
			lat2: 28.5355, lng2: 77.3910,
			wantKm: 19.0, tolerance: 3.0,
		},
		{
			name: "Bangalore to Chennai",
			lat1: 12.9716, lng1: 77.5946,
			lat2: 13.0827, lng2: 80.2707,
			wantKm: 290.0, tolerance: 10.0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := Haversine(tc.lat1, tc.lng1, tc.lat2, tc.lng2)
			if !almostEqual(got, tc.wantKm, tc.tolerance) {
				t.Errorf("Haversine() = %f, want ~%f (±%f)", got, tc.wantKm, tc.tolerance)
			}
		})
	}
}

func TestHaversine_Symmetry(t *testing.T) {
	d1 := Haversine(19.0760, 72.8777, 18.5204, 73.8567)
	d2 := Haversine(18.5204, 73.8567, 19.0760, 72.8777)
	if !almostEqual(d1, d2, 0.001) {
		t.Errorf("Haversine should be symmetric: %f != %f", d1, d2)
	}
}

func TestHaversine_NonNegative(t *testing.T) {
	d := Haversine(0, 0, -12.3, 45.6)
	if d < 0 {
		t.Errorf("Haversine should be non-negative, got %f", d)
	}
}

func TestEstimateETA(t *testing.T) {
	tests := []struct {
		name       string
		distanceKm float64
		wantMin    int
	}{
		{"zero distance", 0, 5},           // 0 km → just the 5 min buffer
		{"1 km", 1.0, 8},                  // (1/25)*60 = 2.4 → ceil=3 + 5 = 8
		{"5 km", 5.0, 17},                 // (5/25)*60 = 12 → ceil=12 + 5 = 17
		{"10 km", 10.0, 29},               // (10/25)*60 = 24 → ceil=24 + 5 = 29
		{"25 km (1 hour travel)", 25.0, 65}, // (25/25)*60 = 60 + 5 = 65
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := EstimateETA(tc.distanceKm)
			if got != tc.wantMin {
				t.Errorf("EstimateETA(%f) = %d, want %d", tc.distanceKm, got, tc.wantMin)
			}
		})
	}
}

func TestEstimateETA_AlwaysPositive(t *testing.T) {
	got := EstimateETA(0)
	if got < 5 {
		t.Errorf("EstimateETA(0) should be at least 5 (buffer), got %d", got)
	}
}

func TestBoundingBox(t *testing.T) {
	// Bangalore center, 5 km radius
	lat, lng, radius := 12.9716, 77.5946, 5.0
	minLat, maxLat, minLng, maxLng := BoundingBox(lat, lng, radius)

	// Basic sanity checks
	if minLat >= maxLat {
		t.Errorf("minLat (%f) should be less than maxLat (%f)", minLat, maxLat)
	}
	if minLng >= maxLng {
		t.Errorf("minLng (%f) should be less than maxLng (%f)", minLng, maxLng)
	}

	// Center should be inside the bounding box
	if lat < minLat || lat > maxLat {
		t.Errorf("Center latitude %f should be within [%f, %f]", lat, minLat, maxLat)
	}
	if lng < minLng || lng > maxLng {
		t.Errorf("Center longitude %f should be within [%f, %f]", lng, minLng, maxLng)
	}

	// Lat delta should be approximately radiusKm/111
	expectedLatDelta := radius / 111.0
	actualLatDelta := maxLat - lat
	if !almostEqual(actualLatDelta, expectedLatDelta, 0.001) {
		t.Errorf("Lat delta = %f, want ~%f", actualLatDelta, expectedLatDelta)
	}
}

func TestBoundingBox_ZeroRadius(t *testing.T) {
	lat, lng := 28.6139, 77.2090
	minLat, maxLat, minLng, maxLng := BoundingBox(lat, lng, 0)

	if !almostEqual(minLat, lat, 0.0001) || !almostEqual(maxLat, lat, 0.0001) {
		t.Errorf("Zero radius should collapse lat to center: [%f, %f] vs %f", minLat, maxLat, lat)
	}
	if !almostEqual(minLng, lng, 0.0001) || !almostEqual(maxLng, lng, 0.0001) {
		t.Errorf("Zero radius should collapse lng to center: [%f, %f] vs %f", minLng, maxLng, lng)
	}
}
