package services

import (
	"github.com/chizze/backend/pkg/utils"
)

// GeoService handles location-based operations
type GeoService struct{}

// NewGeoService creates a geo service
func NewGeoService() *GeoService {
	return &GeoService{}
}

// Distance calculates km between two points
func (s *GeoService) Distance(lat1, lng1, lat2, lng2 float64) float64 {
	return utils.Haversine(lat1, lng1, lat2, lng2)
}

// EstimateDeliveryTime returns estimated minutes for delivery
func (s *GeoService) EstimateDeliveryTime(distanceKm float64, prepTimeMin int) int {
	travelMin := utils.EstimateETA(distanceKm)
	return prepTimeMin + travelMin
}

// NearbyBounds returns bounding box for geo queries
func (s *GeoService) NearbyBounds(lat, lng, radiusKm float64) (minLat, maxLat, minLng, maxLng float64) {
	return utils.BoundingBox(lat, lng, radiusKm)
}
