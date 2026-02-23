# Chizze Backend — Comprehensive Audit Report

**Date:** 2025-01-XX  
**Scope:** `h:\chizze\backend\` — all Go source files  
**Tech Stack:** Go 1.24, Gin v1.11, Appwrite BaaS, Redis (go-redis/v9), Razorpay, JWT (golang-jwt/v5), gorilla/websocket, sony/gobreaker, OpenTelemetry  

---

## Table of Contents

1. [File Inventory](#1-file-inventory)
2. [Architecture Overview](#2-architecture-overview)
3. [Route → Handler Mapping](#3-route--handler-mapping)
4. [Handler → Service Call Matrix](#4-handler--service-call-matrix)
5. [Feature Flow Completeness](#5-feature-flow-completeness)
6. [Critical Bugs & Security Issues](#6-critical-bugs--security-issues)
7. [Code Quality Issues](#7-code-quality-issues)
8. [Circuit Breaker Integration](#8-circuit-breaker-integration)
9. [Redis Usage Audit](#9-redis-usage-audit)
10. [WebSocket Handling](#10-websocket-handling)
11. [Background Workers](#11-background-workers)
12. [Model Structure](#12-model-structure)
13. [Middleware Chain](#13-middleware-chain)
14. [Swagger / API Documentation](#14-swagger--api-documentation)
15. [Test Coverage](#15-test-coverage)
16. [Summary & Priority Matrix](#16-summary--priority-matrix)

---

## 1. File Inventory

### cmd/server/
| File | Lines | Purpose |
|------|-------|---------|
| `main.go` | 404 | Entry point: DI, route registration, middleware chain, worker startup, graceful shutdown |

### internal/config/
| File | Lines | Purpose |
|------|-------|---------|
| `config.go` | ~100 | Environment-based config loader (godotenv), validation, production safety checks |

### internal/handlers/ (15 files)
| File | Lines | Purpose |
|------|-------|---------|
| `auth_handler.go` | ~250 | Auth: SendOTP, VerifyOTP, Exchange (Appwrite JWT→Chizze JWT), Refresh, Logout |
| `user_handler.go` | ~210 | User profile CRUD, addresses, FCM token |
| `restaurant_handler.go` | ~200 | Public: list, nearby (geo), detail, menu, reviews |
| `menu_handler.go` | ~180 | Partner menu CRUD with ownership verification |
| `order_handler.go` | ~450 | Order placement (idempotent, server-side price verification), status management |
| `payment_handler.go` | ~250 | Razorpay: initiate, verify, webhook (payment.captured/failed, refund.processed) |
| `delivery_handler.go` | 936 | Delivery partner: status, location, accept/reject, dashboard, earnings, payouts |
| `review_handler.go` | ~170 | Create review (with checks), reply (owner only), async rating recalc |
| `coupon_handler.go` | ~120 | List available, validate coupon for cart |
| `notification_handler.go` | ~110 | List, mark read, mark all read |
| `partner_handler.go` | ~470 | Partner dashboard, analytics, order management, category CRUD, performance |
| `favorite_handler.go` | ~140 | Favorite restaurants: list, add, remove |
| `gold_handler.go` | ~190 | Gold membership: plans, status, subscribe, cancel |
| `referral_handler.go` | ~170 | Referral code generation, application, listing |
| `scheduled_order_handler.go` | ~120 | Scheduled orders: list, create, cancel |

### internal/services/ (5 source + 2 test)
| File | Lines | Purpose |
|------|-------|---------|
| `appwrite_service.go` | ~340 | Typed Appwrite wrapper: CRUD for all 17 collections |
| `cache_service.go` | ~95 | Redis JSON cache layer with domain-specific keys + TTLs |
| `geo_service.go` | ~32 | Distance, ETA, bounding box (delegates to utils) |
| `order_service.go` | ~60 | Order number gen, fee calculation, transition validation |
| `payment_service.go` | ~155 | Razorpay API client with circuit breaker, signature verification |
| `geo_service_test.go` | 79 | Tests for distance + ETA |
| `order_service_test.go` | 147 | Tests for order number gen + fee calculation |

### internal/models/ (10 source + 2 test)
| File | Lines | Purpose |
|------|-------|---------|
| `common.go` | ~73 | Pagination, 17 collection constants, AppError |
| `order.go` | ~110 | Order struct/statuses/transitions/request DTOs |
| `coupon.go` | ~65 | Coupon struct + IsValid/CalculateDiscount |
| `restaurant.go` | ~80 | Restaurant, MenuCategory, MenuItem structs + DTOs |
| `user.go` | ~70 | User, Address structs + DTOs |
| `notification.go` | ~15 | Notification struct |
| `delivery_partner.go` | ~95 | DeliveryPartner, DeliveryLocation, Payout structs + DTOs |
| `review.go` | ~35 | Review struct + DTOs |
| `favorite.go` | ~18 | Favorite struct + DTO |
| `gold.go` | ~65 | GoldSubscription, GoldPlan structs + hardcoded plans |
| `referral.go` | ~22 | Referral struct + DTO |
| `scheduled_order.go` | ~35 | ScheduledOrder struct + DTO |
| `common_test.go` | ~80 | Tests for pagination + AppError |
| `order_test.go` | 112 | Tests for CanTransition + constants |

### internal/middleware/ (7 source + 2 test)
| File | Lines | Purpose |
|------|-------|---------|
| `auth.go` | ~140 | JWT validation (HS256 pinned), blacklist check, RequireRole, GetUserID/GetUserRole |
| `security.go` | ~60 | Request ID generation, security headers (XSS, HSTS, CSP, etc.), MaxBodySize |
| `ratelimit.go` | ~130 | In-memory token-bucket + Redis sliding-window rate limiters |
| `cors.go` | ~35 | CORS with AllowCredentials safety check |
| `logger.go` | ~40 | Structured logging with request ID, status-based log levels |
| `compress.go` | ~60 | Gzip response compression with sync.Pool |
| `tracing.go` | 91 | OpenTelemetry setup: OTLP/stdout exporters, 10% sampling in prod |
| `auth_test.go` | 237 | JWT auth tests: missing header, invalid format, expired, wrong secret, valid, role |
| `ratelimit_test.go` | — | Rate limiter tests |

### internal/websocket/ (3 source + 1 test)
| File | Lines | Purpose |
|------|-------|---------|
| `hub.go` | ~80 | Hub: register/unregister/broadcast + SendToUser (linear scan) |
| `client.go` | ~155 | WebSocket client: readPump, writePump, ping/pong, ServeWs upgrade |
| `events.go` | 122 | 7 event types, EventBroadcaster typed methods |
| `websocket_test.go` | 273 | Hub register/unregister, SendToUser, broadcast tests |

### internal/workers/ (4 files)
| File | Lines | Purpose |
|------|-------|---------|
| `delivery_matcher.go` | ~155 | Matches ready orders to nearest online riders via Redis geo |
| `order_timeout.go` | ~120 | Auto-cancels unconfirmed orders after 5 min |
| `notification_dispatcher.go` | ~130 | Processes Redis notification queue (BRPOP), stores in Appwrite + WebSocket |
| `scheduled_order_processor.go` | ~105 | Converts due scheduled orders to placed status |

### pkg/appwrite/ (2 files)
| File | Lines | Purpose |
|------|-------|---------|
| `client.go` | 414 | Appwrite REST client: HTTP/2, connection pooling, circuit breaker, retry with exponential backoff, Ctx variants, health check |
| `query.go` | ~130 | Appwrite query builder: Equal, Search, OrderDesc/Asc, IsNull, GT/LT/GTE/LTE, Limit, Offset |

### pkg/redis/ (1 source + 1 test)
| File | Lines | Purpose |
|------|-------|---------|
| `redis.go` | ~210 | Redis client wrapper: KV, rate limiting (sliding window), geo (GeoAdd/GeoSearch), list (LPush/BRPop) |
| `redis_test.go` | — | Redis tests |

### pkg/utils/ (3 source + 2 test)
| File | Lines | Purpose |
|------|-------|---------|
| `response.go` | ~90 | Standard API response helpers: Success, Created, Paginated, Error, BadRequest, etc. |
| `geo.go` | ~45 | Haversine distance, ETA estimation, bounding box |
| `validators.go` | ~50 | Indian phone (+91), email, pincode validators, role validation, string sanitization |
| `validators_test.go` | — | Validator tests |
| `geo_test.go` | — | Geospatial tests |

**Total:** ~50 source files, ~10 test files, ~5,500+ lines of Go code

---

## 2. Architecture Overview

```
Client → Gin Router → Middleware Chain → Handlers → Services → Appwrite REST API
                                             ↓              ↓
                                          Redis           Razorpay
                                             ↓
                                     WebSocket Hub → Clients
                                             ↑
                                     Background Workers
