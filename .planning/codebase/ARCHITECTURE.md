# Architecture

**Analysis Date:** 2026-04-03

## Pattern Overview

**Overall:** Multi-surface layered architecture (Flutter mobile app + Next.js admin app + Gin API) over Appwrite-backed persistence, with Redis-backed operational state and worker processes.

**Key Characteristics:**
- Route-first API composition in `backend/cmd/server/main.go` with role-scoped route groups (`/auth`, `/orders`, `/partner`, `/delivery`, `/admin`).
- Thin HTTP handlers in `backend/internal/handlers/*.go` delegating business logic to services in `backend/internal/services/*.go` and persistence to `backend/pkg/appwrite/client.go` via `backend/internal/services/appwrite_service.go`.
- Dual realtime model: direct WebSocket push for mobile clients (`/api/v1/ws`) and polling for admin live pages (`admin/lib/sse.ts`).

## Layers

**Client Applications Layer:**
- Purpose: End-user and operator UI surfaces.
- Location: `lib/` (Flutter mobile), `admin/app/` (Next.js admin routes), `admin/components/`.
- Contains: Screens/pages, UI components, routing state, client-side auth/session logic.
- Depends on: `lib/core/services/api_client.dart`, `lib/core/services/websocket_service.dart`, `admin/lib/api.ts`, `admin/lib/sse.ts`.
- Used by: Customers, restaurant owners, delivery partners, admins.

**Client Data Access Layer:**
- Purpose: Wrap transport concerns and expose typed API helpers.
- Location: `admin/lib/api.ts`, `admin/lib/sse.ts`, `lib/core/services/api_client.dart`.
- Contains: Axios instance, auth token injection, envelope handling, polling hooks.
- Depends on: Backend REST and WebSocket endpoints.
- Used by: Admin pages in `admin/app/(admin)/**`, Flutter providers in `lib/features/**/providers`.

**HTTP API Layer (Gin):**
- Purpose: Endpoint registration, middleware chain, role segregation.
- Location: `backend/cmd/server/main.go`.
- Contains: Route map, middleware stack, health checks, worker lifecycle hooks.
- Depends on: Handlers, middleware, services.
- Used by: Mobile app, admin app, background workers.

**Handler Layer:**
- Purpose: Request validation, auth/ownership checks, response shaping.
- Location: `backend/internal/handlers/*.go`.
- Contains: Role-specific endpoint handlers (`order_handler.go`, `admin_handler.go`, `delivery_handler.go`, etc.).
- Depends on: `backend/internal/services/*`, `backend/pkg/utils/response.go`, middleware context.
- Used by: Router in `backend/cmd/server/main.go`.

**Domain Service Layer:**
- Purpose: Business rules and shared operational logic.
- Location: `backend/internal/services/*.go`.
- Contains: Fee calculation and status transition checks (`order_service.go`), geospatial calculations (`geo_service.go`), cache access (`cache_service.go`), Appwrite facade (`appwrite_service.go`).
- Depends on: Models and Appwrite/Redis adapters.
- Used by: Handlers and workers.

**Persistence/Integration Adapter Layer:**
- Purpose: Typed access to Appwrite documents and external infrastructure.
- Location: `backend/pkg/appwrite/*.go`, `backend/internal/services/appwrite_service.go`, `backend/pkg/redis/*`.
- Contains: Query builders, CRUD wrappers, connection pooling, retry/circuit-breaker behavior.
- Depends on: Appwrite and Redis endpoints.
- Used by: Services, handlers, workers.

**Realtime and Worker Layer:**
- Purpose: Push events, delivery matching, timeout processing, notification dispatch.
- Location: `backend/internal/websocket/*.go`, `backend/internal/workers/*.go`.
- Contains: Hub/client presence tracking, typed event broadcasting, scheduled background loops.
- Depends on: Appwrite/Redis/services.
- Used by: Mobile websocket consumers and admin live monitoring endpoints.

## Data Flow

**Admin Order Detail Page Pipeline (`/orders/[id]`):**

