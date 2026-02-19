# Chizze — Implementation Plan

> **Stack:** Flutter 3.x (Frontend) · Go 1.22+ (Backend API) · Appwrite 1.5+ (BaaS)
> **Target Scale:** 50,000+ concurrent users, 99.95% uptime, <200ms p95 latency
> **Reference:** See `design.md` for UI/UX specs · See `production_architecture.md` for infrastructure & scaling

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     CLIENTS (Flutter — Mobile Only)              │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ Customer App  │  │ Restaurant App   │  │ Delivery App     │  │
│  │ (Android/iOS) │  │ (Android/iOS)    │  │ (Android/iOS)    │  │
│  └──────┬───────┘  └───────┬──────────┘  └───────┬──────────┘  │
└─────────┼──────────────────┼─────────────────────┼──────────────┘
          │                  │                     │
          ▼                  ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GO BACKEND API                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ REST API │ │WebSocket │ │ Workers  │ │ Middleware        │  │
│  │ (Gin)    │ │(Gorilla) │ │(Queues)  │ │ (Auth/Rate/CORS) │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────────────────┘  │
│       │             │            │                              │
│  ┌────┴─────────────┴────────────┴──────────────────────────┐  │
│  │              Service Layer (Business Logic)               │  │
│  │  Auth · Orders · Restaurants · Delivery · Payments · Geo  │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
            ┌─────────────┴──────────────┐
            ▼                            ▼
┌───────────────────┐    ┌──────────────────────────────────────┐
│   Redis Cluster   │    │      ☁️  APPWRITE CLOUD (Managed)    │
│  ┌─────────────┐  │    │  ┌──────────┐ ┌──────────────────┐  │
│  │ Cache       │  │    │  │   Auth   │ │ Database         │  │
│  │ Sessions    │  │    │  │  (Users, │ │ (Collections,    │  │
│  │ Rate Limit  │  │    │  │   JWT)   │ │  Queries)        │  │
│  │ Geo Index   │  │    │  └──────────┘ └──────────────────┘  │
│  │ Pub/Sub     │  │    │  ┌──────────┐ ┌──────────────────┐  │
│  │ Msg Queue   │  │    │  │ Storage  │ │ Realtime (WS)    │  │
│  └─────────────┘  │    │  │ (CDN)    │ │ (Subscriptions)  │  │
│                   │    │  └──────────┘ └──────────────────┘  │
└───────────────────┘    │  ┌──────────┐ ┌──────────────────┐  │
                         │  │Functions │ │  Messaging (Push) │  │
                         │  │(Triggers)│ │                   │  │
                         │  └──────────┘ └──────────────────┘  │
                         └──────────────────────────────────────┘
```

### Why This Architecture?

| Layer | Technology | Reasoning |
|---|---|---|
| **Frontend** | Flutter | Single codebase for Android & iOS; rich UI toolkit; hot reload; native performance |
| **Backend** | Go (Gin) | High concurrency for real-time tracking; fast compile; strong typing; excellent for microservices |
| **BaaS** | Appwrite Cloud | Fully managed auth/db/storage/realtime/functions; zero database management; auto-scaling; built-in backups |

### Data Flow

```
1. Flutter App → HTTP/WS → Go API (validates, processes logic)
2. Go API → Appwrite SDK → Appwrite Database/Auth/Storage
3. Appwrite Realtime → Flutter App (live updates: orders, tracking)
4. Go Workers → Background jobs (order matching, notifications, analytics)
```

---

## 2. Appwrite Setup

### 2.1 Auth Providers

```
Enabled Providers:
  - Phone (OTP via SMS) — Primary auth method
  - Google OAuth2
  - Apple Sign In
  - Email/Password (fallback)

User Roles (via Appwrite Teams):
  - "customers"           — Regular users ordering food
  - "restaurant_owners"   — Restaurant managers
  - "delivery_partners"   — Riders/drivers
  - "admins"              — Platform administrators

Session Config:
  - Session duration: 365 days (mobile)
  - JWT expiry: 15 minutes (Go API validates)
  - Refresh token: 30 days
