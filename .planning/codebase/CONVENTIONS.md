# Coding Conventions

**Analysis Date:** 2026-04-03

## Naming Patterns

**Files:**
- Go source and tests use snake_case file names with `_test.go` suffix for tests (for example `backend/internal/handlers/order_handler.go`, `backend/internal/handlers/order_handler_test.go`).
- Flutter source and tests use snake_case file names (for example `lib/core/services/api_client.dart`, `test/models/api_response_test.dart`).
- Admin web app uses kebab-case for reusable files and Next App Router conventions for route entries (for example `admin/components/data-table.tsx`, `admin/components/ui/status-badge.tsx`, `admin/app/(admin)/orders/[id]/page.tsx`).

**Functions:**
- Go handler/service methods use PascalCase when exported and camelCase for locals (for example `GetOrder`, `ListOrders`, `resolveDeliveryPartnerDetails` in `backend/internal/handlers/order_handler.go`).
- TypeScript/TSX functions use camelCase (for example `formatCurrency`, `parseOrderItems` in `admin/lib/utils.ts`).
- Flutter methods use camelCase and async suffix-by-meaning patterns (for example `fetchRestaurants` in `lib/features/home/providers/restaurant_provider.dart`).

**Variables:**
- TypeScript and Flutter variables use camelCase (for example `queryFn`, `deliveryPartnerPhone`, `isLoading`).
- Backend JSON payload keys use snake_case to match API documents and clients (for example `customer_id`, `delivery_address`, `payment_status` in `backend/internal/handlers/order_handler.go`).

**Types:**
- TypeScript interfaces/types use PascalCase (for example `Order`, `LiveOrder`, `DashboardStats` in `admin/types/index.ts`).
- Go structs use PascalCase with explicit JSON tags (for example `Order` in `backend/internal/models/order.go`).
- Flutter model classes use PascalCase and map snake_case JSON keys to camelCase fields (for example `Order.fromMap` in `lib/features/orders/models/order.dart`).

## Code Style

**Formatting:**
- Admin web uses ESLint with Next.js presets from `admin/eslint.config.mjs`; no separate Prettier config is detected in first-party admin files.
- Flutter uses `flutter_lints` via `analysis_options.yaml`.
- Go formatting is gofmt-style in checked-in code; lint command is `golangci-lint run` from `Makefile`.

**Linting:**
- Admin TypeScript is strict (`"strict": true`) and uses Next TypeScript lint presets in `admin/tsconfig.json` and `admin/eslint.config.mjs`.
- Flutter linting runs through `flutter analyze --no-fatal-infos` (`Makefile`).
- Go linting is centralized in `make go-lint` (`Makefile`) but no repo-local `.golangci.yml` is detected under first-party `backend/` code.

## Import Organization

**Order:**
1. Platform/standard and third-party imports first.
2. Project alias imports next (admin `@/*`, Flutter package imports under `package:chizze/...`, Go internal packages under `github.com/chizze/backend/...`).
3. Relative imports last (when used).

**Path Aliases:**
- Admin uses `@/*` alias mapped to project root in `admin/tsconfig.json`.
- Flutter does not use a global alias; feature code commonly uses relative imports within a feature and `package:chizze/...` across modules.
- Go uses module-import paths from `go.mod` (`module github.com/chizze/backend`).

## API Contract Handling (Admin Web <-> Backend <-> Flutter)

