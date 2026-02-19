# Chizze — Project Status

> **Last Updated:** 2026-02-19T21:49:00+05:30
> **Current Phase:** Phase 1 — Foundation
> **Phase Status:** ✅ COMPLETE
> **Next Action:** Phase 2 — Customer Core (awaiting user go-ahead)

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
| 2 | Customer Core | 4-6 | ⏳ NOT STARTED | 0% |
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

**Dependencies installed:**

- flutter_riverpod, riverpod_annotation (state management)
- go_router (navigation)
- dio (HTTP client)
- appwrite (BaaS SDK)
- google_fonts, flutter_svg, shimmer, cached_network_image, flutter_animate, lottie (UI)
- shared_preferences, flutter_secure_storage (local storage)
- flutter_form_builder (forms)
- geolocator, geocoding (location)
- connectivity_plus, package_info_plus, permission_handler (utilities)
- image_picker, flutter_local_notifications (media/notifications)

### 1.2 Design System ✅

- [x] `app_colors.dart` — Full dark theme palette (primary orange, backgrounds, text, semantic, glass effects)
- [x] `app_typography.dart` — Plus Jakarta Sans across all levels (h1-h3, body1-2, caption, button, price, badge)
- [x] `app_spacing.dart` — Spacing scale (4-64dp), border radius, icon sizes, avatar sizes, touch targets
- [x] `app_theme.dart` — Complete ThemeData (AppBar, Buttons, Inputs, Cards, Chips, BottomSheet, Dialog, SnackBar, Tabs, Switches, Progress)
- [x] `theme.dart` — Barrel export

### 1.3 Core Widgets ✅

- [x] `glass_card.dart` — Glassmorphism card (6% white bg, 10% white border, 20px blur, tap support)
- [x] `chizze_button.dart` — Primary gradient CTA button (loading state, outline variant, icon support) + ChipButton
- [x] `shimmer_loader.dart` — Skeleton loaders (generic + restaurant card skeleton + list skeleton)
- [x] `widgets.dart` — Barrel export

### 1.4 Architecture ✅

- [x] `appwrite_service.dart` — Riverpod providers (Client, Account, Databases, Storage, Realtime)
- [x] `auth_provider.dart` — AuthNotifier with:
  - Email login/register
  - Phone OTP (2-step: send → verify via createSession)
  - OAuth (Google/Apple via OAuthProvider enum)
  - Session persistence (checkSession on app start)
  - Logout
  - Error handling with clearError()
- [x] `app_router.dart` — GoRouter with:
  - Auth-based redirects (unauthenticated → /login, authenticated → /home)
  - ShellRoute with BottomNavigationBar (Home, Search, Orders, Profile)
  - Splash → Login → OTP → Home flow

### 1.5 Screens ✅

- [x] `splash_screen.dart` — Animated logo + brand name + tagline + loading spinner
- [x] `login_screen.dart` — Phone OTP (primary) + Google/Apple social buttons + Email/password fallback
- [x] `otp_screen.dart` — 6-digit OTP input with auto-advance, auto-submit, resend
- [x] `home_screen.dart` — Location header, search bar, horizontal category chips, promo banner, restaurant feed with glass cards

### 1.6 App Entry ✅

- [x] `main.dart` — Portrait-locked, dark system UI, ProviderScope, GoRouter, dark theme

---

## Phase 2 — Customer Core (NOT STARTED)

### 2.1 Home Screen (Enhanced)

- [ ] Location-based restaurant discovery (Appwrite queries with geolocation)
- [ ] Promo carousel (dynamic from Appwrite)
- [ ] Category browsing (dynamic)
- [ ] "Top Picks" and "Popular Near You" sections

### 2.2 Search & Filters

- [ ] Full-text search (restaurant + dish names)
- [ ] Filter by cuisine, rating, veg, delivery time
- [ ] Sort by relevance, rating, distance, cost
- [ ] Recent & trending searches

### 2.3 Restaurant Detail & Menu

- [ ] Restaurant info with hero banner
- [ ] Menu with category navigation
- [ ] Item customization bottom sheet
- [ ] Veg/non-veg indicators

### 2.4 Cart & Checkout

