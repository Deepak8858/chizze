package utils

import (
	"math"
)

const earthRadiusKm = 6371.0

// Haversine calculates the distance in km between two lat/lng points
func Haversine(lat1, lng1, lat2, lng2 float64) float64 {
	dLat := degreesToRadians(lat2 - lat1)
	dLng := degreesToRadians(lng2 - lng1)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(degreesToRadians(lat1))*math.Cos(degreesToRadians(lat2))*
			math.Sin(dLng/2)*math.Sin(dLng/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return earthRadiusKm * c
}

// EstimateETA estimates delivery time in minutes based on distance.
// Uses a realistic 15 km/h effective speed for two-wheeler deliveries in
// dense Indian cities (accounts for traffic, signals, building access,
// parking, handover). Adds a 10 min pickup buffer so the rider has time to
// reach the restaurant from their current spot. Callers layer prep time
// on top of this travel estimate.
func EstimateETA(distanceKm float64) int {
	minutes := (distanceKm / 15.0) * 60.0
	return int(math.Ceil(minutes)) + 10
}

// BoundingBox returns min/max lat/lng for a center + radius (km)
// Used for efficient nearby queries before haversine refinement
func BoundingBox(lat, lng, radiusKm float64) (minLat, maxLat, minLng, maxLng float64) {
	latDelta := radiusKm / 111.0 // ~111 km per degree latitude
	lngDelta := radiusKm / (111.0 * math.Cos(degreesToRadians(lat)))

	minLat = lat - latDelta
	maxLat = lat + latDelta
	minLng = lng - lngDelta
	maxLng = lng + lngDelta
	return
}

func degreesToRadians(degrees float64) float64 {
	return degrees * math.Pi / 180
}
