package handlers

import (
	"fmt"
	"io"
	"log"
	"math"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/chizze/backend/internal/middleware"
	"github.com/chizze/backend/internal/models"
	"github.com/chizze/backend/internal/services"
	"github.com/chizze/backend/internal/websocket"
	"github.com/chizze/backend/pkg/appwrite"
	redispkg "github.com/chizze/backend/pkg/redis"
	"github.com/chizze/backend/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// AdminHandler handles all /admin/* endpoints
type AdminHandler struct {
	appwrite *services.AppwriteService
	redis    *redispkg.Client
	hub      *websocket.Hub
}

// NewAdminHandler creates an admin handler
func NewAdminHandler(aw *services.AppwriteService, redis *redispkg.Client, hub ...*websocket.Hub) *AdminHandler {
	h := &AdminHandler{appwrite: aw, redis: redis}
	if len(hub) > 0 {
		h.hub = hub[0]
	}
	return h
}

// helper: safely list documents; returns empty list on error (e.g. collection doesn't exist)
func (h *AdminHandler) safeList(collection string, queries []string) ([]map[string]interface{}, int) {
	result, err := h.appwrite.ListDocuments(collection, queries)
	if err != nil || result == nil {
		return []map[string]interface{}{}, 0
	}
	return result.Documents, result.Total
}

func defaultPlatformSettings() gin.H {
	return gin.H{
		"platform_name":                   "Chizze",
		"platform_fee_percentage":         15.0,
		"commission_rate":                 15.0,
		"min_order_amount":                99.0,
		"min_order_value":                 99.0,
		"max_delivery_radius_km":          10.0,
		"delivery_radius":                 10.0,
		"otp_expiry_minutes":              5,
		"razorpay_live_mode":              false,
		"maintenance_mode":                false,
		"gold_subscription_monthly_price": 199.0,
		"gold_subscription_yearly_price":  1999.0,
		"referral_reward_amount":          50.0,
		"referral_min_orders":             1,
		"free_delivery_above_amount":      299.0,
		"support_email":                   "supportchizze@gmail.com",
		"support_phone":                   "7376389133",
		"allow_restaurant_partner_signup": true,
		"allow_delivery_partner_signup":   true,
	}
}

func (h *AdminHandler) listUserIDsByRoles(roles ...string) ([]string, error) {
	const pageSize = 100
	offset := 0
	ids := make([]string, 0)
	seen := make(map[string]struct{})
	allowedRoles := make(map[string]struct{}, len(roles))
	for _, role := range roles {
		normalized := strings.ToLower(strings.TrimSpace(role))
		if normalized != "" {
			allowedRoles[normalized] = struct{}{}
		}
	}

	for {
		result, err := h.appwrite.ListUsers([]string{appwrite.QueryLimit(pageSize), appwrite.QueryOffset(offset)})
		if err != nil {
			return nil, err
		}
		if result == nil || len(result.Documents) == 0 {
			break
		}

		for _, doc := range result.Documents {
			id, _ := doc["$id"].(string)
			if id == "" {
				continue
			}

			if len(allowedRoles) > 0 {
				role := strings.ToLower(strings.TrimSpace(stringFromAny(doc["role"], "")))
				if _, ok := allowedRoles[role]; !ok {
					continue
				}
			}

			if _, exists := seen[id]; exists {
				continue
			}
			seen[id] = struct{}{}
			ids = append(ids, id)
		}

		if len(result.Documents) < pageSize {
			break
		}
		offset += len(result.Documents)
	}

	return ids, nil
}

func (h *AdminHandler) livePresenceByRole() (int, map[string]int) {
	counts := map[string]int{
		"customer":         0,
		"restaurant_owner": 0,
		"delivery_partner": 0,
	}

	if h.hub == nil {
		return 0, counts
	}

	connectedUsers, byRole := h.hub.PresenceSummary()
	counts["customer"] = byRole["customer"]
	counts["restaurant_owner"] = byRole["restaurant_owner"]
	counts["delivery_partner"] = byRole["delivery_partner"]

	appUsers := counts["customer"] + counts["restaurant_owner"] + counts["delivery_partner"]
	if appUsers == 0 {
		appUsers = connectedUsers
	}

	return appUsers, counts
}

func boolFromAny(value interface{}, defaultValue bool) bool {
	switch v := value.(type) {
	case bool:
		return v
	case string:
		parsed, err := strconv.ParseBool(strings.TrimSpace(v))
		if err == nil {
			return parsed
		}
	case float64:
		return v != 0
	case int:
		return v != 0
	}
	return defaultValue
}

func intFromAny(value interface{}, defaultValue int) int {
	switch v := value.(type) {
	case int:
		return v
	case int32:
		return int(v)
	case int64:
		return int(v)
	case float64:
		return int(v)
	case string:
		parsed, err := strconv.Atoi(strings.TrimSpace(v))
		if err == nil {
			return parsed
		}
	}
	return defaultValue
}

func floatFromAny(value interface{}, defaultValue float64) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case float32:
		return float64(v)
	case int:
		return float64(v)
	case int32:
		return float64(v)
	case int64:
		return float64(v)
	case string:
		parsed, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err == nil {
			return parsed
		}
	}
	return defaultValue
}

func stringFromAny(value interface{}, defaultValue string) string {
	if s, ok := value.(string); ok {
		trimmed := strings.TrimSpace(s)
		if trimmed != "" {
			return trimmed
		}
	}
	return defaultValue
}

const (
	defaultStuckOrderMinAgeMinutes = 120
	maxStuckOrderMinAgeMinutes     = 43200
)

var (
	stuckOrderTerminalStatuses = map[string]struct{}{
		models.OrderStatusDelivered: {},
		models.OrderStatusCancelled: {},
	}
	stuckOrderBlockedStatuses = map[string]struct{}{
		models.OrderStatusPlaced:         {},
		models.OrderStatusConfirmed:      {},
		models.OrderStatusPreparing:      {},
		models.OrderStatusReady:          {},
		models.OrderStatusPickedUp:       {},
		models.OrderStatusOutForDelivery: {},
	}
)

