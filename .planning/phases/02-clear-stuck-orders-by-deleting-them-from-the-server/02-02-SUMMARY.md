---
phase: 02-clear-stuck-orders-by-deleting-them-from-the-server
plan: 02
subsystem: admin-ui
tags: [nextjs, react-query, vitest, admin-orders]
requires: [02-01]
provides:
  - Guarded admin stuck-order cleanup panel with explicit confirmation.
  - Typed preview/delete cleanup contracts in admin data layer.
  - Focused Orders page tests for confirmation gating and delete payload behavior.
affects: [admin-ui, orders]
tech-stack:
  added: []
  patterns: ["Destructive admin actions require explicit typed confirmation phrase"]
key-files:
  created: [admin/app/(admin)/orders/page.test.tsx]
  modified: [admin/types/index.ts, admin/lib/api.ts, admin/app/(admin)/orders/page.tsx]
key-decisions:
  - "Use in-page cleanup control panel instead of introducing a new modal system"
  - "Require exact confirmation phrase DELETE {eligible_count} before enabling hard delete"
patterns-established:
  - "Admin cleanup flow uses preview-first behavior before destructive mutation"
  - "Orders list and preview caches are invalidated together after cleanup mutation"
requirements-completed: [AOC-04, AOC-05]
duration: 24 min
completed: 2026-04-03
---

# Phase 02 Plan 02: Admin Orders Cleanup UI Summary

Admin Orders page now supports a guarded stuck-order cleanup flow with preview, explicit destructive confirmation, and focused regression coverage.

## Performance

- Duration: 24 min
- Started: 2026-04-03T11:23:00Z
- Completed: 2026-04-03T11:47:00Z
- Tasks: 3
- Files modified: 4

## Accomplishments

- Added cleanup contracts and API helpers in admin type and API layers.
- Added a preview-driven cleanup panel to Orders page with status/age/limit controls and explicit confirmation gate.
- Added focused Vitest coverage to verify confirmation gating and delete payload behavior.

## Task Commits

1. Task 1: Add typed admin cleanup API contracts and client methods - 675264b8 (feat)
2. Task 2: Build guarded cleanup panel on admin Orders page - 6d54a788 (feat)
3. Task 3: Add focused Orders page tests for confirmation gate and cleanup mutation - 7d68aea8 (test)

Plan metadata: pending

## Files Created/Modified

- admin/types/index.ts - Added cleanup preview/delete interfaces and result metadata types.
- admin/lib/api.ts - Added `ordersApi.previewStuck` and `ordersApi.deleteStuck` helpers.
- admin/app/(admin)/orders/page.tsx - Added guarded cleanup panel, preview query, confirmation gate, and delete mutation wiring.
- admin/app/(admin)/orders/page.test.tsx - Added page-level tests for confirmation and mutation payload behavior.

## Decisions Made

- Kept cleanup controls in the existing Orders page for lower operator friction.
- Used exact-string confirmation (`DELETE {eligible_count}`) to prevent accidental hard deletion.

## Deviations from Plan

### Auto-fixed Issues

1. [Rule 3 - Blocking] Default Vitest fork pool timed out when running the new focused test in this environment.
- Found during: Task 3 verification.
- Fix: Re-ran the focused test with thread pool (`--pool=threads`) and verified all cases passed.
- Verification: `npx vitest run --pool=threads "app/(admin)/orders/page.test.tsx"`

Total deviations: 1 auto-fixed (1 blocking)
Impact on plan: No scope change, verification command adjusted for runtime stability.

## Issues Encountered

None remaining.

## User Setup Required

None - no external service setup needed.

## Next Phase Readiness

- Phase 02 requirements are complete across backend and admin layers.
- No blockers remain for phase verification/completion.

---
Phase: 02-clear-stuck-orders-by-deleting-them-from-the-server
Completed: 2026-04-03