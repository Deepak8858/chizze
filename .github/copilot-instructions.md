# Copilot Instructions for Chizze

## Big Picture
- This repo is a Flutter mobile app (`lib/`), Go API server (`backend/`), Next.js admin web app (`admin/`), and Appwrite Cloud for auth/data/realtime.
- Runtime auth flow: client authenticates with Appwrite, then exchanges Appwrite JWT for backend JWT via `POST /api/v1/auth/exchange`.
- Business logic lives in Go (`backend/internal/services`, `backend/internal/handlers`), while Appwrite is the managed auth/data platform.
- Real-time updates are dual-path: Appwrite Realtime plus Go WebSocket (`/api/v1/ws`) for order and delivery events.

## Code Boundaries
- Flutter app code: `lib/core` (shared infra) and `lib/features/*` (role/user features).
- Backend entrypoint and route map: `backend/cmd/server/main.go`.
- Backend internals: `backend/internal/{handlers,services,middleware,workers,websocket}`.
- Admin web app: `admin/app` (pages), `admin/lib` (API/auth), `admin/types` (contracts).
- Shared contracts to keep in sync:
  - WebSocket events: `backend/internal/websocket/events.go` <-> `lib/core/services/websocket_service.dart` (`WsEventType`).
  - API response envelope (`success/data/error/meta`): `backend/pkg/utils/response.go` <-> `lib/core/models/api_response.dart`.
  - Order statuses/transitions: `backend/internal/models/order.go` plus Flutter/admin order models.

## Build And Test
- Backend local dev: `make dev`.
- Backend via Docker: `make dev-docker`.
- Flutter deps/test/lint: `make flutter-deps`, `make flutter-test`, `make flutter-lint`.
- Go deps/test/lint/vuln: `make go-deps`, `make go-test`, `make go-lint`, `make go-vuln`.
- Android artifacts: `make android-apk`, `make android-aab`.
- Combined checks: `make test`, `make lint`.
- Admin app (from `admin/`): `npm run dev`, `npm run build`, `npm run lint`, `npm run test`.

## Conventions
- Flutter state uses `StateNotifierProvider` and immutable state with `copyWith` (example: `lib/features/home/providers/restaurant_provider.dart`).
- Routing and role guards are centralized in `lib/core/router/app_router.dart`; do not duplicate redirect logic in screens.
- Role strings must stay exact and aligned across layers: `customer`, `restaurant_owner`, `delivery_partner` (plus backend admin roles where relevant).
- Keep endpoint declarations centralized:
  - Flutter: `lib/core/services/api_config.dart`
  - Admin: `admin/lib/api.ts`
- Auth persistence in Flutter must follow `lib/core/auth/auth_provider.dart` (secure storage + backend token restore).
- For new protected backend routes, use the middleware pattern from `backend/cmd/server/main.go`: `Auth(...)` then `RequireRole(...)`.

## Environment
- Flutter env comes from `--dart-define`; see `lib/config/environment.dart`.
- Backend env template: `backend/.env.example`.
- Admin env template: `admin/.env.example`.
- Deployment and infra docs: `deploy/README.md`; backend container config: `backend/Dockerfile`.

## Guardrails
- Prefer editing source under `lib/`, `backend/`, and `admin/`.
- Do not edit generated/vendor/cache outputs: `build/`, `admin/.next/`, `admin/node_modules/`, `backend/.gopath/`, `backend/.gomod/`.
- Validate cross-layer changes end-to-end: backend field/event/route changes usually require Flutter and admin updates.
- Keep API contracts backward-compatible where possible (many consumers parse dynamic maps).
- Keep Sentry noise controls intact unless intentionally changing telemetry (`lib/main.dart`, `lib/core/services/api_client.dart`).

## Reference Docs (Link, Do Not Duplicate)
- Architecture and boundaries: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`.
- Project conventions and testing patterns: `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/TESTING.md`.
- Known risks and integration notes: `.planning/codebase/CONCERNS.md`, `.planning/codebase/INTEGRATIONS.md`.
- Production topology and deployment: `production_architecture.md`, `deploy/README.md`.