func parseCleanupCSV(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func canonicalOrderStatus(raw string) string {
	normalized := strings.ToLower(strings.TrimSpace(raw))
	normalized = strings.ReplaceAll(normalized, "_", "")
	normalized = strings.ReplaceAll(normalized, "-", "")
	normalized = strings.ReplaceAll(normalized, " ", "")

	switch normalized {
	case "placed":
		return models.OrderStatusPlaced
	case "confirmed":
		return models.OrderStatusConfirmed
	case "preparing":
		return models.OrderStatusPreparing
	case "ready":
		return models.OrderStatusReady
	case "pickedup":
		return models.OrderStatusPickedUp
	case "outfordelivery":
		return models.OrderStatusOutForDelivery
	case "delivered":
		return models.OrderStatusDelivered
	case "cancelled", "canceled":
		return models.OrderStatusCancelled
	default:
		return ""
	}
}

func uniqueSortedStatuses(values []string) []string {
	if len(values) == 0 {
		return nil
	}
	uniq := make(map[string]struct{}, len(values))
	for _, value := range values {
		if value == "" {
			continue
		}
		uniq[value] = struct{}{}
	}
	out := make([]string, 0, len(uniq))
	for value := range uniq {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func normalizeStuckOrderStatuses(raw string) (requested, effective, blocked, ignored []string) {
	requestedRaw := parseCleanupCSV(raw)
	if len(requestedRaw) == 0 {
		effective = []string{models.OrderStatusCancelled, models.OrderStatusDelivered}
		requested = append([]string{}, effective...)
		sort.Strings(effective)
		sort.Strings(requested)
		return requested, effective, nil, nil
	}

	for _, value := range requestedRaw {
		canonical := canonicalOrderStatus(value)
		if canonical == "" {
			ignored = append(ignored, strings.TrimSpace(value))
			continue
		}

		requested = append(requested, canonical)
		if _, ok := stuckOrderTerminalStatuses[canonical]; ok {
			effective = append(effective, canonical)
			continue
		}
		if _, ok := stuckOrderBlockedStatuses[canonical]; ok {
			blocked = append(blocked, canonical)
			continue
		}
		ignored = append(ignored, canonical)
	}

	return uniqueSortedStatuses(requested), uniqueSortedStatuses(effective), uniqueSortedStatuses(blocked), uniqueSortedStatuses(ignored)
}

func parseCleanupMinAgeMinutes(raw string) int {
	if strings.TrimSpace(raw) == "" {
		return defaultStuckOrderMinAgeMinutes
	}
	parsed, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || parsed <= 0 {
		return defaultStuckOrderMinAgeMinutes
	}
	if parsed > maxStuckOrderMinAgeMinutes {
		return maxStuckOrderMinAgeMinutes
	}
	return parsed
}

func buildStuckOrderQueries(statuses []string, cutoff time.Time, p models.Pagination) []string {
	statusValues := make([]interface{}, 0, len(statuses))
	for _, status := range statuses {
		statusValues = append(statusValues, status)
	}

	return []string{
		appwrite.QueryEqual("status", statusValues...),
		appwrite.QueryLessThan("placed_at", cutoff.UTC().Format(time.RFC3339)),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	}
}

func parseBannerTime(value interface{}) (time.Time, bool) {
	s, ok := value.(string)
	if !ok || strings.TrimSpace(s) == "" {
		return time.Time{}, false
	}
	layouts := []string{time.RFC3339, "2006-01-02", "2006-01-02 15:04:05"}
	for _, layout := range layouts {
		if parsed, err := time.Parse(layout, s); err == nil {
			return parsed.UTC(), true
		}
	}
	return time.Time{}, false
}

func bannerSegmentAllowed(segment, role string, isGoldMember, isNewUser bool) bool {
	s := strings.ToLower(strings.TrimSpace(segment))
	switch s {
	case "", "all":
		return true
	case "customers":
		return role == "customer"
	case "gold_members":
		return role == "customer" && isGoldMember
	case "new_users":
		return role == "customer" && isNewUser
	case "all_riders", "delivery_partners", "riders":
		return role == "delivery_partner"
	case "all_restaurants", "restaurants", "restaurant_owners":
		return role == "restaurant_owner"
	default:
		// Keep unknown segments visible to avoid accidental content loss.
		return true
	}
}

func floatAliasFromMap(values map[string]interface{}, primary, legacy string, defaultValue float64) (float64, bool) {
	if v, ok := values[primary]; ok {
		return floatFromAny(v, defaultValue), true
	}
	if v, ok := values[legacy]; ok {
		return floatFromAny(v, defaultValue), true
	}
	return defaultValue, false
}

func normalizedSettingsResponse(doc map[string]interface{}) gin.H {
	defaults := defaultPlatformSettings()
	res := gin.H{}

	for k, v := range doc {
		res[k] = v
	}

	platformName := stringFromAny(doc["platform_name"], stringFromAny(defaults["platform_name"], "Chizze"))
	supportEmail := stringFromAny(doc["support_email"], stringFromAny(defaults["support_email"], "supportchizze@gmail.com"))
	supportPhone := stringFromAny(doc["support_phone"], stringFromAny(defaults["support_phone"], "7376389133"))
	if supportEmail == "support@chizze.app" {
		supportEmail = "supportchizze@gmail.com"
	}
	if supportPhone == "+919876543210" {
		supportPhone = "7376389133"
	}

	fee, _ := floatAliasFromMap(doc, "platform_fee_percentage", "commission_rate", floatFromAny(defaults["platform_fee_percentage"], 15))
	minOrder, _ := floatAliasFromMap(doc, "min_order_amount", "min_order_value", floatFromAny(defaults["min_order_amount"], 99))
	maxRadius, _ := floatAliasFromMap(doc, "max_delivery_radius_km", "delivery_radius", floatFromAny(defaults["max_delivery_radius_km"], 10))

	res["platform_name"] = platformName
	res["support_email"] = supportEmail
	res["support_phone"] = supportPhone

	res["platform_fee_percentage"] = fee
	res["commission_rate"] = fee
	res["min_order_amount"] = minOrder
	res["min_order_value"] = minOrder
	res["max_delivery_radius_km"] = maxRadius
	res["delivery_radius"] = maxRadius

	res["otp_expiry_minutes"] = intFromAny(doc["otp_expiry_minutes"], intFromAny(defaults["otp_expiry_minutes"], 5))
	res["gold_subscription_monthly_price"] = floatFromAny(doc["gold_subscription_monthly_price"], floatFromAny(defaults["gold_subscription_monthly_price"], 199))
	res["gold_subscription_yearly_price"] = floatFromAny(doc["gold_subscription_yearly_price"], floatFromAny(defaults["gold_subscription_yearly_price"], 1999))
	res["referral_reward_amount"] = floatFromAny(doc["referral_reward_amount"], floatFromAny(defaults["referral_reward_amount"], 50))
	res["referral_min_orders"] = intFromAny(doc["referral_min_orders"], intFromAny(defaults["referral_min_orders"], 1))
	res["free_delivery_above_amount"] = floatFromAny(doc["free_delivery_above_amount"], floatFromAny(defaults["free_delivery_above_amount"], 299))

	res["razorpay_live_mode"] = boolFromAny(doc["razorpay_live_mode"], boolFromAny(defaults["razorpay_live_mode"], false))
	res["maintenance_mode"] = boolFromAny(doc["maintenance_mode"], boolFromAny(defaults["maintenance_mode"], false))
	res["allow_restaurant_partner_signup"] = boolFromAny(doc["allow_restaurant_partner_signup"], boolFromAny(defaults["allow_restaurant_partner_signup"], true))
	res["allow_delivery_partner_signup"] = boolFromAny(doc["allow_delivery_partner_signup"], boolFromAny(defaults["allow_delivery_partner_signup"], true))

	return res
}

func normalizeSettingsWritePayload(body map[string]interface{}) map[string]interface{} {
	payload := map[string]interface{}{}
	if len(body) == 0 {
		return payload
	}

	if v, ok := body["platform_name"]; ok {
		payload["platform_name"] = stringFromAny(v, "Chizze")
	}
	if v, ok := body["support_email"]; ok {
		payload["support_email"] = stringFromAny(v, "supportchizze@gmail.com")
	}
	if v, ok := body["support_phone"]; ok {
		payload["support_phone"] = stringFromAny(v, "7376389133")
	}

	if fee, ok := floatAliasFromMap(body, "platform_fee_percentage", "commission_rate", 15); ok {
		payload["platform_fee_percentage"] = fee
		payload["commission_rate"] = fee
	}
	if minOrder, ok := floatAliasFromMap(body, "min_order_amount", "min_order_value", 99); ok {
		payload["min_order_amount"] = minOrder
		payload["min_order_value"] = minOrder
	}
	if maxRadius, ok := floatAliasFromMap(body, "max_delivery_radius_km", "delivery_radius", 10); ok {
		payload["max_delivery_radius_km"] = maxRadius
		payload["delivery_radius"] = maxRadius
	}

	if v, ok := body["otp_expiry_minutes"]; ok {
		payload["otp_expiry_minutes"] = intFromAny(v, 5)
	}
	if v, ok := body["gold_subscription_monthly_price"]; ok {
		payload["gold_subscription_monthly_price"] = floatFromAny(v, 199)
	}
	if v, ok := body["gold_subscription_yearly_price"]; ok {
		payload["gold_subscription_yearly_price"] = floatFromAny(v, 1999)
	}
	if v, ok := body["referral_reward_amount"]; ok {
		payload["referral_reward_amount"] = floatFromAny(v, 50)
	}
	if v, ok := body["referral_min_orders"]; ok {
		payload["referral_min_orders"] = intFromAny(v, 1)
	}
	if v, ok := body["free_delivery_above_amount"]; ok {
		payload["free_delivery_above_amount"] = floatFromAny(v, 299)
	}

	if v, ok := body["razorpay_live_mode"]; ok {
		payload["razorpay_live_mode"] = boolFromAny(v, false)
	}
	if v, ok := body["maintenance_mode"]; ok {
		payload["maintenance_mode"] = boolFromAny(v, false)
	}
	if v, ok := body["allow_restaurant_partner_signup"]; ok {
		payload["allow_restaurant_partner_signup"] = boolFromAny(v, true)
	}
	if v, ok := body["allow_delivery_partner_signup"]; ok {
		payload["allow_delivery_partner_signup"] = boolFromAny(v, true)
	}

	return payload
}

func withIntegerNumericSettings(payload map[string]interface{}) map[string]interface{} {
	if len(payload) == 0 {
		return payload
	}

	converted := map[string]interface{}{}
	for k, v := range payload {
		converted[k] = v
	}

	integerLikeKeys := []string{
		"platform_fee_percentage",
		"commission_rate",
		"min_order_amount",
		"min_order_value",
		"max_delivery_radius_km",
		"delivery_radius",
		"otp_expiry_minutes",
		"gold_subscription_monthly_price",
		"gold_subscription_yearly_price",
		"referral_reward_amount",
		"referral_min_orders",
		"free_delivery_above_amount",
	}

	for _, key := range integerLikeKeys {
		value, exists := converted[key]
		if !exists {
			continue
		}

		switch n := value.(type) {
		case float64:
			if math.Trunc(n) == n {
				converted[key] = int(n)
			}
		case float32:
			nv := float64(n)
			if math.Trunc(nv) == nv {
				converted[key] = int(nv)
			}
		case string:
			if parsed, err := strconv.Atoi(strings.TrimSpace(n)); err == nil {
				converted[key] = parsed
			}
		}
	}

	return converted
}

func filterPayloadByExistingKeys(payload map[string]interface{}, existing map[string]interface{}) map[string]interface{} {
	if len(existing) == 0 {
		return payload
	}
	filtered := map[string]interface{}{}
	for k, v := range payload {
		if _, ok := existing[k]; ok {
			filtered[k] = v
		}
	}
	return filtered
}

func legacySettingsPayload(values map[string]interface{}) map[string]interface{} {
	legacy := map[string]interface{}{}

	if v, ok := values["platform_name"]; ok {
		legacy["platform_name"] = v
	}
	if v, ok := values["commission_rate"]; ok {
		legacy["commission_rate"] = v
	} else if v, ok := values["platform_fee_percentage"]; ok {
		legacy["commission_rate"] = v
	}
	if v, ok := values["min_order_value"]; ok {
		legacy["min_order_value"] = v
	} else if v, ok := values["min_order_amount"]; ok {
		legacy["min_order_value"] = v
	}
	if v, ok := values["delivery_radius"]; ok {
		legacy["delivery_radius"] = v
	} else if v, ok := values["max_delivery_radius_km"]; ok {
		legacy["delivery_radius"] = v
	}
	if v, ok := values["support_email"]; ok {
		legacy["support_email"] = v
	}
	if v, ok := values["support_phone"]; ok {
		legacy["support_phone"] = v
	}
	if v, ok := values["maintenance_mode"]; ok {
		legacy["maintenance_mode"] = v
	}
	if v, ok := values["razorpay_live_mode"]; ok {
		legacy["razorpay_live_mode"] = v
	}

	return legacy
}

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) Dashboard(c *gin.Context) {
	now := time.Now()

	// --- Counts ---
	users, _ := h.appwrite.ListUsers([]string{appwrite.QueryLimit(1)})
	restaurants, _ := h.appwrite.ListRestaurants([]string{appwrite.QueryLimit(1)})
	allOrders, _ := h.appwrite.ListOrders([]string{appwrite.QueryLimit(1)})
	partners, _ := h.appwrite.ListDeliveryPartners([]string{appwrite.QueryLimit(1)})

	totalUsers := 0
	totalRestaurants := 0
	totalOrders := 0
	totalPartners := 0
	if users != nil {
		totalUsers = users.Total
	}
	if restaurants != nil {
		totalRestaurants = restaurants.Total
	}
	if allOrders != nil {
		totalOrders = allOrders.Total
	}
	if partners != nil {
		totalPartners = partners.Total
	}

	// --- Today boundaries ---
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).Format(time.RFC3339)

	todayOrdResult, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryGreaterThanEqual("placed_at", todayStart),
		appwrite.QueryLimit(500),
	})
	ordersToday := 0
	revenuToday := 0.0
	if todayOrdResult != nil {
		ordersToday = todayOrdResult.Total
		for _, o := range todayOrdResult.Documents {
			if status, _ := o["status"].(string); status == "delivered" {
				if gt, ok := o["grand_total"].(float64); ok {
					revenuToday += gt
				}
			}
		}
	}

	newUsersRes, _ := h.appwrite.ListUsers([]string{
		appwrite.QueryGreaterThanEqual("$createdAt", todayStart),
		appwrite.QueryLimit(1),
	})
	newUsersTodayCount := 0
	if newUsersRes != nil {
		newUsersTodayCount = newUsersRes.Total
	}

	onlineRest, _ := h.appwrite.ListRestaurants([]string{
		appwrite.QueryEqual("is_online", true), appwrite.QueryLimit(1),
	})
	onlineRestCount := 0
	if onlineRest != nil {
		onlineRestCount = onlineRest.Total
	}

	onlineRiders, _ := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("is_online", true), appwrite.QueryLimit(1),
	})
	onlineRidersCount := 0
	if onlineRiders != nil {
		onlineRidersCount = onlineRiders.Total
	}

	activeOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered", "cancelled"),
		appwrite.QueryLimit(1),
	})
	totalActive := 0
	if activeOrders != nil {
		totalActive = activeOrders.Total
	}

	// --- 30-day revenue chart ---
	thirtyDaysAgo := now.AddDate(0, 0, -30).Format(time.RFC3339)
	revenueOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryGreaterThanEqual("placed_at", thirtyDaysAgo),
		appwrite.QueryLimit(500),
	})
	var totalRevenue float64
	dailyRevenue := map[string]float64{}
	dailyOrderCount := map[string]int{}
	if revenueOrders != nil {
		for _, o := range revenueOrders.Documents {
			if gt, ok := o["grand_total"].(float64); ok {
				totalRevenue += gt
				if placedAt, ok := o["placed_at"].(string); ok && len(placedAt) >= 10 {
					day := placedAt[:10]
					dailyRevenue[day] += gt
					dailyOrderCount[day]++
				}
			}
		}
	}
	revenueChart := make([]gin.H, 0, 30)
	for i := 29; i >= 0; i-- {
		day := now.AddDate(0, 0, -i).Format("2006-01-02")
		revenueChart = append(revenueChart, gin.H{
			"date":    day,
			"revenue": dailyRevenue[day],
			"orders":  dailyOrderCount[day],
		})
	}

	// --- Status chart + recent orders ---
	allRecentOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(200),
	})
	statusCounts := map[string]int{}
	recentOrdersList := []map[string]interface{}{}
	if allRecentOrders != nil {
		for _, o := range allRecentOrders.Documents {
			if status, _ := o["status"].(string); status != "" {
				statusCounts[status]++
			}
		}
		limit := 20
		if len(allRecentOrders.Documents) < limit {
			limit = len(allRecentOrders.Documents)
		}
		recentOrdersList = allRecentOrders.Documents[:limit]
	}
	statusChart := []gin.H{}
	for status, count := range statusCounts {
		statusChart = append(statusChart, gin.H{"status": status, "count": count})
	}

	utils.Success(c, gin.H{
		"stats": gin.H{
			"total_users":        totalUsers,
			"total_restaurants":  totalRestaurants,
			"total_orders":       totalOrders,
			"total_partners":     totalPartners,
			"total_revenue":      totalRevenue,
			"active_orders":      totalActive,
			"orders_today":       ordersToday,
			"revenue_today":      revenuToday,
			"new_users_today":    newUsersTodayCount,
			"online_restaurants": onlineRestCount,
			"online_riders":      onlineRidersCount,
		},
		"revenue_chart": revenueChart,
		"status_chart":  statusChart,
		"recent_orders": recentOrdersList,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANALYTICS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) Analytics(c *gin.Context) {
	now := time.Now()
	period := c.DefaultQuery("period", "month")
	var days int
	switch period {
	case "day":
		days = 1
	case "week":
		days = 7
	default:
		days = 30
	}
	since := now.AddDate(0, 0, -days).Format(time.RFC3339)

	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryGreaterThanEqual("placed_at", since),
		appwrite.QueryLimit(500),
	})

	var revenue float64
	delivered := 0
	cancelled := 0
	dailyRevenue := map[string]float64{}
	dailyOrderCount := map[string]int{}
	if orders != nil {
		for _, o := range orders.Documents {
			status, _ := o["status"].(string)
			if status == "delivered" {
				delivered++
				if gt, ok := o["grand_total"].(float64); ok {
					revenue += gt
					if placedAt, ok := o["placed_at"].(string); ok && len(placedAt) >= 10 {
						day := placedAt[:10]
						dailyRevenue[day] += gt
						dailyOrderCount[day]++
					}
				}
			} else if status == "cancelled" {
				cancelled++
			}
		}
	}

	totalOrders := 0
	if orders != nil {
		totalOrders = orders.Total
	}

	revenueChart := make([]gin.H, 0, days)
	for i := days - 1; i >= 0; i-- {
		day := now.AddDate(0, 0, -i).Format("2006-01-02")
		revenueChart = append(revenueChart, gin.H{
			"date":    day,
			"revenue": dailyRevenue[day],
			"orders":  dailyOrderCount[day],
		})
	}

	utils.Success(c, gin.H{
		"period":       period,
		"total_orders": totalOrders,
		"delivered":    delivered,
		"cancelled":    cancelled,
		"revenue":      revenue,
		"avg_order_value": func() float64 {
			if delivered > 0 {
				return revenue / float64(delivered)
			}
			return 0
		}(),
		"revenue_chart": revenueChart,
	})
}