```

### 2.2 Database Collections

#### `users` (extended profile)

```json
{
  "$id": "string (Appwrite user ID)",
  "name": "string",
  "email": "string",
  "phone": "string",
  "avatar_url": "string",
  "role": "string (customer | restaurant_owner | delivery_partner | admin)",
  "is_gold_member": "boolean",
  "dietary_preferences": "string[] (vegan, keto, gluten_free, jain)",
  "allergens": "string[]",
  "referral_code": "string",
  "referred_by": "string",
  "fcm_token": "string",
  "created_at": "datetime",
  "updated_at": "datetime"
}
// Indexes: role, phone, referral_code
// Permissions: read(user:{userId}), update(user:{userId})
```

#### `addresses`

```json
{
  "$id": "string",
  "user_id": "string",
  "label": "string (home | work | other | custom_label)",
  "address_line_1": "string",
  "address_line_2": "string",
  "landmark": "string",
  "city": "string",
  "state": "string",
  "pincode": "string",
  "latitude": "double",
  "longitude": "double",
  "is_default": "boolean",
  "created_at": "datetime"
}
// Indexes: user_id, is_default
// Permissions: CRUD(user:{userId})
```

#### `restaurants`

```json
{
  "$id": "string",
  "owner_id": "string (user ID)",
  "name": "string",
  "description": "string",
  "cover_image_url": "string",
  "logo_url": "string",
  "cuisines": "string[] (north_indian, chinese, italian, ...)",
  "address": "string",
  "latitude": "double",
  "longitude": "double",
  "city": "string",
  "rating": "double",
  "total_ratings": "integer",
  "price_for_two": "integer",
  "avg_delivery_time_min": "integer",
  "is_veg_only": "boolean",
  "is_online": "boolean",
  "is_featured": "boolean",
  "is_promoted": "boolean",
  "opening_time": "string (HH:mm)",
  "closing_time": "string (HH:mm)",
  "fssai_license": "string",
  "gst_number": "string",
  "bank_account_id": "string",
  "commission_percentage": "double",
  "created_at": "datetime",
  "updated_at": "datetime"
}
// Indexes: city, cuisines, rating, is_online, owner_id, latitude+longitude (geo)
// Permissions: read(any), write(team:restaurant_owners)
```

#### `menu_categories`

```json
{
  "$id": "string",
  "restaurant_id": "string",
  "name": "string",
  "sort_order": "integer",
  "is_active": "boolean"
}
// Indexes: restaurant_id, sort_order
```

#### `menu_items`

```json
{
  "$id": "string",
  "restaurant_id": "string",
  "category_id": "string",
  "name": "string",
  "description": "string",
  "price": "double",
  "image_url": "string",
  "is_veg": "boolean",
  "is_available": "boolean",
  "is_bestseller": "boolean",
  "is_must_try": "boolean",
  "spice_level": "string (mild | medium | spicy)",
  "preparation_time_min": "integer",
  "customizations": "string (JSON: [{group, options: [{name, price}]}])",
  "calories": "integer",
  "allergens": "string[]",
  "sort_order": "integer",
  "created_at": "datetime",
  "updated_at": "datetime"
}
// Indexes: restaurant_id, category_id, is_available, is_bestseller
// Permissions: read(any), write(team:restaurant_owners)
```

#### `orders`

```json
{
  "$id": "string",
  "order_number": "string (CHZ-XXXXXX)",
  "customer_id": "string",
  "restaurant_id": "string",
  "delivery_partner_id": "string | null",
  "delivery_address_id": "string",
  "delivery_address_snapshot": "string (JSON)",
  "items": "string (JSON: [{item_id, name, quantity, price, customizations, is_veg}])",
  "item_total": "double",
  "delivery_fee": "double",
  "platform_fee": "double",
  "gst": "double",
  "discount": "double",
  "coupon_code": "string | null",
  "tip": "double",
  "grand_total": "double",
  "payment_method": "string (upi | card | wallet | cod)",
  "payment_status": "string (pending | paid | refunded | failed)",
  "payment_id": "string | null",
  "status": "string (placed | confirmed | preparing | ready | picked_up | out_for_delivery | delivered | cancelled)",
  "special_instructions": "string",
  "delivery_instructions": "string (leave_at_door | call_on_arrival | no_contact)",
  "estimated_delivery_min": "integer",
  "placed_at": "datetime",
  "confirmed_at": "datetime | null",
  "prepared_at": "datetime | null",
  "picked_up_at": "datetime | null",
  "delivered_at": "datetime | null",
  "cancelled_at": "datetime | null",
  "cancellation_reason": "string | null",
  "cancelled_by": "string (customer | restaurant | delivery | system)",
  "created_at": "datetime",
  "updated_at": "datetime"
}
// Indexes: customer_id, restaurant_id, delivery_partner_id, status, order_number, placed_at
// Permissions: read(user:{customer_id}), read(team:restaurant_owners), read(team:delivery_partners)
```

#### `delivery_partners`

```json
{
  "$id": "string",
  "user_id": "string",
  "vehicle_type": "string (bike | scooter | bicycle | car)",
  "vehicle_number": "string",
  "license_number": "string",
  "is_online": "boolean",
  "is_on_delivery": "boolean",
  "current_latitude": "double",
  "current_longitude": "double",
  "last_location_update": "datetime",
  "rating": "double",
  "total_ratings": "integer",
  "total_deliveries": "integer",
  "total_earnings": "double",
  "bank_account_id": "string",
  "documents_verified": "boolean",
  "created_at": "datetime",
  "updated_at": "datetime"
}
// Indexes: is_online, is_on_delivery, current_latitude+current_longitude, user_id
```

#### `delivery_locations` (high-frequency writes for tracking)

```json
{
  "$id": "string",
  "order_id": "string",
  "partner_id": "string",
  "latitude": "double",
  "longitude": "double",
  "heading": "double",
  "speed": "double",
  "timestamp": "datetime"
}
// Indexes: order_id, partner_id, timestamp
// TTL: 24 hours (auto-delete old location data)
```

#### `reviews`

```json
{
  "$id": "string",
  "order_id": "string",
  "customer_id": "string",
  "restaurant_id": "string",
  "delivery_partner_id": "string | null",
  "food_rating": "integer (1-5)",
  "delivery_rating": "integer (1-5)",
  "review_text": "string",
  "tags": "string[] (great_food, fast_delivery, polite_rider, well_packed)",
  "photos": "string[] (URLs)",
  "restaurant_reply": "string | null",
  "is_visible": "boolean",
  "created_at": "datetime"
}
// Indexes: restaurant_id, customer_id, food_rating
```

#### `coupons`

```json
{
  "$id": "string",
  "code": "string",
  "description": "string",
  "discount_type": "string (percentage | flat)",
  "discount_value": "double",
  "max_discount": "double",
  "min_order_value": "double",
  "valid_from": "datetime",
  "valid_until": "datetime",
  "usage_limit": "integer",
  "used_count": "integer",
  "restaurant_id": "string | null (null = platform-wide)",
  "is_active": "boolean",
  "applicable_to": "string (all | new_users | gold_members)",
  "created_at": "datetime"
}
// Indexes: code, is_active, valid_until, restaurant_id
```

#### `payouts`

```json
{
  "$id": "string",
  "recipient_id": "string (restaurant or partner user ID)",
  "recipient_type": "string (restaurant | delivery_partner)",
  "amount": "double",
  "period_start": "datetime",
  "period_end": "datetime",
  "order_count": "integer",
  "commission_deducted": "double",
  "tips_included": "double",
  "incentives": "double",
  "bank_reference": "string",
  "status": "string (pending | processing | completed | failed)",
  "created_at": "datetime"
}
// Indexes: recipient_id, status, period_start
```

#### `notifications`

```json
{
  "$id": "string",
  "user_id": "string",
  "type": "string (order_update | promo | system | review)",
  "title": "string",
  "body": "string",
  "data": "string (JSON: {order_id, restaurant_id, ...})",
  "is_read": "boolean",
  "created_at": "datetime"
}
// Indexes: user_id, is_read, type, created_at
```

### 2.3 Storage Buckets

```
Buckets:
  - "restaurant-images"     — Cover photos, logos (max 5MB, jpg/png/webp)
  - "menu-item-images"      — Dish photos (max 3MB, jpg/png/webp)
  - "user-avatars"          — Profile photos (max 2MB, jpg/png/webp)
  - "review-photos"         — Customer food photos (max 5MB, jpg/png/webp)
  - "partner-documents"     — License, ID proof (max 10MB, jpg/png/pdf)
  - "promo-banners"         — Promotional banners (max 5MB, jpg/png/webp)

