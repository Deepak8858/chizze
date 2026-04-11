# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Chizze is a food delivery platform with three surfaces:
- **Flutter mobile app** (`lib/`) — customers, restaurant owners, delivery partners
- **Go API server** (`backend/`) — business logic, Gin framework, Appwrite + Redis
- **Next.js admin web app** (`admin/`) — internal ops dashboard

Auth flow: client authenticates with Appwrite → exchanges Appwrite JWT for backend JWT via `POST /api/v1/auth/exchange`. All protected routes use `middleware.Auth(cfg, redisClient)` + `middleware.RequireRole(...)`.

## Commands

```bash
# Backend
make dev                  # Start Go backend locally (go run ./cmd/server)
make dev-docker           # Start via Docker Compose
make go-build             # Build binary to backend/bin/chizze-api
make go-test              # Run tests with race detector + coverage
make go-lint              # Run golangci-lint
make go-vuln              # Run govulncheck
make go-deps              # go mod download && tidy

# Run a single Go test
cd backend && go test -v -run TestPlaceOrder_Success ./internal/handlers/

# Flutter
make flutter-deps         # flutter pub get
make flutter-test         # flutter test --coverage
make flutter-lint         # flutter analyze --no-fatal-infos
make android-apk          # Release APK (split per ABI)
make android-aab          # Release App Bundle

# Admin (from admin/ directory)
npm run dev
npm run build
npm run lint

# Combined
make test                 # go-test + flutter-test
make lint                 # go-lint + flutter-lint
```

Flutter release builds require `--dart-define` flags; see Makefile for all `DART_DEFINE_*` variables. Environment config lives in `lib/config/environment.dart`.

## Architecture

### Backend

Entry point and complete route map: `backend/cmd/server/main.go`. Routes are organized into role-scoped groups:
- `/api/v1/auth` — public, stricter rate limit
- `/api/v1/restaurants`, `/api/v1/coupons` — public
- `/api/v1/*` (authenticated group) — any authenticated user
- `/api/v1/partner/*` — `restaurant_owner` only
- `/api/v1/delivery/*` — `delivery_partner` only
- `/api/v1/admin/*` — `admin` or `super_admin` only

Layers:
- **Handlers** (`backend/internal/handlers/*.go`) — request validation, auth/ownership checks, response shaping
- **Services** (`backend/internal/services/*.go`) — business rules: fee calculation (`order_service.go`), geospatial (`geo_service.go`), cache (`cache_service.go`), Appwrite facade (`appwrite_service.go`)
- **Appwrite adapter** (`backend/pkg/appwrite/client.go`) — generic CRUD with circuit breaker; `appwrite_service.go` wraps it with collection-specific methods
- **Workers** (`backend/internal/workers/*.go`) — delivery matching (8s tick), order timeout (30s tick), scheduled orders, notification dispatch
- **WebSocket** (`backend/internal/websocket/`) — Hub/client presence, typed event broadcasting

Redis is used for: rate limiting, delivery matching state (`busy_riders`, `pending_riders`), session tokens, pub/sub. On startup, stale delivery Redis keys are purged.

### Flutter

- `lib/core/` — shared infrastructure: auth, router, services, models
- `lib/features/*/` — role/user features with screens, providers, models
- State management: Riverpod `StateNotifierProvider` with immutable state + `copyWith`
- Routing and role guards: `lib/core/router/app_router.dart` — do not duplicate redirect logic in screens
- API client: `lib/core/services/api_client.dart` — returns typed `ApiResponse<T>`, throws `ApiException`
- Endpoint declarations: `lib/core/services/api_config.dart`
- Auth persistence: `lib/core/auth/auth_provider.dart` (secure storage + backend token restore)

### Admin

- `admin/app/(admin)/` — protected route pages
- `admin/lib/api.ts` — Axios instance with 401 interceptor (redirects to `/login`), domain-grouped API objects (`ordersApi`, `dashboardApi`, etc.)
- `admin/lib/sse.ts` — polling hooks for live pages (every 5s)
- `admin/types/index.ts` — TypeScript interfaces
- Admin token stored in `localStorage` as `chizze_admin_token` — known security risk (see Concerns)

## Shared Contracts (Keep In Sync)

These must stay aligned across layers when changed:

| Contract | Backend | Flutter | Admin |
|---|---|---|---|
| WS event types | `backend/internal/websocket/events.go` | `lib/core/services/websocket_service.dart` (`WsEventType`) | — |
| API response envelope | `backend/pkg/utils/response.go` | `lib/core/models/api_response.dart` | `admin/lib/api.ts` (`unwrap`) |
| Order statuses | `backend/internal/models/order.go` | `lib/features/orders/models/order.dart` | `admin/types/index.ts` |
| Role strings (exact) | `backend/internal/middleware/auth.go` | `lib/core/router/app_router.dart` | — |

Role string literals: `customer`, `restaurant_owner`, `delivery_partner`, `admin`, `super_admin`.

API envelope shape: `{"success": bool, "data": any, "error": string, "meta": {...}}`. Paginated responses use `per_page`/`totalPages` (not `limit`) — admin web has a known bug passing `limit` instead.

## Testing

**Backend** — route-level integration tests using in-memory fakes:
```bash
cd backend && go test -v -run TestName ./internal/handlers/
```
Test infrastructure: `backend/internal/testutil/test_env.go` (gin router + miniredis + fake Appwrite), `backend/internal/testutil/fake_appwrite.go`.

Pattern: `te.AuthRequest("POST", "/api/v1/orders", body, "user_id", "customer")` — always test through the full middleware/role stack.

**Flutter** — unit tests for model parsing and provider state transitions in `test/`:
```bash
flutter test test/providers/cart_provider_test.dart
```

**Admin** — no automated tests exist.

## Conventions

- **Go**: PascalCase exported symbols, snake_case JSON tags, `New*` constructors with DI from `main.go`, Swagger annotations on handlers
- **TypeScript**: PascalCase types/interfaces, camelCase functions/vars, `@/*` alias for admin root
- **Flutter**: PascalCase classes, camelCase methods, `package:chizze/` for cross-module imports
- Backend handlers follow: validate → authorize → enrich → respond using `utils.Success/Created/Paginated/BadRequest/InternalError`

## Do Not Edit

`build/`, `admin/.next/`, `admin/node_modules/`, `backend/.gopath/`, `backend/.gomod/`, `deepakupkgs@*/`

## Known Issues (from `.planning/codebase/`)

- **Admin order detail** missing customer name/phone/location — `admin_handler.go` returns raw Appwrite docs without enrichment; `admin/types/index.ts` omits those fields
- **Live orders schema mismatch** — backend returns `$id`/`delivery_latitude` etc., admin expects `order_id`/`customer_lat` etc.
- **Pagination param drift** — admin sends `limit`, backend reads `per_page`
- **Reassignment stale data** — reassigning an order doesn't update denormalized partner name/phone fields
- Full details: `.planning/codebase/CONCERNS.md`

## Reference

- Architecture deep-dive: `.planning/codebase/ARCHITECTURE.md`
- Conventions detail: `.planning/codebase/CONVENTIONS.md`
- Testing patterns: `.planning/codebase/TESTING.md`
- Integrations: `.planning/codebase/INTEGRATIONS.md`
- Production topology: `production_architecture.md`, `deploy/README.md`
- Env templates: `backend/.env.example`, `admin/.env.example`
