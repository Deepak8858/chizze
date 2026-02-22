# Chizze — Project Status

> **Last Updated:** 2026-02-25T14:00:00+05:30
> **Current Phase:** Phase 9 — Production Deployment & CI/CD (COMPLETE)
> **Phase Status:** ✅ Phase 9 COMPLETE
> **Next Action:** Production launch — configure secrets, deploy to VPS

---

## Quick Context (for LLM continuity)

```yaml
project: Chizze — Food Delivery App (India market)
type: Mobile-only (Android 8.0+ / iOS 15.0+)
stack:
  frontend: Flutter 3.x + Dart 3.10
  state_management: Riverpod (StateNotifier pattern)
  navigation: GoRouter (auth-based redirects)
  backend_baas: Appwrite Cloud (sgp.cloud.appwrite.io)
  backend_api: Go 1.22 (Gin framework) — FULLY IMPLEMENTED
  database: Appwrite Collections (managed by Appwrite Cloud)
  storage: Appwrite Storage (managed)
  payments: Razorpay (razorpay_flutter 1.4.1 + Go server-side)
  maps: Google Maps (planned)
  cache: Redis 8.6.0 (165.232.177.81:6379, go-redis/v9)
appwrite:
  endpoint: https://sgp.cloud.appwrite.io/v1
  project_id: "6993347c0006ead7404d"
  database_id: "chizze_db"
  collections: users, addresses, restaurants, menu_categories, menu_items, orders, delivery_requests, rider_locations, reviews, coupons, payments, notifications
apps:
  - Customer App (Flutter, implemented through Phase 3)
  - Restaurant Partner App (Flutter routes planned, Go handler ready)
  - Delivery Partner App (Flutter routes planned, Go handler ready)
design_system:
  theme: Dark mode + Light mode (user toggle)
  primary_color: "#F49D25" (orange)
  font: Plus Jakarta Sans (400-800 weights)
  style: Glassmorphism cards, gradient CTAs, staggered animations
```

---

## Phase Overview

| Phase | Name | Weeks | Status | Progress |
|---|---|---|---|---|
| 1 | Foundation | 1-3 | ✅ COMPLETE | 100% |
| 2 | Customer Core | 4-6 | ✅ COMPLETE | 100% |
| 3 | Ordering & Payments | 7-9 | ✅ COMPLETE | 100% |
| 3.5 | Go Backend + Auth/Payment Bridge | — | ✅ COMPLETE | 100% |
| 3.5+ | Production Hardening | — | ✅ COMPLETE | 100% |
| 4 | Restaurant Partner | 10-12 | ✅ COMPLETE + AUDITED | 100% |
| 5 | Delivery Partner | 13-15 | ✅ COMPLETE | 100% |
| 6 | Polish & Advanced | 16-18 | ✅ COMPLETE | 100% |
| 7 | Real-time & Workers | — | ✅ COMPLETE | 100% |
| 8 | Testing & Quality Assurance | — | ✅ COMPLETE | 100% |
| 9 | Production Deployment & CI/CD | — | ✅ COMPLETE | 100% |

---

## Phase 1 — Foundation (COMPLETE)

### 1.1 Project Setup ✅

- [x] Flutter project initialized, 134+ packages
- [x] Asset directories, analysis clean

### 1.2 Design System ✅

- [x] AppColors, AppTypography, AppSpacing, AppTheme, barrel exports

### 1.3 Core Widgets ✅

- [x] GlassCard, ChizzeButton/ChipButton, ShimmerLoader

### 1.4 Architecture ✅

- [x] Appwrite service providers, Auth provider, GoRouter

### 1.5 Auth Screens ✅

- [x] Splash, Login, OTP screens

---

## Phase 2 — Customer Core (COMPLETE)

### 2.1 Data Models ✅

- [x] Restaurant, MenuItem, MenuCategory, CartItem, CartState models

### 2.2 State Management ✅

- [x] CartProvider with full operations

### 2.3–2.7 Screens ✅

- [x] Home (enhanced), Search, Restaurant Detail, Cart, Router updates

---

## Phase 3 — Ordering & Payments (COMPLETE)

### 3.1 Razorpay Payment Integration ✅

- [x] `razorpay_flutter` package added (v1.4.1, official SDK)
- [x] `payment_provider.dart` — Full Razorpay integration:
  - Opens Razorpay checkout with Chizze orange branding
  - Handles success, error, and external wallet callbacks
  - Converts amounts to paise for Razorpay API
  - Creates Order from CartState after payment
  - Clears cart on successful payment
  - Configurable test/live key via `RazorpayConfig`
- [x] `payment_screen.dart` — Payment method selection:
  - Order summary with item list and bill breakdown
  - Delivery tip selector (₹0/20/30/50)
  - Payment method cards: "Pay Online" (Razorpay) with UPI/Cards/Wallets/Net Banking, "Cash on Delivery"
  - Radio selection with animated highlighting
  - Error display for failed payments
  - Split-layout pay bar (Total on left, Pay button on right)
  - COD orders bypass Razorpay gateway

### 3.2 Order Model & State ✅

- [x] `order.dart` — Full order model:
  - 8-stage lifecycle: placed → confirmed → preparing → ready → picked_up → out_for_delivery → delivered → cancelled
  - OrderStatus enum with labels, emoji, and progress percentage
  - OrderItem with veg/non-veg, customizations
  - fromMap/toMap for Appwrite serialization
  - copyWith for status updates
  - Mock orders for UI development
- [x] `orders_provider.dart` — Orders state management:
  - Active and past order filtering
  - Add new orders (from payment)
  - Update status (from Appwrite Realtime)
  - Query by ID

### 3.3 Order Confirmation ✅

- [x] `order_confirmation_screen.dart`:
  - Animated success check (elastic scale animation)
  - Order number and ETA display
  - Order details card (restaurant, items, payment method, total)
  - Track Order button → order tracking
  - Back to Home link

### 3.4 Order Tracking ✅

- [x] `order_tracking_screen.dart`:
  - Status header with emoji and description
  - Vertical timeline with 7 stages, glowing current step with shadow
  - Completed steps show green checkmarks
  - ETA card with countdown
  - Delivery partner card with call/chat buttons (appears on pickup)
  - Order items summary with totals
  - "Rate this Order" button (appears on delivery)
  - **Demo mode**: Auto-progresses through statuses every 8 seconds for testing

### 3.5 Order History ✅

- [x] `orders_screen.dart`:
  - Active/Past tabs with counts
  - Order cards with status badges (color-coded by stage)
  - Item preview (shows first 2 items + "more" count)
  - Relative date formatting (min/hours/yesterday/date)
  - Active orders: "Track Order" button
  - Past orders: "Reorder" + "Rate" buttons
  - Empty states for both tabs

### 3.6 Review & Rating ✅

- [x] `review_screen.dart`:
  - Restaurant info card
  - Star ratings for food (animated scale on select)
  - Star ratings for delivery
  - Selectable tag chips: 😋 Great Food, 🚀 Fast Delivery, 📦 Well Packed, etc.
  - Optional text review field
  - Submit button (disabled until food rating given)

### 3.7 Router & Navigation Updates ✅

- [x] `/payment` route (standalone)
- [x] `/order-confirmation/:id` route (standalone)
- [x] `/order-tracking/:id` route (standalone)
- [x] `/order-detail/:id` route (reuses tracking screen)
- [x] `/review/:id` route (standalone)
- [x] `/orders` tab now uses real OrdersScreen instead of placeholder
- [x] Cart checkout button now navigates to `/payment`

---

## Phase 3.5 — Go Backend + Auth/Payment Bridge (COMPLETE)

### 3.5.1 Go Backend Infrastructure ✅

- [x] Go 1.22, Gin framework, `github.com/chizze/backend` module
- [x] Config from `.env` (Appwrite, Razorpay, Redis, JWT)
- [x] Graceful shutdown with signal handling
- [x] CORS, Gzip, request timeout middleware
- [x] Health check endpoint with Redis status

### 3.5.2 Redis Integration ✅

- [x] go-redis/v9 client (`pkg/redis/redis.go`)
- [x] Connection pooling (min 5, max 50 connections)
- [x] Redis-backed rate limiting middleware
- [x] Token blacklist for JWT revocation
- [x] Health check probing

