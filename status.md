# Chizze — Project Status

> **Last Updated:** 2026-02-19T22:08:00+05:30
> **Current Phase:** Phase 3 — Ordering & Payments
> **Phase Status:** ✅ COMPLETE
> **Next Action:** Phase 4 — Restaurant Partner (awaiting user go-ahead)

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
  backend_api: Go (planned, not yet started)
  database: Appwrite Collections (managed by Appwrite Cloud)
  storage: Appwrite Storage (managed)
  payments: Razorpay (razorpay_flutter 1.4.1)
  maps: Google Maps (planned)
appwrite:
  endpoint: https://sgp.cloud.appwrite.io/v1
  project_id: "6993347c0006ead7404d"
apps:
  - Customer App (primary, in progress)
  - Restaurant Partner App (planned)
  - Delivery Partner App (planned)
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
| 4 | Restaurant Partner | 10-12 | ⏳ NOT STARTED | 0% |
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

## File Tree (Current)

```
H:\chizze\
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── auth/
│   │   │   └── auth_provider.dart
│   │   ├── constants/
│   │   │   └── appwrite_constants.dart
│   │   ├── router/
│   │   │   └── app_router.dart                # [UPDATED] + Phase 3 routes
│   │   ├── services/
│   │   │   └── appwrite_service.dart
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
│   │   │   └── screens/
│   │   │       └── home_screen.dart
│   │   ├── orders/                             # [NEW] Phase 3
│   │   │   ├── models/
│   │   │   │   └── order.dart                 # Order + OrderItem + OrderStatus
│   │   │   ├── providers/
│   │   │   │   └── orders_provider.dart       # Orders state management
│   │   │   └── screens/
│   │   │       ├── order_confirmation_screen.dart  # Post-payment success
│   │   │       ├── order_tracking_screen.dart      # Real-time tracking
│   │   │       ├── orders_screen.dart              # Active/Past history
│   │   │       └── review_screen.dart              # Rating & review
│   │   ├── payment/                            # [NEW] Phase 3
│   │   │   ├── providers/
│   │   │   │   └── payment_provider.dart      # Razorpay integration
│   │   │   └── screens/
│   │   │       └── payment_screen.dart        # Payment method + checkout
│   │   ├── restaurant/
│   │   │   ├── models/
│   │   │   │   └── menu_item.dart
│   │   │   └── screens/
│   │   │       └── restaurant_detail_screen.dart
│   │   ├── search/
│   │   │   └── screens/
│   │   │       └── search_screen.dart
│   │   └── splash/screens/
│   │       └── splash_screen.dart
│   └── shared/widgets/
│       ├── chizze_button.dart
│       ├── glass_card.dart
│       ├── shimmer_loader.dart
│       └── widgets.dart
├── assets/ (images, icons, animations, fonts dirs)
├── pubspec.yaml
├── design.md
├── implementation_plan.md
├── production_architecture.md
└── status.md
```

---

## Complete User Flow (Phases 1-3)

```
App Launch → Splash (animated) → Auth Check
  ├── Not authenticated → Login → Phone OTP / Social / Email → OTP Verify
  └── Authenticated → Home Screen
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
        │                 └── Pay → Razorpay SDK opens
        │                       ├── Success → Order Confirmation → Track Order
        │                       │                                       ├── Timeline (7 stages)
        │                       │                                       ├── Delivery partner card
        │                       │                                       └── Delivered → Rate Order
        │                       │                                             ├── Food stars
        │                       │                                             ├── Delivery stars
        │                       │                                             ├── Tags
        │                       │                                             └── Review text
        │                       └── Error → Error display + retry
        └── Bottom Nav
              ├── Home
              ├── Search
              ├── Orders (Active/Past tabs)
              │     ├── Active → Track Order
              │     └── Past → Reorder / Rate
              └── Profile (placeholder)
```

---

## Known Issues & Tech Debt

| ID | Severity | File | Issue | Status |
|---|---|---|---|---|
| TD-001 | LOW | `appwrite_client.dart` | Legacy file, superseded | To remove |
| TD-002 | LOW | `config/environment.dart` | Legacy config | To remove |
| TD-003 | LOW | `test/widget_test.dart` | References old MyApp | To fix |
| TD-004 | LOW | `test/appwrite_connection_test.dart` | Deprecated APIs | To refactor |
| TD-005 | MEDIUM | Login screen | OAuth needs Appwrite config | Phase 4+ |
| TD-006 | LOW | All screens | Mock data — needs Appwrite collections | When backend ready |
| TD-007 | LOW | Fonts | Using google_fonts (network) | OK for dev |
| TD-008 | LOW | Restaurant detail | Emoji placeholders for images | When storage ready |
| TD-009 | MEDIUM | payment_provider.dart | `RazorpayConfig.keyId` needs real key | Before testing |
| TD-010 | MEDIUM | payment_provider.dart | `order_id` field empty — need Go backend to create Razorpay orders | Before production |

---

## Razorpay Integration Details

```yaml
package: razorpay_flutter 1.4.1
config_file: lib/features/payment/providers/payment_provider.dart
key_location: RazorpayConfig.keyId (currently test placeholder)
flow:
  1. User taps "Pay Now" on payment screen
  2. PaymentNotifier.startPayment() called with amount, user details
  3. Amount converted to paise (× 100)
  4. Razorpay.open() called with options (key, amount, prefill, theme)
  5. Razorpay SDK shows its native checkout UI
  6. On success: PaymentState updated, cart cleared, order created, navigate to confirmation
  7. On error: PaymentState.error set, user can retry
  8. COD: Bypasses Razorpay, creates order directly
production_requirements:
  - Replace test key with live Razorpay key
  - Create Razorpay orders via Go backend (server-side)
  - Verify payment signature server-side
  - Handle refunds via Go backend
```

---

## Changelog

| Date | Action | Details |
|---|---|---|
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
