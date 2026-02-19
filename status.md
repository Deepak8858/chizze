# Chizze — Project Status

> **Last Updated:** 2026-02-19T21:55:00+05:30
> **Current Phase:** Phase 2 — Customer Core
> **Phase Status:** ✅ COMPLETE
> **Next Action:** Phase 3 — Ordering & Payments (awaiting user go-ahead)

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
  cache: Redis (planned)
  payments: Razorpay (planned)
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
| 3 | Ordering & Payments | 7-9 | ⏳ NOT STARTED | 0% |
| 4 | Restaurant Partner | 10-12 | ⏳ NOT STARTED | 0% |
| 5 | Delivery Partner | 13-15 | ⏳ NOT STARTED | 0% |
| 6 | Polish & Advanced | 16-18 | ⏳ NOT STARTED | 0% |

---

## Phase 1 — Foundation (COMPLETE)

### 1.1 Project Setup ✅

- [x] Flutter project initialized
- [x] pubspec.yaml with all Phase 1 dependencies (133 packages installed)
- [x] Asset directories created (images, icons, animations, fonts)
- [x] Analysis clean — 0 errors in `lib/`

### 1.2 Design System ✅

- [x] `app_colors.dart` — Full dark theme palette (primary orange, backgrounds, text, semantic, glass effects, food indicators)
- [x] `app_typography.dart` — Plus Jakarta Sans across all levels (h1-h3, body1-2, caption, button, buttonSmall, price, priceLarge, badge, overline)
- [x] `app_spacing.dart` — Spacing scale (4-64dp), border radius, icon sizes, avatar sizes, touch targets
- [x] `app_theme.dart` — Complete ThemeData for all Material widgets
- [x] `theme.dart` — Barrel export

### 1.3 Core Widgets ✅

- [x] `glass_card.dart` — Glassmorphism card (6% white bg, 10% white border, 20px blur, tap support)
- [x] `chizze_button.dart` — Primary gradient CTA button + ChipButton
- [x] `shimmer_loader.dart` — Skeleton loaders
- [x] `widgets.dart` — Barrel export

### 1.4 Architecture ✅

- [x] `appwrite_service.dart` — Riverpod providers (Client, Account, Databases, Storage, Realtime)
- [x] `auth_provider.dart` — Email, Phone OTP, OAuth, session persistence, logout
- [x] `app_router.dart` — GoRouter with auth redirects + ShellRoute with bottom nav

### 1.5 Auth Screens ✅

- [x] `splash_screen.dart` — Animated splash
- [x] `login_screen.dart` — Phone + Email + Social login
- [x] `otp_screen.dart` — 6-digit OTP verification

---

## Phase 2 — Customer Core (COMPLETE)

### 2.1 Data Models ✅

- [x] `appwrite_constants.dart` — Database/collection/bucket ID constants
- [x] `restaurant.dart` — Restaurant model with fromMap/toMap + 5 mock restaurants (Bengaluru-based)
- [x] `menu_item.dart` — MenuItem + MenuCategory + CustomizationGroup/Option models with mock data (6 items, 3 categories)

### 2.2 State Management ✅

- [x] `cart_provider.dart` — CartItem (with customization pricing), CartState (with fee calc: delivery/platform/GST/discount), CartNotifier (add/remove/update/coupon/clear)

### 2.3 Home Screen (Enhanced) ✅

- [x] Location header with delivery address
- [x] Search bar → navigates to /search
- [x] Horizontal category chips → navigate to /search
- [x] Promo banner (50% off)
- [x] Restaurant cards using Restaurant model with:
  - Cuisine emoji placeholder images
  - Rating badge (green ≥4.0, yellow <4.0)
  - Delivery time & price for two
  - Promoted/Featured badges
  - VEG tag for pure vegetarian restaurants
  - Tap → navigates to /restaurant/:id

### 2.4 Search Screen ✅

- [x] Auto-focus search text field with clear button
- [x] Horizontal filter chips: Sort, Pure Veg, Rating 4.0+, cuisine categories
- [x] Sort bottom sheet: Relevance, Rating, Delivery Time, Cost Low/High
- [x] Filtered restaurant list using Riverpod providers
- [x] Empty state for no results
- [x] Animated card entrance

### 2.5 Restaurant Detail Screen ✅

- [x] Hero header with cuisine emoji + gradient overlay
- [x] Restaurant info: name, rating, cuisines, delivery time, price for two, total ratings
- [x] Pure Veg badge for vegetarian restaurants
- [x] Veg-only toggle (filters menu items)
- [x] Categorized menu sections with item counts
- [x] Menu item cards with:
  - Veg/non-veg indicator (green/red dot)
  - ★ Bestseller and Must Try badges
  - Price, description, image placeholder
  - ADD button
- [x] Customization bottom sheet (checkboxes, required tags, price add-ons)
- [x] Add-to-cart with snackbar confirmation
- [x] Sticky cart bar at bottom (item count + total + "View Cart")

### 2.6 Cart Screen ✅

- [x] Empty cart state with emoji + browse button
- [x] Cart item cards with veg/non-veg badges
- [x] Quantity controls (+/−) with remove on zero
- [x] Selected customizations display
- [x] Special instructions text field
- [x] Delivery instructions selector (Leave at door / Call on arrival / No contact)
- [x] Bill summary: Item Total, Delivery Fee (FREE above ₹500), Platform Fee, GST (5%), Discount
- [x] Grand Total
- [x] Checkout button (→ Phase 3 payment)