func (h *AdminHandler) AnalyticsSLA(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryOrderDesc("delivered_at"),
		appwrite.QueryLimit(200),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) AnalyticsItems(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryLimit(500),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) AnalyticsCities(c *gin.Context) {
	restaurants, _ := h.appwrite.ListRestaurants([]string{appwrite.QueryLimit(500)})
	cityCount := map[string]int{}
	if restaurants != nil {
		for _, r := range restaurants.Documents {
			city, _ := r["city"].(string)
			if city != "" {
				cityCount[city]++
			}
		}
	}
	result := []gin.H{}
	for city, count := range cityCount {
		result = append(result, gin.H{"city": city, "count": count})
	}
	utils.Success(c, result)
}

func (h *AdminHandler) AnalyticsRetention(c *gin.Context) {
	// Return basic retention data from users
	users, _ := h.appwrite.ListUsers([]string{appwrite.QueryLimit(1)})
	total := 0
	if users != nil {
		total = users.Total
	}
	utils.Success(c, gin.H{"total_users": total, "retention_rate": 0.75})
}

func (h *AdminHandler) AnalyticsRevenue(c *gin.Context) {
	now := time.Now()
	rangeParam := c.DefaultQuery("range", "30d")
	var days int
	switch rangeParam {
	case "7d":
		days = 7
	case "90d":
		days = 90
	case "1y":
		days = 365
	default:
		days = 30
	}
	since := now.AddDate(0, 0, -days).Format(time.RFC3339)

	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryGreaterThanEqual("placed_at", since),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(1000),
	})

	dailyRevenue := map[string]float64{}
	dailyCount := map[string]int{}
	if orders != nil {
		for _, o := range orders.Documents {
			if gt, ok := o["grand_total"].(float64); ok {
				if placedAt, ok := o["placed_at"].(string); ok && len(placedAt) >= 10 {
					day := placedAt[:10]
					dailyRevenue[day] += gt
					dailyCount[day]++
				}
			}
		}
	}

	chart := make([]gin.H, 0, days)
	for i := days - 1; i >= 0; i-- {
		day := now.AddDate(0, 0, -i).Format("2006-01-02")
		rev := dailyRevenue[day]
		ord := dailyCount[day]
		avgOrd := 0.0
		if ord > 0 {
			avgOrd = rev / float64(ord)
		}
		chart = append(chart, gin.H{
			"date":      day,
			"revenue":   rev,
			"orders":    ord,
			"avg_order": avgOrd,
		})
	}
	utils.Success(c, chart)
}

