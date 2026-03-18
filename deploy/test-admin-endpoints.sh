#!/bin/bash
# Test all admin API endpoints - 401 means route exists, 404 means missing
endpoints=(
  dashboard
  analytics
  analytics/sla
  analytics/items
  analytics/cities
  analytics/retention
  analytics/revenue
  users
  restaurants
  restaurants/pending
  orders
  orders/active
  delivery-partners
  delivery-partners/pending
  payouts
  coupons
  reviews
  gold/subscriptions
  gold/stats
  referrals
  referrals/stats
  notifications/history
  disputes
  admins
  live/stats
  live/riders
  live/orders
  live/sessions
  zones
  surge
  feature-flags
  audit-log
  support/issues
  content/banners
  content/categories
  settings
  "reports/financial?from=2026-01-01&to=2026-03-18"
  reports/cancellations
  leaderboards
)
for ep in "${endpoints[@]}"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/v1/admin/$ep" -H "Authorization: Bearer test")
  echo "$code /admin/$ep"
done