### 2.7 Router Updates ✅

- [x] `/restaurant/:id` route (standalone, no bottom nav)
- [x] `/cart` route (standalone, no bottom nav)
- [x] `/search` inside ShellRoute with bottom nav
- [x] MainShell now extends ConsumerWidget

---

## Phase 3 — Ordering & Payments (NOT STARTED)

### 3.1 Payment Integration

- [ ] Razorpay SDK integration
- [ ] UPI, Cards, Wallets, COD support
- [ ] Payment verification via Go backend
- [ ] Order confirmation screen

### 3.2 Order Tracking

- [ ] Real-time order status updates (placed → confirmed → preparing → ready → picked_up → delivered)
- [ ] Appwrite Realtime subscription for status changes
- [ ] Order timeline UI
- [ ] Delivery partner info card

### 3.3 Order History

- [ ] Recent orders list
- [ ] Order detail screen
- [ ] Reorder functionality
- [ ] Review & rating flow

---

## File Tree (Current)

```
H:\chizze\
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── auth/
│   │   │   └── auth_provider.dart             # Auth state management
│   │   ├── constants/
│   │   │   └── appwrite_constants.dart        # [NEW] DB/collection/bucket IDs
│   │   ├── router/
│   │   │   └── app_router.dart                # [UPDATED] + restaurant/:id, /cart, /search routes
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
│   │   ├── cart/                               # [NEW] Phase 2
│   │   │   ├── providers/
│   │   │   │   └── cart_provider.dart          # Cart state + notifier
│   │   │   └── screens/
│   │   │       └── cart_screen.dart            # Cart & checkout screen
│   │   ├── home/
│   │   │   ├── models/
│   │   │   │   └── restaurant.dart            # [NEW] Restaurant model
│   │   │   └── screens/
│   │   │       └── home_screen.dart           # [UPDATED] Uses Restaurant model
│   │   ├── restaurant/                         # [NEW] Phase 2
│   │   │   ├── models/
│   │   │   │   └── menu_item.dart             # MenuItem + MenuCategory models
│   │   │   └── screens/
│   │   │       └── restaurant_detail_screen.dart  # Full restaurant + menu screen
│   │   ├── search/                             # [NEW] Phase 2
│   │   │   └── screens/
│   │   │       └── search_screen.dart         # Search + filters screen
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
└── status.md                                   # THIS FILE
```

---

## Known Issues & Tech Debt

| ID | Severity | File | Issue | Status |
|---|---|---|---|---|
| TD-001 | LOW | `appwrite_client.dart` | Legacy file, superseded by `core/services/appwrite_service.dart` | To remove |
| TD-002 | LOW | `config/environment.dart` | Legacy config, not used by new architecture | To remove |
| TD-003 | LOW | `test/widget_test.dart` | References old `MyApp` class, needs update for `ChizzeApp` | To fix |
| TD-004 | LOW | `test/appwrite_connection_test.dart` | Uses `print()` and deprecated APIs | To refactor |
| TD-005 | MEDIUM | Login screen | Google/Apple OAuth wired but need Appwrite OAuth config | Phase 3+ |
| TD-006 | LOW | All screens | Uses mock data — needs Appwrite collections created | When backend ready |
| TD-007 | LOW | Fonts | Using google_fonts package (network) — font files not bundled | OK for dev |
| TD-008 | LOW | Restaurant detail | Image placeholders use emoji — need real images | When storage ready |

---

## Go Backend (NOT STARTED)

```yaml
status: NOT STARTED
go_version: 1.25.7 (confirmed installed)
planned_framework: Gin
planned_features:
  - REST API (70+ endpoints)
  - WebSocket for real-time order tracking
  - Razorpay payment verification
  - Redis caching
  - Appwrite SDK integration
```

---

## Appwrite Cloud Collections (NOT CREATED)

```yaml
status: NOT CREATED
planned_collections:
  - users (extended profile)
  - restaurants
  - menu_categories
  - menu_items
  - orders
  - order_items
  - addresses
  - reviews
  - coupons
  - delivery_partners
  - notifications
  - favorites
```

---

## Changelog

| Date | Action | Details |
|---|---|---|
| 2026-02-19 21:55 | Phase 2 Complete | Created 7 new files, updated 2 files, 0 analysis errors |
| 2026-02-19 21:52 | Search screen created | Filter chips, sort bottom sheet, filtered results |
| 2026-02-19 21:52 | Restaurant detail created | Hero header, categorized menu, customization sheet, cart bar |
| 2026-02-19 21:52 | Cart screen created | Items, quantity controls, bill summary, checkout |
| 2026-02-19 21:51 | Data models created | Restaurant, MenuItem, MenuCategory, CartItem, CartState models |
| 2026-02-19 21:51 | Appwrite constants created | Database/collection/bucket ID constants |
| 2026-02-19 21:49 | status.md created | Project tracking file for LLM continuity |
| 2026-02-19 21:49 | Phase 1 Complete | 19 files, 133 deps, 0 errors |
| 2026-02-19 21:30 | Dependencies fixed | Resolved intl version conflict |
| 2026-02-19 21:25 | Phase 1 started | Theme, widgets, auth, router, screens, main.dart |
| 2026-02-19 ~20:00 | Documents finalized | design.md, implementation_plan.md, production_architecture.md |
