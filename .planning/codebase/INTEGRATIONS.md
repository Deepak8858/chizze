# External Integrations

**Analysis Date:** 2026-04-03

## APIs & External Services

**Core Data/Auth Platform (Appwrite):**
- Appwrite Cloud - Identity, document DB, storage, and realtime substrate for app data.
  - SDK/Client: Flutter SDK in `lib/core/services/appwrite_service.dart`, admin SDK in `admin/lib/appwrite.ts`, backend REST wrapper in `backend/pkg/appwrite/client.go`.
  - Auth: Backend uses `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, `APPWRITE_API_KEY`, `APPWRITE_DATABASE_ID` in `backend/internal/config/config.go`.

**Payments:**
- Razorpay Orders API - Creates payment orders and verifies payment signatures.
  - SDK/Client: Direct HTTPS client in `backend/internal/services/payment_service.go` (`https://api.razorpay.com/v1/orders`).
  - Auth: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` from `backend/internal/config/config.go`.

**Maps & Routing:**
- Mapbox GL + Directions API - Admin live map and mobile route polylines.
  - SDK/Client: `react-map-gl` / `mapbox-gl` in `admin/app/(admin)/live-map/page.tsx`, `mapbox_maps_flutter` in `lib/shared/widgets/delivery_map.dart`.
  - Auth: `NEXT_PUBLIC_MAPBOX_TOKEN` in admin source (`admin/app/(admin)/live-map/page.tsx`), `MAPBOX_ACCESS_TOKEN` in mobile (`lib/core/services/map_config.dart`).

**Push Notifications:**
- Firebase Cloud Messaging - Mobile push transport and backend rider wake-up notifications.
  - SDK/Client: Flutter FCM in `lib/core/services/push_notification_service.dart`, backend FCM sender in `backend/pkg/fcm/fcm.go`.
  - Auth: `FCM_SERVER_KEY` in `backend/internal/config/config.go`.

**Observability:**
- Sentry (Flutter) - Runtime error/perf telemetry from client app.
  - SDK/Client: `sentry_flutter` in `lib/main.dart`.
  - Auth: `SENTRY_DSN` via Dart define in `lib/main.dart`.
- OpenTelemetry (backend) - Trace export to OTLP collector or stdout fallback.
  - SDK/Client: `otelgin`, OTLP exporter in `backend/internal/middleware/tracing.go`.
  - Auth/config: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_INSECURE`, `GIN_MODE`.

## Admin Order Detail Contract (Special Focus)

**Target URL:**
- `https://admin.devdeepak.me/orders/69cf5ce4567de8511940` resolves to route `admin/app/(admin)/orders/[id]/page.tsx`.

**Current fetch path:**
1. Page reads route param `id` in `admin/app/(admin)/orders/[id]/page.tsx`.
2. Page calls `ordersApi.get(id)` from `admin/lib/api.ts`.
3. Request goes to `${NEXT_PUBLIC_API_URL}/admin/orders/:id` (fallback base `https://api.devdeepak.me/api/v1` in `admin/lib/api.ts`).
4. Backend route `/api/v1/admin/orders/:id` is wired in `backend/cmd/server/main.go`.
5. `AdminHandler.GetOrder` returns raw `orders` document from `h.appwrite.GetOrder(c.Param("id"))` in `backend/internal/handlers/admin_handler.go`.

**Where fields should come from:**
- Customer name:
  - Source of truth: `users` collection (`name`) by `orders.customer_id` via `AppwriteService.GetUser` (`backend/internal/services/appwrite_service.go`).
  - Current state: Admin order endpoint does not enrich this field. Enrichment exists only in non-admin `OrderHandler.GetOrder`/`ListOrders` in `backend/internal/handlers/order_handler.go`.
- Customer phone:
  - Source of truth: `users` collection (`phone`) by `orders.customer_id`.
  - Current state: Not enriched in admin `/admin/orders/:id` response; only non-admin list path attaches `customer_phone`.
- Location (customer delivery location):
  - Primary source: Order-level snapshot persisted at placement (`delivery_address`, `delivery_landmark`, `delivery_latitude`, `delivery_longitude`) in `backend/internal/handlers/order_handler.go`.
  - Secondary source: `addresses` collection by `delivery_address_id` (schema in `backend/internal/models/user.go`) if snapshots are missing.
- Full order details:
  - Source: `orders` document fields (`items`, totals, fees, payment fields, status timeline timestamps, instructions) created in `backend/internal/handlers/order_handler.go`.
  - Admin parsing path: `items` JSON string is parsed by `parseOrderItems` in `admin/lib/utils.ts`.

**Observed contract gap:**
- `admin/app/(admin)/orders/[id]/page.tsx` currently renders customer ID and delivery type but not explicit customer name/phone/location sections, despite backend storing enough address snapshots.
- `admin/types/index.ts` `LiveOrder` expects `customer_name`, `customer_lat`, `customer_lng`, `restaurant_lat`, `restaurant_lng`, but `AdminHandler.LiveOrders` in `backend/internal/handlers/admin_handler.go` currently returns raw order docs; field-name transformation/enrichment is not present.

