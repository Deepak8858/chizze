# Chizze Admin Panel — Web App
## Problem
Chizze currently has no admin interface. Platform operators have no way to manage users, restaurants, orders, delivery partners, coupons, payouts, or analytics without direct database access. An admin panel is needed for day-to-day operations.
## Current State
* **Frontend:** Flutter mobile app (Customer, Restaurant Partner, Delivery Partner)
* **Backend:** Go (Gin) API at `api.devdeepak.me/api/v1` — Appwrite (BaaS), Redis, Razorpay, Firebase, WebSocket
* **Models:** User (with `admin` role), Restaurant, MenuItem, MenuCategory, Order, DeliveryPartner, Payout, Coupon, GoldSubscription, Referral, Review, Notification, ScheduledOrder
* **Auth:** OTP + JWT-based, roles: `customer | restaurant_owner | delivery_partner | admin`
* Admin role exists in the User model but no admin-specific endpoints or UI exist yet
## Tech Stack
* **Framework:** Next.js 15 (App Router) + TypeScript
* **UI:** Tailwind CSS + shadcn/ui — Chizze dark theme
* **Charts:** Recharts (line, bar, pie, area, heatmap)
* **Tables:** TanStack Table v8 (sorting, filtering, pagination)
* **State/Fetching:** TanStack Query (React Query)
* **Maps:** react-map-gl + Mapbox GL JS (same provider as Flutter app) — live rider pins, order routes, zone polygons
* **Real-time:** Native WebSocket (reuses existing Go hub) + Server-Sent Events (SSE) for one-way live stat streams
* **Date utilities:** date-fns
* **Export:** Papa Parse (CSV), jsPDF + html2canvas (PDF reports)
* **Auth:** JWT in httpOnly cookie, existing `/auth` endpoints restricted to `admin` role
* **Location:** `admin/` directory inside the existing repo
## Backend Changes (New Admin API Routes)
All under `/api/v1/admin`, protected by `middleware.RequireRole("admin")`.
### Admin endpoints to add in Go backend:
**Dashboard**
* `GET /admin/dashboard` — aggregated stats (today's orders, revenue, active users, active restaurants, online riders)
* `GET /admin/analytics` — time-series data (orders/revenue by day/week/month)
**Users**
* `GET /admin/users` — list all users (paginated, filterable by role, search by name/phone/email)
* `GET /admin/users/:id` — full user detail + order history summary
* `PUT /admin/users/:id` — update user (role, block/unblock)
* `DELETE /admin/users/:id` — soft-delete / deactivate
**Restaurants**
* `GET /admin/restaurants` — list all (paginated, filter by city/status/online)
* `GET /admin/restaurants/:id` — detail + menu + orders + reviews summary
* `PUT /admin/restaurants/:id` — update (featured, promoted, online status, approval)
* `DELETE /admin/restaurants/:id` — deactivate
* `GET /admin/restaurants/:id/menu` — full menu for oversight
**Orders**
* `GET /admin/orders` — list all (paginated, filter by status/date/restaurant/customer)
* `GET /admin/orders/:id` — full detail with timeline
* `PUT /admin/orders/:id/cancel` — admin cancel with refund
* `PUT /admin/orders/:id/reassign` — reassign delivery partner
**Delivery Partners**
* `GET /admin/delivery-partners` — list all (filter by online/verified/rating)
* `GET /admin/delivery-partners/:id` — detail + earnings + deliveries
* `PUT /admin/delivery-partners/:id` — verify documents, update status
* `GET /admin/delivery-partners/:id/payouts` — payout history
* `PUT /admin/payouts/:id` — approve/process/reject payout
**Coupons**
* `GET /admin/coupons` — list all
* `POST /admin/coupons` — create coupon
* `PUT /admin/coupons/:id` — update coupon
* `DELETE /admin/coupons/:id` — deactivate
**Reviews**
* `GET /admin/reviews` — list all (filter by rating, flagged)
* `PUT /admin/reviews/:id` — toggle visibility (moderate)
* `DELETE /admin/reviews/:id` — remove
**Gold Memberships**
* `GET /admin/gold/subscriptions` — list all subscriptions
* `GET /admin/gold/stats` — subscription analytics
**Referrals**
* `GET /admin/referrals` — list all referrals with stats
**Notifications (Broadcast)**
* `POST /admin/notifications/broadcast` — send push to a user segment (all, customers, partners, riders)
* `GET /admin/notifications/history` — sent broadcasts history
**Settings**
* `GET /admin/settings` — get platform config (platform fee %, delivery fee logic, commission %, GST rate)
* `PUT /admin/settings` — update platform config
**Live / Real-time (SSE + WebSocket)**
* `GET /admin/live/stats` — SSE stream: active orders count, online riders, connected users, orders-per-minute (ticks every 5s)
* `GET /admin/live/riders` — snapshot of all online riders with lat/lng + delivery status; then SSE stream of location deltas
* `GET /admin/live/orders` — snapshot of all active orders with restaurant + customer + rider coords; SSE stream of status changes
* `GET /admin/live/sessions` — current WebSocket session counts by role (customer / restaurant_owner / delivery_partner)
**Restaurant Approvals**
* `GET /admin/restaurants/pending` — new restaurant applications awaiting approval
* `PUT /admin/restaurants/:id/approve` — approve restaurant, set is_active
* `PUT /admin/restaurants/:id/reject` — reject with reason string
**Delivery Partner Approvals**
* `GET /admin/delivery-partners/pending` — partners with unverified documents
* `PUT /admin/delivery-partners/:id/verify` — approve or reject document verification
**Disputes & Complaints**
* `GET /admin/disputes` — all disputes (paginated, filter by status/type)
* `POST /admin/disputes` — admin-create dispute on behalf of a user
* `PUT /admin/disputes/:id` — update status, add resolution note, trigger refund
**SLA Monitoring**
* `GET /admin/analytics/sla` — avg accept time, avg prep time, avg delivery time, % on-time, breaches list
**Financial Reports**
* `GET /admin/reports/financial` — date-range breakdown: gross revenue, platform fee, delivery fee, discounts, GST, net; restaurant commissions; rider payouts (supports CSV/PDF export param)
* `GET /admin/reports/cancellations` — cancellation rate by reason / restaurant / time-of-day
**Leaderboards & Item Analytics**
* `GET /admin/leaderboards` — top restaurants (orders/revenue/rating), top customers (spend), top riders (deliveries/rating); time-period param
* `GET /admin/analytics/items` — platform-wide bestsellers: item name, order count, revenue; filter by city/restaurant
* `GET /admin/analytics/cities` — per-city: orders, revenue, active restaurants, active riders
* `GET /admin/analytics/retention` — weekly cohort table: signups, % ordered in week 1/2/3/4
**Content Management**
* `GET /admin/content/banners` — home screen promotional banners list
* `POST /admin/content/banners` — create banner (image URL, title, deeplink, active dates, sort order, target segment)
* `PUT /admin/content/banners/:id` — update
* `DELETE /admin/content/banners/:id` — delete
**Zones / Service Areas**
* `GET /admin/zones` — serviceable city zones (GeoJSON polygon + metadata)
* `POST /admin/zones` — create zone
* `PUT /admin/zones/:id` — update (enable/disable, delivery fee override)
* `DELETE /admin/zones/:id` — remove zone
**Surge Pricing**
* `GET /admin/surge` — active and scheduled surge rules
* `POST /admin/surge` — create surge rule (zone, multiplier, time window)
* `PUT /admin/surge/:id` — update
* `DELETE /admin/surge/:id` — deactivate
**Feature Flags**
* `GET /admin/feature-flags` — all flags with current values
* `PUT /admin/feature-flags/:key` — toggle on/off or update value
**Audit Log**
* `GET /admin/audit-log` — paginated, filterable by actor / resource / action / date range
**Support Tickets**
* `GET /admin/support/issues` — reported issues from delivery partners (`POST /delivery/orders/:id/report`)
* `PUT /admin/support/issues/:id` — assign to admin, add note, mark resolved
**Admin Accounts (Super-admin only)**
* `GET /admin/admins` — list admin accounts
* `POST /admin/admins` — create sub-admin with scoped permissions
* `PUT /admin/admins/:id` — update role/permissions
* `DELETE /admin/admins/:id` — deactivate
## Frontend Pages & Features
### 1. Auth
* `/login` — admin email/phone + OTP login (reuses existing auth flow, restricted to `admin` role)
* Protected route middleware — redirects non-admin to login
### 2. Dashboard (`/`)
* **KPI Cards:** Total Orders Today, Revenue Today, Active Orders (live), New Users Today, Online Restaurants, Online Riders
* **Revenue Chart:** Line/bar chart — daily revenue for the past 30 days
* **Order Status Breakdown:** Pie/donut chart (placed, preparing, out for delivery, delivered, cancelled)
* **Recent Orders Feed:** Live-updating table of last 20 orders
* **Peak Hours Heatmap:** Orders by hour-of-day
### 3. Users (`/users`)
* **Table:** Name, Phone, Email, Role, Gold Status, Orders Count, Joined Date, Status (active/blocked)
* **Filters:** Role (customer/restaurant_owner/delivery_partner), gold member, search
* **Actions:** View detail, change role, block/unblock
* **Detail Page (`/users/:id`):** Profile info, order history, addresses, gold subscription, referral stats
### 4. Restaurants (`/restaurants`)
* **Table:** Name, Owner, City, Rating, Orders, Online Status, Featured, Promoted
* **Filters:** City, online/offline, featured, rating range
* **Actions:** View detail, toggle featured/promoted, deactivate
* **Detail Page (`/restaurants/:id`):** Info, menu categories + items, orders list, reviews, analytics (orders/revenue chart)
### 5. Orders (`/orders`)
* **Table:** Order #, Customer, Restaurant, Items, Total, Status, Payment, Date
* **Filters:** Status, date range, restaurant, payment method
* **Actions:** View detail, cancel + refund, reassign rider
* **Detail Page (`/orders/:id`):** Full timeline (placed → confirmed → preparing → ready → picked up → delivered), items list, payment info, delivery partner info, customer info, map
### 6. Delivery Partners (`/delivery-partners`)
* **Table:** Name, Phone, Vehicle, Rating, Deliveries, Online, Verified, Earnings
* **Filters:** Online/offline, verified/unverified, vehicle type
* **Actions:** View detail, verify documents, toggle status
* **Detail Page (`/delivery-partners/:id`):** Profile, documents, earnings chart, delivery history, payout history
### 7. Payouts (`/payouts`)
* **Table:** Partner Name, Amount, Method, Status, Requested Date
* **Filters:** Status (pending/processing/completed/failed)
* **Actions:** Approve, process, mark complete, reject
### 8. Coupons (`/coupons`)
* **Table:** Code, Type (% / flat), Value, Max Discount, Min Order, Valid Period, Usage (used/limit), Status
* **Actions:** Create, edit, deactivate
* **Create/Edit Form:** All coupon fields + restaurant-specific vs platform-wide, target audience (all/new_users/gold)
### 9. Reviews (`/reviews`)
* **Table:** Restaurant, Customer, Food Rating, Delivery Rating, Text (truncated), Date, Visible
* **Filters:** Rating range, visibility, has photos
* **Actions:** Toggle visibility, delete, view full
### 10. Gold Memberships (`/gold`)
* **Stats Cards:** Total Active, Monthly Revenue, Churn Rate
* **Table:** User, Plan Type, Status, Start Date, End Date, Amount
* **Filters:** Plan type, status
### 11. Referrals (`/referrals`)
* **Stats Cards:** Total Referrals, Completed, Total Rewards Paid
* **Table:** Referrer, Referred User, Code, Status, Reward, Date
### 12. Notifications (`/notifications`)
* **Broadcast Form:** Title, Body, Target Segment (all/customers/partners/riders), Schedule (now/later)
* **History Table:** Title, Segment, Sent At, Recipients Count
### 13. Settings (`/settings`)
* **Platform Fees:** Platform fee %, GST rate, base delivery fee, per-km delivery fee
* **Commission:** Restaurant commission %
* **Gold Plans:** Edit pricing for monthly/quarterly/annual
* **Referral:** Reward amount per referral
### 14. Live Map (`/live-map`)
Full-page Mapbox map — the most powerful real-time view:
* **Online Riders layer:** Each rider is a moving avatar pin (bike/scooter/car icon). Color: green = idle, orange = on delivery. Tooltip shows name, phone, current order ID, last-seen time. Updates via SSE location stream.
* **Active Orders layer:** Lines from restaurant → customer for each in-flight order. Line color = order status. Click a line to see order detail card.
* **Restaurants layer:** Static pins for all restaurants. Orange = online, grey = offline. Click to see today's order count + revenue.
* **Heatmap overlay toggle:** Customer order density heatmap (orders placed in last 24h) to spot high-demand zones.
* **Zone overlay toggle:** Service zone polygons from zone management, color-coded by status.
* **Surge overlay toggle:** Active surge zones highlighted in amber.
* **Sidebar panel:** Live counters — Online Riders, Active Orders, Unassigned Orders (red if >0), Avg Delivery Time. Searchable rider list with click-to-pan.
### 15. Live Users (`/live-users`)
* **Presence Panel:** Total connected WebSocket sessions, broken down by role (customers / restaurant partners / delivery partners) — updates every 5s via SSE.
* **Active Session Table:** User name, role, connected since, last action (order placed, status update, etc.), location city — live updating.
* **Online Riders Sub-panel:** All currently online riders in a card grid: name, vehicle, status, deliveries today, earnings today, last location update timestamp.
* **Session Sparklines:** 24-hour sparkline chart of concurrent connections per role.
### 16. Live Order Board (`/live-orders`)
Kanban-style real-time order flow board — columns map to order statuses:
`Placed → Confirmed → Preparing → Ready → Picked Up → Out for Delivery → Delivered`
* Each order is a card: order #, customer name, restaurant, item count, total, elapsed time since last status change.
* Cards auto-move columns in real-time via WebSocket events.
* **SLA colour coding:** Card turns amber if in a status >2× expected time, red if critically delayed.
* **Admin actions on card:** Force-advance status, cancel order, reassign rider — without leaving the board.
* **Filters:** City, restaurant, specific rider.
### 17. Restaurant Approval Queue (`/approvals/restaurants`)
* Pending applications table: submitted date, owner name/phone, restaurant name, city, cuisines.
* Detail view: all restaurant info + uploaded documents (FSSAI, GST, photos).
* Actions: Approve (activates listing), Reject with reason, Request more info (sends notification).
### 18. Delivery Partner Approval Queue (`/approvals/delivery-partners`)
* Pending verifications table: submitted date, name/phone, vehicle type.
* Detail view: license image, vehicle registration, profile photo.
* Actions: Approve (sets `documents_verified = true`), Reject with reason.
### 19. Disputes & Complaints (`/disputes`)
* **Table:** Dispute ID, Order #, Type (wrong item / late delivery / payment / other), Raised By, Status, Created Date.
* **Filters:** Status (open / investigating / resolved), type.
* **Detail view:** Full order context, customer + rider + restaurant info, timeline of events, admin notes thread.
* **Actions:** Change status, add internal note, issue partial/full refund (triggers Razorpay refund via existing payment handler), close dispute.
### 20. SLA Monitor (`/sla`)
* **KPI Cards:** Avg Accept Time (restaurant), Avg Prep Time, Avg Pickup Time, Avg Total Delivery Time, % On-time deliveries.
* **Breach List:** Orders currently exceeding SLA thresholds — sorted by severity. One-click to view order detail.
* **Trend Charts:** 7-day/30-day line charts for each SLA metric.
* **Per-restaurant SLA table:** Sorted by worst offenders.
### 21. Financial Reports (`/reports`)
* **Summary Cards:** Gross Revenue, Platform Fees, Delivery Fees, Total Discounts, GST Collected, Net Platform Revenue — for selected date range.
* **Revenue Chart:** Area chart with toggleable series (gross / net / fees / discounts).
* **Commission Ledger:** Per-restaurant commission earned.
* **Payout Summary:** Total rider payouts (pending / processed) for period.
* **Export:** Download as CSV or PDF.
### 22. Leaderboards (`/leaderboards`)
* **Top Restaurants:** Ranked by orders / revenue / rating — switchable. Time period selector (today / 7d / 30d / all-time).
* **Top Customers:** Ranked by total spend, orders count. Click to view user profile.
* **Top Riders:** Ranked by deliveries, rating, earnings.
### 23. Item Analytics (`/analytics/items`)
* **Bestsellers table:** Item name, restaurant, total orders, total revenue, avg rating mentions. Filter by city, restaurant, date range.
* **Category breakdown:** Pie chart of orders by cuisine/category.
* **Zero-sales items:** Items with no orders in the last 30 days — flag for partners.
### 24. City Analytics (`/analytics/cities`)
* Per-city cards: orders, revenue, active restaurants, active riders, avg delivery time. Click to drill down.
* Map view: choropleth coloring cities by order volume.
### 25. Retention & Cohort (`/analytics/retention`)
* **Cohort table:** Weekly cohort of new signups — % that placed an order in week 0, 1, 2, 3, 4.
* **Funnel chart:** Signup → First order → Second order → Gold subscriber.
* **Churn indicators:** Users who haven't ordered in 30/60/90 days.
### 26. Content Management (`/content`)
* **Banners:** Card grid of all home screen banners with preview image, active status, date range, target segment, sort order. Drag-to-reorder. Create/edit form with image upload.
* **App Config Preview:** Read-only view of what each role's home screen currently shows (which banners are live).
### 27. Zones & Service Areas (`/zones`)
* **Mapbox map** with drawn zone polygons.
* Side panel: zone name, city, status (active/inactive), delivery fee override, rider count currently inside zone, active orders count.
* Create zone by drawing polygon on map. Edit/delete/toggle active.
### 28. Surge Pricing (`/surge`)
* **Active surges table:** Zone, multiplier, start time, end time, trigger (manual / auto-threshold).
* **Create surge rule form:** Select zone (from zones list), set multiplier (e.g. 1.5×), time window.
* **Map view:** Active surge zones highlighted on Mapbox map.
### 29. Feature Flags (`/feature-flags`)
* Table of all flags: key, description, current value (boolean/string/number), last changed by, last changed at.
* Toggle switches for boolean flags, inline text edit for value flags.
* Changes logged to audit log automatically.
### 30. Audit Log (`/audit-log`)
* Immutable, append-only log of all admin actions.
* **Table:** Timestamp, Admin name, Action (create/update/delete/approve/etc.), Resource type, Resource ID, Change summary (before→after diff).
* **Filters:** Admin actor, resource type, action type, date range, search.
### 31. Support Tickets (`/support`)
* Issues reported by delivery partners via the app.
* **Table:** Issue ID, Reporter (rider name), Order #, Category, Status, Assigned To, Created Date.
* **Detail view:** Issue description, order context, admin notes thread.
* **Actions:** Assign to admin, add note, mark resolved, escalate.
### 32. Admin Accounts (`/settings/admins`)
Super-admin only section:
* **Table:** Admin name, email, role (super_admin / finance / operations / support / read_only), Status, Last login.
* **Create form:** Email, name, role/permission scope.
* **Permission scopes:** super_admin (all), finance (reports + payouts), operations (orders + restaurants + riders), support (disputes + support tickets), read_only (view only).
## Project Structure
```warp-runnable-command
admin/
├── app/
│   ├── layout.tsx                 # Root layout (sidebar + header)
│   ├── page.tsx                   # Dashboard
│   ├── login/page.tsx
│   ├── users/
│   │   ├── page.tsx               # Users list
│   │   └── [id]/page.tsx          # User detail
│   ├── restaurants/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   ├── orders/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   ├── delivery-partners/
│   │   ├── page.tsx
│   │   └── [id]/page.tsx
│   ├── payouts/page.tsx
│   ├── coupons/page.tsx
│   ├── reviews/page.tsx
│   ├── gold/page.tsx
│   ├── referrals/page.tsx
│   ├── notifications/page.tsx
│   └── settings/page.tsx
├── components/
│   ├── ui/                        # shadcn components
│   ├── layout/
│   │   ├── sidebar.tsx
│   │   ├── header.tsx
│   │   └── breadcrumbs.tsx
│   ├── dashboard/
│   │   ├── kpi-cards.tsx
│   │   ├── revenue-chart.tsx
│   │   └── order-status-chart.tsx
│   ├── map/
│   │   ├── live-map.tsx           # Main Mapbox map component
│   │   ├── rider-layer.tsx        # Moving rider pins layer
│   │   ├── order-routes-layer.tsx # Active order lines layer
│   │   ├── restaurant-layer.tsx   # Restaurant pins layer
│   │   ├── zone-layer.tsx         # Service zone polygons
│   │   └── surge-layer.tsx        # Surge zone overlay
│   ├── live/
│   │   ├── live-stats-bar.tsx     # Top bar: counters updating via SSE
│   │   ├── order-kanban.tsx       # Kanban board columns
│   │   └── session-panel.tsx      # Live user sessions panel
│   └── data-table.tsx             # Reusable TanStack Table wrapper
├── lib/
│   ├── api.ts                     # API client (fetch wrapper)
│   ├── sse.ts                     # SSE hook factory (useLiveStats, useRiderStream)
│   ├── ws.ts                      # WebSocket client for admin
│   ├── auth.ts                    # Auth utilities
│   ├── export.ts                  # CSV + PDF export helpers
│   └── utils.ts
├── hooks/
│   ├── use-live-stats.ts          # SSE-backed live counter hook
│   ├── use-rider-locations.ts     # SSE-backed rider location stream
│   ├── use-live-orders.ts         # SSE-backed active orders stream
│   └── use-*.ts                   # React Query hooks per resource
├── types/
│   └── index.ts                   # TypeScript types mirroring Go models
├── tailwind.config.ts
├── next.config.ts
├── package.json
└── tsconfig.json
```
## Design
* **Theme:** Dark mode (matching the Chizze brand — `#0D0D0D` bg, `#1A1A1A` cards, `#F49D25` accent)
* **Layout:** Collapsible sidebar nav + top header with user menu
* **Typography:** Plus Jakarta Sans (brand consistency)
* **Responsive:** Desktop-first, functional on tablets
## Implementation Order
1. Scaffold Next.js project — Tailwind + shadcn, Chizze dark theme, Mapbox token
2. Layout shell: sidebar (all 32 nav items grouped), header, auth guard middleware
3. Backend: core admin REST endpoints (dashboard, users, restaurants, orders, delivery partners, coupons, reviews, gold, referrals, payouts, notifications, settings)
4. Backend: SSE endpoints (`/admin/live/stats`, `/admin/live/riders`, `/admin/live/orders`, `/admin/live/sessions`)
5. Dashboard + Live Stats bar
6. Live Map page (Mapbox + all layers + SSE streams)
7. Live Users page + Live Order Board (Kanban)
8. Users + Restaurants management (list + detail)
9. Orders management (list + detail + timeline)
10. Delivery partners + Approval queues (restaurants + riders)
11. Payouts management
12. Disputes & Complaints
13. SLA Monitor
14. Financial Reports (with CSV/PDF export)
15. Leaderboards + Item Analytics + City Analytics + Retention/Cohort
16. Coupons CRUD
17. Reviews moderation
18. Gold + Referrals views
19. Notifications broadcast
20. Content Management (banners)
21. Zones + Surge Pricing (map-based)
22. Feature Flags + Audit Log
23. Support Tickets
24. Admin Accounts (super-admin)
25. Polish — loading skeletons, error boundaries, empty states, toast notifications, keyboard shortcuts
