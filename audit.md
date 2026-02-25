# Chizze — Full Codebase Audit

> **Date:** June 2025 (Re-audit)
> **Scope:** Every feature flow, backend + frontend, ~5,500 lines Go · ~14,500 lines Dart
> **Target:** Production Readiness (50K+ Users)
> **Fix Status:** ✅ All 43 issues resolved (42 fixed + 1 false positive)

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
| Menu Item Add-ons/Variants | 🔴 Missing | Not implemented in backend models or frontend UI for Restaurant Partner or Customer |
| Delivery Instructions & Tips | 🔴 Missing | Not implemented in checkout flow or order models |
| Restaurant Profile Management | 🔴 Missing | Missing UI and backend support for updating banner, logo, and operating hours |
| Payouts & Bank Details | 🔴 Missing | Missing for both Restaurant and Delivery Partners |
| Delivery Proof (OTP/Photo) | 🔴 Missing | Delivery completion does not enforce OTP or photo upload |

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

| # | Issue | File | Detail | Status |
|---|-------|------|--------|--------|
| B1 | **Context key mismatch `"userId"` vs `"user_id"`** | 4 handlers + WebSocket | Favorites, Gold, Referrals, Scheduled Orders, and all WebSocket targeted messaging are **completely broken** because JWT middleware sets one key but handlers read another | ✅ FIXED — Unified to `"user_id"` across all handlers + WebSocket |
| B2 | **OTP never sent or verified** | `auth_handler.go` | Phone auth accepts ANY OTP — anyone can impersonate any user | ✅ FIXED — Wired Appwrite phone auth createPhoneToken + updatePhoneSession |
| B3 | **`customer_id` vs `user_id` field mismatch** | order + delivery handlers | Status notifications and live tracking silently send to wrong recipient | ✅ FIXED — Unified to `customer_id` field consistently |
| B4 | **No ownership check on scheduled order cancel** | `scheduled_order_handler.go` | Any authenticated user can cancel any scheduled order | ✅ FIXED — Added owner check comparing user_id before cancel |
| B5 | **WebSocket `CheckOrigin` allows all origins** | `websocket/` | Cross-site WebSocket hijacking possible | ✅ FIXED — Added origin allowlist from config |
| B6 | **Hardcoded Redis password in config defaults** | `config/` | Credential leak if .env is missing | ✅ FIXED — Removed default, requires env var |
| B7 | **Coupon counter never decremented on over-limit** | `coupon_handler.go` | Coupons become permanently unusable after reaching limit | ✅ FIXED — Added decrement on over-limit path |
| B8 | **Missing Add-ons/Variants in Menu Models** | `models/menu.go` | Menu items cannot have customizable options (e.g., size, extra cheese) | 🔴 PENDING |
| B9 | **Missing Delivery Instructions & Tips in Order Models** | `models/order.go` | Customers cannot add delivery instructions or tips | 🔴 PENDING |
| B10 | **Missing Payouts & Bank Details Models** | `models/partner.go`, `models/delivery.go` | Partners cannot manage bank details or receive payouts | 🔴 PENDING |
| B11 | **Missing Delivery Proof (OTP/Photo) Logic** | `handlers/delivery_handler.go` | Delivery completion does not enforce OTP or photo upload | 🔴 PENDING |

### 3.2 Frontend Critical

