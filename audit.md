# Chizze — Full Codebase Audit

> **Date:** June 2025 (Re-audit)
> **Scope:** Every feature flow, backend + frontend, ~5,500 lines Go · ~14,500 lines Dart
> **Target:** Production Readiness (50K+ Users)

---

## 1. Project Overview

| Attribute | Value |
|-----------|-------|
| **Name** | Chizze |
| **Type** | Food Delivery (Customer · Restaurant Partner · Delivery Partner) |
| **Frontend** | Flutter 3.x · Dart 3.10 · Riverpod StateNotifier · GoRouter |
| **Backend** | Go 1.22 · Gin · Appwrite Cloud (sgp) · Redis 8.6.0 |
| **Payments** | Razorpay (server-initiated orders, signature verification) |
| **Maps** | Mapbox Maps Flutter |
| **Push** | Firebase Cloud Messaging (firebase_messaging ^15.2.5) |
| **Offline** | Hive ^2.2.3 + hive_flutter ^1.1.0 |
| **Files audited** | ~50 Go · ~68 Dart · native manifests · assets |

---

## 2. Feature Completion Matrix

### 2.1 Infrastructure

| Feature | Status | Evidence |
|---------|--------|----------|
| Circuit Breaker (gobreaker) | 🟢 Done | `pkg/appwrite/client.go` (MaxReq 5, 30s interval, 60s timeout) + `services/payment_service.go` (MaxReq 3, 20s timeout) |
| OpenTelemetry | 🟢 Done | go.mod: otel v1.40.0, otelgin, otlp/http + stdout exporters |
| Swagger API Docs | 🟢 Done | `backend/docs/` (swagger.yaml, swagger.json, docs.go) · Swagger UI at `/swagger/*any` |
| Offline Caching (Hive) | 🟢 Done | pubspec.yaml, initialized in `main.dart`, `cache_service.dart` (per-endpoint TTL, default 5 min) |
| Push Notifications (FCM) | 🟢 Done | `push_notification_service.dart`: init, background handler, token refresh, onMessage, onMessageOpenedApp |
| Deep Linking — Android | 🟢 Done | `AndroidManifest.xml`: `https://chizze.app` + custom scheme `chizze://` |
| Deep Linking — iOS | 🔴 Missing | `Info.plist` has NO `CFBundleURLTypes`, no Associated Domains entitlement |
| WebSockets | 🟢 Done | Backend: `internal/websocket/` · Frontend: `websocket_service.dart` (exponential backoff 1s→30s, heartbeat 25s) |
| Background Workers | 🟢 Done | `internal/workers/`: delivery matching, order timeouts, scheduled order processing |
| Redis Integration | 🟢 Done | Caching, rate limiting, token blacklisting |

### 2.2 UI/UX Enhancements

| Feature | Status | Evidence |
|---------|--------|----------|
| Skeleton Loaders | 🟢 Done | 6 widgets in `shimmer_loader.dart` · Applied to Home, Favorites, Orders, Restaurant Detail, Analytics, Earnings |
| Lottie Empty States | 🟢 Done | 4 animations (empty_cart, no_orders, no_results, no_notifications) · 10 factory constructors in `EmptyStateWidget` |
| Accessibility / Semantics | 🟡 Partial | 20+ Semantics across 7 screens (empty_state, search, restaurant_detail, partner_dashboard, orders, home, cart, login) · ~95% of custom-painted widgets still lack semantic annotations |
| Micro-interactions | 🟢 Done | flutter_animate integrated for transitions |
| Design System | 🟢 Done | AppColors, AppTheme (dark + light M3), AppTypography, AppSpacing, GlassCard |

### 2.3 Role-Based Flows

| Flow | Status | Notes |
|------|--------|-------|
| Customer — 5-tab shell (Home, Search, Favorites, Orders, Profile) | 🟢 Working | GoRouter ShellRoute with StatefulNavigationShell |
| Partner — 4-tab shell (Dashboard, Orders, Menu, Analytics) | 🟢 Working | Realtime order subscription, order sounds |
| Delivery — 4-tab shell (Dashboard, Active, Earnings, Profile) | 🟡 Partial | Core flow works; Navigate/Call/Profile menu items are empty stubs |

