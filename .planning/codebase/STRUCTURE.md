# Codebase Structure

**Analysis Date:** 2026-04-03

## Directory Layout

```
chizze/
├── lib/                 # Flutter mobile app
├── admin/               # Next.js admin panel
├── backend/             # Go API server + workers + websocket
├── test/                # Flutter tests
├── backend/internal/    # Core backend app layers
├── backend/pkg/         # Infrastructure adapters (Appwrite, Redis, utils)
├── deploy/              # Deployment manifests/scripts
├── tools/               # Utility scripts and verification helpers
├── build/               # Generated Flutter build artifacts
└── .planning/codebase/  # Generated architecture/codebase mapping docs
```

## Directory Purposes

**`lib/`:**
- Purpose: Flutter application runtime and feature implementation.
- Contains: `core/` shared infrastructure, `features/` role/user features, `shared/` shared screens.
- Key files: `lib/main.dart`, `lib/core/router/app_router.dart`, `lib/core/services/api_client.dart`, `lib/core/services/websocket_service.dart`.

**`admin/`:**
- Purpose: Administrative web console.
- Contains: App Router pages, reusable components, API clients, typed DTOs.
- Key files: `admin/app/layout.tsx`, `admin/app/(admin)/layout.tsx`, `admin/app/(admin)/orders/page.tsx`, `admin/app/(admin)/orders/[id]/page.tsx`, `admin/lib/api.ts`, `admin/lib/sse.ts`, `admin/types/index.ts`.

**`backend/cmd/`:**
- Purpose: Executable entrypoints.
- Contains: Server bootstrap and route wiring.
- Key files: `backend/cmd/server/main.go`.

**`backend/internal/handlers/`:**
- Purpose: HTTP endpoint handlers by domain/role.
- Contains: `*_handler.go` and handler tests.
- Key files: `backend/internal/handlers/admin_handler.go`, `backend/internal/handlers/order_handler.go`, `backend/internal/handlers/delivery_handler.go`.

**`backend/internal/services/`:**
- Purpose: Business logic and data-access facades.
- Contains: Domain services, fee/geo/payment/cache logic, Appwrite facade.
- Key files: `backend/internal/services/order_service.go`, `backend/internal/services/geo_service.go`, `backend/internal/services/appwrite_service.go`.

**`backend/internal/models/`:**
- Purpose: Domain constants/types and request model contracts.
- Contains: Order/user/restaurant/etc model definitions and collection ids.
- Key files: `backend/internal/models/order.go`, `backend/internal/models/common.go`.

**`backend/internal/websocket/`:**
- Purpose: Realtime transport and event abstractions.
- Contains: Hub/client lifecycle and typed event broadcaster.
- Key files: `backend/internal/websocket/client.go`, `backend/internal/websocket/hub.go`, `backend/internal/websocket/events.go`.

**`backend/internal/workers/`:**
- Purpose: Background processing loops.
- Contains: Delivery matching, order timeout, scheduled order processing, notification dispatch.
- Key files: `backend/internal/workers/delivery_matcher.go`, `backend/internal/workers/order_timeout.go`.

**`backend/pkg/`:**
- Purpose: Infrastructure clients/utilities reused across handlers/services.
- Contains: Appwrite HTTP client, Redis wrapper, response utilities.
- Key files: `backend/pkg/appwrite/client.go`, `backend/pkg/utils/response.go`.

## Key File Locations

**Entry Points:**
- `lib/main.dart`: Flutter app bootstrap.
- `admin/app/page.tsx`: Admin root redirect.
- `admin/app/(admin)/layout.tsx`: Admin shell + auth gate.
- `backend/cmd/server/main.go`: Gin server/bootstrap/route map.

**Configuration:**
- `pubspec.yaml`: Flutter dependency/runtime config.
- `admin/next.config.ts`: Next.js config.
- `admin/tsconfig.json`: TS compiler + path aliases (`@/*`).
- `backend/go.mod`: Go module dependencies.
- `analysis_options.yaml`: Flutter/Dart analysis rules.

