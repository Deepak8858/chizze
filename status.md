# Chizze — Project Status

> Last updated: 2026-03-03

## Architecture

| Layer | Stack | Location |
|-------|-------|----------|
| Mobile App | Flutter (Riverpod, Mapbox, dio, go_router) | `lib/` |
| API Server | Go (Gin, JWT, WebSocket) | `backend/` |
| Platform | Appwrite Cloud (auth, DB, storage, realtime) | managed |
| Cache/Geo | Redis (geo set `rider_locations`) | Docker sidecar |
| Hosting | DigitalOcean droplet, Nginx reverse proxy | `deploy/` |

**Runtime flow:** Flutter → Appwrite auth → JWT exchange with Go backend → role-based API access.

---

## Feature Inventory

### Complete (25 features)

| # | Feature | Flutter | Backend |
|---|---------|---------|---------|
| 1 | Phone OTP login | `login_screen.dart` | Appwrite phone auth |
| 2 | Email/password login | `login_screen.dart` | Appwrite email auth |
| 3 | Google OAuth login | `login_screen.dart` | Appwrite OAuth |
| 4 | Apple OAuth login | `login_screen.dart` | Appwrite OAuth |
| 5 | Role-based onboarding | `onboarding_screen.dart` | `POST /auth/onboard` |
| 6 | JWT exchange (Appwrite → backend) | `auth_provider.dart` | `POST /auth/exchange` |
| 7 | Restaurant discovery & search | `home_screen.dart`, `search_screen.dart` | `GET /restaurants` |
| 8 | Restaurant detail & menu | `restaurant_detail_screen.dart` | `GET /restaurants/:id` |
| 9 | Cart management | `cart_provider.dart`, `cart_screen.dart` | client-side |
| 10 | Order placement + Razorpay | `checkout_screen.dart` | `POST /orders` |
| 11 | Order tracking (real-time) | `order_tracking_screen.dart` | WebSocket + Realtime |
| 12 | Order history | `orders_screen.dart` | `GET /orders` |
| 13 | Scheduled orders | `scheduled_orders_provider.dart` | `GET/POST /orders/scheduled` |
| 14 | Coupons & promo codes | `coupons_provider.dart` | `GET/POST /coupons` |
| 15 | Favorites / wishlists | `favorites_provider.dart` | `GET/POST /favorites` |
| 16 | Saved addresses (CRUD) | `address_provider.dart` | Appwrite DB |
| 17 | User profile (name, avatar, prefs) | `user_profile_provider.dart` | `GET/PUT /users/me` |
| 18 | Notifications (push + in-app) | `notifications_provider.dart` | `GET /notifications` + FCM |
| 19 | Chizze Gold subscription | `gold_provider.dart` | `GET/POST /gold` |
| 20 | Referral system | `referral_provider.dart` | `GET/POST /referrals` |
| 21 | Restaurant partner dashboard | `partner_provider.dart` | `GET /partner/dashboard` |
| 22 | Menu management (CRUD) | `menu_management_provider.dart` | `GET/POST/PUT /partner/menu` |
| 23 | Partner analytics | `analytics_provider.dart` | `GET /partner/analytics` |
| 24 | Delivery partner dashboard | `delivery_provider.dart` | `GET /delivery/dashboard` |
| 25 | Delivery earnings tracking | `earnings_provider.dart` | `GET /delivery/earnings` |

### Partial (1 feature)

| Feature | Status | Details |
|---------|--------|---------|
| Delivery profile sub-screens | UI stub | Vehicle/bank/documents screens show "coming soon" in `delivery_profile_screen.dart` |

### Stubs / Planned (2 features)

| Feature | Status | Details |
|---------|--------|---------|
| In-app support chat | Coming soon | `order_tracking_screen.dart` L197 — "Support coming soon" snackbar |
| In-app messaging | Coming soon | `order_tracking_screen.dart` L545 — "Chat coming soon" snackbar |