---

## 3. Critical Issues (P0 — Must Fix Before Production)

### 3.1 Backend Critical

| # | Issue | File | Detail |
|---|-------|------|--------|
| B1 | **Context key mismatch `"userId"` vs `"user_id"`** | 4 handlers + WebSocket | Favorites, Gold, Referrals, Scheduled Orders, and all WebSocket targeted messaging are **completely broken** because JWT middleware sets one key but handlers read another |
| B2 | **OTP never sent or verified** | `auth_handler.go` | Phone auth accepts ANY OTP — anyone can impersonate any user |
| B3 | **`customer_id` vs `user_id` field mismatch** | order + delivery handlers | Status notifications and live tracking silently send to wrong recipient |
| B4 | **No ownership check on scheduled order cancel** | `scheduled_order_handler.go` | Any authenticated user can cancel any scheduled order |
| B5 | **WebSocket `CheckOrigin` allows all origins** | `websocket/` | Cross-site WebSocket hijacking possible |
| B6 | **Hardcoded Redis password in config defaults** | `config/` | Credential leak if .env is missing |
| B7 | **Coupon counter never decremented on over-limit** | `coupon_handler.go` | Coupons become permanently unusable after reaching limit |

### 3.2 Frontend Critical

| # | Issue | File | Detail |
|---|-------|------|--------|
| F1 | **Restaurant detail menu always empty** | `restaurant_detail_screen.dart` | `_initData()` sets `_menuItems = []` and `_reviews = []` with no API fetch wiring — menu screen shows nothing |
| F2 | **`DeliveryMap._addRouteLine` uses `.toString()` not `jsonEncode()`** | `delivery_map.dart` | Dart Map.toString() is not valid JSON — route line never renders |
| F3 | **Navigate + Call buttons empty** | `active_delivery_screen.dart` | `onPressed: () {}` — delivery partner cannot navigate to pickup/dropoff or call customer |
| F4 | **All 5 delivery profile menu items are empty** | `delivery_profile_screen.dart` | Bank Details, Documents, Availability, Support, About — all `() {}` |
| F5 | **Notification tap routing not implemented** | `push_notification_service.dart` | `// TODO: Navigate based on notification data` — tapping a notification does nothing |

---

## 4. High-Priority Issues (P1 — Security & Data Integrity)

| # | Issue | File | Detail |
|---|-------|------|--------|
| H1 | **Mapbox token hardcoded** | `map_config.dart` | Should use `--dart-define` |
| H2 | **Razorpay test key as client fallback** | `payment_provider.dart` | `rzp_test_SIjgJ176oKm8mn` leaks to production if env var missing |
| H3 | **Debug "Simulate Request" button in production** | `delivery_dashboard_screen.dart` | Not gated behind `kDebugMode` |
| H4 | **Appwrite project ID hardcoded** | `appwrite_constants.dart` | Should come from environment config |
| H5 | **`.ignore()` on CRUD operations** | address_provider, menu_management_provider, notifications_provider | Server errors silently swallowed — user thinks action succeeded when it didn't |
| H6 | **Mock fallback on all exceptions in ~6 providers** | restaurant, coupons, favorites, scheduled_orders, referral, gold | Masks real API errors behind mock data — users never know API is failing |
| H7 | **Pagination not applied at DB level** | Backend order/restaurant handlers | All records fetched then sliced in memory — breaks at scale |
| H8 | **N+1 queries** | Backend restaurant/order handlers | Per-record DB calls in loops |

---

## 5. Medium-Priority Issues (P2 — UX & Consistency)

