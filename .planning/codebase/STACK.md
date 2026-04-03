# Technology Stack

**Analysis Date:** 2026-04-03

## Languages

**Primary:**
- Dart (SDK `^3.10.8`) - Flutter mobile app in `lib/` and app config in `pubspec.yaml`.
- Go (`1.24.0`) - API server in `backend/cmd/server/main.go` with domain logic under `backend/internal/`.
- TypeScript (`^5`) - Admin web app in `admin/app/`, `admin/lib/`, `admin/components/`, and `admin/types/`.

**Secondary:**
- JavaScript (Node.js tooling) - Scripts like `tools/verify_notification_flow.js`, `get_order.js`, and admin bootstrap scripts.
- PowerShell/Shell - Deployment and operational scripts such as `deploy-admin.ps1`, `deploy-all.ps1`, `deploy-backend.ps1`, `backend-deploy.sh`.
- YAML - CI/CD and infra configuration in `.github/workflows/ci.yml` and `deploy/docker-compose.prod.yml`.

## Runtime

**Environment:**
- Flutter runtime from `pubspec.yaml`: Flutter `>=3.38.0 <4.0.0` with Dart `^3.10.8`.
- Go runtime from `backend/go.mod`: `go 1.24.0`.
- Node runtime for admin: Node.js `18+` documented in `admin/uses.md` (with Next.js 16 toolchain in `admin/package.json`).

**Package Manager:**
- Flutter: `pub` (lockfile present: `pubspec.lock`).
- Go: Go Modules (lockfile present: `backend/go.sum`).
- Admin web: `npm` (lockfile present: `admin/package-lock.json`, lockfileVersion `3`).

## Frameworks

**Core:**
- Flutter + Material + Riverpod (`flutter_riverpod`) for mobile UI/state in `lib/main.dart` and providers across `lib/features/**`.
- Gin (`github.com/gin-gonic/gin`) for HTTP API routing and middleware in `backend/cmd/server/main.go`.
- Next.js (`16.1.7`) + React (`19.2.3`) for admin portal in `admin/package.json` and route pages under `admin/app/`.

**Testing:**
- Go built-in testing (`go test`, race/coverage) orchestrated by `Makefile` and CI job `go-lint-test` in `.github/workflows/ci.yml`.
- Flutter testing (`flutter test`) configured via `pubspec.yaml`, `Makefile`, and CI job `flutter-test` in `.github/workflows/ci.yml`.
- Admin app: Not detected as having dedicated unit/integration test runner scripts in `admin/package.json`.

**Build/Dev:**
- Docker multi-stage backend image build in `backend/Dockerfile`.
- Docker Compose production orchestration in `deploy/docker-compose.prod.yml`.
- GitHub Actions pipeline (lint/test/build/deploy) in `.github/workflows/ci.yml`.
- ESLint 9 + `eslint-config-next` in `admin/eslint.config.mjs`.

## Key Dependencies

**Critical:**
- `appwrite` (Flutter `^21.1.0`, Admin `^23.0.0`) - Appwrite auth/database/storage/realtime client integration in `lib/core/services/appwrite_service.dart` and `admin/lib/appwrite.ts`.
- `github.com/chizze/backend/pkg/appwrite` client wrapper - Backend Appwrite REST integration in `backend/pkg/appwrite/client.go`.
- `github.com/gin-gonic/gin v1.11.0` - Core API framework in `backend/go.mod`.
- `github.com/golang-jwt/jwt/v5 v5.2.1` - Backend JWT issuance/verification in `backend/internal/handlers/auth_handler.go` and auth middleware.
- `next@16.1.7` + `react@19.2.3` - Admin app runtime in `admin/package.json`.

**Infrastructure:**
- `github.com/redis/go-redis/v9 v9.18.0` - Cache, rate-limit, queue, geo lookups in `backend/pkg/redis/redis.go`.
- `github.com/gorilla/websocket v1.5.3` + `web_socket_channel ^3.0.3` - Backend and Flutter WebSocket channels (`backend/internal/websocket/client.go`, `lib/core/services/websocket_service.dart`).
- `go.opentelemetry.io/*` packages - Tracing in `backend/internal/middleware/tracing.go`.
- `firebase_core` + `firebase_messaging` - Mobile push integration in `lib/main.dart` and `lib/core/services/push_notification_service.dart`.
- `mapbox_maps_flutter` (mobile) + `mapbox-gl`/`react-map-gl` (admin) - Map rendering and live map features in `lib/shared/widgets/delivery_map.dart` and `admin/app/(admin)/live-map/page.tsx`.
- `sentry_flutter ^9.14.0` - Error/perf telemetry in `lib/main.dart`.

## Configuration

**Environment:**
- Backend runtime config is environment-driven in `backend/internal/config/config.go` via `getEnv(...)`, including Appwrite, Redis, JWT, Razorpay, CORS, and performance settings.
- Flutter config is compile-time `--dart-define` driven in `lib/config/environment.dart`, `lib/core/services/map_config.dart`, and `lib/main.dart`.
- Admin config is public env driven via `process.env.NEXT_PUBLIC_*` in `admin/lib/api.ts`, `admin/lib/sse.ts`, `admin/app/(admin)/live-map/page.tsx`, and `admin/app/(admin)/content/page.tsx`.
- `.env`/`.env.*` files are present in the repo; values were intentionally not used for this analysis.

**Build:**
- Backend container build and runtime hardening: `backend/Dockerfile`.
- Production compose topology: `deploy/docker-compose.prod.yml`.
- CI/CD and deploy automation: `.github/workflows/ci.yml`.
- Admin web build/runtime config: `admin/next.config.ts`, `admin/tsconfig.json`, `admin/eslint.config.mjs`.

## Platform Requirements

**Development:**
- Flutter SDK `>=3.38.0 <4.0.0` and Dart `^3.10.8` (`pubspec.yaml`).
- Go toolchain `1.24.x` (`backend/go.mod`).
- Node.js `18+` for admin (`admin/uses.md`).
- Docker/Docker Compose for local/prod-like orchestration (`Makefile`, `deploy/docker-compose.prod.yml`).

**Production:**
- Linux container host running Docker Compose and Nginx reverse proxy (`deploy/docker-compose.prod.yml`, `deploy/chizze-api.nginx`, `deploy/chizze-admin.nginx`).
- Backend served on `api.devdeepak.me` via Nginx upstream `backend_api` (`deploy/chizze-api.nginx`).
- Admin served on `admin.devdeepak.me` via Nginx upstream `admin_panel` (`deploy/chizze-admin.nginx`).
- CI deploy path uses GHCR images + SSH rollout (`.github/workflows/ci.yml`).

---

*Stack analysis: 2026-04-03*