Image Processing (via Appwrite):
  - Thumbnails: 200x200 crop
  - Cards: 400x300 cover
  - Hero: 800x400 cover
  - Profile: 200x200 circle crop
```

### 2.4 Appwrite Functions (Triggers)

```
1. on_order_placed       — Trigger: orders.create
   → Send push to restaurant, start auto-cancel timer (5 min)

2. on_order_status_change — Trigger: orders.update (status field)
   → Notify customer, update restaurant dashboard, assign delivery

3. on_review_created     — Trigger: reviews.create
   → Recalculate restaurant rating aggregate

4. on_user_signup        — Trigger: users.create
   → Send welcome notification, apply referral bonus

5. delivery_matching     — Scheduled (every 10s via Go worker)
   → Match ready orders with nearest available delivery partners

6. daily_analytics       — Scheduled (cron: 0 2 * * *)
   → Generate daily analytics for restaurants

7. weekly_payouts        — Scheduled (cron: 0 6 * * 1)
   → Process weekly payouts for restaurants and partners
```

---

## 3. Go Backend API

### 3.1 Project Structure

```
backend/
├── cmd/
│   └── server/
│       └── main.go                 # Entry point
├── internal/
│   ├── config/
│   │   └── config.go               # Env vars, Appwrite keys
│   ├── middleware/
│   │   ├── auth.go                 # JWT validation via Appwrite
│   │   ├── cors.go                 # CORS config
│   │   ├── ratelimit.go            # Rate limiting
│   │   └── logger.go               # Request logging
│   ├── handlers/
│   │   ├── auth_handler.go         # Login, signup, OTP
│   │   ├── user_handler.go         # Profile, addresses
│   │   ├── restaurant_handler.go   # CRUD, search, nearby
│   │   ├── menu_handler.go         # Menu items, categories
│   │   ├── order_handler.go        # Create, update status, history
│   │   ├── cart_handler.go         # Cart management
│   │   ├── payment_handler.go      # Payment initiation, webhooks
│   │   ├── delivery_handler.go     # Partner location, assignment
│   │   ├── review_handler.go       # Create, list reviews
│   │   ├── coupon_handler.go       # Validate, apply coupons
│   │   ├── notification_handler.go # List, mark read
│   │   └── analytics_handler.go    # Restaurant/partner analytics
│   ├── services/
│   │   ├── appwrite_service.go     # Appwrite SDK wrapper
│   │   ├── auth_service.go
│   │   ├── order_service.go        # Order state machine
│   │   ├── delivery_service.go     # Matching algorithm
│   │   ├── payment_service.go      # Razorpay/Stripe integration
│   │   ├── notification_service.go # FCM push notifications
│   │   ├── geo_service.go          # Distance, ETA calculations
│   │   ├── search_service.go       # Full-text + geo search
│   │   └── analytics_service.go
│   ├── models/
│   │   ├── user.go
│   │   ├── restaurant.go
│   │   ├── menu_item.go
│   │   ├── order.go
│   │   ├── delivery_partner.go
│   │   ├── review.go
│   │   ├── coupon.go
│   │   └── common.go               # Pagination, errors, responses
│   ├── websocket/
│   │   ├── hub.go                  # WS connection manager
│   │   ├── client.go               # Individual connection
│   │   └── handlers.go             # Location updates, order events
│   └── workers/
│       ├── delivery_matcher.go     # Background delivery matching
│       ├── order_timeout.go        # Auto-cancel unconfirmed orders
│       └── analytics_worker.go     # Aggregate analytics
├── pkg/
│   ├── appwrite/
│   │   └── client.go               # Appwrite Go SDK wrapper
│   └── utils/
│       ├── geo.go                  # Haversine distance, bounding box
│       ├── validators.go
│       └── response.go             # Standard API response format
├── go.mod
├── go.sum
├── Dockerfile
└── docker-compose.yml
```

### 3.2 API Endpoints

#### Authentication

```
POST   /api/v1/auth/send-otp          # Send OTP to phone
POST   /api/v1/auth/verify-otp        # Verify OTP → session token
POST   /api/v1/auth/social-login      # Google/Apple OAuth callback
POST   /api/v1/auth/refresh           # Refresh JWT
DELETE /api/v1/auth/logout             # Invalidate session
```

#### Users

```
GET    /api/v1/users/me                # Get current user profile
PUT    /api/v1/users/me                # Update profile
PUT    /api/v1/users/me/avatar         # Upload avatar
GET    /api/v1/users/me/addresses      # List saved addresses
POST   /api/v1/users/me/addresses      # Add address
PUT    /api/v1/users/me/addresses/:id  # Update address
DELETE /api/v1/users/me/addresses/:id  # Delete address
GET    /api/v1/users/me/favorites      # List favorite restaurants
POST   /api/v1/users/me/favorites/:id  # Add to favorites
DELETE /api/v1/users/me/favorites/:id  # Remove from favorites
```

#### Restaurants

```
GET    /api/v1/restaurants             # List/search (query, filters, sort, pagination)
GET    /api/v1/restaurants/nearby      # Nearby restaurants (lat, lng, radius)
GET    /api/v1/restaurants/:id         # Restaurant detail
GET    /api/v1/restaurants/:id/menu    # Full menu with categories
GET    /api/v1/restaurants/:id/reviews # Reviews list (paginated)
```

#### Restaurant Partner (requires restaurant_owner role)

```
GET    /api/v1/partner/restaurant      # Get my restaurant
PUT    /api/v1/partner/restaurant      # Update restaurant info
PUT    /api/v1/partner/restaurant/status # Toggle online/offline