| # | Issue | File | Detail |
|---|-------|------|--------|
| M1 | `AppTypography` hardcodes `Colors.white` in all text styles | `app_typography.dart` | Breaks light theme unless overridden at every call site |
| M2 | `_PriceRow` hardcodes `Colors.white` for value text | `payment_screen.dart`, `cart_screen.dart` | Broken in light theme |
| M3 | Profile "More" section items have empty `onTap` | `profile_screen.dart` | Help & Support, About, Privacy Policy — non-navigable |
| M4 | `toggleVeg` / `toggleDarkMode` not persisted | `user_profile_provider.dart` | Only local state; lost on restart |
| M5 | `setDefault` address is local-only | `address_provider.dart` | Not persisted to backend |
| M6 | `OrderTrackingScreen.dispose()` checks `mounted` post-dispose | `order_tracking_screen.dart` | Always returns false — dead code |
| M7 | OTP auto-submit on 4th digit with no debounce | `otp_screen.dart` | Rapid typing could trigger double-submit |
| M8 | Onboarding "seen" flag not persisted | `onboarding_screen.dart` | User re-sees onboarding on reinstall |
| M9 | Search is client-only (in-memory filter) | `search_screen.dart` | No server-side search — degrades with large restaurant lists |
| M10 | Review submit not wired to backend API | `review_screen.dart` | `context.pop()` with payload only — review never saved |
| M11 | Reorder shows "coming soon!" snackbar | `orders_provider.dart` | Not implemented |
| M12 | Phone/Chat rider shows "coming soon!" | `order_tracking_screen.dart` | Not implemented |
| M13 | Address "Pick on Map" shows "coming soon" | `address_management_screen.dart` | Not implemented |
| M14 | Google/Apple OAuth shows "Coming soon!" | `login_screen.dart` | Social login not wired |
| M15 | Referral share uses clipboard, not `share_plus` | `referral_screen.dart` | No native share sheet |

---

## 6. Low-Priority Issues (P3 — Polish)

| # | Issue | File | Detail |
|---|-------|------|--------|
| L1 | `appwrite_client.dart` is dead code | `lib/appwrite_client.dart` | `auth_provider.dart` creates its own client — this file is never imported |
| L2 | `widgets.dart` barrel missing exports | `shared/widgets/widgets.dart` | `delivery_map.dart`, `empty_state_widget.dart` not exported |
| L3 | GPS heading/speed hardcoded to `0.0` | `delivery_provider.dart` | Should read from position data |
| L4 | `rider_location_provider` simulates movement | `rider_location_provider.dart` | Could confuse users in production |
| L5 | CacheService implemented but never wired | Backend `cache_service.go` | Full Redis cache layer ready but unused by handlers |
| L6 | O(n) WebSocket client scan | Backend `websocket/` | Linear scan for every targeted message |
| L7 | `_reconnectAttempts` only resets on message, not on connect | `websocket_service.dart` | Should reset on successful connection open |
| L8 | `_VisibilityWrapper` misused in home screen | `home_screen.dart` | Wraps text, doesn't control viewport-based visibility |

---

## 7. Test Coverage

### 7.1 Flutter Tests (`test/`)

| Test File | Tests |
|-----------|-------|
| `test/models/api_response_test.dart` | ApiResponse model parsing |
| `test/models/delivery_partner_test.dart` | DeliveryPartner model |
| `test/models/menu_item_test.dart` | MenuItem model |
| `test/models/order_test.dart` | Order model |
| `test/models/restaurant_test.dart` | Restaurant model |
| `test/providers/cart_provider_test.dart` | Cart state management |
| `test/providers/coupons_provider_test.dart` | Coupons state management |
| `test/providers/gold_provider_test.dart` | Gold subscription state |

**Coverage:** 5 model tests + 3 provider tests. **Zero** widget/screen tests. **Zero** integration tests.

### 7.2 Backend Tests

| Test File | Tests |
|-----------|-------|
| `internal/services/geo_service_test.go` | Geo calculations |
| `internal/services/order_service_test.go` | Order business logic |
| Model/middleware tests | Various `*_test.go` files |

**Coverage:** Service + model + middleware tests. **Zero** handler tests. **Zero** integration/E2E tests.

---

## 8. Architecture Strengths