```

**Key patterns:**
- **Thin handlers** — parse request, call service, format response
- **AppwriteService** — domain-typed CRUD wrapper (no raw Appwrite calls in handlers)
- **Circuit breaker** — on both Appwrite client and Razorpay payment service
- **Retry with backoff** — Appwrite client retries 3× with exponential backoff + jitter
- **WebSocket** — Hub-spoke model for real-time events (order updates, delivery location)
- **Background workers** — 4 goroutines: delivery matching, order timeout, scheduled orders, notification queue

---

## 3. Route → Handler Mapping

### Public Routes (no auth)
| Method | Route | Handler | Rate Limit |
|--------|-------|---------|------------|
| POST | `/api/v1/auth/send-otp` | `authHandler.SendOTP` | 10 req/s (Redis) |
| POST | `/api/v1/auth/verify-otp` | `authHandler.VerifyOTP` | 10 req/s |
| POST | `/api/v1/auth/exchange` | `authHandler.Exchange` | 10 req/s |
| GET | `/api/v1/restaurants` | `restaurantHandler.List` | global 200/s |
| GET | `/api/v1/restaurants/nearby` | `restaurantHandler.Nearby` | global 200/s |
| GET | `/api/v1/restaurants/:id` | `restaurantHandler.GetDetail` | global 200/s |
| GET | `/api/v1/restaurants/:id/menu` | `restaurantHandler.GetMenu` | global 200/s |
| GET | `/api/v1/restaurants/:id/reviews` | `restaurantHandler.GetReviews` | global 200/s |
| GET | `/api/v1/coupons` | `couponHandler.ListAvailable` | global 200/s |
| GET | `/health` | inline | global 200/s |
| GET | `/health/ready` | inline | global 200/s |
| GET | `/swagger/*any` | Swagger UI | global 200/s |

### Authenticated Routes (JWT required)
| Method | Route | Handler |
|--------|-------|---------|
| GET | `/api/v1/ws` | `websocket.ServeWs` |
| POST | `/api/v1/auth/refresh` | `authHandler.Refresh` |
| DELETE | `/api/v1/auth/logout` | `authHandler.Logout` |
| GET | `/api/v1/users/me` | `userHandler.GetProfile` |
| PUT | `/api/v1/users/me` | `userHandler.UpdateProfile` |
| GET | `/api/v1/users/me/addresses` | `userHandler.ListAddresses` |
| POST | `/api/v1/users/me/addresses` | `userHandler.CreateAddress` |
| PUT | `/api/v1/users/me/addresses/:id` | `userHandler.UpdateAddress` |
| DELETE | `/api/v1/users/me/addresses/:id` | `userHandler.DeleteAddress` |
| PUT | `/api/v1/users/me/fcm-token` | `userHandler.UpdateFCMToken` |
| POST | `/api/v1/orders` | `orderHandler.PlaceOrder` |
| GET | `/api/v1/orders` | `orderHandler.ListOrders` |
| GET | `/api/v1/orders/:id` | `orderHandler.GetOrder` |
| PUT | `/api/v1/orders/:id/cancel` | `orderHandler.CancelOrder` |
| POST | `/api/v1/orders/:id/review` | `reviewHandler.CreateReview` |
| POST | `/api/v1/cart/validate-coupon` | `couponHandler.Validate` |
| POST | `/api/v1/payments/initiate` | `paymentHandler.Initiate` |
| POST | `/api/v1/payments/verify` | `paymentHandler.Verify` |
| GET | `/api/v1/notifications` | `notifHandler.List` |
| PUT | `/api/v1/notifications/:id/read` | `notifHandler.MarkRead` |
| PUT | `/api/v1/notifications/read-all` | `notifHandler.MarkAllRead` |
| GET | `/api/v1/users/me/favorites` | `favoriteHandler.List` |
| POST | `/api/v1/users/me/favorites` | `favoriteHandler.Add` |
| DELETE | `/api/v1/users/me/favorites/:restaurant_id` | `favoriteHandler.Remove` |
| GET | `/api/v1/gold/plans` | `goldHandler.GetPlans` |
| GET | `/api/v1/gold/status` | `goldHandler.GetStatus` |
| POST | `/api/v1/gold/subscribe` | `goldHandler.Subscribe` |
| PUT | `/api/v1/gold/cancel` | `goldHandler.Cancel` |
| GET | `/api/v1/referrals/code` | `referralHandler.GetCode` |
| POST | `/api/v1/referrals/apply` | `referralHandler.Apply` |
| GET | `/api/v1/referrals` | `referralHandler.ListReferrals` |
| GET | `/api/v1/orders/scheduled` | `scheduledOrderHandler.List` |
| POST | `/api/v1/orders/scheduled` | `scheduledOrderHandler.Create` |
| PUT | `/api/v1/orders/scheduled/:id/cancel` | `scheduledOrderHandler.Cancel` |

### Partner Routes (role: restaurant_owner)
| Method | Route | Handler |
|--------|-------|---------|
| GET | `/api/v1/partner/dashboard` | `partnerHandler.Dashboard` |
| GET | `/api/v1/partner/analytics` | `partnerHandler.Analytics` |
| GET | `/api/v1/partner/performance` | `partnerHandler.Performance` |
| PUT | `/api/v1/partner/restaurant/status` | `partnerHandler.ToggleOnline` |
| GET | `/api/v1/partner/orders` | `partnerHandler.ListOrders` |
| PUT | `/api/v1/partner/orders/:id/status` | `orderHandler.UpdateStatus` |
| GET | `/api/v1/partner/menu` | `menuHandler.ListItems` |
| POST | `/api/v1/partner/menu` | `menuHandler.CreateItem` |
| PUT | `/api/v1/partner/menu/:id` | `menuHandler.UpdateItem` |
| DELETE | `/api/v1/partner/menu/:id` | `menuHandler.DeleteItem` |
| GET | `/api/v1/partner/categories` | `partnerHandler.ListCategories` |
| POST | `/api/v1/partner/categories` | `partnerHandler.CreateCategory` |
| PUT | `/api/v1/partner/categories/:id` | `partnerHandler.UpdateCategory` |
| DELETE | `/api/v1/partner/categories/:id` | `partnerHandler.DeleteCategory` |
| POST | `/api/v1/partner/reviews/:id/reply` | `reviewHandler.ReplyToReview` |

### Delivery Routes (role: delivery_partner)
| Method | Route | Handler |
|--------|-------|---------|
| GET | `/api/v1/delivery/dashboard` | `deliveryHandler.Dashboard` |
| GET | `/api/v1/delivery/earnings` | `deliveryHandler.Earnings` |
| GET | `/api/v1/delivery/performance` | `deliveryHandler.Performance` |
| GET | `/api/v1/delivery/profile` | `deliveryHandler.GetProfile` |
| PUT | `/api/v1/delivery/profile` | `deliveryHandler.UpdateProfile` |
| PUT | `/api/v1/delivery/status` | `deliveryHandler.ToggleOnline` |
| PUT | `/api/v1/delivery/location` | `deliveryHandler.UpdateLocation` |
| PUT | `/api/v1/delivery/orders/:id/accept` | `deliveryHandler.AcceptOrder` |
| PUT | `/api/v1/delivery/orders/:id/reject` | `deliveryHandler.RejectOrder` |
| PUT | `/api/v1/delivery/orders/:id/status` | `orderHandler.UpdateStatus` |
| GET | `/api/v1/delivery/orders` | `deliveryHandler.ActiveOrders` |
| GET | `/api/v1/delivery/payouts` | `deliveryHandler.ListPayouts` |
| POST | `/api/v1/delivery/payouts/request` | `deliveryHandler.RequestPayout` |

### Webhook (no auth, signature validated)
| Method | Route | Handler |
|--------|-------|---------|
| POST | `/api/v1/payments/webhook` | `paymentHandler.Webhook` |

**Verdict:** All routes are properly wired. No orphaned handlers found.

---

## 4. Handler → Service Call Matrix

| Handler | AppwriteService | OrderService | PaymentService | GeoService | CacheService | Redis | WebSocket |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| auth | ✅ | — | — | — | — | ✅ | — |
| user | ✅ | — | — | — | — | — | — |
| restaurant | ✅ | — | — | ✅ | — | — | — |
| menu | ✅ | — | — | — | — | — | — |
| order | ✅ | ✅ | — | ✅ | — | ✅ | ✅ |
| payment | ✅ | — | ✅ | — | — | — | — |
| delivery | ✅ | — | — | ✅ | — | ✅ | ✅ |
| review | ✅ | — | — | — | — | — | — |
| coupon | ✅ | — | — | — | — | — | — |
| notification | ✅ | — | — | — | — | — | — |
| partner | ✅ | — | — | — | — | — | — |
| favorite | ✅ | — | — | — | — | — | — |
| gold | ✅ | — | — | — | — | — | — |
| referral | ✅ | — | — | — | — | — | — |
| scheduled_order | ✅ | — | — | — | — | — | — |

**Notable:** CacheService is defined but **never injected into any handler**. Restaurant list/detail, menu, user profile, and coupon list all define cache keys and TTLs but never actually use cache.

---

## 5. Feature Flow Completeness

| Feature | Flow Status | Notes |
|---------|-------------|-------|
| **Auth (OTP)** | ⚠️ INCOMPLETE | OTP not sent/verified — placeholder. Exchange works for JWT issuance. |
| **User Profile** | ✅ COMPLETE | CRUD + addresses + FCM token |
| **Restaurant Browse** | ✅ COMPLETE | List, nearby, detail, menu (grouped by category), reviews |
| **Menu Management** | ✅ COMPLETE | CRUD with ownership checks |
| **Order Placement** | ✅ COMPLETE | Idempotent, price verification, fee calc, coupon, address snapshot |
| **Order Status** | ✅ COMPLETE | Role-based transitions, notifications, WebSocket |
| **Order Cancellation** | ✅ COMPLETE | Owner check, transition validation |
| **Payments** | ✅ COMPLETE | Razorpay create → verify → webhook lifecycle |
| **Delivery Matching** | ✅ COMPLETE | Worker: geo query → assign → notify (WebSocket) |
| **Delivery Tracking** | ✅ COMPLETE | Redis geo + WebSocket location broadcast |
| **Reviews** | ✅ COMPLETE | Create + reply + async rating recalc |
| **Coupons** | ✅ COMPLETE | List + validate (IsValid + CalculateDiscount) |
| **Notifications** | ⚠️ PARTIAL | CRUD works. FCM push is TODO. Async queue works via worker. |
| **Partner Dashboard** | ✅ COMPLETE | Revenue, orders, analytics, top items, peak hours |
| **Favorites** | ✅ COMPLETE | Add/remove/list (with N+1) |
| **Gold Membership** | ✅ COMPLETE | Plans, subscribe, cancel, status |
| **Referrals** | ✅ COMPLETE | Generate code, apply, list |
| **Scheduled Orders** | ⚠️ PARTIAL | Create/list/cancel work. Worker converts to "placed" but doesn't call PlaceOrder logic (no price verification, no payment). |
| **Order Timeout** | ✅ COMPLETE | Auto-cancel after 5 min, notifies customer + restaurant |
| **WebSocket** | ✅ COMPLETE | 7 event types, hub/spoke with per-user targeting |

---

## 6. Critical Bugs & Security Issues

### 🔴 P0 — Security

| # | File | Line(s) | Issue |
|---|------|---------|-------|
| 1 | `config.go` | default RedisURL | **Hardcoded production Redis password** in source: `redis://:Dream%408858@165.232.177.81:6379`. This is a credential leak if the repo is public or shared. |
| 2 | `auth_handler.go` | SendOTP/VerifyOTP | **OTP is never actually sent or verified.** `SendOTP` returns success without sending. `VerifyOTP` trusts the `user_id` from the request body — any client can claim to be any user. This is an **authentication bypass**. |
| 3 | `scheduled_order_handler.go` | Cancel | **No ownership check.** Any authenticated user can cancel any other user's scheduled order by ID. Should verify `scheduled_order.user_id == caller`. |
| 4 | `client.go` (websocket) | ServeWs | **`CheckOrigin` returns true for all origins.** While commented "for now", in production this allows cross-site WebSocket hijacking. |

### 🔴 P0 — Data Integrity

| # | File | Line(s) | Issue |
|---|------|---------|-------|
| 5 | `order_handler.go` | UpdateStatus notification | **Field name mismatch:** Uses `order["user_id"]` but PlaceOrder stores the field as `"customer_id"`. Notifications to customers after status updates will silently fail (empty user ID → no WebSocket delivery). |
| 6 | `delivery_handler.go` | UpdateLocation broadcast | **Same mismatch:** Uses `order["user_id"]` but the field is `"customer_id"`. Live location updates won't reach the customer. |
| 7 | `order_handler.go` | PlaceOrder coupon | **Coupon counter not decremented on over-limit.** When the Redis INCR exceeds the usage limit, discount is set to 0 but the counter remains incremented. Over time, the counter inflates and permanently blocks the coupon even when usage is below the real limit. |

---

## 7. Code Quality Issues

### 🟡 P1 — Moderate

| # | File | Issue |
|---|------|-------|
| 8 | `favorite_handler.go`, `gold_handler.go`, `referral_handler.go`, `scheduled_order_handler.go` | **Inconsistent user ID extraction.** Use `c.GetString("user_id")` instead of `middleware.GetUserID(c)`. The auth middleware sets key as `"userId"` (camelCase via `ContextUserID = "userId"`). `c.GetString("user_id")` reads a *different* key → **returns empty string** → all these handlers operate with an empty user ID. This is a **functional bug** (favorites/gold/referrals/scheduled orders are broken for all users). |
| 9 | `notification_handler.go` | **Pagination not applied at DB level.** `ListNotifications` calls `_ = pg` — explicitly ignores pagination. Fetches ALL notifications every time. |
| 10 | `restaurant_handler.go` | **GetReviews pagination not applied at DB level.** Fetches all reviews, returns all via `Paginated` (which only sets meta, doesn't slice). |
| 11 | `notification_handler.go` | **MarkAllRead N+1.** Fetches all notifications then updates each one individually in a loop. For a user with 500 notifications, this is 501 HTTP requests to Appwrite. |
| 12 | `favorite_handler.go` | **List enrichment N+1.** For each favorite, fetches the restaurant individually. 50 favorites = 51 API calls. |
| 13 | `scheduled_order_handler.go` | **Items not validated.** Unlike PlaceOrder (which verifies each item's price from the menu), scheduled order creation stores raw `interface{}` items from the request body. No server-side validation. |

### 🟢 P2 — Minor

| # | File | Issue |
|---|------|-------|
| 14 | `payment_handler.go` | `CreatePayment` return value (doc, error) — error is not checked. |
| 15 | `delivery_handler.go` | `AcceptOrder` checks for status `ready` but doesn't transition the order status — only assigns the partner ID. The status remains `ready`. |
| 16 | `order_timeout.go` | Uses `"cancel_reason"` field but `Order` model defines `"cancellation_reason"`. Field name mismatch means the reason won't be stored properly. |
| 17 | `scheduled_order_processor.go` | `ListScheduledOrders("")` is called with empty userID, but the service method filters by user_id. The `queries` variable is built but unused (`_ = queries`). This means the worker fetches no results (or all results with empty filter depending on Appwrite behavior). |
| 18 | `delivery_matcher.go` | Assigns only the nearest rider with no fallback/retry. If that rider rejects, the order waits until next poll (15s). |
| 19 | CacheService | **Defined but unused.** `cache_service.go` has well-defined keys and TTLs but is never wired into handlers. No caching layer is active. |
| 20 | `websocket/hub.go` | `SendToUser` iterates all clients with a read-lock. At scale (thousands of connections), this is O(n) per send. Consider a `map[userID][]*Client` index. |

---

## 8. Circuit Breaker Integration

| Component | Status | Config |
|-----------|--------|--------|
| **Appwrite client** | ✅ Active | Trip: 5 consecutive failures OR >50% failure rate with ≥10 requests. Open→half-open: 15s. Half-open probes: 5. |
| **Razorpay (PaymentService)** | ✅ Active | Trip: 3 consecutive failures OR >60% failure rate with ≥5 requests. Open→half-open: 20s. Half-open probes: 3. |
| **Redis** | ❌ No breaker | Redis calls fail-open in rate limiter but no circuit breaker wrapping. |
| **Health endpoint** | ✅ Exposes `circuit_breaker` state in `/health/ready` response |

**Appwrite client also has retry:** 3 retries with exponential backoff (100ms, 300ms + jitter). Only retries on 5xx/network errors. 4xx errors fail immediately (correct behavior).

---

## 9. Redis Usage Audit

| Feature | Key Pattern | Operation | Notes |
|---------|-------------|-----------|-------|
| Rate limiting (global) | `rl:{IP}` | INCR + EXPIRE pipeline | Sliding-window, fail-open on Redis error |
| Rate limiting (auth) | `rl:{IP}` | Same (separate middleware instance) | 10 req/s, burst 20 |
| OTP rate limit | `otp_rate:{phone}` | INCR + EXPIRE | 3 per 10 min per phone |
| Token blacklist | `token_blacklist:{userID}` | SET (7d TTL) → EXISTS | Used in auth middleware for logout |
| Order idempotency | `order_lock:{userID}` | SetNX (30s) → DEL | Prevents duplicate order placement |
| Coupon usage atomic | `coupon_usage:{couponID}` | INCR + EXPIRE | ⚠️ Not decremented on over-limit (bug #7) |
| Delivery order lock | `delivery_lock:{orderID}` | SetNX (30s) | Prevents concurrent accept races |
| Rider locations | `rider_locations` | GEOADD / GeoSearch / ZRem | Geo index for nearby rider matching |
| Notification queue | `notification_queue` | LPush / BRPop | Async notification processing |

**Missing:** No cache usage despite CacheService being defined. Restaurant lists, menus, user profiles, and coupons are all fetched fresh from Appwrite on every request.

---

## 10. WebSocket Handling

**Architecture:** Hub-spoke pattern via `gorilla/websocket`

**Event Types (7):**
1. `order_update` — status changes to customer
2. `delivery_request` — new delivery assignment to rider
3. `delivery_location` — live rider location to customer
4. `new_order` — incoming order to restaurant partner
5. `notification` — in-app notification push
6. `rider_status_change` — rider online/offline
7. `restaurant_update` — generic restaurant updates

**Connection lifecycle:**
- Auth required (JWT via middleware before upgrade)
- Read/write deadlines: 10s write, 60s pong
- Ping interval: 54s (90% of pongWait)
- Max message size: 512 bytes inbound
- Send buffer: 256 messages per client

**Issues:**
- **Linear scan for SendToUser** — O(n) over all clients. No userID→client index.
- **`CheckOrigin` allows all** — XSS/CSRF risk in production.
- **WebSocket user_id context key:** ServeWs reads `c.Get("user_id")` but auth middleware sets `"userId"` (camelCase). **WebSocket connections will fail to associate with users** — upgrade succeeds but `UserID` field is empty.

---

## 11. Background Workers

| Worker | Interval | Purpose | Issues |
|--------|----------|---------|--------|
| **DeliveryMatcher** | 15s | Match ready orders → nearest rider via Redis geo | Only assigns 1 rider (nearest). No retry on rejection. |
| **OrderTimeout** | 30s check, 5m timeout | Auto-cancel unconfirmed orders | Uses wrong field name `"cancel_reason"` vs model's `"cancellation_reason"` |
| **ScheduledOrderProcessor** | 30s | Convert due scheduled orders to placed | **Broken:** calls `ListScheduledOrders("")` with empty user ID; ignores built query. Also only changes status to "placed" without running actual PlaceOrder logic (no price verification, no payment). |
| **NotificationDispatcher** | N/A (BRPOP) | Process queued notifications | Works correctly. FCM push is TODO. |

---

## 12. Model Structure

**17 Appwrite collections** mapped:

| Collection | Model Struct | Key Fields |
|------------|-------------|------------|
| `users` | `User` | ID, name, email, phone, role, referral_code, fcm_token |
| `addresses` | `Address` | user_id, label, lat/lng, pincode |
| `restaurants` | `Restaurant` | owner_id, name, lat/lng, rating, is_online, commission |
| `menu_categories` | `MenuCategory` | restaurant_id, name, sort_order |
| `menu_items` | `MenuItem` | restaurant_id, category_id, price, is_available |
| `orders` | `Order` | customer_id, restaurant_id, delivery_partner_id, status, items (JSON string), grand_total |
| `delivery_requests` | `DeliveryPartner` | user_id, vehicle_type, is_online, current_lat/lng |
| `rider_locations` | `DeliveryLocation` | order_id, partner_id, lat/lng, heading, speed |
| `payouts` | `Payout` | partner_id, amount, status, method |
| `reviews` | `Review` | order_id, customer_id, restaurant_id, food_rating, delivery_rating |
| `coupons` | `Coupon` | code, discount_type/value, min_order_value, usage_limit |
| `payments` | — (untyped map) | order_id, razorpay_order_id, amount, status |
| `notifications` | `Notification` | user_id, type, title, body, is_read |
| `favorites` | `Favorite` | user_id, restaurant_id |
| `gold_subscriptions` | `GoldSubscription` | user_id, plan_type, status, start/end_date |
| `referrals` | `Referral` | referrer_user_id, referred_user_id, referral_code, status |
| `scheduled_orders` | `ScheduledOrder` | user_id, restaurant_id, items, scheduled_for, status |

**NOTE:** Models use `json:"$id"` tags (Appwrite convention). Data flows as `map[string]interface{}` throughout — no strong typing in service/handler layers. Type assertions like `doc["customer_id"].(string)` are used without nil checks in many places.

---

## 13. Middleware Chain

**Order (as registered in main.go):**

1. `Security()` — request ID, security headers
2. `OtelGin("chizze-api")` — OpenTelemetry tracing
3. `Logger()` — structured request logging
4. `gin.Recovery()` — panic recovery
5. `CORS(cfg)` — CORS headers
6. `MaxBodySize(2MB)` — request body limit
7. `Gzip()` — response compression
8. `RedisRateLimit(200, 500)` — global rate limit

**Per-group:**
- Auth routes: + `RedisRateLimit(10, 20)`
- Authenticated routes: + `Auth(cfg, redisClient)`
- Partner routes: + `Auth(cfg, redisClient)` + `RequireRole("restaurant_owner")`
- Delivery routes: + `Auth(cfg, redisClient)` + `RequireRole("delivery_partner")`

**JWT Security:**
- HS256 algorithm pinned (prevents "none" algorithm attack)
- Issuer validated: `"chizze-api"`
- Token blacklist checked via Redis (logout invalidation)
- 7-day expiry

---

## 14. Swagger / API Documentation

- Swagger annotations present on **all handler methods** from what was observed
- Generated docs at `backend/docs/` (docs.go, swagger.json, swagger.yaml)
- Swagger UI accessible at `/swagger/*any`
- `@securityDefinitions.apikey BearerAuth` defined
- Host: `api.devdeepak.me`, BasePath: `/api/v1`

---

## 15. Test Coverage

**Test files found (10):**

| File | What's Tested |
|------|---------------|
| `middleware/auth_test.go` (237 lines) | JWT: missing header, invalid format, expired, wrong secret, valid token, role injection, RequireRole |
| `middleware/ratelimit_test.go` | Rate limiter |
| `models/common_test.go` (80 lines) | Pagination defaults, offset calc, AppError |
| `models/order_test.go` (112 lines) | CanTransition: valid, invalid, coverage, constants |
| `services/geo_service_test.go` (79 lines) | Distance (Mumbai→Pune), ETA estimation |
| `services/order_service_test.go` (147 lines) | Order number generation (format + uniqueness), fee calculation (free/paid/GST) |
| `websocket/websocket_test.go` (273 lines) | Hub register/unregister, SendToUser targeting, broadcast |
| `pkg/redis/redis_test.go` | Redis operations |
| `pkg/utils/validators_test.go` | Phone, email, pincode validators |
| `pkg/utils/geo_test.go` | Haversine, bounding box |

**NOT tested:**
- ❌ No handler/integration tests
- ❌ No payment flow tests
- ❌ No coupon validation tests
- ❌ No worker tests
- ❌ No end-to-end order placement test

---

## 16. Summary & Priority Matrix

### 🔴 Must Fix (P0) — 7 issues

| # | Issue | Impact |
|---|-------|--------|
| 1 | Hardcoded Redis password in config defaults | Credential leak |
| 2 | OTP not sent/verified — auth bypass | Anyone can impersonate any user |
| 3 | Scheduled order cancel has no ownership check | Any user can cancel others' orders |
| 4 | WebSocket `CheckOrigin` allows all | Cross-site WebSocket hijacking |
| 5,6 | `user_id` vs `customer_id` field mismatch in order + delivery handlers | Status notifications + live tracking silently broken |
| 7 | Coupon counter never decremented on over-limit | Coupons become permanently unusable |
| 8 | `c.GetString("user_id")` vs `middleware.GetUserID(c)` — 4 handlers use wrong key | Favorites, gold, referrals, scheduled orders all broken (empty user ID) |

### 🟡 Should Fix (P1) — 6 issues

| # | Issue | Impact |
|---|-------|--------|
| 9,10 | Pagination not applied at DB level (notifications, reviews) | Performance degrades as data grows |
| 11,12 | N+1 queries (MarkAllRead, favorites list) | Appwrite API hammering |
| 13 | Scheduled order items not validated | Price manipulation possible |
| 17 | ScheduledOrderProcessor broken (empty user filter + unused query) | Scheduled orders never auto-placed |

### 🟢 Should Improve (P2) — 5 issues

| # | Issue | Impact |
|---|-------|--------|
| 14 | CreatePayment error unchecked | Silent payment record failures |
| 15 | AcceptOrder doesn't transition status | Order stays "ready" after partner accepts |
| 16 | Worker uses wrong cancellation field name | Cancel reason not persisted |
| 19 | CacheService unused | Unnecessary Appwrite load on every request |
| 20 | WebSocket SendToUser O(n) scan | Performance at scale |

### WebSocket Context Key Bug (additional P0)
- `ServeWs` reads `c.Get("user_id")` but auth middleware sets context key `"userId"`. **All WebSocket connections have empty UserID** — no targeted messages (order updates, delivery location) are delivered.

---

*End of audit. Total issues found: 20+ across security, data integrity, functionality, and performance.*