### 3.5.3 Appwrite SDK (Custom Go) ✅

- [x] Custom Appwrite REST client (`pkg/appwrite/client.go`)
- [x] JWT verification via `GET /account` with `X-Appwrite-JWT`
- [x] Full CRUD for all 12 collections
- [x] Query support (equal, search, greater/less than, limit, offset)

### 3.5.4 Authentication Flow ✅

- [x] `POST /auth/exchange` — Appwrite JWT → Go JWT (HS256, 7-day expiry)
- [x] `POST /auth/send-otp` — Redis rate-limited (3/phone/10min)
- [x] `POST /auth/verify-otp` — Session verification
- [x] `POST /auth/refresh` — Redis blacklist check + re-issue JWT
- [x] `DELETE /auth/logout` — Redis blacklist (7-day TTL)
- [x] Auth middleware: JWT validation → userID + role in context
- [x] RequireRole middleware for partner/delivery routes
- [x] Flutter auth bridge: `_exchangeToken()` after every Appwrite auth
- [x] Dio 401 interceptor → automatic JWT refresh via re-exchange

### 3.5.5 Payment Flow (Server-Side) ✅

- [x] `POST /payments/initiate` — Creates Razorpay order from app order
- [x] `POST /payments/verify` — HMAC-SHA256 signature verification
- [x] `POST /payments/webhook` — Razorpay webhook handler (captured/failed/refund)
- [x] Flutter payment provider calls Go backend with `order_id`
- [x] Server-side amount sourced from order (prevents client tampering)
- [x] Razorpay key_id returned to client from server
- [x] Test keys configured: `rzp_test_SIjgJ176oKm8mn`

### 3.5.6 All Handlers Implemented ✅

- [x] **auth_handler.go** — Exchange, SendOTP, VerifyOTP, Refresh, Logout
- [x] **restaurant_handler.go** — List, Nearby (Haversine), GetDetail, GetMenu, GetReviews
- [x] **menu_handler.go** — CRUD with ownership validation (restaurant_owner)
- [x] **order_handler.go** — PlaceOrder (server-side price verification, fee calc, coupon), ListOrders, GetOrder, CancelOrder, UpdateStatus (role-based)
- [x] **payment_handler.go** — Initiate, Verify, Webhook
- [x] **delivery_handler.go** — ToggleOnline, UpdateLocation, AcceptOrder, ActiveOrders
- [x] **review_handler.go** — CreateReview (ownership, duplicate check), ReplyToReview, async rating aggregation
- [x] **coupon_handler.go** — ListAvailable, Validate (date parsing, min order, usage limits)
- [x] **notification_handler.go** — List, MarkRead, MarkAllRead
- [x] **user_handler.go** — GetProfile, UpdateProfile (field whitelist), Address CRUD

### 3.5.7 Three-Tier Route Architecture ✅

- [x] **Public** — `/restaurants/*`, `/coupons`, `/auth/*`
- [x] **Authenticated (any role)** — `/users/*`, `/orders/*`, `/payments/*`, `/notifications/*`
- [x] **Partner (restaurant_owner)** — `/partner/menu/*`, `/partner/orders/:id/status`, `/partner/reviews/:id/reply`
- [x] **Delivery (delivery_partner)** — `/delivery/status`, `/delivery/location`, `/delivery/orders/*`
- [x] **Webhooks (signature-verified)** — `/payments/webhook`

### 3.5.8 Fee Calculation Logic ✅

- [x] Free delivery ≥ ₹299, else ₹8/km (min ₹20, max ₹80)
- [x] Flat ₹5 platform fee
- [x] 5% GST on subtotal
- [x] Coupon discount with server-side validation

---

## Phase 3.5+ — Production Hardening (COMPLETE)

> Full security + correctness audit of all 37 Go files and ~60 Flutter files.
> 30 backend issues and 28 Flutter issues identified. Critical/high items fixed below.

### Backend Security Fixes ✅

- [x] **auth.go** — Redis token blacklist check on every request (not just refresh)
- [x] **auth.go** — JWT algorithm pinning (`jwt.WithValidMethods([]string{"HS256"})`) — prevents `none` algorithm attack
- [x] **auth.go** — JWT issuer validation (`jwt.WithIssuer("chizze-api")`)
- [x] **auth_handler.go** — OTP rate limit fixed: was string comparison `count >= "3"`, now `strconv.Atoi` + integer check
- [x] **config.go** — Added `RazorpayWebhookSecret` field from `RAZORPAY_WEBHOOK_SECRET` env var
- [x] **config.go** — Removed hardcoded Appwrite project ID default
- [x] **payment_service.go** — Separate `webhookSecret` field (was reusing API secret)
- [x] **payment_service.go** — Shared `http.Client` instance (was creating new client per request)
- [x] **cors.go** — Fixed `AllowAllOrigins: true` + `AllowCredentials: true` conflict (violates CORS spec)
- [x] **cors.go** — Added `X-Idempotency-Key` to allowed headers
- [x] **cors.go** — Added `MaxAge: 12h` for preflight caching

### Backend Correctness Fixes ✅

- [x] **order_service.go** — Order number collision fix: `CHZ-<unix_ms%1M>-<6 hex via crypto/rand>`
- [x] **redis.go** — Added `SetNX(ctx, key, value, expiration)` method for distributed locking
- [x] **order_handler.go** — Added Redis to handler struct and constructor
- [x] **order_handler.go** — Idempotency key on PlaceOrder: `X-Idempotency-Key` header → Redis cache (24h TTL) → returns cached response on replay
- [x] **order_handler.go** — Atomic coupon usage: Redis `INCR` on `coupon_usage:<id>` with rollback if over limit
- [x] **delivery_handler.go** — Added Redis to handler struct and constructor
- [x] **delivery_handler.go** — Distributed lock on AcceptOrder: `SetNX("delivery_lock:<orderID>", userID, 30s)` prevents double-accept
- [x] **security.go** — Added `MaxBodySize(2MB)` middleware using `http.MaxBytesReader`
- [x] **main.go** — Updated all `Auth()` calls to pass Redis client — enables blacklist checking
- [x] **main.go** — Updated handler constructors: `NewOrderHandler(…, redisClient)`, `NewDeliveryHandler(…, redisClient)`
- [x] **main.go** — Added MaxBodySize middleware to global chain

### Flutter Production Blockers Fixed ✅

- [x] **environment.dart** — Full environment config: `--dart-define=ENV=dev|staging|production`, `--dart-define=API_URL=…`
- [x] **api_config.dart** — Hardcoded private IP (`10.163.246.51`) → `Environment.apiBaseUrl` getter
- [x] **api_client.dart** — `const Duration` → non-const (required for env-based baseUrl)
- [x] **restaurant_provider.dart** — [NEW] API-backed restaurant provider with mock fallback
- [x] **home_screen.dart** — `Restaurant.mockList` → `restaurantProvider` (API-backed)
- [x] **payment_provider.dart** — Added `placeBackendOrder()` for real backend order creation
- [x] **payment_screen.dart** — Complete rewrite: real auth data, real address, backend order first, then Razorpay/COD
- [x] **payment_provider.dart** — Razorpay key now `String.fromEnvironment('RAZORPAY_KEY', …)` — configurable per build

### Flutter Critical Fixes ✅

- [x] **orders_provider.dart** — Removed `Order.mockList` fallback in catch blocks → empty list + error
- [x] **auth_provider.dart** — Removed OTP value from debug log, gated success log behind `kDebugMode`
- [x] **api_client.dart** — JWT persistence via `flutter_secure_storage`: `persistToken()`, `loadPersistedToken()`, `clearPersistedToken()`
- [x] **auth_provider.dart** — `_exchangeToken()` now calls `persistToken()` after successful exchange
- [x] **auth_provider.dart** — `checkSession()` restores persisted JWT before falling back to full exchange
- [x] **auth_provider.dart** — `logout()` calls `clearPersistedToken()`
- [x] **auth_provider.dart** — Refresh callback also persists new token
- [x] **search_screen.dart** — `Restaurant.mockList` → `restaurantProvider` (API-backed)
- [x] **restaurant_detail_screen.dart** — Restaurant lookup from provider first, mock fallback if not found