- Backend canonical envelope is `{"success": bool, "data": any, "error": string, "meta": {...}}` from `backend/pkg/utils/response.go`.
- Backend pagination metadata keys are camelCase-in-JSON (`perPage`, `totalPages`) via `utils.Meta` in `backend/pkg/utils/response.go`.
- Backend handlers consistently respond through `utils.Success`, `utils.Created`, `utils.Paginated`, and error helpers (`utils.BadRequest`, `utils.InternalError`) in files like `backend/internal/handlers/order_handler.go` and `backend/internal/handlers/admin_handler.go`.
- Flutter consumes the envelope as a first-class type using `ApiResponse<T>` in `lib/core/models/api_response.dart` and returns `ApiResponse<T>` from every `ApiClient` method in `lib/core/services/api_client.dart`.
- Flutter feature providers gate on `response.success` and then parse `response.data` with defensive shape checks (for example `lib/features/home/providers/restaurant_provider.dart`).
- Admin `admin/lib/api.ts` currently returns the raw backend body unchanged from `unwrap<T>()`, so pages generally cast query results to shapes like `Promise<{ data: Order[] }>` and often ignore `success` and `meta` at call sites.
- Admin polling in `admin/lib/sse.ts` explicitly unwraps `data` when it sees `success` and `data` keys.
- Data field naming remains snake_case across backend and client payloads; frontend model layers map this to typed fields (`admin/types/index.ts`, `lib/features/orders/models/order.dart`).
- Role strings are contract-sensitive and used as exact literals across layers (`customer`, `restaurant_owner`, `delivery_partner`, plus admin-side `admin`/`super_admin`) in `backend/internal/middleware/auth.go`, `backend/cmd/server/main.go`, and `lib/core/router/app_router.dart`.

## Error Handling

**Patterns:**
- Backend returns envelope errors with HTTP status and `error` string through middleware and utils helpers (`backend/internal/middleware/auth.go`, `backend/pkg/utils/response.go`).
- Admin global 401 handling is centralized in Axios interceptor, clearing local token and redirecting to `/login` (`admin/lib/api.ts`).
- Flutter centralizes Dio error conversion into `ApiException`, extracting backend `error` field when present (`lib/core/services/api_client.dart`).

## Logging

**Framework:**
- Backend: standard `log.Printf` in handlers/services.
- Flutter: `debugPrint` behind `kDebugMode` and Sentry breadcrumbs in API client.
- Admin: minimal runtime logging, mostly user-facing toast/error UI states.

**Patterns:**
- Log on backend write failures and external service failures (for example payment/order updates in `backend/internal/handlers/payment_handler.go`).
- Flutter logs transient issues in debug mode and avoids noisy production capture for known non-actionable network/server classes (`lib/main.dart`, `lib/core/services/api_client.dart`).

## Comments

**When to Comment:**
- Files use section-divider comments to mark functional blocks (for example `// Orders`, `// Dashboard`, `// ---` sections in Go and TSX files).
- Inline comments are used around non-obvious behavior, especially auth refresh, idempotency, and fallback logic.

**JSDoc/TSDoc:**
- Admin TypeScript uses sparse JSDoc-style comments for key helpers (for example envelope unwrap in `admin/lib/sse.ts`).
- Go uses Swagger annotations on handlers for API docs (for example `backend/internal/handlers/order_handler.go`).

## Function Design

**Size:**
- Go handlers are orchestration-heavy and can be long; logic is still segmented into validation, authorization, enrichment, and response sections (for example `GetOrder`/`ListOrders` in `backend/internal/handlers/order_handler.go`).
- Flutter notifiers keep state transitions explicit and isolated to methods that update immutable state objects.

**Parameters:**
- DTO/request structs in Go use `binding` tags for required fields (`backend/internal/models/order.go`).
- TypeScript API wrappers use typed helper methods (`GET/POST/PUT/DELETE`) and domain-grouped API objects (`admin/lib/api.ts`).

**Return Values:**
- Backend returns envelope JSON only.
- Flutter returns typed `ApiResponse<T>` and throws `ApiException` for transport/status failures.
- Admin query functions generally return envelope-shaped objects but call sites usually consume only `.data`.

## Module Design

**Exports:**
- Admin groups exports by domain API object (for example `ordersApi`, `dashboardApi`, `deliveryApi` in `admin/lib/api.ts`).
- Flutter uses feature-scoped providers and model classes with explicit constructors/fromMap methods.
- Go uses package-level constructor patterns (`NewOrderHandler`, `NewAuthHandler`) and dependency injection from `backend/cmd/server/main.go`.

**Barrel Files:**
- Limited use in Flutter shared widgets (`lib/shared/widgets/widgets.dart`).
- Admin and backend primarily use direct module imports rather than broad barrel re-exports.

---

*Convention analysis: 2026-04-03*