1. Admin navigation starts from `admin/components/layout/sidebar.tsx` (`/orders`) and order row links in `admin/app/(admin)/orders/page.tsx` (`Link href={`/orders/${row.original.$id}`}`).
2. Route resolves to `admin/app/(admin)/orders/[id]/page.tsx`, where `useParams<{ id: string }>()` supplies the order id.
3. React Query in `admin/app/(admin)/orders/[id]/page.tsx` calls `ordersApi.get(id)` from `admin/lib/api.ts`.
4. `admin/lib/api.ts` executes `GET("/admin/orders/${id}")` via Axios, attaching `Authorization: Bearer <token>` from `localStorage`.
5. Backend router in `backend/cmd/server/main.go` maps `GET /api/v1/admin/orders/:id` to `adminHandler.GetOrder` under middleware `Auth(...)` + `RequireRole("admin", "super_admin")`.
6. `backend/internal/handlers/admin_handler.go` (`GetOrder`) calls `h.appwrite.GetOrder(c.Param("id"))` and returns `utils.Success(c, doc)` without enrichment.
7. `backend/internal/services/appwrite_service.go` (`GetOrder`) delegates to `client.GetDocument(models.CollectionOrders, id)`.
8. `backend/pkg/appwrite/client.go` fetches Appwrite order document from `orders` collection and returns raw map data.
9. Frontend transforms and renders in `admin/app/(admin)/orders/[id]/page.tsx`:
- `parseOrderItems(order.items)` from `admin/lib/utils.ts` parses the serialized `items` JSON string.
- `formatDateTime`, `timeAgo`, `formatCurrency` format timestamps and amounts.
- Timeline/UI derives presentation state from `order.status` and timestamp fields.

**Field-Level Path for Order Detail Data (special emphasis):**

1. **Location fields (`delivery_address`, `delivery_latitude`, `delivery_longitude`, `delivery_landmark`)**
- Loaded at creation: `backend/internal/handlers/order_handler.go` (`PlaceOrder`) reads `addresses` via `h.appwrite.GetAddress(req.DeliveryAddressID)` and writes snapshot fields into `orderData` before `CreateOrder`.
- Transported for admin detail: raw through `adminHandler.GetOrder` (`backend/internal/handlers/admin_handler.go`) and `ordersApi.get` (`admin/lib/api.ts`).
- Transformed in admin detail page: no dedicated location transform exists in `admin/app/(admin)/orders/[id]/page.tsx`.
- Rendered in admin detail page: currently not rendered in `admin/app/(admin)/orders/[id]/page.tsx` (despite `MapPin` import).

2. **Customer phone/name (`customer_name`, `customer_phone`)**
- Persisted in order document at creation: not written into `orderData` in `backend/internal/handlers/order_handler.go`.
- Enriched in non-admin order APIs: `backend/internal/handlers/order_handler.go` (`GetOrder` and `ListOrders`) fetches from `users` and injects `customer_name` (and `customer_phone` in list path).
- Enriched in admin order detail API: no enrichment in `backend/internal/handlers/admin_handler.go` (`GetOrder`).
- Rendered in admin detail page: no customer name/phone rendering in `admin/app/(admin)/orders/[id]/page.tsx` (customer card uses `customer_id` only).

3. **Full detail payload (comprehensive customer + destination context)**
- Available data source: Appwrite `orders` doc plus optional joins to `users` and `addresses` collections through `GetUser`/`GetAddress` in `backend/internal/services/appwrite_service.go`.
- Admin detail flow behavior: currently returns only raw `orders` document in `backend/internal/handlers/admin_handler.go`.
- UI usage: admin detail page consumes raw `Order` type from `admin/types/index.ts`; fields outside that type are not modeled for render.

**Admin Order Actions Pipeline (Cancel/Reassign):**

1. `admin/app/(admin)/orders/[id]/page.tsx` mutation calls `ordersApi.cancel` or `ordersApi.reassign` (`admin/lib/api.ts`).
2. Routes map in `backend/cmd/server/main.go` to `adminHandler.CancelOrder` and `adminHandler.ReassignOrder`.
3. `backend/internal/handlers/admin_handler.go` updates order document directly via `h.appwrite.UpdateOrder`.
4. Response envelope returns updated order, and React Query invalidates `queryKey: ["order-detail", id]`.

**Order Creation to Admin Visibility Flow:**

1. Customer places order via `POST /api/v1/orders` handled by `backend/internal/handlers/order_handler.go`.
2. Handler validates menu/address ownership, computes fees through `backend/internal/services/order_service.go`, and writes denormalized order snapshot fields.
3. Order document is stored in Appwrite `orders` collection (`models.CollectionOrders` in `backend/internal/models/common.go`).
4. Admin list/detail pages consume the same stored document through `/api/v1/admin/orders` and `/api/v1/admin/orders/:id`.

**Realtime Flow:**