### Infrastructure ✅

- [x] **.gitignore** — Added: `*.env`, `backend/.env`, `appwrite.config.json`, `local.properties`, analysis/build output files, backend artifacts
- [x] **backend/.dockerignore** — [NEW] Excludes .env, tests, tools, IDE files from Docker build context
- [x] **backend/.env.example** — Added `RAZORPAY_WEBHOOK_SECRET` entry

---

## File Tree (Current)

```
H:\chizze\
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── auth/
│   │   │   └── auth_provider.dart              # [UPDATED] JWT persistence, refresh persist, log sanitization
│   │   ├── constants/
│   │   │   └── appwrite_constants.dart
│   │   ├── router/
│   │   │   └── app_router.dart                # [UPDATED] + Phase 3 routes
│   │   ├── services/
│   │   │   ├── appwrite_service.dart
│   │   │   ├── api_client.dart                # [UPDATED] flutter_secure_storage, persist/load/clear token
│   │   │   └── api_config.dart                # [UPDATED] Environment-based baseUrl getter
│   │   └── theme/
│   │       ├── app_colors.dart
│   │       ├── app_spacing.dart
│   │       ├── app_theme.dart
│   │       ├── app_typography.dart
│   │       └── theme.dart
│   ├── features/
│   │   ├── auth/screens/
│   │   │   ├── login_screen.dart
│   │   │   └── otp_screen.dart
│   │   ├── cart/
│   │   │   ├── providers/
│   │   │   │   └── cart_provider.dart          # [UPDATED] import fix + checkout nav
│   │   │   └── screens/
│   │   │       └── cart_screen.dart            # [UPDATED] → /payment
│   │   ├── home/
│   │   │   ├── models/
│   │   │   │   └── restaurant.dart
│   │   │   ├── providers/
│   │   │   │   └── restaurant_provider.dart   # [NEW] API-backed restaurant fetching
│   │   │   └── screens/
│   │   │       └── home_screen.dart           # [UPDATED] Uses restaurantProvider
│   │   ├── orders/                             # [NEW] Phase 3
│   │   │   ├── models/
│   │   │   │   └── order.dart                 # Order + OrderItem + OrderStatus
│   │   │   ├── providers/
│   │   │   │   └── orders_provider.dart       # [UPDATED] Removed mock fallback
│   │   │   └── screens/
│   │   │       ├── order_confirmation_screen.dart  # Post-payment success
│   │   │       ├── order_tracking_screen.dart      # Real-time tracking
│   │   │       ├── orders_screen.dart              # Active/Past history
│   │   │       └── review_screen.dart              # Rating & review
│   │   ├── payment/                            # [NEW] Phase 3
│   │   │   ├── providers/
│   │   │   │   └── payment_provider.dart      # [UPDATED] placeBackendOrder(), env-based Razorpay key
│   │   │   └── screens/
│   │   │       └── payment_screen.dart        # [UPDATED] Real auth/address/backend flow
│   │   ├── restaurant/
│   │   │   ├── models/
│   │   │   │   └── menu_item.dart
│   │   │   └── screens/
│   │   │       └── restaurant_detail_screen.dart
│   │   ├── search/
│   │   │   └── screens/
│   │   │       └── search_screen.dart         # [UPDATED] Uses restaurantProvider
│   │   └── splash/screens/
│   │       └── splash_screen.dart
│   └── shared/widgets/
│       ├── chizze_button.dart
│       ├── glass_card.dart
│       ├── shimmer_loader.dart
│       └── widgets.dart
├── assets/ (images, icons, animations, fonts dirs)
├── backend/                                    # [NEW] Phase 3.5 — Go API
│   ├── .env                                   # Config (Appwrite, Razorpay, Redis, JWT)
│   ├── .env.example                           # [UPDATED] + RAZORPAY_WEBHOOK_SECRET
│   ├── .dockerignore                          # [NEW] Docker build context exclusions
│   ├── go.mod / go.sum
│   ├── cmd/server/main.go                     # [UPDATED] Redis params, handler constructors, body size limit
│   ├── internal/
│   │   ├── config/config.go                   # [UPDATED] + RazorpayWebhookSecret, no hardcoded project ID
│   │   ├── handlers/                          # All 10 handlers
│   │   │   ├── auth_handler.go                # [UPDATED] OTP rate limit int fix
│   │   │   ├── restaurant_handler.go          # List, Nearby, Detail, Menu, Reviews
│   │   │   ├── menu_handler.go                # CRUD (restaurant_owner only)
│   │   │   ├── order_handler.go               # [UPDATED] + Redis, idempotency, atomic coupons
│   │   │   ├── payment_handler.go             # Initiate, Verify, Webhook
│   │   │   ├── delivery_handler.go            # [UPDATED] + Redis, distributed lock on AcceptOrder
│   │   │   ├── review_handler.go              # Create, Reply
│   │   │   ├── coupon_handler.go              # List, Validate
│   │   │   ├── notification_handler.go        # List, MarkRead, MarkAllRead
│   │   │   └── user_handler.go                # Profile, Address CRUD
│   │   ├── middleware/
│   │   │   ├── auth.go                        # [UPDATED] Redis blacklist, JWT algo pinning, issuer
│   │   │   ├── cors.go                        # [UPDATED] Credentials fix, idempotency header
│   │   │   ├── security.go                    # [UPDATED] + MaxBodySize middleware
│   │   │   └── rate_limit.go                  # Redis-backed rate limiting
│   │   ├── models/                            # Constants (OrderStatus, PaymentStatus)
│   │   └── services/
│   │       ├── appwrite_service.go            # Collection CRUD via Appwrite REST
│   │       ├── payment_service.go             # [UPDATED] Webhook secret, shared http.Client
│   │       ├── order_service.go               # [UPDATED] crypto/rand order number
│   │       └── geo_service.go                 # Haversine distance calculation
│   └── pkg/
│       ├── appwrite/client.go                 # Custom Appwrite REST client + JWT verify
│       ├── redis/redis.go                     # [UPDATED] + SetNX for distributed locking
│       └── utils/response.go                  # Gin response helpers
├── pubspec.yaml
├── design.md
├── implementation_plan.md
├── production_architecture.md
└── status.md
```

---

## Complete User Flow (Phases 1-3.5)

```
App Launch → Splash (animated) → Auth Check
  │
  ├── checkSession() → Appwrite account.get()
  │     ├── Success → _exchangeToken() → POST /auth/exchange { jwt } → Go JWT set
  │     └── Fail → Login Screen
  │
  ├── Not authenticated → Login → Phone OTP / Social / Email → OTP Verify
  │     └── _exchangeToken() → POST /auth/exchange { jwt } → Go JWT set
  │
  └── Authenticated (Go JWT + Appwrite session) → Home Screen
        │
        │  ┌─── 401 on any API call? ───┐
        │  │ Dio interceptor auto-refreshes via re-exchange │
        │  └────────────────────────────────┘
        │
        ├── Search bar → Search Screen (filters, sort, results)
        ├── Category chips → Search Screen
        ├── Restaurant card → Restaurant Detail
        │     ├── Browse menu by category
        │     ├── Toggle veg only
        │     ├── ADD item (with customization sheet)
        │     └── Cart bar → Cart Screen
        │           ├── Edit quantities
        │           ├── Special/delivery instructions
        │           ├── View bill summary
        │           └── Proceed to Payment → Payment Screen
        │                 ├── Choose: Razorpay (UPI/Card/Wallet) or COD
        │                 ├── Add delivery tip
        │                 └── Pay → POST /orders → POST /payments/initiate
        │                       → Razorpay SDK opens (server-provided order_id)
        │                       ├── Success → POST /payments/verify → Order Confirmation
        │                       │                                       ├── Timeline (7 stages)
        │                       │                                       ├── Delivery partner card
        │                       │                                       └── Delivered → Rate Order
        │                       └── Error → Error display + retry
        │
        ├── Logout → DELETE /auth/logout (blacklist JWT) → Appwrite session delete
        │
        └── Bottom Nav
              ├── Home
              ├── Search
              ├── Orders (Active/Past tabs)
              │     ├── Active → Track Order
              │     └── Past → Reorder / Rate
              └── Profile (placeholder)
```