GET    /api/v1/partner/menu            # List menu items
POST   /api/v1/partner/menu            # Add menu item
PUT    /api/v1/partner/menu/:id        # Update item (price, availability)
DELETE /api/v1/partner/menu/:id        # Delete item
PUT    /api/v1/partner/menu/bulk       # Bulk update availability/prices

GET    /api/v1/partner/categories      # List categories
POST   /api/v1/partner/categories      # Add category
PUT    /api/v1/partner/categories/:id  # Update category
DELETE /api/v1/partner/categories/:id  # Delete category

GET    /api/v1/partner/orders          # List orders (status filter, date range)
PUT    /api/v1/partner/orders/:id/accept   # Accept order
PUT    /api/v1/partner/orders/:id/reject   # Reject order
PUT    /api/v1/partner/orders/:id/ready    # Mark as ready

GET    /api/v1/partner/analytics       # Revenue, orders, ratings analytics
GET    /api/v1/partner/analytics/top-items  # Top selling items
GET    /api/v1/partner/analytics/heatmap   # Peak hours heatmap data
GET    /api/v1/partner/payouts         # Payout history

POST   /api/v1/partner/reviews/:id/reply  # Reply to review
```

#### Orders

```
POST   /api/v1/orders                  # Place order
GET    /api/v1/orders                  # Order history (paginated)
GET    /api/v1/orders/:id              # Order detail
GET    /api/v1/orders/:id/track        # Live tracking data (partner location, ETA)
PUT    /api/v1/orders/:id/cancel       # Cancel order
POST   /api/v1/orders/:id/review       # Submit review
POST   /api/v1/orders/:id/reorder      # Re-create cart from past order
```

#### Cart

```
GET    /api/v1/cart                     # Get current cart
POST   /api/v1/cart/items              # Add item to cart
PUT    /api/v1/cart/items/:id          # Update quantity/customizations
DELETE /api/v1/cart/items/:id          # Remove item
DELETE /api/v1/cart                     # Clear cart
POST   /api/v1/cart/validate-coupon    # Validate and apply coupon
DELETE /api/v1/cart/coupon             # Remove coupon
GET    /api/v1/cart/bill               # Calculate bill breakdown
```

#### Payments

```
POST   /api/v1/payments/initiate       # Create payment order (Razorpay)
POST   /api/v1/payments/verify         # Verify payment after gateway callback
POST   /api/v1/payments/webhook        # Payment gateway webhook
GET    /api/v1/payments/:id/status     # Check payment status
```

#### Delivery Partner

```
GET    /api/v1/delivery/profile        # Get partner profile
PUT    /api/v1/delivery/profile        # Update profile
PUT    /api/v1/delivery/status         # Toggle online/offline
PUT    /api/v1/delivery/location       # Update current location (called every 5s)
GET    /api/v1/delivery/current-order  # Get active delivery
PUT    /api/v1/delivery/orders/:id/arrived    # Arrived at restaurant
PUT    /api/v1/delivery/orders/:id/picked-up  # Picked up order
PUT    /api/v1/delivery/orders/:id/at-customer # Arrived at customer
PUT    /api/v1/delivery/orders/:id/delivered   # Mark delivered
GET    /api/v1/delivery/earnings       # Earnings (period filter)
GET    /api/v1/delivery/history        # Delivery history
GET    /api/v1/delivery/incentives     # Active incentives/bonuses
GET    /api/v1/delivery/payouts        # Payout history
```

#### Coupons

```
GET    /api/v1/coupons                 # Available coupons for user
POST   /api/v1/coupons/validate        # Validate coupon code
```

#### Notifications

```
GET    /api/v1/notifications            # List notifications (paginated)
PUT    /api/v1/notifications/:id/read   # Mark as read
PUT    /api/v1/notifications/read-all   # Mark all as read
PUT    /api/v1/notifications/fcm-token  # Register/update FCM token
```

### 3.3 WebSocket Events

```
Connection: ws://api.chizze.com/ws?token={jwt}

Client → Server:
  "location_update"     — Delivery partner sends GPS coordinates
  "typing"              — Chat typing indicator
  "chat_message"        — In-app chat message

Server → Client:
  "order_status"        — Order status change notification
  "delivery_location"   — Rider location for tracking screen
  "delivery_request"    — New delivery request for partner
  "new_order"           — New order for restaurant partner
  "chat_message"        — Incoming chat message
  "notification"        — General notification push