1. Backend websocket endpoint `/api/v1/ws` in `backend/cmd/server/main.go` upgrades connections via `backend/internal/websocket/client.go`.
2. Events are typed in `backend/internal/websocket/events.go` and dispatched through `EventBroadcaster` into `Hub` (`backend/internal/websocket/hub.go`).
3. Flutter maps identical event strings in `lib/core/services/websocket_service.dart` (`WsEventType.fromString`).
4. Admin uses polling hooks in `admin/lib/sse.ts` against `/admin/live/*` routes instead of websocket subscription.

**State Management:**
- Flutter: Riverpod providers + router redirect orchestration in `lib/core/router/app_router.dart`.
- Admin: React Query cache + page-local component state in `admin/app/(admin)/**/page.tsx`.
- Backend: Stateless request handlers; Redis-backed ephemeral state for rate limit, delivery matching, and worker coordination in `backend/cmd/server/main.go` and `backend/internal/workers/*.go`.

## Key Abstractions

**Route-Orchestrated Role Boundaries:**
- Purpose: Keep role permissions centralized at route-group level.
- Examples: `backend/cmd/server/main.go` admin/partner/delivery groups with `RequireRole(...)`.
- Pattern: API segmentation by role before handler execution.

**Appwrite Service Facade:**
- Purpose: Provide collection-specific methods and isolate raw Appwrite client usage.
- Examples: `backend/internal/services/appwrite_service.go`, `backend/pkg/appwrite/client.go`.
- Pattern: Service facade over generic CRUD client.

**Response Envelope Contract:**
- Purpose: Stable response shape for frontend consumers.
- Examples: `backend/pkg/utils/response.go`, `admin/lib/api.ts` (`unwrap`), `admin/lib/sse.ts` (`unwrap`).
- Pattern: `success/data/error/meta` envelope across endpoints.

**Order Snapshot Denormalization:**
- Purpose: Store operationally useful order context at creation time.
- Examples: `backend/internal/handlers/order_handler.go` (`orderData` with restaurant and delivery snapshot fields).
- Pattern: Denormalized write-time snapshot rather than read-time joins for every request.

## Entry Points

**Flutter App Entry Point:**
- Location: `lib/main.dart`
- Triggers: Mobile app launch.
- Responsibilities: Initialize Firebase/Sentry/Mapbox/cache, boot router, start websocket auto-connect.

**Admin Web Entry Points:**
- Location: `admin/app/layout.tsx`, `admin/app/page.tsx`, `admin/app/(admin)/layout.tsx`
- Triggers: Next.js route rendering.
- Responsibilities: Query client/provider setup, root redirect to `/dashboard`, auth guard and admin shell composition.

**Backend Server Entry Point:**
- Location: `backend/cmd/server/main.go`
- Triggers: Process start (`go run ./cmd/server`).
- Responsibilities: Config load, middleware stack, route registration, websocket hub start, worker startup, graceful shutdown.

**Order Detail UI Entry Point:**
- Location: `admin/app/(admin)/orders/[id]/page.tsx`
- Triggers: Route navigation to `/orders/:id`.
- Responsibilities: Fetch order details, parse/format fields, render timeline/cards, execute cancel/reassign actions.

## Error Handling

**Strategy:** Layered error handling with standardized backend envelope and frontend interceptor-driven auth fallback.

**Patterns:**
- Backend handler failures return `utils.BadRequest/NotFound/InternalError` in `backend/pkg/utils/response.go`.
- Admin API client globally handles 401 in `admin/lib/api.ts` (token clear + redirect to `/login`).
- Admin page-level mutations surface operation status through `toast` and query invalidation in `admin/app/(admin)/orders/[id]/page.tsx`.
- Backend startup and runtime uses structured log statements and graceful shutdown in `backend/cmd/server/main.go`.

## Cross-Cutting Concerns

**Logging:** `backend/internal/middleware/logger` via `middleware.Logger()` and handler-level log lines in `backend/cmd/server/main.go`.

**Validation:** Request body binding in handlers (`ShouldBindJSON`) and domain transition checks in `backend/internal/services/order_service.go`.

**Authentication:**
- Backend middleware: `middleware.Auth(cfg, redisClient)` + `middleware.RequireRole(...)` in `backend/cmd/server/main.go`.
- Admin frontend: local token/session checks in `admin/lib/auth.ts` and `admin/app/(admin)/layout.tsx`.

**Observability and Runtime Safety:** OpenTelemetry init in `backend/cmd/server/main.go`, Sentry in `lib/main.dart`, health/readiness probes in backend routes.

---

*Architecture analysis: 2026-04-03*