### Auth Flow Detail
```
Flutter                     Appwrite Cloud                   Go Backend (Gin)
  │                              │                               │
  ├── createPhoneToken() ───────►│                               │
  │◄── token (userId) ──────────│                               │
  ├── createSession(otp) ──────►│                               │
  │◄── session ─────────────────│                               │
  ├── createJWT() ─────────────►│                               │
  │◄── JWT (15min) ─────────────│                               │
  ├── POST /auth/exchange ──────┼──────────────────────────────►│
  │   { "jwt": "eyJ..." }      │                               │
  │                              │◄── GET /account (X-Appwrite-JWT)
  │                              │──── account data ───────────►│
  │                              │                               ├─ Find/create user
  │                              │                               ├─ Issue Go JWT (7d)
  │◄── { token, role } ─────────┼───────────────────────────────│
  ├── setAuthToken(goJWT)       │                               │
  │                              │                               │
  │── All API calls use Go JWT ─┼──────────────────────────────►│ Auth middleware validates
```

### Payment Flow Detail
```
Flutter                        Go Backend                    Razorpay API
  │                              │                               │
  ├── POST /orders ─────────────►│ (creates order in Appwrite)  │
  │◄── { order_id } ────────────│                               │
  ├── POST /payments/initiate ──►│                               │
  │   { "order_id": "..." }     │                               │
  │                              ├─ Fetch order, get grand_total │
  │                              ├─ POST /v1/orders ────────────►│
  │                              │◄── { id: "order_xxx" } ──────│
  │                              ├─ Store payment record         │
  │◄── { razorpay_order_id,  ───│                               │
  │      razorpay_key_id,        │                               │
  │      amount, currency }      │                               │
  ├── Razorpay.open(options) ───┼──────────────────────────────►│
  │◄── PaymentSuccess ──────────┼───────────────────────────────│
  ├── POST /payments/verify ────►│                               │
  │   { order_id, payment_id,   │                               │
  │     signature }              ├─ HMAC-SHA256 verify           │
  │                              ├─ Update payment + order       │
  │◄── { verified: true } ──────│                               │
  │                              │                               │
  │                              │◄── Webhook (backup) ─────────│
  │                              ├─ Verify webhook signature     │
  │                              ├─ Update payment + order       │
```

---

## Phase 4 — Restaurant Partner (COMPLETE)

### What's Done (100%)

**Backend — Go API (100% complete)**
- `partner_handler.go` — 9 endpoints: Dashboard, ListOrders, Analytics, Performance, ToggleOnline, ListCategories, CreateCategory, UpdateCategory, DeleteCategory
- `appwrite_service.go` — 4 new category CRUD methods (Get, Create, Update, Delete)
- `main.go` — 13 partner routes registered under `/api/v1/partner/*` with JWT auth

**Flutter — Providers wired to API (100% complete)**
- `partner_provider.dart` — Dashboard metrics + orders from API, Realtime subscription with 15s polling fallback, new order detection, connection status tracking, haptic feedback on accept/reject
- `menu_management_provider.dart` — Menu items + categories from API, full CRUD with image upload via Appwrite Storage
- `analytics_provider.dart` — Revenue trends, top items, peak hours from API, period filter

**Flutter — Services (NEW)**
- `image_upload_service.dart` — Appwrite Storage upload for menu items, restaurants, review photos; image picker integration with quality/size compression
- `order_notification_service.dart` — Local notifications + haptic feedback for new orders; repeated 10s alert timer for unattended orders; platform-specific notification channels

**Flutter — Screens (4 screens, all enhanced)**
- `partner_dashboard_screen.dart` — Metrics cards, online/offline toggle, active orders, **connection status banner** (shows when Realtime degraded to polling or disconnected), **new order alert banner** with tap-to-view
- `partner_orders_screen.dart` — Tabbed order list (New/Preparing/Ready/Completed) with countdown timer, **enhanced reject dialog** with 5 selectable reasons (Too busy, Items unavailable, Kitchen closing, etc.)
- `menu_management_screen.dart` — Category/item CRUD, **image picker** in add/edit bottom sheet with preview, item card now shows thumbnail from CachedNetworkImage, upload progress state
- `analytics_screen.dart` — Bar chart, top items list, peak hours heatmap

### What Was Completed in This Session

| Task | Status | Details |
|---|---|---|
| Real-time order updates | ✅ DONE | Appwrite Realtime + 15s polling fallback, connection status enum, new order detection via ID diff |
| Image upload for menu items | ✅ DONE | ImageUploadService (Appwrite Storage), image picker in menu sheet, thumbnail in item cards |
| Order accept/reject flow | ✅ DONE | Haptic feedback (confirm/reject), 5 selectable reject reasons, notification sound + repeated alert |
| Menu item availability toggle | ✅ DONE | Was already implemented in provider + screen |
| Printer integration | ⏳ DEFERRED | Thermal printer receipt support (Phase 6 candidate) |

### Post-Phase 4 Comprehensive Audit

**Audit scope:** Full codebase static analysis + deep logic review of all Phase 1-4 code.
**Result:** 25 issues identified (5 compile/runtime errors, 3 logic errors, 11 warnings, 6 info). **All 25 fixed.** `flutter analyze` now reports **0 issues**.

| ID | Severity | File | Issue | Fix |
|---|---|---|---|---|
| E1 | ERROR | rider_location_provider.dart | `_mockTimer` undefined (dead code from mock removal) | Removed dead references |
| E2 | ERROR | menu_management_provider.dart | `String?` to `String` type mismatch on imageUrl | Added `?? ''` fallback |
| E3 | ERROR | partner_provider.dart | `_parseOrders` mutates unmodifiable Appwrite map | `Map<String, dynamic>.from()` copy |
| E4 | ERROR | partner_provider.dart | Unsafe hard cast of `dashboardResponse.data` | Added `is Map<String, dynamic>` type check |
| E5 | ERROR | order.dart | `DateTime.tryParse` receives non-String type | Added `.toString()` to all 5 date fields |
| L1 | LOGIC | partner_provider.dart | Confirmed orders disappear from all tabs | Added `OrderStatus.confirmed` to `preparingOrders` getter |
| L2 | LOGIC | partner_provider.dart | `completedOrders` includes in-transit statuses | Restricted to `delivered` + `cancelled` only |
| L3 | LOGIC | menu_management_provider.dart | `toggleItemAvailability` drops 6 fields (data loss) | Added `imageUrl`, `spiceLevel`, `preparationTimeMin`, `calories`, `allergens`, `sortOrder` |
| L4 | LOGIC | partner_provider.dart | Order data nested inside dashboard success check | Decoupled — each parsed independently with fallback |
| L5 | WARNING | partner_provider.dart | Fire-and-forget API calls — no error handling | Added `.catchError` rollback on all 4 order mutations |
| L6 | WARNING | menu_management_provider.dart | `addItem` temp item stuck on API failure | Added `.catchError` to remove temp item |
| L7 | WARNING | partner_dashboard_screen.dart | Settings quick action navigates to self | Changed route to `/partner/menu` |
| L9 | WARNING | partner_dashboard_screen.dart | Hardcoded reject reason from dashboard | Added `_showQuickRejectDialog()` with 5 selectable reasons |
| R1 | WARNING | partner_provider.dart | Realtime never reconnects after failure | Added exponential backoff reconnection (10s-160s, max 5 attempts) |
| R3 | WARNING | api_client.dart | Token refresh interceptor infinite loop risk | Added `_isRefreshing` guard with `finally` reset |
| R4 | WARNING | partner_provider.dart | Polling and realtime could race `_loadData` | Added `_isLoadingGuard` boolean concurrency guard |
| T1 | INFO | menu_management_screen.dart | Null checks on non-nullable `imageUrl` | Changed to `.isNotEmpty` (no null check needed) |
| CTX | INFO | menu_management_screen.dart | `context` used across async gaps | Added `context.mounted` guards in `.then()` callbacks |
| DEP | INFO | partner_orders_screen.dart | Deprecated `RadioListTile` API (Flutter 3.32+) | Migrated to `RadioGroup<String>` + `Radio<String>` |
| DEP | INFO | partner_dashboard_screen.dart | Deprecated `Radio.groupValue/onChanged` | Migrated to `RadioGroup<String>` ancestor pattern |
| UN | INFO | menu_management_screen.dart | Unnecessary underscores in callback params | Replaced with descriptive names |