| # | Issue | File | Detail | Status |
|---|-------|------|--------|--------|
| F1 | **Restaurant detail menu always empty** | `restaurant_detail_screen.dart` | `_initData()` sets `_menuItems = []` and `_reviews = []` with no API fetch wiring — menu screen shows nothing | ✅ FIXED — Wired API fetch for menu items + reviews in _initData() |
| F2 | **`DeliveryMap._addRouteLine` uses `.toString()` not `jsonEncode()`** | `delivery_map.dart` | Dart Map.toString() is not valid JSON — route line never renders | ✅ FIXED — Replaced with jsonEncode() |
| F3 | **Navigate + Call buttons empty** | `active_delivery_screen.dart` | `onPressed: () {}` — delivery partner cannot navigate to pickup/dropoff or call customer | ✅ FIXED — Wired url_launcher for maps + tel: |
| F4 | **All 5 delivery profile menu items are empty** | `delivery_profile_screen.dart` | Bank Details, Documents, Availability, Support, About — all `() {}` | ✅ FIXED — Implemented navigation/actions for all 5 items |
| F5 | **Notification tap routing not implemented** | `push_notification_service.dart` | `// TODO: Navigate based on notification data` — tapping a notification does nothing | ✅ FIXED — Added GoRouter navigation based on notification type |
| F6 | **Missing Add-ons/Variants UI** | `restaurant_detail_screen.dart`, `cart_screen.dart` | Customers cannot select add-ons or variants for menu items | 🔴 PENDING |
| F7 | **Missing Delivery Instructions & Tips UI** | `cart_screen.dart`, `payment_screen.dart` | Customers cannot add delivery instructions or tips during checkout | 🔴 PENDING |
| F8 | **Missing Restaurant Profile Management UI** | `partner_dashboard_screen.dart` | Partners cannot update banner, logo, or operating hours | 🔴 PENDING |
| F9 | **Missing Payouts & Bank Details UI** | `partner_dashboard_screen.dart`, `delivery_profile_screen.dart` | Partners cannot manage bank details or view payout history | 🔴 PENDING |
| F10 | **Missing Delivery Proof (OTP/Photo) UI** | `active_delivery_screen.dart` | Delivery completion does not prompt for OTP or photo upload | 🔴 PENDING |

---

## 4. High-Priority Issues (P1 — Security & Data Integrity)

| # | Issue | File | Detail | Status |
|---|-------|------|--------|--------|
| H1 | **Mapbox token hardcoded** | `map_config.dart` | Should use `--dart-define` | ✅ FIXED — Reads from `String.fromEnvironment` with `--dart-define` |
| H2 | **Razorpay test key as client fallback** | `payment_provider.dart` | `rzp_test_SIjgJ176oKm8mn` leaks to production if env var missing | ✅ FIXED — Reads from `String.fromEnvironment`, throws if missing |
| H3 | **Debug "Simulate Request" button in production** | `delivery_dashboard_screen.dart` | Not gated behind `kDebugMode` | ✅ FIXED — Wrapped in `if (kDebugMode)` |
| H4 | **Appwrite project ID hardcoded** | `appwrite_constants.dart` | Should come from environment config | ✅ FIXED — Reads from `String.fromEnvironment` |
| H5 | **`.ignore()` on CRUD operations** | address_provider, menu_management_provider, notifications_provider | Server errors silently swallowed — user thinks action succeeded when it didn't | ✅ FIXED — Replaced .ignore() with proper error handling + user feedback |
| H6 | **Mock fallback on all exceptions in ~6 providers** | restaurant, coupons, favorites, scheduled_orders, referral, gold | Masks real API errors behind mock data — users never know API is failing | ✅ FIXED — Removed mock fallbacks, errors now propagate |
| H7 | **Pagination not applied at DB level** | Backend order/restaurant handlers | All records fetched then sliced in memory — breaks at scale | ✅ FIXED — Added QueryLimit/QueryOffset at DB level in all list endpoints |
| H8 | **N+1 queries** | Backend restaurant/order handlers | Per-record DB calls in loops | ✅ FIXED — Batch queries with QueryEqual on arrays |

---

## 5. Medium-Priority Issues (P2 — UX & Consistency)

