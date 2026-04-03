# Codebase Concerns

**Analysis Date:** 2026-04-03

## Tech Debt

**Admin Order Contract Drift (Backend vs Admin Web):**
- Issue: Order documents are written with denormalized location fields (`delivery_address`, `delivery_landmark`, `delivery_latitude`, `delivery_longitude`, `restaurant_latitude`, `restaurant_longitude`) in `backend/internal/handlers/order_handler.go`, but the typed order contracts in `backend/internal/models/order.go` and `admin/types/index.ts` (`Order`) omit these fields.
- Files: `backend/internal/handlers/order_handler.go`, `backend/internal/models/order.go`, `admin/types/index.ts`, `admin/app/(admin)/orders/[id]/page.tsx`
- Impact: The admin detail page cannot rely on a stable typed contract for required location/customer data, leading to UI blind spots and runtime-only detection.
- Fix approach: Introduce a dedicated admin order detail DTO in backend (normalized map/struct), update `admin/types/index.ts` to match it, and stop relying on raw Appwrite document passthrough.

**Raw Appwrite Passthrough for Admin Orders:**
- Issue: `AdminHandler.GetOrder` and `AdminHandler.ListOrders` return raw Appwrite order documents without normalization or enrichment.
- Files: `backend/internal/handlers/admin_handler.go`, `backend/internal/services/appwrite_service.go`
- Impact: Field shape is implicit and can vary with schema evolution; required fields for `/orders/:id` (customer name/phone/location) are not guaranteed.
- Fix approach: Add backend response shaping for `/api/v1/admin/orders/:id` and `/api/v1/admin/orders` with explicit field names, null-handling, and typed OpenAPI docs.

**Reassignment Data Consistency Debt:**
- Issue: Admin reassign flow updates only `delivery_partner_id` and does not clear/rebuild `delivery_partner_name`/`delivery_partner_phone`.
- Files: `backend/internal/handlers/admin_handler.go`, `admin/app/(admin)/orders/[id]/page.tsx`
- Impact: Stale rider identity/phone can be shown after reassignment, creating operational confusion and privacy leakage.
- Fix approach: On reassign, clear partner denormalized fields and repopulate from current partner profile, or return a normalized payload from backend immediately after mutation.

## Known Bugs

**Admin `/orders/:id` does not show required customer/location fields:**
- Symptoms: Order detail UI shows customer ID only; it does not render customer name, customer phone, delivery address, or delivery coordinates.
- Files: `admin/app/(admin)/orders/[id]/page.tsx`, `admin/types/index.ts`, `backend/internal/handlers/admin_handler.go`
- Trigger: Open any admin order detail page.
- Workaround: None in UI; manual lookup in other tools/collections is required.

**Live Order API Schema Mismatch (Admin Live Board/Map):**
- Symptoms: `LiveOrder` in admin expects `order_id`, `customer_lat`, `customer_lng`, `restaurant_lat`, `restaurant_lng`, but backend `LiveOrders` returns raw order docs using `$id`, `delivery_latitude`, `delivery_longitude`, `restaurant_latitude`, `restaurant_longitude`.
- Files: `backend/internal/handlers/admin_handler.go`, `admin/types/index.ts`, `admin/lib/sse.ts`, `admin/app/(admin)/live-orders/page.tsx`, `admin/app/(admin)/live-map/page.tsx`
- Trigger: Open live orders board or live map with active orders.
- Workaround: None implemented; consumers rely on mismatched keys.

**Pagination Parameter Mismatch (`limit` vs `per_page`):**
- Symptoms: Admin web calls frequently pass `limit`, but backend pagination parser reads `per_page`; responses fall back to defaults.
- Files: `admin/app/(admin)/orders/page.tsx`, `admin/app/(admin)/orders/[id]/page.tsx`, `admin/lib/api.ts`, `backend/internal/models/common.go`, `backend/internal/handlers/admin_handler.go`
- Trigger: Listing orders/riders with `limit` from frontend.
- Workaround: Call endpoints with `per_page` manually.

## Security Considerations

**PII Exposure Without Field-Level Policy:**
- Risk: Expanding `/orders/:id` to include customer phone + precise location (required by product) can expose sensitive data broadly to any `admin`/`super_admin` account without purpose-based controls.
- Files: `backend/cmd/server/main.go`, `backend/internal/handlers/admin_handler.go`, `admin/app/(admin)/orders/[id]/page.tsx`
- Current mitigation: Route-level role gate (`RequireRole("admin", "super_admin")`).
- Recommendations: Add field-level authorization policy, default masking for phone/address in UI, explicit reveal actions, and reason-for-access capture for sensitive fields.

**Admin Token Stored in `localStorage`:**
- Risk: XSS in admin app can exfiltrate `chizze_admin_token`, enabling unauthorized access to customer/order PII endpoints.
- Files: `admin/lib/auth.ts`, `admin/lib/api.ts`
- Current mitigation: 401 handler clears token and redirects to login.
- Recommendations: Move auth token to secure HttpOnly cookie session flow, harden CSP, and reduce inline script risk.

**Auditability Gap for PII Access:**
- Risk: Sensitive read access (e.g., order detail views) is not audit-tracked; `logAudit` helper exists but is unused.
- Files: `backend/internal/handlers/admin_handler.go`
- Current mitigation: Audit collection endpoint exists (`ListAuditLog`) but write path is not used.
- Recommendations: Log read/write actions on `/admin/orders` and `/admin/orders/:id`, include admin ID, order ID, accessed fields, and timestamp.

## Performance Bottlenecks