## Data Storage

**Databases:**
- Appwrite Document Database (`chizze_db`) for all primary entities.
  - Connection: `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, `APPWRITE_API_KEY`, `APPWRITE_DATABASE_ID` in `backend/internal/config/config.go`.
  - Client: Backend Appwrite REST client in `backend/pkg/appwrite/client.go`.
  - Key collections declared in `backend/internal/models/common.go`: `users`, `addresses`, `restaurants`, `orders`, `menu_items`, `payments`, `notifications`, `delivery_partners`, `rider_locations`, `delivery_requests`, `payouts`, `banners`, `settings`, and others.

**File Storage:**
- Appwrite Storage buckets (images and content assets).
  - Backend upload API: `AdminHandler.UploadBannerImage` in `backend/internal/handlers/admin_handler.go` and multipart uploader in `backend/pkg/appwrite/storage.go`.
  - Mobile bucket constants: `lib/core/constants/appwrite_constants.dart`.

**Caching:**
- Redis - Rate limiting, idempotency keys, rider state, notification queue, and geo matching.
  - Connection: `REDIS_URL` in `backend/internal/config/config.go`.
  - Client wrapper: `backend/pkg/redis/redis.go`.

## Authentication & Identity

**Auth Provider:**
- Hybrid Appwrite + backend JWT.
  - Implementation: App authenticates with Appwrite, then exchanges Appwrite JWT at `/api/v1/auth/exchange` in `backend/internal/handlers/auth_handler.go`; backend issues JWT signed with `JWT_SECRET`.

## Monitoring & Observability

**Error Tracking:**
- Flutter: Sentry (`lib/main.dart`).
- Backend: Not detected as using Sentry in Go server path.

**Logs:**
- Backend structured middleware logging and security headers in `backend/cmd/server/main.go` and `backend/internal/middleware/**`.
- Container/runtime logs managed through Docker logging config in `deploy/docker-compose.prod.yml`.

## CI/CD & Deployment

**Hosting:**
- API hosted behind Nginx on `api.devdeepak.me` (`deploy/chizze-api.nginx`).
- Admin hosted behind Nginx on `admin.devdeepak.me` (`deploy/chizze-admin.nginx`).
- Production stack orchestrated by Docker Compose (`deploy/docker-compose.prod.yml`).

**CI Pipeline:**
- GitHub Actions pipeline in `.github/workflows/ci.yml` runs Go + Flutter lint/test, Docker image build/push to GHCR, Android artifacts, and SSH deploy.

## Environment Configuration

**Required env vars:**
- Backend core: `PORT`, `GIN_MODE`, `ALLOWED_ORIGINS`, `REQUEST_TIMEOUT_SECONDS`, `MAX_CONNECTIONS`.
- Backend Appwrite: `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`, `APPWRITE_API_KEY`, `APPWRITE_DATABASE_ID`.
- Backend auth/cache: `JWT_SECRET`, `REDIS_URL`.
- Backend payments/push: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `FCM_SERVER_KEY`.
- Backend tracing/links: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_INSECURE`, `ANDROID_APP_PACKAGE`, `ANDROID_ASSETLINKS_SHA256_FINGERPRINTS`.
- Admin frontend: `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_MAPBOX_TOKEN`, `NEXT_PUBLIC_APPWRITE_BANNERS_BUCKET`.
- Flutter build-time defines: `ENV`, `API_URL`/`DEV_API_URL`, `APPWRITE_PROJECT_ID`, `APPWRITE_ENDPOINT`, `MAPBOX_ACCESS_TOKEN`, `SENTRY_DSN`, `RAZORPAY_KEY`.

**Secrets location:**
- Backend runtime env is loaded from environment / `.env` in `backend/internal/config/config.go` and from `deploy/.env.prod` via `deploy/docker-compose.prod.yml`.
- Admin local env is expected in `admin/.env.local` (documented in `admin/uses.md`).
- CI secrets are stored in GitHub Actions secrets (`.github/workflows/ci.yml`, `deploy/README.md`).
- `.env` and `.env.*` files exist and should be treated as sensitive sources.

## Webhooks & Callbacks

**Incoming:**
- Razorpay webhook endpoint: `POST /api/v1/payments/webhook` in `backend/internal/handlers/payment_handler.go`.
- Mobile deep link asset links endpoints: `/.well-known/assetlinks.json` and `/assetlinks.json` in `backend/cmd/server/main.go`.

**Outgoing:**
- Backend to Razorpay Orders API: `https://api.razorpay.com/v1/orders` in `backend/internal/services/payment_service.go`.
- Backend to Firebase FCM send endpoint: `https://fcm.googleapis.com/fcm/send` in `backend/pkg/fcm/fcm.go`.
- Mobile client to Mapbox Directions API: `https://api.mapbox.com/directions/v5/mapbox/driving` in `lib/core/services/route_service.dart`.

---

*Integration audit: 2026-04-03*