- **Clean modular structure:** Backend follows handlers→services→models. Frontend follows features→(screens, providers, models).
- **Riverpod StateNotifier pattern:** ~20+ providers, properly scoped, no global mutable singletons.
- **GoRouter:** 3 ShellRoutes with role-based redirects, deep link `/referral/:code`, auth guard via `_RouterNotifier`.
- **Appwrite Realtime:** Used in 4 providers (notifications, rider GPS, partner orders, delivery requests).
- **Payment flow:** Backend-initiated Razorpay orders with idempotency keys and server-side signature verification.
- **Optimistic updates + rollback:** `favorites_provider` and `partner_provider` properly revert on API failure.
- **Skeleton loaders:** 6 widget variants covering all major loading states.
- **Lottie empty states:** 4 animations with 10 factory constructors in `EmptyStateWidget`.
- **Circuit breaker:** gobreaker on both Appwrite client (5 req, 60s timeout) and Razorpay (3 req, 20s timeout).
- **WebSocket resilience:** Exponential backoff (1s→30s) + heartbeat every 25s.

---

## 9. Recommended Fix Order

### Phase 1: Backend P0 Fixes (Estimated: 2-3 days)
1. Fix context key mismatch (`"userId"` → `"user_id"` or vice versa) across all handlers + WebSocket
2. Implement actual OTP send/verify (Appwrite phone auth or Twilio)
3. Fix `customer_id` vs `user_id` field mismatch in order/delivery handlers
4. Add ownership check on scheduled order cancel
5. Restrict WebSocket `CheckOrigin` to allowed origins
6. Move Redis password to env-only (remove default)
7. Fix coupon counter decrement logic

### Phase 2: Frontend P0 Fixes (Estimated: 2-3 days)
1. Wire restaurant detail screen to API (fetch menu items + reviews)
2. Fix `DeliveryMap._addRouteLine` — use `jsonEncode()` instead of `.toString()`
3. Implement Navigate (launch maps) + Call (launch dialer) in active delivery screen
4. Implement delivery profile menu items (at minimum Bank Details + Documents)
5. Implement notification tap routing in `push_notification_service.dart`

### Phase 3: Security Hardening (Estimated: 1 day)
1. Move Mapbox token, Razorpay key, Appwrite project ID to `--dart-define` / env config
2. Gate "Simulate Request" behind `kDebugMode`
3. Replace `.ignore()` calls with proper error handling + user feedback
4. Add proper error handling instead of catch-all mock fallbacks

### Phase 4: iOS Deep Linking (Estimated: 0.5 day)
1. Add `CFBundleURLTypes` to `ios/Runner/Info.plist` for custom `chizze://` scheme
2. Add Associated Domains entitlement for `applinks:chizze.app`
3. Host `apple-app-site-association` file on `chizze.app`

### Phase 5: UX Polish (Estimated: 2-3 days)
1. Fix `AppTypography` / `_PriceRow` light theme colors
2. Wire review submission to backend API
3. Implement reorder functionality
4. Add server-side search
5. Persist user preferences (veg toggle, dark mode, default address)
6. Implement remaining "coming soon" stubs (Phone/Chat rider, Address map picker, Social OAuth)

### Phase 6: Testing (Estimated: 3-5 days)
1. Add widget tests for key screens (Home, Cart, Orders, Restaurant Detail)
2. Add handler tests for all backend endpoints
3. Add integration/E2E tests for critical flows (auth → order → payment → tracking)
4. Expand accessibility coverage to remaining ~95% of custom widgets

---

## 10. Summary

| Category | Count |
|----------|-------|
| **P0 Critical (must fix)** | 12 (7 backend + 5 frontend) |
| **P1 High (security/data)** | 8 |
| **P2 Medium (UX)** | 15 |
| **P3 Low (polish)** | 8 |
| **Total issues** | 43 |
| **"Coming soon" stubs** | 6 (reorder, phone/chat rider, map picker, social OAuth, address map, delivery profile items) |
| **Test files** | 8 Flutter + 2 Go service tests |

**Bottom line:** The architecture is solid and well-organized. Core flows (auth → browse → cart → payment → tracking) work end-to-end on the happy path. The 7 backend P0 bugs (especially the context key mismatch and OTP bypass) are the highest-priority blockers — they break authentication, favorites, gold subscriptions, referrals, and real-time delivery tracking. The 5 frontend P0 issues prevent the restaurant detail screen from showing any menu items and leave the delivery partner flow non-functional. Fixing these 12 P0 items is the critical path to a shippable product.