# Copilot Instructions for Chizze

## Big picture (use this mental model first)
- This repo is a **Flutter mobile app** (`lib/`) + **Go API server** (`backend/`) + **Appwrite Cloud** (managed auth/db/storage/realtime).
- Runtime flow: Flutter authenticates with Appwrite, then exchanges Appwrite JWT for backend JWT via `POST /api/v1/auth/exchange`.
- Business logic lives in Go (`backend/internal/services`, `backend/internal/handlers`), while Appwrite acts as data/auth platform.
- Real-time updates are dual-path: Appwrite Realtime + Go WebSocket (`/api/v1/ws`) for order/delivery events.

## Where to change code
- Flutter app code: `lib/core` (shared infra), `lib/features/*` (role-specific/user-facing features).
- Go API entrypoint + route map: `backend/cmd/server/main.go`.
- Go internals: `backend/internal/{handlers,services,middleware,workers,websocket}`.
- Shared contracts to keep in sync:
  - WebSocket events: `backend/internal/websocket/events.go` ↔ `lib/core/services/websocket_service.dart` (`WsEventType`).
  - API response shape (`success/data/error/meta`): `lib/core/models/api_response.dart`.
  - Order statuses/transitions: `backend/internal/models/order.go` and Flutter order models/providers.

## Project conventions (important)
- State management in Flutter uses `StateNotifierProvider` + immutable `State` classes with `copyWith` (see `lib/features/home/providers/restaurant_provider.dart`).
- Routing/role guards are centralized in `lib/core/router/app_router.dart`; do not duplicate auth/role redirect logic in screens.
- Role strings are exact: `customer`, `restaurant_owner`, `delivery_partner`; keep backend middleware and Flutter checks aligned.
- API endpoints are centralized in `lib/core/services/api_config.dart`; update this when backend routes change.
- Auth persistence uses secure storage + backend token restore (`lib/core/auth/auth_provider.dart`); avoid bypassing this flow.

## Dev workflows (preferred commands)
- Full stack dev backend (local): `make dev` (runs `go run ./cmd/server` in `backend/`).
- Docker dev backend+redis: `make dev-docker`.
- Flutter deps/test/lint: `make flutter-deps`, `make flutter-test`, `make flutter-lint`.
- Go deps/test/lint: `make go-deps`, `make go-test`, `make go-lint`, `make go-vuln`.
- Combined checks: `make test`, `make lint`.

## Environment and config
- Flutter API/Appwrite endpoints are controlled with `--dart-define`; see `lib/config/environment.dart`.
- Backend env keys are in `backend/.env.example` (Appwrite, Redis, JWT, Razorpay).
- Production deploy assets are in `deploy/` and `deploy/README.md`; backend container config is `backend/Dockerfile`.

## Agent guardrails for this repo
- Prefer editing source under `lib/` and `backend/`; avoid touching generated/third-party content in `build/`, `backend/.gopath/`, and `backend/.gomod/`.
- Validate cross-layer changes end-to-end: if you add/rename a backend field/event/route, update corresponding Flutter model/provider/service.
- Keep response contracts backward-compatible where possible; many providers parse dynamic maps from API payloads.
- For new authenticated backend routes, apply existing middleware pattern: `Auth(...)` then `RequireRole(...)` when role-scoped.
- Keep Sentry noise controls intact unless intentionally changing telemetry (`lib/main.dart`, `lib/core/services/api_client.dart`).