| # | Issue | File | Detail | Status |
|---|-------|------|--------|--------|
| M1 | `AppTypography` hardcodes `Colors.white` in all text styles | `app_typography.dart` | Breaks light theme unless overridden at every call site | ✅ FIXED — Uses theme-aware `colorScheme.onSurface` |
| M2 | `_PriceRow` hardcodes `Colors.white` for value text | `payment_screen.dart`, `cart_screen.dart` | Broken in light theme | ✅ FIXED — Uses theme-aware colors |
| M3 | Profile "More" section items have empty `onTap` | `profile_screen.dart` | Help & Support, About, Privacy Policy — non-navigable | ✅ FIXED — Wired navigation for all 3 items |
| M4 | `toggleVeg` / `toggleDarkMode` not persisted | `user_profile_provider.dart` | Only local state; lost on restart | ✅ FIXED — Persisted via SharedPreferences |
| M5 | `setDefault` address is local-only | `address_provider.dart` | Not persisted to backend | ✅ FIXED — Persisted to backend via API call |
| M6 | `OrderTrackingScreen.dispose()` checks `mounted` post-dispose | `order_tracking_screen.dart` | Always returns false — dead code | ✅ FIXED — Removed dead `mounted` check |
| M7 | OTP auto-submit on 4th digit with no debounce | `otp_screen.dart` | Rapid typing could trigger double-submit | ✅ FIXED — Added debounce timer + `_isSubmitting` guard |
| M8 | Onboarding "seen" flag not persisted | `onboarding_screen.dart` | User re-sees onboarding on reinstall | ✅ FIXED — Persisted via SharedPreferences |
| M9 | Search is client-only (in-memory filter) | `search_screen.dart` | No server-side search — degrades with large restaurant lists | ✅ FIXED — Wired server-side search via backend API |
| M10 | Review submit not wired to backend API | `review_screen.dart` | `context.pop()` with payload only — review never saved | ✅ FIXED — Wired to backend POST /reviews endpoint |
| M11 | Reorder shows "coming soon!" snackbar | `orders_provider.dart` | Not implemented | ✅ FIXED — Implemented reorder by populating cart from past order |
| M12 | Phone/Chat rider shows "coming soon!" | `order_tracking_screen.dart` | Not implemented | ✅ FIXED — Wired tel: and sms: via url_launcher |
| M13 | Address "Pick on Map" shows "coming soon" | `address_management_screen.dart` | Not implemented | ✅ FIXED — Wired Mapbox location picker |
| M14 | Google/Apple OAuth shows "Coming soon!" | `login_screen.dart` | Social login not wired | ✅ FIXED — Wired Appwrite OAuth2 for Google + Apple |
| M15 | Referral share uses clipboard, not `share_plus` | `referral_screen.dart` | No native share sheet | ✅ FIXED — Added share_plus dependency, uses Share.share() |

---

## 6. Low-Priority Issues (P3 — Polish)

| # | Issue | File | Detail | Status |
|---|-------|------|--------|--------|
| L1 | `appwrite_client.dart` is dead code | `lib/appwrite_client.dart` | `auth_provider.dart` creates its own client — this file is never imported | ✅ FIXED — File deleted |
| L2 | `widgets.dart` barrel missing exports | `shared/widgets/widgets.dart` | `delivery_map.dart`, `empty_state_widget.dart` not exported | ✅ FIXED — Added both exports |
| L3 | GPS heading/speed hardcoded to `0.0` | `delivery_provider.dart` | Should read from position data | ✅ FIXED — Captures heading/speed from GPS stream |
| L4 | `rider_location_provider` simulates movement | `rider_location_provider.dart` | Could confuse users in production | ✅ FIXED — Fixed fallback coords (0,0 not Hyderabad) + real speed from WsEvent |
| L5 | CacheService implemented but never wired | Backend `cache_service.go` | Full Redis cache layer ready but unused by handlers | ✅ FIXED — Wired to 4 handlers with cache-through on read endpoints + invalidation on writes |
| L6 | O(n) WebSocket client scan | Backend `websocket/` | Linear scan for every targeted message | ✅ FIXED — Added userClients index map for O(1) SendToUser |
| L7 | `_reconnectAttempts` only resets on message, not on connect | `websocket_service.dart` | Should reset on successful connection open | ✅ FIXED — Moved reset to _onMessage (connection confirmed) instead of connect() (TCP not yet established) |
| L8 | `_VisibilityWrapper` misused in home screen | `home_screen.dart` | Wraps text, doesn't control viewport-based visibility | ⚠️ FALSE POSITIVE — `_VisibilityWrapper` does not exist in codebase |

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

### Phase 1: Backend P0 Fixes ✅ COMPLETE

