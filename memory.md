# Chizze Admin Panel — Memory

## Project Overview
- **App:** Chizze — Premium food delivery platform
- **Tagline:** "Delicious food, delivered fast"
- **Version:** 1.2.4+9 (Flutter), 1.2.0 (Backend)
- **Apps:** Customer App · Restaurant Partner App · Delivery Partner App · **Admin Panel (building)**

## Architecture
- **Mobile Frontend:** Flutter (Riverpod, go_router, Dio, Appwrite SDK)
- **Backend:** Go (Gin framework) — `H:\chizze\backend\`
- **BaaS:** Appwrite — `https://sgp.cloud.appwrite.io/v1`
- **Database:** Appwrite DB, ID: `chizze_db`
- **Cache / Rate limiting:** Redis (`redis://localhost:6379` dev, env-configured prod)
- **Payments:** Razorpay
- **Push Notifications:** Firebase Cloud Messaging (FCM)
- **Real-time:** WebSocket hub (Go) + Appwrite Realtime
- **Monitoring:** Sentry + OpenTelemetry

## Backend API
- **Base URL:** `https://api.devdeepak.me/api/v1`
- **Dev URL:** `http://localhost:8080/api/v1`
- **Auth:** JWT Bearer token in `Authorization` header
- **Swagger UI:** `/swagger/index.html` (non-release mode only)

## Appwrite Config
- **Endpoint:** `https://sgp.cloud.appwrite.io/v1`
- **Project ID:** `6993347c0006ead7404d`
- **Database ID:** `chizze_db`

## Auth System
- OTP-based login (phone number → OTP → JWT)
- **Roles:** `customer` | `restaurant_owner` | `delivery_partner` | `admin`
- JWT stored in Redis for session management + revocation
- Admin role exists in User model — no admin UI existed before this build

## Backend Models (Go structs in `backend/internal/models/`)
- `User` — id, name, email, phone, role, is_gold_member, referral_code, fcm_token, lat/lng
- `Restaurant` — id, owner_id, name, cuisines, city, rating, is_featured, is_promoted, is_online
- `MenuCategory`, `MenuItem` — restaurant menu structure
- `Order` — full lifecycle with timestamps per status
- `OrderItem` — line items
- `DeliveryPartner` — vehicle, location, rating, earnings, documents_verified
- `DeliveryLocation` — real-time rider lat/lng (Appwrite `rider_locations` collection)
- `Payout` — pending | processing | completed | failed
- `Coupon` — percentage | flat, usage limits, validity window
- `GoldSubscription` — monthly | quarterly | annual (₹149 / ₹349 / ₹999)
- `Referral` — referrer/referred tracking, reward amount
- `Review` — food_rating + delivery_rating (1-5), photos, restaurant_reply
- `Notification` — order_update | promo | system | review
- `ScheduledOrder` — future-scheduled orders

## Order Status Flow
placed → confirmed → preparing → ready → pickedUp → outForDelivery → delivered
(cancelled possible from placed/confirmed/preparing)

## Payment Status
pending → paid | refunded | failed

## Payout Status
pending → processing → completed | failed

## Backend Workers (background)
- `DeliveryMatcher` — matches orders to nearby riders (15s tick + instant on order ready/rider reject)
- `OrderTimeout` — auto-cancel unconfirmed orders (5 min timeout, 30s check)
- `ScheduledOrderProcessor` — processes scheduled orders (30s tick)
- `NotificationDispatcher` — sends FCM push notifications (10s tick)

## Admin Panel Location
- **Directory:** `H:\chizze\admin\`
- **Framework:** Next.js 15 (App Router) + TypeScript
- **UI:** Tailwind CSS + shadcn/ui
- **Maps:** react-map-gl + Mapbox GL JS
- **Real-time:** SSE + WebSocket

## Brand Colors
- Orange (Primary/Brand): `#F49D25`
- Deep Orange (Hover): `#E8751A`
- Background: `#0D0D0D`
- Card BG: `#1A1A1A`
- Elevated Surface: `#252525`
- Primary Text: `#FFFFFF`
- Secondary Text: `#A0A0A0`
- Tertiary/Hint: `#666666`
- Success/Green: `#22C55E`
- Error/Red: `#EF4444`
- Warning/Yellow: `#FACC15`
- Info/Blue: `#3B82F6`
- Rating Star: `#FBBF24`

## Typography
- **Font:** Plus Jakarta Sans (all weights)
- Weights used: 400, 500, 600, 700, 800

## Admin Panel Pages (32 total)
1. `/login` — OTP auth restricted to admin role
2. `/` — Dashboard (KPI cards, charts, live feed)
3. `/users` + `/users/:id` — User management
4. `/restaurants` + `/restaurants/:id` — Restaurant management
5. `/orders` + `/orders/:id` — Order management
6. `/delivery-partners` + `/delivery-partners/:id` — Rider management
7. `/payouts` — Payout approval
8. `/coupons` — Coupon CRUD
9. `/reviews` — Review moderation
10. `/gold` — Gold membership management
11. `/referrals` — Referral tracking
12. `/notifications` — Push broadcast
13. `/settings` — Platform config
14. `/live-map` — Real-time Mapbox map (riders + orders + restaurants)
15. `/live-users` — Active WebSocket sessions
16. `/live-orders` — Kanban order board (real-time)
17. `/approvals/restaurants` — New restaurant applications
18. `/approvals/delivery-partners` — Document verification queue
19. `/disputes` — Dispute resolution
20. `/sla` — SLA monitoring
21. `/reports` — Financial reports + CSV/PDF export
22. `/leaderboards` — Top restaurants/customers/riders
23. `/analytics/items` — Item-level analytics
24. `/analytics/cities` — City-level breakdown
25. `/analytics/retention` — Cohort + retention analysis
26. `/content` — Home screen banners
27. `/zones` — Service area management (map-based)
28. `/surge` — Surge pricing rules
29. `/feature-flags` — Feature toggles
30. `/audit-log` — Admin action log
31. `/support` — Support tickets
32. `/settings/admins` — Admin account management

## Key Dependencies (admin panel)
- next@15, react@19, typescript
- tailwindcss, @shadcn/ui
- @tanstack/react-table, @tanstack/react-query
- recharts
- react-map-gl, mapbox-gl
- date-fns
- papaparse (CSV export)
- jspdf, html2canvas (PDF export)
- axios (HTTP client)
- sonner (toasts)
- lucide-react (icons)
- next-themes

## Notes
- Admin role already exists in Go User model — just needs endpoints + UI
- Backend WebSocket hub already handles real-time events — admin SSE taps into this
- Mapbox token needed in `.env.local` as `NEXT_PUBLIC_MAPBOX_TOKEN`
- All admin routes under `/api/v1/admin` require `middleware.RequireRole("admin")`
