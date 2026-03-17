# Chizze Admin Panel — Usage Guide

## Table of Contents
1. [Getting Started](#1-getting-started)
2. [Login & Authentication](#2-login--authentication)
3. [Dashboard](#3-dashboard)
4. [Real-Time Monitoring](#4-real-time-monitoring)
5. [User Management](#5-user-management)
6. [Restaurant Management](#6-restaurant-management)
7. [Order Management](#7-order-management)
8. [Delivery Partner Management](#8-delivery-partner-management)
9. [Payouts](#9-payouts)
10. [Approval Queues](#10-approval-queues)
11. [Disputes](#11-disputes)
12. [Coupons](#12-coupons)
13. [Gold Subscriptions](#13-gold-subscriptions)
14. [Referrals](#14-referrals)
15. [Notifications](#15-notifications)
16. [Content Management](#16-content-management)
17. [SLA Monitor](#17-sla-monitor)
18. [Reports](#18-reports)
19. [Analytics](#19-analytics)
20. [Reviews](#20-reviews)
21. [Zones](#21-zones)
22. [Surge Pricing](#22-surge-pricing)
23. [Feature Flags](#23-feature-flags)
24. [Audit Log](#24-audit-log)
25. [Support Tickets](#25-support-tickets)
26. [Settings](#26-settings)
27. [Admin Accounts](#27-admin-accounts)

---

## 1. Getting Started

### Prerequisites
- Node.js 18+ installed
- Access to the Chizze backend API
- A Mapbox public token (for the Live Map feature)

### Setup
1. Clone the repository and navigate to the `admin/` folder.
2. Install dependencies:
   ```
   npm install
   ```
3. Copy `.env.example` to `.env.local` and fill in your values:
   - `NEXT_PUBLIC_API_URL` — your Chizze backend API base URL (no trailing slash)
   - `NEXT_PUBLIC_MAPBOX_TOKEN` — your Mapbox public access token
4. Start the dev server:
   ```
   npm run dev
   ```
5. Open `http://localhost:3000` in your browser. You will be redirected to the login page.

### Production Build
```
npm run build
npm start
```

---

## 2. Login & Authentication

**Route:** `/login`

1. Enter your registered admin phone number (10 digits, India +91).
2. Click **Send OTP**. A 6-digit code is sent via SMS.
3. Enter the OTP and click **Verify & Sign In**.
4. Only users with an admin role are allowed. Customers, restaurant owners, and delivery partners will see "Access denied."
5. Your session token is stored in the browser. You stay logged in until you log out or the token expires (automatic redirect on 401).

**Logging out:** Click the logout icon (top-right corner of the header).

---

## 3. Dashboard

**Route:** `/dashboard`

The dashboard is your landing page. It provides a high-level overview of the platform:

- **KPI Cards** — Orders today, revenue today, active orders, new users, online restaurants, online riders. Each card shows the value and a percentage delta vs. yesterday.
- **Revenue Chart** — 30-day area chart of daily revenue.
- **Order Status Pie** — Donut chart showing the breakdown of current order statuses.
- **Orders Per Day** — Bar chart of daily order counts.
- **Recent Orders Table** — The latest orders with order number, customer, restaurant, total, status, and time ago.

Data auto-refreshes every 30 seconds.

---

## 4. Real-Time Monitoring

### Live Map (`/live-map`)
An interactive Mapbox map showing:
- **Rider pins** (green = idle, orange = on delivery). Click a rider to see their name, phone, status, and current order.
- **Restaurant pins** (orange = online, grey = offline).
- **Order route lines** connecting restaurant → rider → customer.
- **Heatmap overlay** — Toggle to visualize customer demand hotspots.
- **Sidebar** — Shows live stats (on delivery, active orders, online riders), a rider search bar, and a scrollable rider list. Click any rider to fly the map to their location.
- **Overlay toggles** — Heatmap, Zones, Surge.

### Live Users (`/live-users`)
Real-time WebSocket session counts:
- Total sessions, customers, restaurant partners, delivery partners.
- Sparkline charts showing trend over the last 24 data points.
- Online rider grid with avatar, name, phone, vehicle type, status (active/idle), last seen.

### Live Orders (`/live-orders`)
A Kanban board with columns for each active order status:
- Placed → Confirmed → Preparing → Ready → Picked Up → Out for Delivery
- Each order card shows order number, restaurant name, customer name, grand total, and time since placement.
- Cards are color-coded by SLA status: normal (no border), warning (yellow left border), critical (red border + pulse animation).
- A "Disconnected" indicator appears if the SSE connection drops.

---

## 5. User Management

**Route:** `/users`

- View all platform users (customers, restaurant owners, delivery partners).
- **Filter by role** using the tabs at the top: All, Customer, Restaurant Owner, Delivery Partner.
- **Search** by name.
- Each row shows: avatar, name, phone, email, role, Gold membership status, join date.
- **Block/Unblock** — Click the Block or Unblock button per row to toggle a user's blocked status.

---

## 6. Restaurant Management

**Route:** `/restaurants`

- View all registered restaurants with: logo, name, city, cuisines, rating, online status, featured badge, avg delivery time, and join date.
- **Search** by restaurant name.
- **Toggle Featured** — Click the "Feature" or "Featured" button on any row to toggle the featured badge.
- Sortable columns (click headers).
- Paginated with 20 items per page.

---

## 7. Order Management

### Orders List (`/orders`)
- View all orders with: order number (clickable link), customer ID, restaurant name, grand total, status badge, payment method, placed at timestamp.
- **Search** by order number.
- Click an order number to navigate to the **Order Detail** page.
- Auto-refreshes every 30 seconds.

### Order Detail (`/orders/[id]`)
A full detail page with:
- **Header** — Order number, status badge, payment status badge, time since placement.
- **Action buttons** (for non-final orders):
  - **Reassign Rider** — Opens a modal with a dropdown of online riders. Select one and click Reassign.
  - **Cancel Order** — Opens a modal requiring a cancellation reason. Confirm to cancel.
- **Status Timeline** — A horizontal timeline showing each status step (Placed → Confirmed → Preparing → Ready → Picked Up → Out for Delivery → Delivered) with checkmarks for completed steps and timestamps.
- **Cancelled orders** — Show a red banner with the cancellation reason and timestamp instead of the timeline.
- **Items List** — All items with veg/non-veg indicator, name, quantity, and line total. Special instructions shown if present.
- **Pricing Breakdown** — Item total, delivery fee, platform fee, GST, tip, discount (with coupon code if applicable), grand total, payment method, and payment ID.
- **Customer Card** — Customer ID, delivery type, delivery instructions.
- **Restaurant Card** — Name, ID, estimated delivery time.
- **Delivery Rider Card** — Name, phone (clickable), partner ID. Shows "No rider assigned yet" if none.
- **Order Meta** — Full order ID, placed timestamp, delivered timestamp.

---

## 8. Delivery Partner Management

**Route:** `/delivery-partners`

- View all delivery partners with: name, phone, vehicle type, rating, total deliveries, total earnings, online status, block/unblock button, join date.
- **Search** by name.
- **Block/Unblock** — Toggle a partner's blocked status.

---

## 9. Payouts

**Route:** `/payouts`

- View payout records with: recipient name and ID, amount, method (bank transfer/UPI), status, note, reference.
- **Filter by status** using tabs: All, Pending, Processing, Completed, Failed.
- **Summary cards** — Total payout volume and pending amount.
- **Actions** (for pending payouts only):
  - **Approve** — Moves the payout to "processing" status.
  - **Reject** — Marks the payout as "failed."
- **Export CSV** — Click the "Export CSV" button to download all displayed payouts as a CSV file.

---

## 10. Approval Queues

### Restaurant Approvals (`/approvals/restaurants`)
- View pending restaurant applications with: name, owner ID, cuisines, city, approval status, applied date.
- **Approve** or **Reject** each application.

### Rider Approvals (`/approvals/delivery-partners`)
- View pending delivery partner applications with: name, phone, vehicle type, vehicle number, license number, applied date.
- **Approve** or **Reject** each application.

---

## 11. Disputes

**Route:** `/disputes`

- View all disputes with: order ID, raised by (role + ID), type, description, refund amount, status, raised at.
- **Filter by status**: All, Open, Investigating, Resolved, Closed.
- **Search** by order ID.
- **Resolve** — Click the "Resolve" button on any open/investigating dispute to open a modal where you:
  - Enter a resolution note.
  - Optionally check "Trigger refund to customer."
  - Click "Resolve" to close the dispute.

---

## 12. Coupons

**Route:** `/coupons`

- View all coupons with: code, type (percentage/flat/free delivery), min order, used/limit, expiry, active status.
- **Search** by coupon code.
- **Create New Coupon** — Click "New Coupon" to open a form with:
  - Code, discount value, min order, max discount, usage limit, valid until date, discount type.
- **Delete** — Click the trash icon on any coupon row.

---

## 13. Gold Subscriptions

**Route:** `/gold`

- **Stats cards** — Active members, total revenue, monthly plans, yearly plans.
- **Subscriptions table** — User ID, plan type, amount, start date, end date, status (active/expired/cancelled).
- **Search** by user ID.

---

## 14. Referrals

**Route:** `/referrals`

- **Stats cards** — Total referrals, completed, total rewarded amount.
- **Referrals table** — Referrer, referred user, referral code, reward amount, status, created date.
- **Search** by referral code.

---

## 15. Notifications

**Route:** `/notifications`

A split-view page:

**Left panel — Send Notification:**
1. Enter a **title** and **message body**.
2. Select a **target**: All Users, All Riders, All Restaurants, or Specific User (enter their ID).
3. Select a **type**: Promotional, Order Update, System, Offer.
4. Click **Send Notification**.

**Right panel — Recent Notifications:**
- Scrollable list of previously sent notifications with title, body, and timestamp.

---

## 16. Content Management

**Route:** `/content`

Two tabs: **Banners** and **Categories**.

### Banners
- View all banners as image cards with title, target segment, sort order, active/inactive status.
- **Add Banner** — Click "Add Banner" to open a form with: title, image URL, deep link, sort order, target segment.
- **Activate/Deactivate** — Toggle a banner's active state.
- **Delete** — Click the trash icon to remove a banner.

### Categories
- View all food categories as grid cards with image (or initial), name, and position number.

---

## 17. SLA Monitor

**Route:** `/sla`

Real-time delivery SLA tracking (auto-refreshes every 30 seconds):

- **Summary cards** — Critical (>45 min), Warning (30–45 min), On Track (<30 min).
- **Order cards** — Each active order shows: order number, restaurant name, status, elapsed time, and a progress bar.
  - Cards are visually colored: red border for critical, yellow for warning, green for on-track.
- When no active orders exist, a success message is displayed.

---

## 18. Reports

**Route:** `/reports`

Financial and operational reports:

- **Range selector** — 7d, 30d, 90d, 1y.
- **KPI row** — Total revenue, total orders, average order value (for the selected range).
- **Revenue Over Time** — Area chart.
- **Orders Per Day** — Bar chart.
- **Raw Data Table** — Date-by-date breakdown of revenue, orders, and avg order value.
- **Export** — Click "CSV" to download the data, or "PDF" to export the entire page as a PDF document.

---

## 19. Analytics

**Route:** `/analytics`

Advanced analytics with:

- **Leaderboards** — Toggle between Restaurants, Riders, and Items to see the top 10 by revenue and order count.
- **City Performance** — Horizontal bar chart of revenue by city.
- **User Retention Cohorts** — Table showing week-over-week retention percentages with heatmap-style coloring.
- **Top Items** — Sortable table of the 20 most popular items by order count or revenue. Shows item name, restaurant, city, orders, and revenue.
- **Orders by City** — Grouped bar chart comparing orders and restaurant counts by city.

---

## 20. Reviews

**Route:** `/reviews`

- View all reviews with: restaurant name, user name, star rating (visual), review text, visibility status, date.
- **Filter by status**: All, Pending, Approved, Rejected, Flagged.
- **Moderate** — Click "Show" to make a review visible, or "Hide" to hide it.

---

## 21. Zones

**Route:** `/zones`

Manage delivery zones:

- View all zones with: name, city, delivery fee override, active status.
- **Search** by zone name.
- **Add Zone** — Click "Add Zone" to create a new delivery zone with name, city, optional delivery fee override, and optional GeoJSON polygon coordinates.
- **Activate/Deactivate** — Toggle a zone's active state.
- **Delete** — Remove a zone.

---

## 22. Surge Pricing

**Route:** `/surge`

Dynamic pricing management:

- View all surge rules with: zone name, multiplier (e.g., 1.5x), reason, active window (start → end time), active status.
- **Add Surge** — Select a zone, set the multiplier (1–5x), choose a reason (high demand, bad weather, festival, peak hours, low riders), and optionally set a time window.
- **Start/Stop** — Toggle a surge rule on or off.
- **Delete** — Remove a surge rule.

---

## 23. Feature Flags

**Route:** `/flags`

Toggle platform features without redeploying:

- Each flag shows: key name, description, current value, enabled/disabled status, and a toggle switch.
- Click the toggle to enable or disable a feature instantly.
- Useful for A/B testing, gradual rollouts, or emergency kill switches.

---

## 24. Audit Log

**Route:** `/audit-log`

A read-only log of all admin actions:

- Each entry shows: admin name, action type (create/update/delete/approve/reject/verify/broadcast/export), resource type and ID, summary, and timestamp.
- **Search** by action type.
- Sortable columns.

---

## 25. Support Tickets

**Route:** `/support`

Manage customer support issues:

- View all tickets with: description, category, reporter ID, status, created date.
- **Filter by status**: All, Open, Investigating, Resolved.
- **View** — Click "View" on any ticket to open a detail drawer with:
  - Ticket info (order number, category, status).
  - **Message thread** — Chat-style view of all messages between admin and user.
  - **Reply** — Type a message and press Enter or click Send.
  - **Close ticket** — Mark the ticket as resolved.

---

## 26. Settings

**Route:** `/settings`

Global platform configuration:

- **General** — Platform name, support email, support phone, maintenance mode toggle.
- **Pricing & Fees** — Platform fee %, min order amount, free delivery threshold, max delivery radius, Razorpay live mode toggle.
- **Gold Subscription** — Monthly and yearly price.
- **Referrals & OTP** — Referral reward amount, min orders for reward, OTP expiry time.

Click **Save Changes** to persist all settings at once.

---

## 27. Admin Accounts

**Route:** `/admin-accounts`

Manage who has access to the admin panel:

- View all admins with: name, email, permission level, phone, active status, last login.
- **Permission levels**: Super Admin, Finance, Operations, Support, Read Only — each displayed with a distinct color badge.
- **Add Admin** — Click "Add Admin" to create a new admin account with name, email, phone, and permission level.
- **Delete** — Remove an admin account (you cannot delete yourself).

---

## Quick Reference — Keyboard Shortcuts

| Action | How |
|---|---|
| Navigate between pages | Click sidebar links |
| Collapse/Expand sidebar | Click the collapse button at the bottom of the sidebar |
| Search within any table | Type in the search input above the table |
| Sort table columns | Click any column header |
| Submit forms | Fill required fields and click the primary action button |
| Close modals | Click outside the modal or click Cancel |

---

## Environment Variables

| Variable | Description | Required |
|---|---|---|
| `NEXT_PUBLIC_API_URL` | Chizze backend API base URL | Yes |
| `NEXT_PUBLIC_MAPBOX_TOKEN` | Mapbox public access token (for Live Map) | Yes |

---

## Tech Stack

- **Framework**: Next.js 16 (App Router, Turbopack)
- **Language**: TypeScript
- **Styling**: Tailwind CSS v4 (dark theme)
- **Data Fetching**: TanStack React Query
- **Tables**: TanStack Table
- **Charts**: Recharts
- **Maps**: Mapbox GL via react-map-gl
- **Real-time**: Server-Sent Events (SSE)
- **Toasts**: Sonner
- **Icons**: Lucide React
- **Exports**: PapaParse (CSV), html2canvas + jsPDF (PDF)