```

### 3.4 Order State Machine

```
                    ┌──────────────┐
                    │   PLACED     │ ← Customer places order
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            │            ▼
     ┌──────────────┐      │   ┌──────────────┐
     │  CONFIRMED   │      │   │  CANCELLED   │ ← Restaurant rejects / auto-timeout
     └──────┬───────┘      │   └──────────────┘
            │              │
            ▼              │
     ┌──────────────┐      │
     │  PREPARING   │      │ ← Restaurant starts cooking
     └──────┬───────┘      │
            │              │
            ▼              │
     ┌──────────────┐      │
     │    READY      │     │ ← Food ready, match delivery partner
     └──────┬───────┘      │
            │              │
            ▼              │
     ┌──────────────┐      │
     │  PICKED_UP   │      │ ← Delivery partner picks up
     └──────┬───────┘      │
            │              │
            ▼              │
     ┌──────────────────┐  │
     │ OUT_FOR_DELIVERY  │ │ ← Partner en route to customer
     └──────┬───────────┘  │
            │              │
            ▼              │
     ┌──────────────┐      │
     │  DELIVERED   │      │ ← Delivery confirmed
     └──────────────┘      │
                           │
    (Customer can cancel before PREPARING stage)
```

### 3.5 Delivery Partner Matching Algorithm

```go
// Pseudocode for delivery matching
func MatchDeliveryPartner(order Order) (*DeliveryPartner, error) {
    restaurant := GetRestaurant(order.RestaurantID)

    // 1. Find available partners within 5km radius
    candidates := FindNearbyPartners(
        restaurant.Latitude,
        restaurant.Longitude,
        radiusKm: 5.0,
        filter: {IsOnline: true, IsOnDelivery: false},
    )

    // 2. Score each candidate
    for _, partner := range candidates {
        score := 0.0
        // Distance weight (closer = higher score) — 40%
        score += (1 - distance/5.0) * 40

        // Rating weight — 20%
        score += (partner.Rating / 5.0) * 20

        // Acceptance rate — 20%
        score += partner.AcceptanceRate * 20

        // Time since last delivery (avoid idle too long) — 10%
        idleMinutes := time.Since(partner.LastDeliveryAt).Minutes()
        score += min(idleMinutes/30.0, 1.0) * 10

        // Vehicle preference for distance — 10%
        if order.Distance > 5 && partner.VehicleType == "bike" {
            score += 10
        }
        partner.MatchScore = score
    }

    // 3. Sort by score descending, send to top candidate
    sort.Slice(candidates, func(i, j int) bool {
        return candidates[i].MatchScore > candidates[j].MatchScore
    })

    // 4. Send request to top candidate (30s timeout)
    // If declined/timeout → next candidate
    return sendDeliveryRequest(candidates[0], order)
}
```

### 3.6 Key Go Dependencies

```go
// go.mod
module github.com/chizze/backend

go 1.22

require (
    github.com/gin-gonic/gin v1.9.1           // HTTP framework
    github.com/gorilla/websocket v1.5.1        // WebSocket
    github.com/appwrite/sdk-for-go v0.1.0      // Appwrite SDK
    github.com/razorpay/razorpay-go v1.3.1     // Payment gateway
    firebase.google.com/go/v4 v4.14.0          // FCM push notifications
    github.com/golang-jwt/jwt/v5 v5.2.0        // JWT parsing/validation
    github.com/redis/go-redis/v9 v9.5.0        // Redis (caching, rate limit)
    go.uber.org/zap v1.27.0                    // Structured logging
    github.com/robfig/cron/v3 v3.0.1           // Cron scheduler
    github.com/kelseyhightower/envconfig v1.4.0 // Env config
)
```

---

## 4. Flutter Frontend

### 4.1 State Management — Riverpod

```dart
// Providers architecture:
// 1. Service Providers — singleton services
final appwriteServiceProvider = Provider((ref) => AppwriteService());
final apiServiceProvider = Provider((ref) => ApiService(ref));

// 2. State Notifier Providers — complex stateful logic
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(apiServiceProvider));
});
final cartProvider = StateNotifierProvider<CartNotifier, CartState>(...);
final orderTrackingProvider = StreamProvider.family<OrderTracking, String>(...);

// 3. Future Providers — async data fetching
final nearbyRestaurantsProvider = FutureProvider.family<List<Restaurant>, LatLng>(...);
final restaurantMenuProvider = FutureProvider.family<Menu, String>(...);
final orderHistoryProvider = FutureProvider<List<Order>>(...);

// 4. Stream Providers — real-time data
final orderStatusProvider = StreamProvider.family<OrderStatus, String>((ref, orderId) {
  return ref.read(appwriteServiceProvider).subscribeToOrder(orderId);
});
final deliveryLocationProvider = StreamProvider.family<LatLng, String>(...);
```

### 4.2 Routing — GoRouter

```dart
final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final isLoggedIn = /* check auth state */;
    if (!isLoggedIn && !state.matchedLocation.startsWith('/auth')) {
      return '/auth/welcome';
    }
    return null;
  },
  routes: [
    // Auth
    GoRoute(path: '/auth/welcome', builder: (_, __) => WelcomeScreen()),
    GoRoute(path: '/auth/phone', builder: (_, __) => PhoneInputScreen()),
    GoRoute(path: '/auth/otp', builder: (_, __) => OtpVerificationScreen()),
    GoRoute(path: '/auth/profile-setup', builder: (_, __) => ProfileSetupScreen()),

    // Customer App - Shell route with bottom nav
    ShellRoute(
      builder: (_, __, child) => CustomerShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => HomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => SearchScreen()),
        GoRoute(path: '/cart', builder: (_, __) => CartScreen()),
        GoRoute(path: '/favorites', builder: (_, __) => FavoritesScreen()),
        GoRoute(path: '/profile', builder: (_, __) => ProfileScreen()),
      ],
    ),

    // Detail screens (outside shell for full-page navigation)
    GoRoute(path: '/restaurant/:id', builder: (_, state) =>
      RestaurantDetailScreen(id: state.pathParameters['id']!)),
    GoRoute(path: '/checkout', builder: (_, __) => CheckoutScreen()),
    GoRoute(path: '/order/:id/track', builder: (_, state) =>
      OrderTrackingScreen(orderId: state.pathParameters['id']!)),
    GoRoute(path: '/order/:id/rate', builder: (_, state) =>
      RatingScreen(orderId: state.pathParameters['id']!)),

    // Partner routes (separate shell)
    ShellRoute(
      builder: (_, __, child) => PartnerShell(child: child),
      routes: [
        GoRoute(path: '/partner/dashboard', builder: (_, __) => PartnerDashboardScreen()),
        GoRoute(path: '/partner/orders', builder: (_, __) => PartnerOrdersScreen()),
        GoRoute(path: '/partner/menu', builder: (_, __) => MenuManagementScreen()),
        GoRoute(path: '/partner/analytics', builder: (_, __) => AnalyticsScreen()),
      ],
    ),

    // Delivery partner routes
    ShellRoute(
      builder: (_, __, child) => DeliveryShell(child: child),
      routes: [
        GoRoute(path: '/delivery/dashboard', builder: (_, __) => DeliveryDashboardScreen()),
        GoRoute(path: '/delivery/active', builder: (_, __) => ActiveDeliveryScreen()),
        GoRoute(path: '/delivery/earnings', builder: (_, __) => EarningsScreen()),
        GoRoute(path: '/delivery/profile', builder: (_, __) => DeliveryProfileScreen()),
      ],
    ),
  ],
);
```

### 4.3 Core Services

#### AppwriteService (BaaS client)

```dart
class AppwriteService {
  late final Client client;
  late final Account account;
  late final Databases databases;
  late final Storage storage;
  late final Realtime realtime;