---

## Recent Changes (This Session)

### Bug Fixes

1. **Customer profile not showing name/avatar**
   - **Root cause:** `userProfileProvider` fetched before auth JWT was ready (race condition)
   - **Fix:** Provider now watches `authProvider.isAuthenticated` — only fetches when authorized
   - Files: `user_profile_provider.dart`

2. **Avatar never displayed even when URL exists**
   - **Root cause:** `_buildAvatar()` always showed initials circle, never used `avatarUrl`
   - **Fix:** Added `CachedNetworkImage` with gradient fallback when URL is present
   - Files: `profile_screen.dart`

3. **Home screen greeting shows "Foodie" for phone users**
   - **Root cause:** Used `authState.user?.name` (Appwrite account name, empty for phone signups)
   - **Fix:** Now prefers `profile.name` from backend (set during onboarding)
   - Files: `home_screen.dart`

4. **Profile data stale after onboarding**
   - **Root cause:** No `userProfileProvider` invalidation after `completeOnboarding()`
   - **Fix:** Added `ref.invalidate(userProfileProvider)` post-onboarding
   - Files: `onboarding_screen.dart`

### Feature Enablements

5. **Google OAuth login — enabled**
   - Was: "Coming soon" snackbar
   - Now: Calls `loginWithOAuth(OAuthProvider.google)` via Appwrite SDK
   - Files: `login_screen.dart`

6. **Apple OAuth login — enabled**
   - Was: "Coming soon" snackbar
   - Now: Calls `loginWithOAuth(OAuthProvider.apple)` via Appwrite SDK
   - Files: `login_screen.dart`

### Code Quality

7. **Silent catch block logging** — Added `debugPrint` to 13 previously silent `catch (_) {}` blocks across 9 files:
   - `partner_provider.dart` — JSON parse error logging
   - `menu_management_provider.dart` — API error logging (2 catches)
   - `analytics_provider.dart` — API error logging
   - `address_provider.dart` — fetch error logging
   - `notifications_provider.dart` — realtime + API error logging (2 catches)
   - `rider_location_provider.dart` — realtime error logging
   - `orders_provider.dart` — realtime + fetchById error logging (2 catches)
   - `auth_provider.dart` — secure storage error logging (2 catches)
   - `location_service.dart` — position error logging

---

## Code Health

| Metric | Value |
|--------|-------|
| Mock data / hardcoded values | 0 |
| TODO / FIXME comments | 0 |
| Dead / unreachable routes | 0 |
| Silent catch blocks (no logging) | ~7 remaining (all low-risk: JSON parse fallbacks, `firstWhere` guards) |
| Backend handler files | 15 — all complete |
| Background workers | 4 — all complete |
| API endpoint alignment | 100% — all Flutter constants map to backend routes |

---

## Remaining Work

| Priority | Item | Effort | Notes |
|----------|------|--------|-------|
| Medium | Delivery profile sub-screens | 2-3 days | Vehicle, bank, documents CRUD screens |
| Medium | In-app support/help | 3-5 days | Needs support ticket backend + chat UI |
| Low | In-app messaging (customer ↔ rider) | 5-7 days | Needs message backend, WebSocket channels, chat UI |
| Low | Remaining 7 low-risk silent catches | < 1 hr | JSON parse, firstWhere guards — minimal impact |

---

## Deployment

- **Backend:** Docker Compose on DigitalOcean (`deploy/docker-compose.prod.yml`)
- **Deploy command:** `python tools/deploy_backend.py`
- **APK build:**
  ```bash
  flutter build apk --release \
    --dart-define=ENV=production \
    --dart-define=API_URL=https://api.devdeepak.me/api/v1 \
    --dart-define=APPWRITE_PROJECT_ID=6993347c0006ead7404d \
    --dart-define=APPWRITE_ENDPOINT=https://sgp.cloud.appwrite.io/v1
  ```