**Core Logic:**
- `backend/internal/handlers/order_handler.go`: Order placement/status/ownership flows.
- `backend/internal/handlers/admin_handler.go`: Admin operations including order read/cancel/reassign.
- `backend/internal/services/order_service.go`: Fee and transition logic.
- `admin/lib/api.ts`: Admin transport layer.
- `admin/app/(admin)/orders/[id]/page.tsx`: Order detail rendering/transforms.

**Testing:**
- `backend/internal/handlers/order_handler_test.go`: Backend order handler behavior.
- `backend/internal/handlers/flow_test.go`: End-to-end role flow tests.
- `backend/internal/services/order_service_test.go`: Service-level tests.
- `test/`: Flutter tests.

## Naming Conventions

**Files:**
- Flutter files use snake_case by feature (`lib/features/orders/screens/order_tracking_screen.dart`).
- Next App Router pages use `page.tsx` and `layout.tsx`, with dynamic segments as `[id]` (`admin/app/(admin)/orders/[id]/page.tsx`).
- Go handler/service/model files use lower_snake style with suffixes (`order_handler.go`, `order_service.go`, `order.go`).

**Directories:**
- Flutter modules are grouped by feature (`lib/features/<feature>/screens|providers|models`).
- Admin route groups use App Router folder grouping (`admin/app/(admin)/...`).
- Backend layers are grouped by concern (`backend/internal/handlers`, `backend/internal/services`, `backend/internal/models`).

## Where to Add New Code

**New Backend API Endpoint:**
- Primary code: add handler in `backend/internal/handlers/<domain>_handler.go`.
- Route registration: wire route in `backend/cmd/server/main.go` under the correct role group.
- Business logic: place reusable logic in `backend/internal/services/<domain>_service.go`.
- Data access: add Appwrite operations in `backend/internal/services/appwrite_service.go` if needed.
- Tests: add/extend tests in `backend/internal/handlers/*_test.go` or `backend/internal/services/*_test.go`.

**New Admin Page/Module:**
- Route implementation: `admin/app/(admin)/<feature>/page.tsx`.
- API methods: `admin/lib/api.ts`.
- Streaming/polling needs: `admin/lib/sse.ts`.
- Shared UI: `admin/components/`.
- Type contracts: `admin/types/index.ts`.

**New Flutter Feature:**
- Screens/providers/models: `lib/features/<feature>/`.
- Shared infrastructure updates: `lib/core/services/` and `lib/core/router/app_router.dart`.
- Shared UI or cross-feature page: `lib/shared/`.

**Order Detail Field Expansion Pipeline (admin-specific):**
- Backend read/enrichment: extend `backend/internal/handlers/admin_handler.go` (`GetOrder`) to join user/address details.
- Backend access helpers: use `GetUser`/`GetAddress` in `backend/internal/services/appwrite_service.go`.
- Frontend model: add fields to `admin/types/index.ts` (`Order`).
- Frontend rendering: render in `admin/app/(admin)/orders/[id]/page.tsx`.
- Optional list sync: update `admin/app/(admin)/orders/page.tsx` if list view must surface new fields.

## Special Directories

**`build/`:**
- Purpose: Flutter generated build output.
- Generated: Yes.
- Committed: No (generated artifacts).

**`admin/.next/`:**
- Purpose: Next.js build cache/output.
- Generated: Yes.
- Committed: No.

**`backend/bin/`:**
- Purpose: Built backend binaries.
- Generated: Yes.
- Committed: Typically no (environment/build output).

**`backend/.gopath/` and `backend/.gomod/`:**
- Purpose: Local Go workspace/cache artifacts used by tooling.
- Generated: Yes.
- Committed: No.

**`coverage/` and `backend/coverage`:**
- Purpose: Test coverage outputs.
- Generated: Yes.
- Committed: Optional/reporting artifact depending on workflow.

**`.planning/codebase/`:**
- Purpose: Generated architecture/stack/convention/concern mapping documents used by GSD planning/execution.
- Generated: Yes.
- Committed: Yes, when maintaining planning artifacts in-repo.

---

*Structure analysis: 2026-04-03*