  AppwriteService() {
    client = Client()
      .setEndpoint('https://appwrite.chizze.com/v1')
      .setProject('chizze_project_id')
      .setSelfSigned(status: true); // Dev only

    account = Account(client);
    databases = Databases(client);
    storage = Storage(client);
    realtime = Realtime(client);
  }

  // Real-time subscription for order tracking
  Stream<OrderStatus> subscribeToOrder(String orderId) {
    return realtime
      .subscribe(['databases.chizze_db.collections.orders.documents.$orderId'])
      .stream
      .map((event) => OrderStatus.fromJson(event.payload));
  }

  // Real-time subscription for delivery location
  Stream<LatLng> subscribeToDeliveryLocation(String orderId) {
    return realtime
      .subscribe(['databases.chizze_db.collections.delivery_locations.documents'])
      .stream
      .where((event) => event.payload['order_id'] == orderId)
      .map((event) => LatLng(
        event.payload['latitude'],
        event.payload['longitude'],
      ));
  }
}
```

#### ApiService (Go backend client)

```dart
class ApiService {
  late final Dio _dio;

  ApiService(Ref ref) {
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.chizze.com/api/v1',
      connectTimeout: Duration(seconds: 10),
      receiveTimeout: Duration(seconds: 30),
    ));

    // Add auth interceptor
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ref.read(authProvider.notifier).getToken();
        options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          ref.read(authProvider.notifier).refreshToken();
        }
        handler.next(error);
      },
    ));
  }

  // Example endpoints
  Future<List<Restaurant>> getNearbyRestaurants(double lat, double lng, {int radius = 10}) =>
    _dio.get('/restaurants/nearby', queryParameters: {'lat': lat, 'lng': lng, 'radius': radius})
      .then((r) => (r.data['data'] as List).map((e) => Restaurant.fromJson(e)).toList());

  Future<Order> placeOrder(OrderRequest request) =>
    _dio.post('/orders', data: request.toJson())
      .then((r) => Order.fromJson(r.data['data']));
}
```

### 4.4 Theme Implementation

```dart
// lib/core/theme/app_theme.dart
class AppTheme {
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.surfaceBg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.brandOrange,
      secondary: AppColors.deepOrange,
      surface: AppColors.cardBg,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSurface: Colors.white,
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      const TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.secondaryText),
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.tertiaryText),
      ),
    ),
    cardTheme: CardTheme(
      color: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cardBg,
      indicatorColor: AppColors.brandOrange.withOpacity(0.15),
      height: 72,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.brandOrange),
      ),
      hintStyle: const TextStyle(color: AppColors.tertiaryText),
    ),
  );
}
```

---

## 5. Feature Implementation Phases

### Phase 1 — Foundation (Weeks 1-3)

```
Priority: CRITICAL

1. Project Setup
   - Flutter project with Riverpod, GoRouter, Dio
   - Go project with Gin, Appwrite SDK
   - Appwrite instance setup with all collections
   - CI/CD pipeline (GitHub Actions)

2. Authentication
   - Phone OTP login/signup
   - Google & Apple social login
   - JWT token management
   - Role-based routing (customer/partner/delivery)

3. Core Theme & Widgets
   - Implement full design system from design.md
   - Build all shared widgets (glassmorphism card, buttons, etc.)
   - Skeleton loaders, empty states, error states

4. User Profile
   - Profile CRUD
   - Address management with map picker
```

### Phase 2 — Customer Core (Weeks 4-6)

```
Priority: HIGH

5. Home Screen
   - Location-based restaurant discovery
   - Promo carousel
   - Category browsing
   - "Top Picks" and "Popular Near You"

6. Search & Filters
   - Full-text search (restaurant + dish names)
   - Filter by cuisine, rating, veg, delivery time
   - Sort by relevance, rating, distance, cost
   - Recent & trending searches

7. Restaurant Detail & Menu
   - Restaurant info with hero banner
   - Menu with category navigation
   - Item customization bottom sheet
   - Veg/non-veg indicators

8. Cart & Checkout
   - Cart management (add/remove/quantity)
   - Bill calculation with all fees
   - Coupon validation & application
   - Delivery instructions
```

### Phase 3 — Ordering & Payments (Weeks 7-9)

```
Priority: HIGH