---

## Phase 5 — Delivery Partner (COMPLETE)

### Flutter — Models, Providers, Screens (100%)

**Models**
- `delivery_partner.dart` — `DeliveryPartner` (fromDashboard, copyWith with vehicleType/vehicleNumber, empty), `DeliveryRequest` (fromMap, mock, countdown, expiry), `DeliveryMetrics` (fromDashboard, weekly goals), `DeliveryStep` enum, `ActiveDelivery` (step progression)

**Providers**
- `delivery_provider.dart` — Full `DeliveryNotifier` with `_isLoadingGuard`, Appwrite Realtime subscription for delivery requests, **real GPS tracking** via `LocationService.getPositionStream()` (10m distance filter) + 15s push timer with one-shot fallback, `toggleOnline()` with rollback, `acceptRequest()` / `rejectRequest()`, step-by-step `advanceStep()` / `completeDelivery()`, `updateProfile()` (vehicle type, number, bank account), `fetchPerformance()`, `simulateNewRequest()` for testing
- `earnings_provider.dart` — Complete rewrite: `EarningsPeriod` enum (today/week/month/custom), `TripEarning.fromMap()`, `DailyEarning.fromMap()`, `PayoutRecord.fromMap()` + status helpers, `EarningsState.copyWith()` with computed `avgPerTrip` / `weeklyAvgPerTrip`, `EarningsNotifier` with `_isLoadingGuard`, `selectPeriod()`, `setCustomRange()`, `fetchEarnings()` (period-aware), `fetchPayouts()`, `requestPayout()` (bank_transfer default), `refresh()`, `clearError()`

**Screens (4 screens)**
- `delivery_dashboard_screen.dart` — Online/offline toggle, today metrics, weekly goal progress, incoming request card with countdown, active delivery banner, simulate button, quick actions grid
- `active_delivery_screen.dart` — Live map with markers, step progress circles, navigate/call buttons, veg/non-veg indicators, earning/distance/payment info, step advancement, delivery complete dialog
- `earnings_screen.dart` — Period selector chips, custom date range picker, summary cards, breakdown tiles, weekly bar chart, recent trips list with surge/tip badges, payout section with request + confirmation dialog
- `delivery_profile_screen.dart` — Avatar with gradient, rating, phone, 3-column stats, vehicle card, menu items (Bank Details, Documents, Availability, Support, About), logout with confirmation

**API Config**
- `deliveryPayouts`, `deliveryProfile`, `deliveryPayoutRequest` endpoints in `ApiConfig`

**Router**
- All 4 delivery routes pre-configured in `app_router.dart` under delivery shell with bottom nav

### Go Backend — Handlers, Routes, Notifications (100%)

**Models**
- `Payout` struct (ID, PartnerID, UserID, Amount, Status [pending/processing/completed/failed], Method [bank_transfer/upi], Reference, Note, timestamps)
- `RequestPayoutRequest` DTO (Amount binding:required,gt=0; Method binding:required,oneof=bank_transfer upi)
- `UpdateDeliveryProfileRequest` DTO (VehicleType, VehicleNumber, BankAccountID)
- `CollectionPayouts` constant added to `common.go`

**Appwrite Service**
- `CreatePayout`, `GetPayout`, `UpdatePayout`, `ListPayouts` — full CRUD on payouts collection

**Handlers (13 routes total)**
- Existing: ToggleOnline, UpdateLocation, AcceptOrder, ActiveOrders, Dashboard, Earnings, Performance, UpdateStatus
- New: `GetProfile` (GET), `UpdateProfile` (PUT — partial update), `ListPayouts` (GET — paginated), `RequestPayout` (POST — min ₹100, balance check, duplicate prevention, notification), `RejectOrder` (PUT — unassign partner)

**Notification Triggers**
- `AcceptOrder` → customer notification ("Delivery Partner Assigned")
- `UpdateStatus` → customer notifications for all transitions: Confirmed, Preparing, Ready, Picked Up, Out for Delivery, Delivered

### Verification
- `dart analyze lib` — **0 issues**
- `go build ./...` — **0 errors**
- `go vet ./...` — **0 issues**

---

## Phase 6 — Polish & Advanced (COMPLETE)

### 6.1 Dark/Light Theme Toggle ✅

- [x] `userProfileProvider.darkMode` drives `ThemeMode` in `main.dart`
- [x] Full `AppTheme.lightTheme` with semantic light colors
- [x] `AppColors.light*` variants for all surfaces/text
- [x] Toggle on Profile screen

### 6.2 Favorites & Recommendations ✅

**Go Backend**
- [x] `favorite.go` model (UserID, RestaurantID, timestamps)
- [x] `appwrite_service.go` — `ListFavorites`, `AddFavorite`, `RemoveFavorite`
- [x] `favorite_handler.go` — GET/POST/DELETE `/users/me/favorites`
- [x] Routes registered in `main.go`

**Flutter**
- [x] `favorites_provider.dart` — `FavoritesState` + `FavoritesNotifier` with optimistic updates, `toggleFavorite()`
- [x] `favorites_screen.dart` — Empty state, swipe-to-delete cards, rating/cuisine/delivery time
- [x] Heart icon on restaurant cards in `home_screen.dart` — `Positioned(top:8, right:8)` with filled/outline toggle
- [x] 5-tab bottom nav: Home / Search / Favorites / Orders / Profile

### 6.3 Offers UI on Home Screen ✅

- [x] "Offers For You" section header + 130px horizontal carousel on home screen
- [x] `_buildOffersCarousel` — gradient cards (5 color schemes), discount %, coupon code chip, days remaining
- [x] Tap navigates to `/coupons` screen
- [x] Powered by existing `couponsProvider`

### 6.4 Notification Filters ✅

- [x] `_notifFilterProvider` — `StateProvider<NotificationType?>` for active filter
- [x] Filter chips row: All / 📦 Orders / 🎁 Offers / ⚙️ Updates
- [x] `AnimatedContainer` active/inactive styling
- [x] Filtering applied before Today/Earlier grouping

### 6.5 Chizze Gold Membership ✅

**Go Backend**
- [x] `gold.go` model — `GoldPlan`, `GoldSubscription` structs
- [x] `appwrite_service.go` — `ListGoldPlans`, `GetGoldStatus`, `CreateGoldSubscription`, `CancelGoldSubscription`
- [x] `gold_handler.go` — GET plans, GET status, POST subscribe, PUT cancel

**Flutter**
- [x] `gold_provider.dart` — `GoldPlan` (3 tiers: Monthly ₹149 / Quarterly ₹349 / Annual ₹999), `GoldSubscription`, `GoldNotifier` with fetchPlans/fetchStatus/subscribe/cancel
- [x] `gold_screen.dart` — SliverAppBar with gold gradient, active subscription card (progress bar, days left, cancel), 2-column benefits grid (6 items), plan cards with "⭐ Most Popular" badge
- [x] Route `/gold` registered in `app_router.dart`

### 6.6 Referral System ✅

**Go Backend**
- [x] `referral.go` model — `Referral`, `ReferralCode` structs
- [x] `appwrite_service.go` — `GetReferralCode`, `ApplyReferralCode`, `ListReferrals`
- [x] `referral_handler.go` — GET code, POST apply, GET history

**Flutter**
- [x] `referral_provider.dart` — `Referral` model, `ReferralState`, `ReferralNotifier` with fetchReferralCode/fetchReferrals/applyCode
- [x] `referral_screen.dart` — Hero banner (purple gradient), code sharing (copy + share), apply code (TextField + button), how-it-works (4 steps), referral history list
- [x] Route `/referral` registered in `app_router.dart`

### 6.7 Scheduled Orders ✅

**Go Backend**
- [x] `scheduled_order.go` model — `ScheduledOrder`, `CreateScheduledOrderRequest` structs  
- [x] `appwrite_service.go` — `ListScheduledOrders`, `CreateScheduledOrder`, `CancelScheduledOrder`
- [x] `scheduled_order_handler.go` — GET list, POST create, PUT cancel

