# Phase 1: Admin Order Detail Enrichment - Context

Gathered: 2026-04-03
Status: Ready for planning

<domain>
## Phase Boundary

This phase delivers complete operational order context on the admin order detail page so admins can see customer name, customer phone number, and delivery location information after clicking an order.

</domain>

<decisions>
## Implementation Decisions

### Data contract
- D-01: Backend admin order detail endpoint must enrich the order response with customer identity and delivery address/location fields.
- D-02: Existing order response keys must remain intact while adding optional enriched fields.

### UI behavior
- D-03: Admin order detail page at /orders/:id must render customer name, customer phone, and location details in the Customer section.
- D-04: UI must provide safe fallbacks when enriched fields are missing.

### Scope
- D-05: This phase is focused on detail visibility only, not customer profile editing.

### the agent's Discretion
- Exact naming of new enriched response fields if consistent and documented.
- Exact placement and styling details in the order detail card layout.
- Whether to include quick actions such as tel: link and map deep link if existing patterns support them.

</decisions>

<specifics>
## Specific Ideas

- User expectation: after opening an order details page, admin should see every key detail including location, customer phone number, and customer name.
- Reference URL example: https://admin.devdeepak.me/orders/69cf5ce4567de8511940

</specifics>

<canonical_refs>
## Canonical References

Downstream agents must read these before planning or implementing.

### Admin UI order details
- admin/app/(admin)/orders/[id]/page.tsx - Current order detail rendering and missing customer identity/location fields.
- admin/lib/api.ts - ordersApi.get contract used by order detail page.
- admin/types/index.ts - Order type definitions that need enriched-field compatibility.

### Backend admin order detail pipeline
- backend/cmd/server/main.go - Admin route registration for GET /api/v1/admin/orders/:id.
- backend/internal/handlers/admin_handler.go - GetOrder handler currently returns raw order document.
- backend/internal/services/appwrite_service.go - GetOrder, GetUser, and GetAddress helper methods used for enrichment.

### Product and platform constraints
- .planning/PROJECT.md - Scope, constraints, and core value for this phase.
- .planning/REQUIREMENTS.md - Requirement IDs AORD-01..AORD-05 that plans must cover.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Appwrite service already exposes GetOrder, GetUser, and GetAddress methods needed for enrichment logic.
- Admin order detail UI already has Customer and Delivery Rider cards that can host extra fields.

### Established Patterns
- Backend handlers use utils.Success and map payloads directly from Appwrite documents.
- Admin panel fetches detail with React Query and typed Order responses from admin/types/index.ts.

### Integration Points
- Enriched fields flow from backend/internal/handlers/admin_handler.go through admin/lib/api.ts into admin/app/(admin)/orders/[id]/page.tsx.

</code_context>

<deferred>
## Deferred Ideas

- Embedding an interactive map widget in the order detail page.
- Customer profile drill-down and order history side panel.

</deferred>

---
Phase: 01-admin-order-detail-enrichment
Context gathered: 2026-04-03