**Polling-Based Live Views Cause Linear Backend Load:**
- Problem: Admin live hooks poll `/admin/live/orders` and `/admin/live/riders` every 5 seconds per browser tab.
- Files: `admin/lib/sse.ts`, `backend/internal/handlers/admin_handler.go`
- Cause: Polling strategy pulls full snapshots repeatedly instead of incremental updates.
- Improvement path: Use WebSocket push for admin live views or add ETag/delta endpoints; throttle on hidden tabs; aggregate shared polling server-side.

**Live Orders Endpoint Returns Raw Full Documents:**
- Problem: `/admin/live/orders` returns raw docs, including fields not required by live board/map.
- Files: `backend/internal/handlers/admin_handler.go`, `admin/app/(admin)/live-orders/page.tsx`, `admin/app/(admin)/live-map/page.tsx`
- Cause: No response projection/DTO.
- Improvement path: Return minimal typed payload (`order_id`, status, totals, mapped location/name fields) to reduce payload size and parse overhead.

**Potential N+1 Risk if Admin Enrichment Mirrors Other Handlers:**
- Problem: Existing non-admin handlers enrich customer/delivery data via per-order lookups in loops.
- Files: `backend/internal/handlers/order_handler.go`, `backend/internal/handlers/delivery_handler.go`
- Cause: Repeated `GetUser`/`GetRestaurant` lookups without batching/cache.
- Improvement path: Batch lookup IDs and cache profiles per request (or pre-denormalize consistently).

## Fragile Areas

**Order Item Parsing Assumes String-Encoded JSON:**
- Files: `admin/lib/utils.ts`, `admin/app/(admin)/orders/[id]/page.tsx`
- Why fragile: `parseOrderItems` expects `items` as a JSON string only; if backend returns object/array for some records, UI drops to "No item details available".
- Safe modification: Accept string or array payloads and normalize.
- Test coverage: No admin frontend tests validate mixed item payload shapes.

**Dynamic Field Access Without Contract Guardrails:**
- Files: `admin/app/(admin)/orders/[id]/page.tsx`, `backend/internal/handlers/admin_handler.go`
- Why fragile: UI assumes presence/shape for fields like `payment_method`, `customer_id`, timestamps; backend emits dynamic maps.
- Safe modification: Introduce strict DTO validation and fallback rendering for null/unknown fields.
- Test coverage: No contract tests for `/admin/orders/:id` response shape.

**Live Order Field Naming Inconsistency Across Layers:**
- Files: `backend/internal/handlers/admin_handler.go`, `admin/types/index.ts`, `admin/lib/sse.ts`
- Why fragile: Field names differ by layer with no adapter (`delivery_*` vs `customer_*`, `$id` vs `order_id`).
- Safe modification: Centralize a mapper (`toLiveOrder`) and enforce one canonical schema.
- Test coverage: No backend/admin integration tests assert live payload shape.

## Scaling Limits

**Hard Cap of 100 Active Orders in Live Admin:**
- Current capacity: `/admin/live/orders` returns at most 100 active orders.
- Limit: Beyond 100, live board/map silently omit additional active orders.
- Scaling path: Cursor-based pagination for live endpoints + prioritized streaming for recently changed orders.

**Pagination Cap and Param Drift in Admin Lists:**
- Current capacity: Backend parser allows `per_page` up to 100.
- Limit: Frontend often sends `limit`, causing default pagination and reduced visibility during high load.
- Scaling path: Standardize query params in shared client (`per_page`, `page`) and enforce in API docs/types.

## Dependencies at Risk

**Not detected for the `/orders/:id` admin visibility path.**
- Risk: No direct package deprecation/blocker was identified as the primary source of order detail visibility issues.
- Impact: Current risk is mostly schema/process debt rather than third-party library instability.
- Migration plan: Not applicable.

## Missing Critical Features

**Admin Order Detail Missing Mandatory Operational Fields:**
- Problem: `/orders/:id` does not provide/show customer name, customer phone, delivery location, and complete normalized detail payload expected by operations.
- Blocks: Fast support resolution, manual dispatch correction, and customer contact workflows from a single admin page.

**No Canonical Admin Order Detail Schema:**
- Problem: Backend returns raw order doc; frontend type omits important fields and relies on implicit shape.
- Blocks: Reliable UI rendering and safe evolution of order detail features.

**No Privacy Controls for Sensitive Data Reveal:**
- Problem: Sensitive fields (phone/location) are not governed by explicit reveal/mask policy despite admin-wide access.
- Blocks: Compliance-friendly expansion of customer detail visibility.

## Test Coverage Gaps

**Admin Orders Backend Endpoints Untested:**
- What's not tested: `/api/v1/admin/orders`, `/api/v1/admin/orders/:id`, `/api/v1/admin/orders/:id/reassign`, `/api/v1/admin/orders/:id/cancel` behavior and schema.
- Files: `backend/internal/handlers/admin_handler.go`
- Risk: Regressions in field availability or mutation side effects can ship unnoticed.
- Priority: High

**Admin Order Detail UI Rendering Untested:**
- What's not tested: Rendering of customer identity/contact/location and robust handling of missing/malformed order payload fields.
- Files: `admin/app/(admin)/orders/[id]/page.tsx`, `admin/lib/utils.ts`, `admin/types/index.ts`
- Risk: Runtime errors and silent data loss in core operations page.
- Priority: High

**Live Order Contract Compatibility Untested:**
- What's not tested: Compatibility between `/api/v1/admin/live/orders` payload and `LiveOrder` contract used by live board/map.
- Files: `backend/internal/handlers/admin_handler.go`, `admin/types/index.ts`, `admin/lib/sse.ts`, `admin/app/(admin)/live-orders/page.tsx`, `admin/app/(admin)/live-map/page.tsx`
- Risk: Live monitoring appears online but renders incomplete/incorrect operational data.
- Priority: High

---

*Concerns audit: 2026-04-03*