**Flutter**
- [x] `scheduled_orders_provider.dart` — `ScheduledOrder` model, `ScheduledOrdersNotifier` with fetch/cancel
- [x] `scheduled_orders_screen.dart` — Upcoming/Cancelled sections, status chips (pending/confirmed/cancelled), scheduled time display, cancel dialog
- [x] Route `/scheduled-orders` registered in `app_router.dart`

### 6.8 Push Notification Service ✅

**Go Backend**
- [x] `UpdateFCMToken` handler — PUT `/users/me/fcm-token`
- [x] `fcm_token` attribute on users collection

**Flutter**
- [x] `push_notification_service.dart` — Device token generation + backend registration, `flutter_local_notifications` init, `showLocalNotification()` helper
- [x] Provider `pushNotificationServiceProvider` for DI
- [x] Ready for Firebase messaging swap-in (placeholder token generator)

### 6.9 API Config ✅

- [x] 10 new endpoints added to `ApiConfig`: favorites, goldPlans, goldStatus, goldSubscribe, goldCancel, referralCode, referralApply, referrals, scheduledOrders, fcmToken

### Verification
- `dart analyze lib` — **0 issues**

---

## Phase 7 — Real-time & Workers (COMPLETE)

### 7.1 Go WebSocket Hub ✅

- [x] `internal/websocket/hub.go` — Central Hub with client registry, per-user messaging (`SendToUser`), register/unregister/broadcast channels
- [x] `internal/websocket/client.go` — gorilla/websocket Client with read/write pumps, 60s pong timeout, ping keepalive
- [x] `internal/websocket/events.go` — EventBroadcaster with 6 typed event methods: `BroadcastOrderUpdate`, `BroadcastDeliveryRequest`, `BroadcastDeliveryLocation`, `BroadcastNewOrder`, `BroadcastNotification`, `BroadcastRiderStatusChange`
- [x] WebSocket endpoint: `GET /api/v1/ws` (behind JWT auth middleware)

### 7.2 Go Background Workers ✅

- [x] `internal/workers/delivery_matcher.go` — Matches unassigned ready orders to nearby riders via Redis GeoSearch (5km radius, 15s interval)
- [x] `internal/workers/order_timeout.go` — Auto-cancels orders stuck in "placed" status > 5 minutes (30s interval)
- [x] `internal/workers/scheduled_order_processor.go` — Promotes scheduled orders to "placed" when their time arrives (30s interval, 2min lookahead)
- [x] `internal/workers/notification_dispatcher.go` — Redis queue-based async notification delivery via `BRPop` (10s interval), stores in Appwrite + sends via WebSocket
- [x] All workers wired into `main.go` with context cancellation and graceful shutdown

### 7.3 Handler WebSocket Integration ✅

- [x] `OrderHandler` — Broadcasts `order_update` on status change and cancellation
- [x] `DeliveryHandler` — Broadcasts `delivery_request` on rider assignment, `delivery_location` on live location updates (to all customers with active out-for-delivery orders)
- [x] Variadic constructor pattern for backward compatibility

### 7.4 Flutter WebSocket Client ✅

- [x] `lib/core/services/websocket_service.dart` — Full WebSocket client:
  - Connects to Go backend `/api/v1/ws` with JWT auth
  - Auto-reconnect with exponential backoff (1s → 30s max)
  - Typed `WsEvent` model with `WsEventType` enum (7 event types)
  - Filtered streams: `orderUpdates`, `deliveryLocations`, `notifications`, etc.
  - Heartbeat ping every 25s
  - Riverpod providers: `webSocketServiceProvider`, `wsEventsProvider`, `wsOrderUpdatesProvider`, `wsDeliveryLocationProvider`, `wsNotificationsProvider`
  - `wsAutoConnectProvider` — auto-connects on auth, disconnects on logout
- [x] `web_socket_channel: ^3.0.3` added to pubspec.yaml

### 7.5 Flutter Provider Integration ✅

- [x] `OrdersNotifier` — Listens to WS `order_update` events alongside Appwrite Realtime
- [x] `RiderLocationNotifier` — Listens to WS `delivery_location` events alongside Appwrite Realtime (higher frequency from Go backend)
- [x] `ChizzeApp` (main.dart) — Watches `wsAutoConnectProvider` to activate WS lifecycle

### Verification
- `flutter analyze` — **0 issues**
- `go build ./...` — **0 errors**

---

## Phase 9 — Production Deployment & CI/CD (COMPLETE)

### 9.1 GitHub Actions CI/CD Pipeline ✅

- [x] `.github/workflows/ci.yml` — 5-job pipeline:
  - **go-test**: golangci-lint, `go test ./...`, govulncheck
  - **flutter-test**: `flutter analyze`, `flutter test --coverage`
  - **docker-build**: Multi-platform buildx, GHCR push, layer caching
  - **android-build**: APK (split-per-abi) + AAB, keystore from secrets
  - **deploy**: SSH blue-green deploy with health check + auto-rollback
- [x] Triggers: push main/develop, PRs to main, concurrency group cancellation

### 9.2 Makefile ✅

- [x] `Makefile` — 18 targets: dev, go-build, go-test, go-lint, go-vuln, flutter-test, flutter-lint, android-apk, android-aab, docker-build, docker-up, docker-down, test, lint, build, clean, deploy-staging, deploy-prod

### 9.3 Enhanced Health Endpoints ✅

- [x] `/health` — Liveness probe (always 200, used by container orchestrators)
- [x] `/health/ready` — Readiness probe (checks Redis + Appwrite, returns 503 if degraded)
- [x] Build-time version injection via `-ldflags -X main.version=${VERSION}`
- [x] `appwrite/client.go` — Added `Health()` method for readiness check

### 9.4 Nginx Reverse Proxy ✅

- [x] `deploy/nginx/nginx.conf`:
  - Rate limiting: 100 req/s general, 10 req/min auth endpoints
  - Connection limiting: 50 per IP
  - TLS 1.2+ with modern cipher suite
  - Security headers: HSTS, X-Frame-Options DENY, CSP, X-Content-Type-Options
  - WebSocket upgrade for `/api/v1/ws` (86400s timeout)
  - Upstream: least_conn, keepalive 64
- [x] `deploy/nginx/proxy_params.conf` — Shared proxy headers and timeouts

### 9.5 Production Docker Compose ✅

- [x] `deploy/docker-compose.prod.yml` — 4 services:
  - **nginx**: 1.25-alpine, ports 80/443, SSL + certbot volumes
  - **api**: GHCR image, 2 replicas, 512M RAM / 2 CPU limit, 15s health interval
  - **redis**: 7-alpine, 512mb maxmemory allkeys-lru, AOF persistence, password auth, internal network only
  - **certbot**: Auto-renewal every 12 hours
- [x] Networks: `frontend` (public) + `backend` (internal, no external access)
- [x] Logging: json-file driver with rotation (50m/5 files api, 20m/3 files redis)

### 9.6 Environment Configuration ✅

- [x] `deploy/.env.example` — Production vars: Appwrite, Razorpay live, Redis, JWT, Docker image, monitoring
- [x] `backend/.env.example` — Updated with REQUEST_TIMEOUT, MAX_CONNECTIONS, SENTRY_DSN, LOG_LEVEL, FCM
- [x] `.env.example` (Flutter root) — Documents `--dart-define` for dev/staging/production builds

### 9.7 Android Release Build ✅

- [x] `android/app/build.gradle.kts`:
  - Application ID: `com.chizze.app` (changed from `com.example.chizze`)
  - Release signing: key.properties with conditional fallback to debug
  - R8/ProGuard: `isMinifyEnabled = true`, `isShrinkResources = true`
  - ABI splits: armeabi-v7a, arm64-v8a, x86_64 + universal
- [x] `android/app/proguard-rules.pro` — Rules for Flutter, Razorpay, Gson, OkHttp, Firebase, Appwrite, Mapbox
- [x] `android/key.properties.example` — Template with keytool generation command

### 9.8 Deployment Scripts ✅

