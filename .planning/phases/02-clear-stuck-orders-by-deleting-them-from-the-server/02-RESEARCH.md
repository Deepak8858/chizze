# Phase 2: Clear stuck orders by deleting them from the server - Research

Researched: 2026-04-03
Domain: Admin order cleanup (Go API + Next.js admin)
Confidence: HIGH

<user_constraints>
## User Constraints (from requirements and direct request)

### Locked Decisions
- D-01: Admin API must preview stuck-order candidates using status and age filters (AOC-01).
- D-02: Admin API must support bulk hard deletion and return deleted/failed counts (AOC-02).
- D-03: Cleanup must block active in-progress statuses from deletion (AOC-03).
- D-04: Admin Orders UI must include an explicit confirmation gate before deletion (AOC-04).
- D-05: Backend and admin layers must have automated test coverage for cleanup rules and result reporting (AOC-05).

### the agent's Discretion
- Exact endpoint names and payload keys for preview/delete operations.
- Default cleanup filters (status defaults, minimum age defaults, max limits).
- UI layout details for the cleanup control panel in the orders page.

### Deferred Ideas (OUT OF SCOPE)
- Background archival jobs and soft-delete retention workflows.
- New analytics dashboards for deletion trends.
- Cross-surface cleanup flows in Flutter mobile apps.

</user_constraints>

<discovery>
## Discovery Level

Level 0 (skip deep external research).

Reason: This phase extends existing in-repo patterns only (Gin admin handlers, Appwrite service wrappers, existing admin page/test stack) and does not require new third-party dependencies.
</discovery>

<research_summary>
## Summary

Backend already has admin order list/detail/cancel/reassign endpoints but no order deletion route. The Appwrite service already supports generic `DeleteDocument(collection,id)` and query helpers for `equal`, `lessThan`, `notEqual`, and pagination.

Admin web already has `ordersApi` wrappers and an `OrdersPage` table with React Query polling. The page currently has no cleanup controls. Vitest + Testing Library are already configured from Phase 1 and can be reused for page-level cleanup tests.

Primary recommendation: implement a two-step cleanup flow:
1. Preview endpoint with status + minimum-age filters.
2. Bulk delete endpoint using the same filters plus strict active-status guardrails.

Then wire a guarded admin UI panel that requires explicit confirmation before executing delete.
</research_summary>

<standard_stack>
## Standard Stack

### Existing stack used for this feature
| Library | Purpose | Why it should be used here |
|---------|---------|----------------------------|
| Gin handlers in backend/internal/handlers/admin_handler.go | Admin endpoint logic | Existing pattern for admin APIs and response envelopes |
| Appwrite service wrapper in backend/internal/services/appwrite_service.go | Order list/delete operations | Reuses current persistence adapter and collection constants |
| Query helpers in backend/pkg/appwrite/query.go | Status and age filtering | Already supports needed operators (`equal`, `lessThan`, pagination) |
| React Query + Next.js admin orders page | Preview/delete UX and cache refresh | Existing data layer on admin orders list page |
| Vitest + Testing Library | Admin regression tests | Already present in admin package and used in Phase 1 |

### Alternatives considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Dedicated worker for cleanup | Manual admin-triggered cleanup endpoint | Worker adds orchestration overhead for immediate admin need |
| Direct DB scripts | API-level cleanup endpoints | Scripts bypass role checks, auditability, and UI safeguards |

</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Backend pattern
1. Parse and normalize requested statuses and age filter.
2. Build Appwrite queries (`QueryEqual(status)`, `QueryLessThan(placed_at, cutoff)`, order + limit/offset).
3. Apply server-side safety guard: allow only terminal statuses (`delivered`, `cancelled`) for deletion.
4. Return envelope responses via `utils.Success`/`utils.Paginated` with counts and failure details.

### UI pattern
1. Keep existing Orders table unchanged.
2. Add a cleanup panel above the table with filter controls and preview button.
3. Require explicit confirmation text before enabling delete action.
4. On success, show toast and invalidate orders + preview queries.

### Route integration pattern
- Add cleanup routes inside existing admin route group in `backend/cmd/server/main.go` under current auth + role middleware.
- Keep response shape backward-compatible (`success/data/error/meta`).

</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Do not build | Use instead | Why |
|---------|--------------|-------------|-----|
| Data access abstraction | New cleanup repository layer | Existing AppwriteService + generic DeleteDocument wrapper | Consistent with current architecture |
| Admin confirmation UI framework | New modal framework | Existing page-level controls and sonner toasts | Avoids dependency churn |

</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Deleting active in-progress orders
What goes wrong: operational orders disappear mid-fulfillment.
How to avoid: hard-block non-terminal statuses server-side even if client sends them.

### Pitfall 2: Preview/delete filter mismatch
What goes wrong: admin previews one set but deletes a different set.
How to avoid: share one normalized filter/eligibility helper used by both endpoints.

### Pitfall 3: Weak delete result reporting
What goes wrong: admin cannot tell partial failures from success.
How to avoid: return detailed counters and failed IDs/reasons in delete response.

</common_pitfalls>

## Validation Architecture

- Backend: focused handler tests for preview filtering and active-status guard + count reporting.
- Admin: focused page test validating explicit confirmation gating and cleanup mutation call behavior.

Suggested automated checks:
- `cd backend; go test ./internal/handlers -run TestAdmin(StuckOrdersPreview|DeleteStuckOrders) -count=1`
- `cd admin; npm run test -- "app/(admin)/orders/page.test.tsx"`

Phase: 02-clear-stuck-orders-by-deleting-them-from-the-server
Research completed: 2026-04-03
Ready for planning: yes