9. Payment Integration
    - Razorpay SDK integration
    - UPI, card, wallet, COD support
    - Payment verification flow
    - Refund handling

10. Order Placement & History
    - Order creation with validation
    - Order history with reorder
    - Order detail view

11. Real-time Order Tracking
    - Order status progress bar (Appwrite Realtime)
    - Live map with delivery partner location
    - ETA calculation
    - Delivery partner info card
    - Call/chat with partner

12. Rating & Reviews
    - Post-delivery rating flow
    - Star ratings for food + delivery
    - Photo upload
    - Review history
```

### Phase 4 — Restaurant Partner (Weeks 10-12)

```
Priority: HIGH

13. Partner Dashboard
    - Today's metrics (revenue, orders, rating)
    - Active orders queue
    - Quick actions grid

14. Order Management
    - New order notifications (push + sound)
    - Accept/reject with timer
    - Mark as preparing/ready
    - Order lifecycle management

15. Menu Management
    - CRUD for categories and items
    - Image upload
    - Availability toggles
    - Bulk operations

16. Partner Analytics
    - Revenue trends (charts)
    - Top selling items
    - Peak hours heatmap
    - Comparison period analysis
    - Export reports
```

### Phase 5 — Delivery Partner (Weeks 13-15)

```
Priority: HIGH

17. Delivery Dashboard
    - Online/offline toggle
    - Delivery request with countdown
    - Earnings summary
    - Weekly goal tracking

18. Active Delivery
    - Turn-by-turn navigation (Google Maps)
    - Step-by-step delivery flow
    - Call customer/restaurant
    - Report issue

19. Earnings & Payouts
    - Daily/weekly/monthly earnings
    - Trip-by-trip breakdown
    - Incentives & surge tracking
    - Payout schedule
```

### Phase 6 — Polish & Advanced (Weeks 16-18)

```
Priority: MEDIUM

20. Push Notifications
    - FCM integration
    - Order updates, promos, system alerts
    - In-app notification center

21. Favorites & Recommendations
    - Save/unsave restaurants
    - Personalized recommendations (based on order history)

22. Offers & Coupons System
    - Platform coupons
    - Restaurant-specific offers
    - First-order discounts
    - Referral rewards

23. Chizze Gold Membership
    - Subscription management
    - Free delivery
    - Exclusive offers
    - Priority support

24. Advanced Features
    - Schedule orders for later
    - Group ordering
    - Live chat support
    - Multi-language support (i18n)
    - Dark/light theme toggle
```

---

## 6. Deployment Architecture

> **Full production architecture details:** See [`production_architecture.md`](./production_architecture.md)
> Includes: multi-node scaling, auto-scaling rules, capacity planning for 50K users,
> caching strategy (4-layer), observability stack, disaster recovery, CI/CD pipeline,
> load testing targets, and future-proofing roadmap.

### Docker Compose (Development)

> **Note:** Appwrite runs on **Appwrite Cloud** (cloud.appwrite.io) — no local container needed.
> Only the Go API, Workers, and Redis run locally in Docker.

```yaml
version: '3.8'
services:
  go-api:
    build: ./backend
    ports:
      - "8080:8080"
    env_file: .env
    environment:
      - APP_ENV=development
      - APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1  # Appwrite Cloud
      - APPWRITE_PROJECT_ID=${APPWRITE_PROJECT_ID}
      - APPWRITE_API_KEY=${APPWRITE_API_KEY}
      - REDIS_URL=redis://redis:6379
      - LOG_LEVEL=debug
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  go-worker:
    build:
      context: ./backend
      dockerfile: Dockerfile.worker
    env_file: .env
    environment:
      - APP_ENV=development
      - APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1
      - APPWRITE_PROJECT_ID=${APPWRITE_PROJECT_ID}
      - APPWRITE_API_KEY=${APPWRITE_API_KEY}
      - REDIS_URL=redis://redis:6379
    depends_on:
      - go-api

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru --save 900 1 --save 300 10
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  redis-data:
```

### Environment Configuration (.env.example)

```env
# Appwrite Cloud (get from https://cloud.appwrite.io → Project Settings)
APPWRITE_PROJECT_ID=your-project-id
APPWRITE_API_KEY=your-appwrite-api-key

# Payments
RAZORPAY_KEY=rzp_live_xxxxxxxxxxxx
RAZORPAY_SECRET=xxxxxxxxxxxxxxxxxxxx

# Monitoring
SENTRY_DSN=https://xxx@sentry.io/xxx

# FCM (Push Notifications)
FIREBASE_PROJECT_ID=chizze-app
FIREBASE_CREDENTIALS_PATH=/secrets/firebase.json
```

---

## 7. Testing Strategy

> **Load Testing Details:** See [`production_architecture.md` §12](./production_architecture.md#12-load-testing-plan)

### 7.1 Flutter Testing Pyramid

```
Unit Tests (80%+ coverage):
  - Business logic: cart calculations, order state, price formatting
  - Providers: auth state, cart state, order tracking state transitions
  - Models: JSON serialization/deserialization, validation
  - Utils: geo calculations, date formatting, currency formatting
  - Run: flutter test --coverage (CI enforces >= 80%)

Widget Tests:
  - Every shared widget from design.md §2 (glassmorphism card, buttons, etc.)
  - All screen compositions with mocked providers
  - Interaction tests: tap, scroll, swipe, drag
  - Accessibility: semantics labels, contrast ratios
  - Run: flutter test test/widgets/

Integration Tests:
  - Critical user flows:
    1. Sign up → OTP → Profile setup → Home
    2. Browse → Restaurant → Add to cart → Checkout → Payment → Tracking
    3. Reorder from history
    4. Partner: Accept order → Mark preparing → Mark ready
    5. Delivery: Accept → Navigate → Pick up → Deliver
  - Run: flutter drive --driver=test_driver/integration_test.dart