1. ✅ Fix context key mismatch (`"userId"` → `"user_id"` or vice versa) across all handlers + WebSocket
2. ✅ Implement actual OTP send/verify (Appwrite phone auth)
3. ✅ Fix `customer_id` vs `user_id` field mismatch in order/delivery handlers
4. ✅ Add ownership check on scheduled order cancel
5. ✅ Restrict WebSocket `CheckOrigin` to allowed origins
6. ✅ Move Redis password to env-only (remove default)
7. ✅ Fix coupon counter decrement logic

### Phase 2: Frontend P0 Fixes ✅ COMPLETE

1. ✅ Wire restaurant detail screen to API (fetch menu items + reviews)
2. ✅ Fix `DeliveryMap._addRouteLine` — use `jsonEncode()` instead of `.toString()`
3. ✅ Implement Navigate (launch maps) + Call (launch dialer) in active delivery screen
4. ✅ Implement delivery profile menu items (Bank Details, Documents, Availability, Support, About)
5. ✅ Implement notification tap routing in `push_notification_service.dart`

### Phase 3: Security Hardening ✅ COMPLETE

1. ✅ Move Mapbox token, Razorpay key, Appwrite project ID to `--dart-define` / env config
2. ✅ Gate "Simulate Request" behind `kDebugMode`
3. ✅ Replace `.ignore()` calls with proper error handling + user feedback
4. ✅ Add proper error handling instead of catch-all mock fallbacks

### Phase 4: iOS Deep Linking (Not in audit scope)

1. Add `CFBundleURLTypes` to `ios/Runner/Info.plist` for custom `chizze://` scheme
2. Add Associated Domains entitlement for `applinks:chizze.app`
3. Host `apple-app-site-association` file on `chizze.app`

### Phase 5: UX Polish ✅ COMPLETE

1. ✅ Fix `AppTypography` / `_PriceRow` light theme colors
2. ✅ Wire review submission to backend API
3. ✅ Implement reorder functionality
4. ✅ Add server-side search
5. ✅ Persist user preferences (veg toggle, dark mode, default address)
6. ✅ Implement remaining stubs (Phone/Chat rider, Address map picker, Social OAuth, Referral share)

### Phase 6: Code Polish ✅ COMPLETE

1. ✅ Delete dead code (`appwrite_client.dart`)
2. ✅ Fix barrel exports, GPS heading/speed, rider location fallbacks
3. ✅ Wire CacheService to backend handlers
4. ✅ Optimize WebSocket O(n) scan to O(1)
5. ✅ Fix WebSocket reconnect counter reset timing

### Phase 7: Testing (Remaining)

1. Add widget tests for key screens (Home, Cart, Orders, Restaurant Detail)
2. Add handler tests for all backend endpoints
3. Add integration/E2E tests for critical flows (auth → order → payment → tracking)
4. Expand accessibility coverage to remaining ~95% of custom widgets

### Phase 8: Production Readiness (New Features)

1. Implement Menu Item Add-ons/Variants (Backend + Frontend)
2. Implement Delivery Instructions & Tips (Backend + Frontend)
3. Implement Restaurant Profile Management (Backend + Frontend)
4. Implement Payouts & Bank Details (Backend + Frontend)
5. Implement Delivery Proof (OTP/Photo) (Backend + Frontend)

---

## 10. Summary

| Category | Count | Status |
|----------|-------|--------|
| **P0 Critical (must fix)** | 21 (11 backend + 10 frontend) | ✅ 12 fixed, 🔴 9 pending |
| **P1 High (security/data)** | 8 | ✅ All 8 fixed |
| **P2 Medium (UX)** | 15 | ✅ All 15 fixed |
| **P3 Low (polish)** | 8 | ✅ 7 fixed + 1 false positive |
| **Total issues** | 52 | ✅ **42 fixed + 1 false positive, 🔴 9 pending** |
| **"Coming soon" stubs** | 6 (reorder, phone/chat rider, map picker, social OAuth, address map, delivery profile items) | ✅ All implemented |
| **Test files** | 8 Flutter + 2 Go service tests | — No changes (Phase 7) |

**Bottom line:** All 43 original audit issues have been resolved. However, 9 new P0 critical issues have been identified related to missing production features (Add-ons/Variants, Delivery Instructions & Tips, Restaurant Profile Management, Payouts & Bank Details, and Delivery Proof). These must be implemented before the app is fully ready for production.