- [x] `deploy/scripts/setup.sh` — VPS setup: Docker + Compose, ufw firewall (22/80/443), fail2ban, 2GB swap, sysctl tuning (somaxconn, tcp_tw_reuse, file-max), deploy user
- [x] `deploy/scripts/ssl-setup.sh` — Let's Encrypt via certbot with temporary Nginx for ACME challenge
- [x] `deploy/scripts/deploy.sh` — Manual deploy: image pull, blue-green rollout, health check (30 attempts × 2s), automatic rollback on failure
- [x] `deploy/README.md` — Documentation for deployment workflow + required GitHub Secrets

### 9.9 Security & Gitignore ✅

- [x] `.gitignore` updated: android/key.properties, *.jks, deploy/ssl/, deploy/certbot/, *.pem, deploy/.env.prod, deploy/.env.staging

### 9.10 Validation ✅

- [x] `go build ./cmd/server` — Compiles successfully with all health endpoint changes
- [x] `go test ./...` — All 55+ Go backend tests PASS
- [x] `flutter test` — All 132 Flutter tests PASS

### 9.11 GitHub Secrets Required for CI/CD

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | Production server IP/hostname |
| `DEPLOY_USER` | SSH username (deploy) |
| `DEPLOY_SSH_KEY` | SSH private key for deployment |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded release .jks keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias (chizze) |
| `ANDROID_KEY_PASSWORD` | Key password |

### 9.12 Files Created/Modified

**New Files (13):**
- `.github/workflows/ci.yml` — CI/CD pipeline
- `Makefile` — Build/test/deploy targets
- `deploy/docker-compose.prod.yml` — Production stack
- `deploy/nginx/nginx.conf` — Nginx reverse proxy
- `deploy/nginx/proxy_params.conf` — Shared proxy params
- `deploy/.env.example` — Production env template
- `.env.example` — Flutter build env docs
- `android/app/proguard-rules.pro` — R8 rules
- `android/key.properties.example` — Signing template
- `deploy/scripts/setup.sh` — VPS setup
- `deploy/scripts/ssl-setup.sh` — SSL setup
- `deploy/scripts/deploy.sh` — Deploy with rollback
- `deploy/README.md` — Deployment docs

**Modified Files (7):**
- `backend/cmd/server/main.go` — Split health/ready, version var
- `backend/pkg/appwrite/client.go` — Added Health() method
- `backend/Dockerfile` — VERSION build arg + ldflags
- `backend/.env.example` — Added monitoring/perf vars
- `android/app/build.gradle.kts` — Release signing, ProGuard, ABI splits
- `.gitignore` — Added deploy secrets, keystore, SSL entries
- `lib/features/cart/providers/cart_provider.dart` — Fixed copyWith bug (from Phase 8)

---

## Known Issues & Tech Debt

| ID | Severity | File | Issue | Status |
|---|---|---|---|---|
| TD-001 | LOW | `appwrite_client.dart` | Legacy file, superseded | To remove |
| TD-002 | ~~LOW~~ | `config/environment.dart` | ~~Legacy config~~ | ✅ FIXED — full env system |
| TD-003 | LOW | `test/widget_test.dart` | References old MyApp | To fix |
| TD-004 | LOW | `test/appwrite_connection_test.dart` | Deprecated APIs | To refactor |
| TD-005 | MEDIUM | Login screen | OAuth needs Appwrite config | Phase 4+ |
| TD-006 | ~~LOW~~ | All screens | ~~Mock data — needs Appwrite collections~~ | ✅ FIXED — API-backed providers |
| TD-007 | LOW | Fonts | Using google_fonts (network) | OK for dev |
| TD-008 | LOW | Restaurant detail | Emoji placeholders for images | When storage ready |
| TD-009 | ~~MEDIUM~~ | payment_provider.dart | ~~`RazorpayConfig.keyId` needs real key~~ | ✅ FIXED — env-configurable |
| TD-010 | ~~MEDIUM~~ | payment_provider.dart | ~~`order_id` field empty — need Go backend~~ | ✅ FIXED — backend creates orders |
| TD-011 | ~~MEDIUM~~ | Auth middleware | ~~Token blacklist not checked on every request~~ | ✅ FIXED — Redis blacklist check |
| TD-012 | ~~MEDIUM~~ | Flutter screens | ~~Restaurant partner screens need building~~ | ✅ FIXED — 4 screens + 3 providers wired to API (delivery partner remains Phase 5) |
| TD-013 | LOW | ratelimit.go | In-memory RateLimit() has potential data race (visitor mutations after sync.Map Load) | Use RedisRateLimit in production |
| TD-014 | LOW | notification_handler.go | MarkAllRead is O(N) — fetches all, updates one-by-one | Acceptable at current scale |
| TD-015 | LOW | review_handler.go | Rating recalculation is O(N Reviews) | Consider caching in Redis |
| TD-016 | MEDIUM | menu_item.dart | Menu items still use mock data on restaurant detail | Need menu API endpoint integration |
| TD-017 | ~~LOW~~ | partner_provider.dart | ~~Partner screens use mock orders~~ | ✅ FIXED — All 3 providers (partner, menu, analytics) wired to Go API with mock fallback |
| TD-018 | LOW | cart_provider.dart | In-memory only (no persistence) | Consider Hive/SharedPrefs |

---

## Razorpay Integration Details

```yaml
package: razorpay_flutter 1.4.1
backend: Go payment_handler.go + payment_service.go
config_file: lib/features/payment/providers/payment_provider.dart
key_location: Server returns key_id from /payments/initiate response (Flutter fallback via --dart-define=RAZORPAY_KEY)
test_key: rzp_test_SIjgJ176oKm8mn (configured in backend/.env, Flutter fallback)
flow:
  1. Flutter places order → POST /orders → gets order_id
  2. Flutter calls POST /payments/initiate with { order_id }
  3. Go backend fetches order, gets grand_total (prevents client tampering)
  4. Go calls Razorpay API to create order (amount in paise)
  5. Go stores payment record in Appwrite payments collection
  6. Go returns { razorpay_order_id, razorpay_key_id, amount, currency }
  7. Flutter opens Razorpay SDK checkout with server-provided order_id + key
  8. On success: Flutter calls POST /payments/verify with { razorpay_order_id, razorpay_payment_id, razorpay_signature }
  9. Go verifies HMAC-SHA256 signature, updates payment + order status
  10. Razorpay webhook (POST /payments/webhook) as backup for payment.captured/failed/refund
  11. COD: Bypasses Razorpay, creates order directly with payment_status=cod
security:
  - Amount sourced from server (not client)
  - HMAC-SHA256 signature verification
  - Webhook signature verification
  - Payment ownership check (customer_id must match)
```

---

## Phase 8 — Testing & Quality Assurance (COMPLETE)

### 8.1 Go Backend Unit Tests ✅

**10 test files, 55+ tests across 5 packages — ALL PASSING**

| Package | File | Tests | Coverage |
|---|---|---|---|
| `pkg/utils` | `geo_test.go` | 9 | Haversine, EstimateETA, BoundingBox |
| `pkg/utils` | `validators_test.go` | 5 (52 sub-cases) | Phone, email, pincode, role, sanitize |
| `internal/models` | `order_test.go` | 4 (24 transitions) | CanTransition valid/invalid, constants |
| `internal/models` | `common_test.go` | 6 | Pagination, AppError, collection constants |
| `internal/services` | `order_service_test.go` | 3 | GenerateOrderNumber, CalculateFees, ValidateTransition |
| `internal/services` | `geo_service_test.go` | 3 | Distance, EstimateDeliveryTime, NearbyBounds |
| `pkg/redis` | `redis_test.go` | 3 | IsNilError, CloseNil, Underlying/GetRedis |
| `internal/websocket` | `websocket_test.go` | 11 | Hub lifecycle, SendToUser, Broadcast, Events, EventBroadcaster |
| `internal/middleware` | `auth_test.go` | 9 | JWT auth (missing/invalid/expired/wrong/valid), RequireRole, context helpers |
| `internal/middleware` | `ratelimit_test.go` | 4 | Token bucket, burst exhaustion, different IPs, middleware 429 |

### 8.2 Flutter Unit Tests ✅

**8 test files, 132 tests — ALL PASSING (`flutter test` exit 0)**