Golden Tests:
  - Screenshot comparison for all screens in design.md
  - Dark theme + Light theme variants
  - Multiple screen sizes: 360dp, 390dp, 428dp widths
  - Run: flutter test --update-goldens (baseline), flutter test (compare)

Performance Tests:
  - Widget build time profiling (< 16ms per frame)
  - Memory leak detection via DevTools
  - App startup time benchmarks (cold < 3s, warm < 1.5s)
  - Scroll performance (60fps on mid-range devices)
```

### 7.2 Go Backend Testing

```
Unit Tests (85%+ coverage):
  - Service layer: order state machine, delivery matching, billing
  - Handlers: request validation, response formatting, error handling
  - Middleware: auth validation, rate limiting logic
  - Workers: delivery matching algorithm, analytics aggregation
  - Run: go test ./... -race -coverprofile=coverage.out

Integration Tests:
  - API endpoint testing with Docker test containers
  - Database migration tests
  - WebSocket connection lifecycle tests
  - Payment webhook verification
  - Run: go test ./... -tags=integration

Load Tests (k6):
  - Scenario 1: 500 concurrent users browsing + ordering (normal load)
  - Scenario 2: 3000 req/sec spike (flash sale simulation)
  - Scenario 3: 800 delivery partners updating location every 5s
  - Scenario 4: 5000 concurrent WebSocket connections
  - Targets: p95 < 200ms, error rate < 0.1%, 0 dropped WS connections
  - Run: k6 run --vus=500 --duration=30m load_test.js

Security Tests:
  - gosec static analysis (no critical/high findings)
  - Dependency vulnerability scan (trivy, govulncheck)
  - OWASP API Security Top 10 checklist
  - Run: gosec ./... && govulncheck ./...
```

### 7.3 E2E & Chaos Testing

```
E2E (Patrol / Flutter Integration Test):
  - Full user journey automation on real devices (BrowserStack)
  - Run on: Android (API 28, 33), iOS (16, 17)
  - Schedule: nightly on staging

Chaos Testing (Monthly):
  - Kill random Go API pod → verify auto-recovery in < 10s
  - Simulate Redis failure → verify cache fallback serves stale data
  - Inject 500ms latency → verify timeout handling + user-facing messages
  - Simulate payment gateway 503 → verify retry + user notification
  - Network partition API↔DB → verify circuit breaker trips
  - See production_architecture.md §9.3 for full drill checklist
```

---

## 8. Security Checklist (Production-Grade)

### 8.1 Authentication & Authorization

```
✓ JWT with short expiry (15 min) + refresh tokens (30 day)
✓ Rate limiting on OTP: 5 per phone per hour (Redis counter)
✓ Phone verification before account creation
✓ Session invalidation on password/phone change
✓ Brute-force protection: account lockout after 10 failed OTP attempts
✓ Role-based access control (RBAC) enforced at middleware level
✓ API key rotation policy: every 90 days
✓ OAuth2 PKCE flow for mobile social login (no implicit grant)
✓ Secure token storage: flutter_secure_storage (Keychain/Keystore)
```

### 8.2 API Security

```
✓ HTTPS everywhere (TLS 1.3, HSTS header)
✓ CORS whitelist: only chizze.com domains
✓ Rate limiting per endpoint (see production_architecture.md §5.2)
✓ Input validation: struct tags + custom validators on every handler
✓ Request body size limits: 1MB default, 10MB for file uploads
✓ SQL injection prevention: parameterized queries via Appwrite SDK
✓ XSS prevention: Content-Security-Policy headers, HTML sanitization
✓ CSRF protection: SameSite cookies + CSRF tokens for web
✓ File upload validation: type whitelist, size limit, magic byte check
✓ Idempotency keys for all write operations (prevent duplicate orders)
✓ Request signing for payment webhooks (HMAC-SHA256 verification)
✓ API versioning with deprecation sunset headers
```

### 8.3 Data Protection

```
✓ PII encryption at rest (AES-256 via Appwrite)
✓ Mask sensitive data in all logs (card numbers, OTP, phone)
✓ GDPR/IT Act compliance: data export API, right to deletion
✓ Appwrite permissions: document-level access control per user
✓ Payment data: NEVER stored — handled entirely by Razorpay (PCI DSS)
✓ Database connection encryption (TLS between API↔MariaDB)
✓ Secrets management: environment variables, never in code/repo
✓ Audit trail: all admin actions logged with actor + timestamp
✓ Data retention policy: orders >1yr archived, locations >7d deleted
✓ Backup encryption: AES-256 for all database backups
```

### 8.4 Mobile Security

```
✓ Certificate pinning (Dio certificate pinning interceptor)
✓ ProGuard/R8 code obfuscation (Android release builds)
✓ Root/jailbreak detection (flutter_jailbreak_detection)
✓ Secure storage for tokens (flutter_secure_storage)
✓ App integrity check (Play Integrity API / App Attest)
✓ Screenshot/screen recording prevention on sensitive screens
✓ Deep link validation (prevent URL injection attacks)
✓ Minimum OS version enforcement (Android 8+, iOS 15+)
✓ Binary protection: no debug symbols in release builds
✓ Network security config: cleartext traffic disabled
```

### 8.5 Infrastructure Security

```
✓ Cloudflare WAF: OWASP Core Ruleset, bot management
✓ DDoS protection: Cloudflare L3/L4/L7 protection
✓ Container security: non-root user, read-only filesystem
✓ Docker image scanning: Trivy in CI pipeline
✓ SSH access: key-based only, no root login, fail2ban
✓ Network segmentation: API, DB, Redis on separate VLANs
✓ Automated dependency updates: Dependabot/Renovate
✓ Incident response plan documented + tested quarterly
```
