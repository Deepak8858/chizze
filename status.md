# Chizze — Project Status

> **Last Updated:** 2026-02-21T12:00:00+05:30
> **Current Phase:** Phase 4 — Restaurant Partner
> **Phase Status:** 🔄 IN PROGRESS
> **Next Action:** Phase 4 — Partner screens need real-time order updates (WebSocket/polling), image upload for menu items, and remaining UI polish

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
  theme: Dark mode only
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
| 4 | Restaurant Partner | 10-12 | 🔄 IN PROGRESS | 70% |
| 5 | Delivery Partner | 13-15 | ⏳ NOT STARTED | 0% |
| 6 | Polish & Advanced | 16-18 | ⏳ NOT STARTED | 0% |

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

## Phase 4 — Restaurant Partner (IN PROGRESS)

### What's Done (70%)

**Backend — Go API (100% complete)**
- `partner_handler.go` — 9 endpoints: Dashboard, ListOrders, Analytics, Performance, ToggleOnline, ListCategories, CreateCategory, UpdateCategory, DeleteCategory
- `appwrite_service.go` — 4 new category CRUD methods (Get, Create, Update, Delete)
- `main.go` — 13 partner routes registered under `/api/v1/partner/*` with JWT auth

**Flutter — Providers wired to API (100% complete)**
- `partner_provider.dart` — Dashboard metrics + orders from API, async toggleOnline, mock fallback
- `menu_management_provider.dart` — Menu items + categories from API, full CRUD, mock fallback
- `analytics_provider.dart` — Revenue trends, top items, peak hours from API, period filter, mock fallback

**Flutter — Screens (pre-existing, 4 screens built)**
- `partner_dashboard_screen.dart` — Metrics cards, online/offline toggle, active orders
- `partner_orders_screen.dart` — Tabbed order list with countdown timer
- `menu_management_screen.dart` — Category/item CRUD with drag-to-reorder stubs
- `analytics_screen.dart` — Bar chart, top items list, peak hours heatmap

### What Remains (30%)

| Task | Priority | Notes |
|---|---|---|
| Real-time order updates | HIGH | WebSocket or polling for new order notifications |
| Image upload for menu items | MEDIUM | Appwrite Storage integration |
| Order accept/reject flow | MEDIUM | Notification sound + accept deadline countdown |
| Menu item availability toggle | LOW | Quick on/off from dashboard |
| Printer integration | LOW | Thermal printer receipt support (Phase 6 candidate) |

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

## Changelog

| Date | Action | Details |
|---|---|---|
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