func (h *AdminHandler) ReportsFinancial(c *gin.Context) {
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "delivered"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(500),
	})
	docs := []map[string]interface{}{}
	if orders != nil {
		docs = orders.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) ReportsCancellations(c *gin.Context) {
	p := models.ParsePagination(c)
	orders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryEqual("status", "cancelled"),
		appwrite.QueryOrderDesc("cancelled_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	docs := []map[string]interface{}{}
	total := 0
	if orders != nil {
		docs = orders.Documents
		total = orders.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) Leaderboards(c *gin.Context) {
	// Top restaurants by rating
	restaurants, _ := h.appwrite.ListRestaurants([]string{
		appwrite.QueryOrderDesc("rating"),
		appwrite.QueryLimit(20),
	})
	docs := []map[string]interface{}{}
	if restaurants != nil {
		docs = restaurants.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// USERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListUsers(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if role := c.Query("role"); role != "" {
		queries = append(queries, appwrite.QueryEqual("role", role))
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("name", search))
	}
	result, err := h.appwrite.ListUsers(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list users")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	user, err := h.appwrite.GetUser(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "User not found")
		return
	}
	utils.Success(c, user)
}

func (h *AdminHandler) UpdateUser(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateUser(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update user")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	if err := h.appwrite.DeleteUser(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete user")
		return
	}
	utils.Success(c, gin.H{"message": "User deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESTAURANTS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListRestaurants(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("name", search))
	}
	result, err := h.appwrite.ListRestaurants(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list restaurants")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) PendingRestaurants(c *gin.Context) {
	result, err := h.appwrite.ListRestaurants([]string{
		appwrite.QueryEqual("is_online", false),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list pending restaurants")
		return
	}
	utils.Success(c, result.Documents)
}

func (h *AdminHandler) GetRestaurant(c *gin.Context) {
	doc, err := h.appwrite.GetRestaurant(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Restaurant not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) GetRestaurantMenu(c *gin.Context) {
	result, err := h.appwrite.ListMenuItems(c.Param("id"))
	if err != nil {
		utils.InternalError(c, "Failed to get menu")
		return
	}
	utils.Success(c, result.Documents)
}

func (h *AdminHandler) UpdateRestaurant(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ApproveRestaurant(c *gin.Context) {
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), map[string]interface{}{"is_online": true})
	if err != nil {
		utils.InternalError(c, "Failed to approve restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) RejectRestaurant(c *gin.Context) {
	var body struct {
		Reason string `json:"reason"`
	}
	c.ShouldBindJSON(&body)
	doc, err := h.appwrite.UpdateRestaurant(c.Param("id"), map[string]interface{}{"is_online": false})
	if err != nil {
		utils.InternalError(c, "Failed to reject restaurant")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteRestaurant(c *gin.Context) {
	if err := h.appwrite.DeleteRestaurant(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete restaurant")
		return
	}
	utils.Success(c, gin.H{"message": "Restaurant deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// ORDERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListOrders(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("placed_at"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("order_number", search))
	}
	result, err := h.appwrite.ListOrders(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list orders")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) PreviewStuckOrders(c *gin.Context) {
	p := models.ParsePagination(c)
	requested, effective, blocked, ignored := normalizeStuckOrderStatuses(c.Query("statuses"))
	minAgeMinutes := parseCleanupMinAgeMinutes(c.Query("min_age_minutes"))
	cutoff := time.Now().UTC().Add(-time.Duration(minAgeMinutes) * time.Minute)

	orders := []map[string]interface{}{}
	total := 0
	if len(effective) > 0 {
		queries := buildStuckOrderQueries(effective, cutoff, p)
		result, err := h.appwrite.ListOrders(queries)
		if err != nil {
			utils.InternalError(c, "Failed to preview stuck orders")
			return
		}
		if result != nil {
			orders = result.Documents
			total = result.Total
		}
	}

	utils.Success(c, gin.H{
		"orders":          orders,
		"eligible_count":  total,
		"blocked_count":   len(blocked),
		"min_age_minutes": minAgeMinutes,
		"cutoff_time":     cutoff.Format(time.RFC3339),
		"filters": gin.H{
			"requested_statuses": requested,
			"effective_statuses": effective,
			"blocked_statuses":   blocked,
			"ignored_statuses":   ignored,
		},
		"pagination": gin.H{
			"page":     p.Page,
			"per_page": p.PerPage,
			"total":    total,
		},
	})
}

func (h *AdminHandler) GetOrder(c *gin.Context) {
	doc, err := h.appwrite.GetOrder(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Order not found")
		return
	}

	customerID := stringFromAny(doc["customer_id"], "")
	if customerID != "" {
		user, userErr := h.appwrite.GetUser(customerID)
		if userErr == nil && user != nil {
			if name := stringFromAny(user["name"], ""); name != "" {
				doc["customer_name"] = name
			}
			if phone := stringFromAny(user["phone"], ""); phone != "" {
				doc["customer_phone"] = phone
			}
			if email := stringFromAny(user["email"], ""); email != "" {
				doc["customer_email"] = email
			}
		}
	}

	addressID := stringFromAny(doc["delivery_address_id"], "")
	if addressID != "" {
		address, addressErr := h.appwrite.GetAddress(addressID)
		if addressErr == nil && address != nil {
			if line := stringFromAny(address["full_address"], stringFromAny(address["address"], "")); line != "" {
				doc["delivery_address_line"] = line
			}
			if city := stringFromAny(address["city"], ""); city != "" {
				doc["delivery_city"] = city
			}

			if lat, ok := address["latitude"]; ok {
				doc["delivery_latitude"] = floatFromAny(lat, 0)
			} else if lat, ok := address["lat"]; ok {
				doc["delivery_latitude"] = floatFromAny(lat, 0)
			}

			if lng, ok := address["longitude"]; ok {
				doc["delivery_longitude"] = floatFromAny(lng, 0)
			} else if lng, ok := address["lng"]; ok {
				doc["delivery_longitude"] = floatFromAny(lng, 0)
			}
		}
	}

	utils.Success(c, doc)
}

func (h *AdminHandler) ActiveOrders(c *gin.Context) {
	p := models.ParsePagination(c)
	result, err := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered", "cancelled"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list active orders")
		return
	}
	docs := []map[string]interface{}{}
	total := 0
	if result != nil {
		docs = result.Documents
		total = result.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) CancelOrder(c *gin.Context) {
	var body struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Cancellation reason is required")
		return
	}
	adminID := middleware.GetUserID(c)
	doc, err := h.appwrite.UpdateOrder(c.Param("id"), map[string]interface{}{
		"status":              "cancelled",
		"cancellation_reason": body.Reason,
		"cancelled_by":        adminID,
		"cancelled_at":        time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to cancel order")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ReassignOrder(c *gin.Context) {
	var body struct {
		RiderID string `json:"rider_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Rider ID is required")
		return
	}
	doc, err := h.appwrite.UpdateOrder(c.Param("id"), map[string]interface{}{
		"delivery_partner_id": body.RiderID,
	})
	if err != nil {
		utils.InternalError(c, "Failed to reassign order")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELIVERY PARTNERS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListDeliveryPartners(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if search := c.Query("search"); search != "" {
		queries = append(queries, appwrite.QuerySearch("vehicle_number", search))
	}
	result, err := h.appwrite.ListDeliveryPartners(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list delivery partners")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) PendingDeliveryPartners(c *gin.Context) {
	result, err := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("documents_verified", false),
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list pending partners")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

func (h *AdminHandler) GetDeliveryPartner(c *gin.Context) {
	doc, err := h.appwrite.Client().GetDocument(models.CollectionDeliveryPartners, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Delivery partner not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateDeliveryPartner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryPartner(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update delivery partner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) VerifyDeliveryPartner(c *gin.Context) {
	var body struct {
		Approved bool   `json:"approved"`
		Reason   string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryPartner(c.Param("id"), map[string]interface{}{
		"documents_verified": body.Approved,
	})
	if err != nil {
		utils.InternalError(c, "Failed to verify delivery partner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeliveryPartnerPayouts(c *gin.Context) {
	result, err := h.appwrite.ListPayouts([]string{
		appwrite.QueryEqual("partner_id", c.Param("id")),
		appwrite.QueryOrderDesc("created_at"),
		appwrite.QueryLimit(50),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list payouts")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAYOUTS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListPayouts(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("created_at"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	result, err := h.appwrite.ListPayouts(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list payouts")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) UpdatePayout(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdatePayout(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update payout")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// COUPONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListCoupons(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	result, err := h.appwrite.ListCoupons(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list coupons")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) CreateCoupon(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("cpn_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateCoupon(id, body)
	if err != nil {
		utils.InternalError(c, "Failed to create coupon")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateCoupon(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateCoupon(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update coupon")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteCoupon(c *gin.Context) {
	if err := h.appwrite.DeleteCoupon(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete coupon")
		return
	}
	utils.Success(c, gin.H{"message": "Coupon deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// REVIEWS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListReviews(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("created_at"),
	}
	result, err := h.appwrite.ListReviewsByQuery(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list reviews")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) UpdateReview(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateReview(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update review")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteReview(c *gin.Context) {
	if err := h.appwrite.DeleteReview(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete review")
		return
	}
	utils.Success(c, gin.H{"message": "Review deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// GOLD SUBSCRIPTIONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListGoldSubscriptions(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	if status := c.Query("status"); status != "" {
		queries = append(queries, appwrite.QueryEqual("status", status))
	}
	result, err := h.appwrite.ListAllGoldSubscriptions(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list gold subscriptions")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) GoldStats(c *gin.Context) {
	active, _ := h.appwrite.ListAllGoldSubscriptions([]string{
		appwrite.QueryEqual("status", "active"),
		appwrite.QueryLimit(1),
	})
	all, _ := h.appwrite.ListAllGoldSubscriptions([]string{
		appwrite.QueryLimit(1),
	})
	totalActive := 0
	totalAll := 0
	if active != nil {
		totalActive = active.Total
	}
	if all != nil {
		totalAll = all.Total
	}
	utils.Success(c, gin.H{
		"total_subscriptions": totalAll,
		"active":              totalActive,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// REFERRALS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListReferrals(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
		appwrite.QueryOrderDesc("$createdAt"),
	}
	result, err := h.appwrite.ListAllReferrals(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list referrals")
		return
	}
	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

func (h *AdminHandler) ReferralStats(c *gin.Context) {
	all, _ := h.appwrite.ListAllReferrals([]string{appwrite.QueryLimit(1)})
	completed, _ := h.appwrite.ListAllReferrals([]string{
		appwrite.QueryEqual("status", "completed"),
		appwrite.QueryLimit(1),
	})
	totalAll := 0
	totalCompleted := 0
	if all != nil {
		totalAll = all.Total
	}
	if completed != nil {
		totalCompleted = completed.Total
	}
	utils.Success(c, gin.H{
		"total_referrals":     totalAll,
		"completed_referrals": totalCompleted,
	})
}

// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATIONS
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) BroadcastNotification(c *gin.Context) {
	var body struct {
		Title      string `json:"title" binding:"required"`
		Body       string `json:"body" binding:"required"`
		Type       string `json:"type"`
		TargetType string `json:"target_type"`
		TargetID   string `json:"target_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Title and body are required")
		return
	}

	nType := body.Type
	if nType == "" {
		nType = "system"
	}

	targetType := strings.TrimSpace(body.TargetType)
	if targetType == "" {
		targetType = "all_users"
	}

	var (
		targetUserIDs []string
		err           error
	)

	switch targetType {
	case "all_users":
		targetUserIDs, err = h.listUserIDsByRoles("customer", "restaurant_owner", "delivery_partner")
	case "all_riders":
		targetUserIDs, err = h.listUserIDsByRoles("delivery_partner")
	case "all_restaurants":
		targetUserIDs, err = h.listUserIDsByRoles("restaurant_owner")
	case "all_customers":
		targetUserIDs, err = h.listUserIDsByRoles("customer")
	case "specific_user":
		targetID := strings.TrimSpace(body.TargetID)
		if targetID == "" {
			utils.BadRequest(c, "target_id is required for specific_user")
			return
		}
		targetUserIDs = []string{targetID}
	default:
		utils.BadRequest(c, "Unsupported target_type")
		return
	}
	if err != nil {
		log.Printf("BroadcastNotification list targets failed: %v", err)
		utils.InternalError(c, "Failed to resolve recipients")
		return
	}

	if len(targetUserIDs) == 0 {
		utils.Success(c, gin.H{
			"message":     "No recipients matched the selected target",
			"target_type": targetType,
			"recipients":  0,
		})
		return
	}

	var (
		firstDoc    map[string]interface{}
		delivered   int
		broadcaster *websocket.EventBroadcaster
	)
	if h.hub != nil {
		broadcaster = websocket.NewEventBroadcaster(h.hub)
	}

	workerCount := 20
	if len(targetUserIDs) < workerCount {
		workerCount = len(targetUserIDs)
	}

	jobs := make(chan string, workerCount)
	var (
		mu sync.Mutex
		wg sync.WaitGroup
	)

	sendToUser := func(userID string) {
		id := fmt.Sprintf("notif_%s", uuid.New().String()[:8])
		doc, createErr := h.appwrite.CreateNotification(id, map[string]interface{}{
			"user_id":    userID,
			"type":       nType,
			"title":      body.Title,
			"body":       body.Body,
			"is_read":    false,
		})
		if createErr != nil {
			log.Printf("BroadcastNotification create failed for user %s: %v", userID, createErr)
			return
		}

		if broadcaster != nil {
			broadcaster.BroadcastNotification(userID, body.Title, body.Body, nType)
		}

		mu.Lock()
		delivered++
		if firstDoc == nil {
			firstDoc = doc
		}
		mu.Unlock()
	}

	for i := 0; i < workerCount; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for userID := range jobs {
				sendToUser(userID)
			}
		}()
	}

	for _, userID := range targetUserIDs {
		jobs <- userID
	}
	close(jobs)
	wg.Wait()

	if delivered == 0 {
		utils.InternalError(c, "Failed to send notification")
		return
	}

	utils.Success(c, gin.H{
		"message":      "Notification sent",
		"target_type":  targetType,
		"requested":    len(targetUserIDs),
		"delivered":    delivered,
		"notification": firstDoc,
	})
}

func (h *AdminHandler) NotificationHistory(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	}
	result, err := h.appwrite.ListAllNotifications(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list notifications")
		return
	}

	for _, doc := range result.Documents {
		if existing := stringFromAny(doc["created_at"], ""); existing != "" {
			continue
		}
		if createdAt := stringFromAny(doc["$createdAt"], ""); createdAt != "" {
			doc["created_at"] = createdAt
		}
	}

	utils.Paginated(c, result.Documents, p.Page, p.PerPage, result.Total)
}

// ═══════════════════════════════════════════════════════════════════════════════
// DISPUTES (delivery_issues)
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListDisputes(c *gin.Context) {
	p := models.ParsePagination(c)
	queries := []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	}
	result, err := h.appwrite.ListDeliveryIssuesByQuery(queries)
	if err != nil {
		utils.InternalError(c, "Failed to list disputes")
		return
	}
	docs := []map[string]interface{}{}
	total := 0
	if result != nil {
		docs = result.Documents
		total = result.Total
	}
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) GetDispute(c *gin.Context) {
	doc, err := h.appwrite.GetDeliveryIssue(c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Dispute not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateDispute(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDeliveryIssue(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update dispute")
		return
	}
	utils.Success(c, doc)
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN ACCOUNTS (users with admin/super_admin role)
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) ListAdmins(c *gin.Context) {
	// Fetch admin + super_admin users
	admins, err := h.appwrite.ListUsers([]string{
		appwrite.QueryEqual("role", "admin"),
		appwrite.QueryLimit(100),
	})
	superAdmins, _ := h.appwrite.ListUsers([]string{
		appwrite.QueryEqual("role", "super_admin"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to list admins")
		return
	}
	all := []map[string]interface{}{}
	if admins != nil {
		all = append(all, admins.Documents...)
	}
	if superAdmins != nil {
		all = append(all, superAdmins.Documents...)
	}
	utils.Success(c, all)
}

func (h *AdminHandler) CreateAdmin(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	// Ensure role is admin
	if _, ok := body["role"]; !ok {
		body["role"] = "admin"
	}
	role, _ := body["role"].(string)
	if role != "admin" && role != "super_admin" {
		body["role"] = "admin"
	}
	id := fmt.Sprintf("admin_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateUser(id, body)
	if err != nil {
		utils.InternalError(c, "Failed to create admin")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateAdmin(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateUser(c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update admin")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteAdmin(c *gin.Context) {
	// Prevent self-deletion
	if c.Param("id") == middleware.GetUserID(c) {
		utils.BadRequest(c, "Cannot delete your own account")
		return
	}
	if err := h.appwrite.DeleteUser(c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete admin")
		return
	}
	utils.Success(c, gin.H{"message": "Admin deleted"})
}

// ═══════════════════════════════════════════════════════════════════════════════
// LIVE DATA
// ═══════════════════════════════════════════════════════════════════════════════

func (h *AdminHandler) LiveSessions(c *gin.Context) {
	connectedUsers, roleCounts := h.livePresenceByRole()

	// Return online riders from delivery partner records
	online, _ := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(100),
	})
	riders := 0
	if online != nil {
		riders = online.Total
	}

	utils.Success(c, gin.H{
		"online_riders":     riders,
		"connected_users":   connectedUsers,
		"connected_by_role": roleCounts,
	})
}

func (h *AdminHandler) LiveStats(c *gin.Context) {
	// Active orders (not delivered/cancelled)
	activeOrders, _ := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered"),
		appwrite.QueryNotEqual("status", "cancelled"),
		appwrite.QueryLimit(1),
	})
	activeCount := 0
	if activeOrders != nil {
		activeCount = activeOrders.Total
	}

	// Online riders
	online, _ := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(1),
	})
	ridersCount := 0
	if online != nil {
		ridersCount = online.Total
	}

	connectedUsers, roleCounts := h.livePresenceByRole()
	if roleCounts["delivery_partner"] == 0 && ridersCount > 0 {
		// Fallback when riders are online but no active WebSocket presence was detected.
		roleCounts["delivery_partner"] = ridersCount
		if connectedUsers < ridersCount {
			connectedUsers = ridersCount
		}
	}

	utils.Success(c, gin.H{
		"active_orders":     activeCount,
		"online_riders":     ridersCount,
		"connected_users":   connectedUsers,
		"orders_per_minute": 0,
		"connected_by_role": roleCounts,
	})
}

func (h *AdminHandler) LiveRiders(c *gin.Context) {
	partners, err := h.appwrite.ListDeliveryPartners([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(500),
	})
	if err != nil {
		utils.InternalError(c, "Failed to get online riders")
		return
	}

	locResult, _ := h.appwrite.ListDeliveryLocations([]string{
		appwrite.QueryEqual("is_online", true),
		appwrite.QueryLimit(500),
	})

	locByRider := make(map[string]map[string]interface{})
	if locResult != nil {
		for _, loc := range locResult.Documents {
			riderID, _ := loc["rider_id"].(string)
			if riderID != "" {
				locByRider[riderID] = loc
			}
		}
	}

	userByID := make(map[string]map[string]interface{})
	if partners != nil {
		riderIDs := make([]string, 0, len(partners.Documents))
		seenRiderIDs := make(map[string]struct{}, len(partners.Documents))
		for _, p := range partners.Documents {
			riderID, _ := p["user_id"].(string)
			if riderID == "" {
				continue
			}
			if _, exists := seenRiderIDs[riderID]; exists {
				continue
			}
			seenRiderIDs[riderID] = struct{}{}
			riderIDs = append(riderIDs, riderID)
		}

		if len(riderIDs) > 0 {
			idValues := make([]interface{}, 0, len(riderIDs))
			for _, id := range riderIDs {
				idValues = append(idValues, id)
			}

			usersResult, usersErr := h.appwrite.ListUsers([]string{
				appwrite.QueryEqual("$id", idValues...),
				appwrite.QueryLimit(len(riderIDs)),
			})
			if usersErr != nil {
				log.Printf("LiveRiders: failed to batch fetch users: %v", usersErr)
			} else if usersResult != nil {
				for _, user := range usersResult.Documents {
					id, _ := user["$id"].(string)
					if id != "" {
						userByID[id] = user
					}
				}
			}
		}
	}

	riders := make([]map[string]interface{}, 0)
	if partners != nil {
		for _, p := range partners.Documents {
			riderID, _ := p["user_id"].(string)
			if riderID == "" {
				continue
			}

			user := userByID[riderID]
			name, _ := user["name"].(string)
			phone, _ := user["phone"].(string)
			if name == "" {
				name = "Rider"
			}

			vehicleType, _ := p["vehicle_type"].(string)
			isOnDelivery, _ := p["is_on_delivery"].(bool)
			currentOrderID, _ := p["current_order_id"].(string)

			lat, _ := p["current_latitude"].(float64)
			lng, _ := p["current_longitude"].(float64)
			heading, _ := p["heading"].(float64)
			lastUpdate := time.Now().UTC().Format(time.RFC3339)

			if lu, ok := p["last_location_at"].(string); ok && lu != "" {
				lastUpdate = lu
			}

			if loc := locByRider[riderID]; loc != nil {
				if v, ok := loc["latitude"].(float64); ok {
					lat = v
				}
				if v, ok := loc["longitude"].(float64); ok {
					lng = v
				}
				if v, ok := loc["heading"].(float64); ok {
					heading = v
				}
				if lu, ok := loc["$updatedAt"].(string); ok && lu != "" {
					lastUpdate = lu
				}
			}

			riders = append(riders, gin.H{
				"rider_id":         riderID,
				"name":             name,
				"phone":            phone,
				"vehicle_type":     vehicleType,
				"latitude":         lat,
				"longitude":        lng,
				"heading":          heading,
				"is_on_delivery":   isOnDelivery,
				"current_order_id": currentOrderID,
				"last_update":      lastUpdate,
			})
		}
	}

	utils.Success(c, riders)
}

func (h *AdminHandler) LiveOrders(c *gin.Context) {
	result, err := h.appwrite.ListOrders([]string{
		appwrite.QueryNotEqual("status", "delivered"),
		appwrite.QueryNotEqual("status", "cancelled"),
		appwrite.QueryOrderDesc("placed_at"),
		appwrite.QueryLimit(100),
	})
	if err != nil {
		utils.InternalError(c, "Failed to get live orders")
		return
	}
	docs := []map[string]interface{}{}
	if result != nil {
		docs = result.Documents
	}
	utils.Success(c, docs)
}

// ═══════════════════════════════════════════════════════════════════════════════
// GENERIC COLLECTION ENDPOINTS (zones, surge, flags, audit, support, content, settings)
// These use the generic ListDocuments/CreateDocument/etc. methods.
// If the Appwrite collection doesn't exist yet, they gracefully return empty.
// ═══════════════════════════════════════════════════════════════════════════════

// --- Audit Log ---

func (h *AdminHandler) ListAuditLog(c *gin.Context) {
	p := models.ParsePagination(c)
	docs, total := h.safeList(models.CollectionAuditLog, []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

// --- Zones ---

func (h *AdminHandler) ListZones(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionZones, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) CreateZone(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("zone_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionZones, id, body)
	if err != nil {
		log.Printf("CreateZone error: %v", err)
		utils.InternalError(c, "Failed to create zone")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateZone(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionZones, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update zone")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteZone(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionZones, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete zone")
		return
	}
	utils.Success(c, gin.H{"message": "Zone deleted"})
}

// --- Surge Rules ---

func (h *AdminHandler) ListSurge(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionSurgeRules, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) CreateSurge(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("surge_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionSurgeRules, id, body)
	if err != nil {
		log.Printf("CreateSurge error: %v", err)
		utils.InternalError(c, "Failed to create surge rule")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateSurge(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionSurgeRules, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update surge rule")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteSurge(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionSurgeRules, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete surge rule")
		return
	}
	utils.Success(c, gin.H{"message": "Surge rule deleted"})
}

// --- Feature Flags ---

func (h *AdminHandler) ListFeatureFlags(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionFeatureFlags, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

func (h *AdminHandler) UpdateFeatureFlag(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionFeatureFlags, c.Param("key"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update feature flag")
		return
	}
	utils.Success(c, doc)
}

// --- Support Issues ---

func (h *AdminHandler) ListSupportIssues(c *gin.Context) {
	p := models.ParsePagination(c)
	docs, total := h.safeList(models.CollectionSupportIssues, []string{
		appwrite.QueryOrderDesc("$createdAt"),
		appwrite.QueryLimit(p.PerPage),
		appwrite.QueryOffset(p.Offset()),
	})
	utils.Paginated(c, docs, p.Page, p.PerPage, total)
}

func (h *AdminHandler) GetSupportIssue(c *gin.Context) {
	doc, err := h.appwrite.GetDocument(models.CollectionSupportIssues, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Support issue not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) UpdateSupportIssue(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionSupportIssues, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update support issue")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) SupportIssueMessages(c *gin.Context) {
	// Messages are embedded or can be a sub-collection; return the issue with messages field
	doc, err := h.appwrite.GetDocument(models.CollectionSupportIssues, c.Param("id"))
	if err != nil {
		utils.NotFound(c, "Support issue not found")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) ReplySupportIssue(c *gin.Context) {
	var body struct {
		Message string `json:"message" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Message is required")
		return
	}
	adminID := middleware.GetUserID(c)
	// Append reply as update; actual implementation depends on Appwrite schema
	doc, err := h.appwrite.UpdateDocument(models.CollectionSupportIssues, c.Param("id"), map[string]interface{}{
		"last_reply":    body.Message,
		"last_reply_by": adminID,
		"last_reply_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		utils.InternalError(c, "Failed to reply to support issue")
		return
	}
	utils.Success(c, doc)
}

// --- Content / Banners ---

func (h *AdminHandler) UploadBannerImage(c *gin.Context) {
	fileHeader, err := c.FormFile("file")
	if err != nil {
		utils.BadRequest(c, "Image file is required")
		return
	}

	bucketID := strings.TrimSpace(c.PostForm("bucket_id"))
	if bucketID == "" {
		bucketID = "promo-banners"
	}

	if fileHeader.Size <= 0 {
		utils.BadRequest(c, "Uploaded file is empty")
		return
	}
	if fileHeader.Size > 10*1024*1024 {
		utils.BadRequest(c, "Image size must be 10MB or less")
		return
	}

	contentType := strings.ToLower(strings.TrimSpace(fileHeader.Header.Get("Content-Type")))
	if !strings.HasPrefix(contentType, "image/") {
		utils.BadRequest(c, "Only image files are allowed")
		return
	}

	file, err := fileHeader.Open()
	if err != nil {
		utils.InternalError(c, "Failed to read uploaded image")
		return
	}
	defer file.Close()

	bytesData, err := io.ReadAll(file)
	if err != nil {
		utils.InternalError(c, "Failed to process uploaded image")
		return
	}

	uploaded, err := h.appwrite.UploadFile(bucketID, fileHeader.Filename, contentType, bytesData)
	if err != nil {
		log.Printf("UploadBannerImage error: %v", err)
		utils.InternalError(c, "Failed to upload banner image")
		return
	}

	fileID, _ := uploaded["$id"].(string)
	imageURL, _ := uploaded["view_url"].(string)
	utils.Success(c, gin.H{
		"bucket_id": bucketID,
		"file_id":   fileID,
		"image_url": imageURL,
	})
}

func (h *AdminHandler) ListBanners(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionBanners, []string{appwrite.QueryLimit(500)})
	utils.Success(c, docs)
}

// ListAppBanners returns active banners relevant to the authenticated app user.
func (h *AdminHandler) ListAppBanners(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetUserRole(c)

	isGoldMember := false
	isNewUser := false
	if user, err := h.appwrite.GetUser(userID); err == nil && user != nil {
		isGoldMember = boolFromAny(user["is_gold_member"], false)
		if createdAt, ok := parseBannerTime(user["$createdAt"]); ok {
			isNewUser = time.Since(createdAt) <= 30*24*time.Hour
		}
	}

	docs, _ := h.safeList(models.CollectionBanners, []string{appwrite.QueryLimit(500)})
	now := time.Now().UTC()
	filtered := make([]map[string]interface{}, 0)

	for _, doc := range docs {
		if !boolFromAny(doc["is_active"], true) {
			continue
		}

		segment := stringFromAny(doc["target_segment"], "all")
		if !bannerSegmentAllowed(segment, role, isGoldMember, isNewUser) {
			continue
		}

		if from, ok := parseBannerTime(doc["valid_from"]); ok && now.Before(from) {
			continue
		}
		if until, ok := parseBannerTime(doc["valid_until"]); ok && now.After(until) {
			continue
		}

		filtered = append(filtered, doc)
	}

	sort.SliceStable(filtered, func(i, j int) bool {
		leftOrder := intFromAny(filtered[i]["sort_order"], 9999)
		rightOrder := intFromAny(filtered[j]["sort_order"], 9999)
		if leftOrder != rightOrder {
			return leftOrder < rightOrder
		}

		leftCreated, _ := parseBannerTime(filtered[i]["created_at"])
		rightCreated, _ := parseBannerTime(filtered[j]["created_at"])
		return leftCreated.After(rightCreated)
	})

	utils.Success(c, filtered)
}

func (h *AdminHandler) CreateBanner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	id := fmt.Sprintf("banner_%s", uuid.New().String()[:8])
	doc, err := h.appwrite.CreateDocument(models.CollectionBanners, id, body)
	if err != nil {
		log.Printf("CreateBanner error: %v", err)
		utils.InternalError(c, "Failed to create banner")
		return
	}
	utils.Created(c, doc)
}

func (h *AdminHandler) UpdateBanner(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}
	doc, err := h.appwrite.UpdateDocument(models.CollectionBanners, c.Param("id"), body)
	if err != nil {
		utils.InternalError(c, "Failed to update banner")
		return
	}
	utils.Success(c, doc)
}

func (h *AdminHandler) DeleteBanner(c *gin.Context) {
	if err := h.appwrite.DeleteDocument(models.CollectionBanners, c.Param("id")); err != nil {
		utils.InternalError(c, "Failed to delete banner")
		return
	}
	utils.Success(c, gin.H{"message": "Banner deleted"})
}

func (h *AdminHandler) ListContentCategories(c *gin.Context) {
	// Return all menu categories across restaurants
	docs, _ := h.safeList(models.CollectionMenuCategories, []string{
		appwrite.QueryLimit(500),
	})
	utils.Success(c, docs)
}

// --- Settings ---

func (h *AdminHandler) GetSettings(c *gin.Context) {
	docs, _ := h.safeList(models.CollectionSettings, []string{appwrite.QueryLimit(1)})
	if len(docs) > 0 {
		utils.Success(c, normalizedSettingsResponse(docs[0]))
	} else {
		utils.Success(c, normalizedSettingsResponse(map[string]interface{}{}))
	}
}

func (h *AdminHandler) UpdateSettings(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		utils.BadRequest(c, "Invalid request body")
		return
	}

	normalizedBody := normalizeSettingsWritePayload(body)
	if len(normalizedBody) == 0 {
		utils.BadRequest(c, "No valid settings fields provided")
		return
	}

	// Try to update existing settings doc, or create one
	docs, _ := h.safeList(models.CollectionSettings, []string{appwrite.QueryLimit(1)})
	if len(docs) > 0 {
		id, _ := docs[0]["$id"].(string)
		if strings.TrimSpace(id) == "" {
			id = "platform_settings"
		}
		doc, err := h.appwrite.UpdateDocument(models.CollectionSettings, id, normalizedBody)
		if err != nil {
			fallbackBodies := []map[string]interface{}{
				filterPayloadByExistingKeys(normalizedBody, docs[0]),
				withIntegerNumericSettings(normalizedBody),
				withIntegerNumericSettings(filterPayloadByExistingKeys(normalizedBody, docs[0])),
				legacySettingsPayload(withIntegerNumericSettings(normalizedBody)),
				filterPayloadByExistingKeys(legacySettingsPayload(withIntegerNumericSettings(normalizedBody)), docs[0]),
			}

			for _, candidate := range fallbackBodies {
				if len(candidate) == 0 {
					continue
				}
				doc, err = h.appwrite.UpdateDocument(models.CollectionSettings, id, candidate)
				if err == nil {
					break
				}
			}

			if err != nil {
				log.Printf("UpdateSettings error: %v", err)
				utils.InternalError(c, "Failed to update settings")
				return
			}
		}
		utils.Success(c, normalizedSettingsResponse(doc))
	} else {
		id := "platform_settings"

		createData := normalizeSettingsWritePayload(map[string]interface{}(defaultPlatformSettings()))
		for k, v := range normalizedBody {
			createData[k] = v
		}

		var (
			doc map[string]interface{}
			err error
		)

		createCandidates := []map[string]interface{}{
			createData,
			withIntegerNumericSettings(createData),
			legacySettingsPayload(createData),
			withIntegerNumericSettings(legacySettingsPayload(createData)),
		}

		for _, candidate := range createCandidates {
			if len(candidate) == 0 {
				continue
			}
			doc, err = h.appwrite.CreateDocument(models.CollectionSettings, id, candidate)
			if err == nil {
				break
			}
		}

		if err != nil {
			log.Printf("CreateSettings error (collection may not exist): %v", err)
			utils.InternalError(c, "Failed to save settings")
			return
		}
		utils.Success(c, normalizedSettingsResponse(doc))
	}
}

// logAudit is a helper that writes an audit log entry (best-effort, non-blocking)
func (h *AdminHandler) logAudit(adminID, action, summary string) {
	id := fmt.Sprintf("audit_%s", uuid.New().String()[:8])
	_, err := h.appwrite.CreateDocument(models.CollectionAuditLog, id, map[string]interface{}{
		"admin_id":   adminID,
		"admin_name": "",
		"action":     action,
		"summary":    summary,
		"created_at": time.Now().Format(time.RFC3339),
	})
	if err != nil {
		log.Printf("Audit log write failed (non-critical): %v", err)
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
// UNUSED IMPORT GUARD
// ═══════════════════════════════════════════════════════════════════════════════

var _ = strings.TrimSpace