| Directory | File | Tests | Coverage |
|---|---|---|---|
| `test/models/` | `order_test.dart` | 19 | OrderStatus (fromString, progress, isActive, label/emoji), OrderItem, Order (fromMap, toMap, copyWith, mockList) |
| `test/models/` | `restaurant_test.dart` | 9 | Restaurant (fromMap, toMap, mockList, defaults, veg-only) |
| `test/models/` | `menu_item_test.dart` | 16 | CustomizationOption, CustomizationGroup, MenuCategory, MenuItem (fromMap, JSON customizations, mockList, mockCategories) |
| `test/models/` | `api_response_test.dart` | 7 | PaginationMeta, ApiResponse (success/error/meta), ApiException |
| `test/models/` | `delivery_partner_test.dart` | 22 | DeliveryPartner (fromDashboard, copyWith, empty), DeliveryRequest (fromMap, computed), DeliveryMetrics (weeklyProgress, earnings, mock, copyWith), DeliveryStep, ActiveDelivery |
| `test/providers/` | `cart_provider_test.dart` | 27 | CartItem (totalPrice, cartKey), CartState (itemTotal, deliveryFee, platformFee, gst, grandTotal), CartNotifier (add/update/remove/coupon/clear) |
| `test/providers/` | `coupons_provider_test.dart` | 12 | Coupon (isExpired, isUsable, daysRemaining, defaults), CouponsState (appliedCoupon lookup) |
| `test/providers/` | `gold_provider_test.dart` | 20 | GoldPlan (durationLabel, benefits), GoldSubscription (isActive, daysRemaining), GoldState (isGoldMember, copyWith, clearSubscription) |

### 8.3 Test Summary ✅

- **Go backend:** `go test ./...` — 55+ tests PASS (0 failures)
- **Flutter frontend:** `flutter test` — 132 tests PASS (0 failures)
- **Total test coverage:** All pure business logic, models, state management, middleware, WebSocket events
- **Bug found:** `CartState.copyWith` nullable pattern means `removeCoupon()` can't clear `couponCode` via `null` (documented in test)

---

## Changelog

| Date | Action | Details |
|---|---|---|
| 2026-02-25 14:00 | Phase 9 — COMPLETE | Production Deployment & CI/CD. 13 new files, 7 modified. GitHub Actions CI/CD (5 jobs: go-test, flutter-test, docker-build, android-build, deploy). Makefile (18 targets). Health endpoints split (liveness /health + readiness /health/ready). Nginx reverse proxy (rate limiting, TLS, WebSocket, security headers). Production docker-compose (nginx + api×2 + redis + certbot, dual network). Environment configs (3 .env.example files). Android release build (com.chizze.app, ProGuard, ABI splits, release signing). Deployment scripts (setup.sh, ssl-setup.sh, deploy.sh with rollback). deploy/README.md. All tests pass: 55+ Go, 132 Flutter. |
| 2026-02-25 10:30 | Bug Fix | CartState.copyWith nullable pattern fixed — added clearCouponCode flag so removeCoupon() can set couponCode to null. 28/28 cart tests pass. |
| 2026-02-25 10:00 | Phase 8 — COMPLETE | 10 Go test files (55+ tests), 8 Flutter test files (132 tests). All passing. Covers: utils (geo, validators), models (order transitions, pagination, errors), services (order numbers, fees, geo), redis (nil errors, client), websocket (hub, events, broadcaster), middleware (JWT auth, rate limiting), Flutter models (order, restaurant, menu_item, api_response, delivery_partner), Flutter providers (cart, coupons, gold). 1 bug documented (copyWith nullable pattern). |
| 2026-02-21 16:00 | Phase 4 Audit Complete | 25 issues found (5 errors, 3 logic, 11 warnings, 6 info) — all fixed, `flutter analyze` reports 0 issues |
| 2026-02-21 10:00 | Production Hardening Complete | 22 backend fixes, 11 Flutter fixes, 3 infrastructure items |
| 2026-02-21 09:30 | Infrastructure | .gitignore updated, .dockerignore created, .env.example updated |
| 2026-02-21 09:00 | Flutter Critical Fixes | JWT persistence (secure storage), mock data removal, OTP log sanitization |
| 2026-02-21 08:30 | Flutter Blocker Fixes | Environment config, API-backed restaurants, real payment flow, search/detail screens |
| 2026-02-21 08:00 | Backend Correctness Fixes | Idempotency keys, distributed locks, atomic coupons, body size limit, crypto/rand |
| 2026-02-21 07:30 | Backend Security Fixes | JWT blacklist/pinning/issuer, OTP rate limit, webhook secret, CORS, shared http.Client |
| 2026-02-21 07:00 | Production Audit | 30 backend + 28 Flutter issues cataloged (5 CRITICAL, 6 HIGH, 12 MEDIUM, 7 LOW) |
| 2026-02-20 14:00 | Auth/Payment Audit | Fixed auth field mismatch, payment flow, Razorpay key, logout, JWT refresh |
| 2026-02-20 13:30 | Phase 3.5 Complete | Go backend, auth bridge, payment bridge — all verified |
| 2026-02-20 12:00 | Redis fix | `go mod tidy` promoted go-redis/v9 to direct dependency |
| 2026-02-24 10:00 | Phase 7 — COMPLETE | WebSocket hub (Go): hub.go, client.go, events.go with 6 event types. 4 background workers: delivery_matcher (Redis GeoSearch), order_timeout, scheduled_order_processor, notification_dispatcher. Handler integration: OrderHandler + DeliveryHandler broadcast events. Flutter WebSocket client: websocket_service.dart with auto-reconnect, typed events, Riverpod providers. Integrated into OrdersNotifier + RiderLocationNotifier. flutter analyze 0 issues, go build 0 errors |
| 2026-02-23 14:00 | Phase 6 — COMPLETE | Dark/light theme, favorites (full stack + heart icon), offers carousel, notification filters, Chizze Gold (full stack), referral system (full stack), scheduled orders (full stack), push notification service, 10 new API endpoints. Go backend: 4 new handler files, 14 new Appwrite CRUD methods. Flutter: 8 new files, 5 modified. dart analyze 0 issues |
| 2026-02-22 12:00 | Phase 5 — COMPLETE | Go backend: Payout model + CRUD, 5 new handlers (profile GET/PUT, payouts GET, payout request POST, reject order), 5 new routes, notification triggers (AcceptOrder + all UpdateStatus transitions). Flutter: real GPS tracking via LocationService, updateProfile(), fetchPerformance(), earnings payout endpoint fix, DeliveryPartner.copyWith expanded. dart analyze 0 issues, go build 0 errors, go vet 0 issues |
| 2026-02-22 10:00 | Phase 5 — Delivery screens enhanced | Earnings provider rewrite (period selector, fromMap, payouts), earnings screen (period chips, breakdown, payout section), profile screen (logout, hours online, subtitles), simulateNewRequest(), deliveryPayouts endpoint, 0 analyze issues |
| 2026-02-20 10:00 | All 10 handlers rewritten | Auth, payment, restaurant, menu, order, delivery, review, coupon, notification, user |
| 2026-02-20 09:00 | Go backend infrastructure | Config, middleware, Appwrite SDK, Redis, rate limiting |
| 2026-02-19 22:08 | Phase 3 Complete | 8 new files, 3 updated, 0 analysis errors |
| 2026-02-19 22:07 | Router updated | Phase 3 routes, Orders tab wired |
| 2026-02-19 22:06 | Review screen | Star ratings, tags, text review |
| 2026-02-19 22:06 | Orders screen | Active/Past tabs, order cards |
| 2026-02-19 22:05 | Order tracking | Timeline, ETA, delivery partner, demo mode |
| 2026-02-19 22:05 | Order confirmation | Animated success, order details |
| 2026-02-19 22:04 | Payment screen | Razorpay + COD, tip, bill summary |
| 2026-02-19 22:03 | Payment provider | Razorpay SDK integration |
| 2026-02-19 22:02 | Orders provider | Active/past orders, status updates |
| 2026-02-19 22:01 | Order model | 8-stage lifecycle, OrderStatus enum |
| 2026-02-19 22:00 | razorpay_flutter added | v1.4.1 installed |
| 2026-02-19 21:55 | Phase 2 Complete | 7 files, 0 errors |
| 2026-02-19 21:49 | Phase 1 Complete | 19 files, 133 deps, 0 errors |