- [ ] Cart management (add/remove/quantity)
- [ ] Bill calculation with all fees
- [ ] Coupon validation & application
- [ ] Delivery instructions

---

## File Tree (Current)

```
H:\chizze\
├── lib/
│   ├── main.dart                              # App entry (ProviderScope + GoRouter + Dark theme)
│   ├── appwrite_client.dart                   # Legacy — superseded by core/services/
│   ├── config/
│   │   └── environment.dart                   # Legacy config
│   ├── core/
│   │   ├── auth/
│   │   │   └── auth_provider.dart             # Auth state (email, phone OTP, OAuth, logout)
│   │   ├── router/
│   │   │   └── app_router.dart                # GoRouter + bottom nav shell
│   │   ├── services/
│   │   │   └── appwrite_service.dart          # Appwrite client + Riverpod providers
│   │   └── theme/
│   │       ├── app_colors.dart                # Color palette
│   │       ├── app_spacing.dart               # Spacing tokens
│   │       ├── app_theme.dart                 # ThemeData
│   │       ├── app_typography.dart            # Typography
│   │       └── theme.dart                     # Barrel export
│   ├── features/
│   │   ├── auth/screens/
│   │   │   ├── login_screen.dart              # Phone + Email + Social login
│   │   │   └── otp_screen.dart                # 6-digit OTP verification
│   │   ├── home/screens/
│   │   │   └── home_screen.dart               # Customer home feed
│   │   └── splash/screens/
│   │       └── splash_screen.dart             # Animated splash
│   └── shared/widgets/
│       ├── chizze_button.dart                 # Primary CTA + chip buttons
│       ├── glass_card.dart                    # Glassmorphism card
│       ├── shimmer_loader.dart                # Skeleton loaders
│       └── widgets.dart                       # Barrel export
├── assets/
│   ├── images/.gitkeep
│   ├── icons/.gitkeep
│   ├── animations/.gitkeep
│   └── fonts/.gitkeep
├── test/
│   ├── widget_test.dart                       # Default (needs update)
│   └── appwrite_connection_test.dart          # Legacy test (has warnings)
├── pubspec.yaml                               # 40+ dependencies
├── design.md                                  # UI/UX design system (820 lines)
├── implementation_plan.md                     # Full implementation plan (1451 lines)
├── production_architecture.md                 # Production scaling blueprint (1300+ lines)
└── status.md                                  # THIS FILE
```

---

## Known Issues & Tech Debt

| ID | Severity | File | Issue | Status |
|---|---|---|---|---|
| TD-001 | LOW | `appwrite_client.dart` | Legacy file, superseded by `core/services/appwrite_service.dart` | To remove |
| TD-002 | LOW | `config/environment.dart` | Legacy config, not used by new architecture | To remove |
| TD-003 | LOW | `test/widget_test.dart` | References old `MyApp` class, needs update for `ChizzeApp` | To fix |
| TD-004 | LOW | `test/appwrite_connection_test.dart` | Uses `print()` and deprecated APIs | To refactor |
| TD-005 | MEDIUM | Login screen | Google/Apple OAuth buttons are wired but `TODO` — need Appwrite OAuth config | Phase 2 |
| TD-006 | LOW | Home screen | Uses hardcoded restaurant data — needs Appwrite collections | Phase 2 |
| TD-007 | LOW | Fonts | Plus Jakarta Sans font files not in assets/fonts/ — using google_fonts package as fallback | OK for now |

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
| 2026-02-19 21:49 | Phase 1 Complete | Created 19 files, 133 deps installed, 0 analysis errors |
| 2026-02-19 21:30 | Dependencies fixed | Resolved intl version conflict, removed form_builder_validators |
| 2026-02-19 21:25 | Phase 1 started | Created theme, widgets, auth, router, screens, main.dart |
| 2026-02-19 20:56 | Appwrite MCP checked | Not available — using Appwrite Cloud SDK directly |
| 2026-02-19 20:44 | Architecture updated | Switched from self-hosted Appwrite to Appwrite Cloud |
| 2026-02-19 20:41 | MariaDB discussion | Explained MariaDB is internal to Appwrite, user chose Appwrite Cloud |
| 2026-02-19 ~20:00 | Documents finalized | design.md, implementation_plan.md, production_architecture.md ready |
