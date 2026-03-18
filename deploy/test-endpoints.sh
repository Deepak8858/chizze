#!/bin/bash
API="http://localhost:8080"

check() {
  local method=$1 path=$2 expect=$3
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X "$method" "$API$path")
  if [ "$code" = "$expect" ]; then
    printf '  ✔ %-6s %-50s %s\n' "$method" "$path" "$code"
  else
    printf '  ✘ %-6s %-50s %s (expected %s)\n' "$method" "$path" "$code" "$expect"
  fi
}

echo "═══════════════════════════════════════════════"
echo "  Chizze API — Endpoint Verification"
echo "═══════════════════════════════════════════════"

echo ""
echo "── Public Endpoints ──"
check GET  "/health"                                          200
check GET  "/health/ready"                                    200
check GET  "/api/v1/restaurants"                              200
check GET  "/api/v1/restaurants/nearby?lat=25.8&lng=81.9"     200
check GET  "/api/v1/coupons"                                  200

echo ""
echo "── Auth Endpoints (POST without body → 400) ──"
check POST "/api/v1/auth/send-otp"                            400
check POST "/api/v1/auth/verify-otp"                          400
check POST "/api/v1/auth/exchange"                            400
check POST "/api/v1/auth/check-phone"                         400

echo ""
echo "── Protected Endpoints (no auth → 401) ──"
check GET  "/api/v1/users/me"                                 401
check GET  "/api/v1/orders"                                   401
check GET  "/api/v1/notifications"                            401
check GET  "/api/v1/gold/plans"                               401
check GET  "/api/v1/gold/status"                              401
check GET  "/api/v1/referrals/code"                           401
check GET  "/api/v1/referrals"                                401
check POST "/api/v1/cart/validate-coupon"                     401
check POST "/api/v1/payments/initiate"                        401

echo ""
echo "── Partner Endpoints (no auth → 401) ──"
check GET  "/api/v1/partner/dashboard"                        401
check GET  "/api/v1/partner/analytics"                        401
check GET  "/api/v1/partner/orders"                           401
check GET  "/api/v1/partner/menu"                             401
check GET  "/api/v1/partner/categories"                       401

echo ""
echo "── Delivery Partner Endpoints (no auth → 401) ──"
check GET  "/api/v1/delivery/dashboard"                       401
check GET  "/api/v1/delivery/earnings"                        401
check GET  "/api/v1/delivery/performance"                     401
check GET  "/api/v1/delivery/profile"                         401
check GET  "/api/v1/delivery/orders"                          401
check GET  "/api/v1/delivery/payouts"                         401

echo ""
echo "── Admin Endpoints (no auth → 401) ──"
check GET  "/api/v1/admin/dashboard"                          401
check GET  "/api/v1/admin/users"                              401
check GET  "/api/v1/admin/restaurants"                        401
check GET  "/api/v1/admin/orders"                             401
check GET  "/api/v1/admin/delivery-partners"                  401
check GET  "/api/v1/admin/coupons"                            401
check GET  "/api/v1/admin/reviews"                            401
check GET  "/api/v1/admin/disputes"                           401
check GET  "/api/v1/admin/zones"                              401
check GET  "/api/v1/admin/surge"                              401
check GET  "/api/v1/admin/feature-flags"                      401
check GET  "/api/v1/admin/audit-log"                          401
check GET  "/api/v1/admin/live/orders"                        401
check GET  "/api/v1/admin/live/riders"                        401
check GET  "/api/v1/admin/settings"                           401

echo ""
echo "── Webhook (POST without payload → 400) ──"
check POST "/api/v1/payments/webhook"                         400

echo ""
echo "═══════════════════════════════════════════════"
echo "  Done!"
echo "═══════════════════════════════════════════════"
