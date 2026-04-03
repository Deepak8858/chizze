# Roadmap: Chizze Admin Order Details

## Overview

This roadmap delivers complete order-detail visibility for admins by enriching backend order responses and rendering customer identity plus location data in the admin order detail screen.

## Phases

Phase Numbering:

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] Phase 1: Admin Order Detail Enrichment - Show complete customer and location context in admin order detail.
  (completed 2026-04-03)

## Phase Details

### Phase 1: Admin Order Detail Enrichment

**Goal**: Admin can open an order and see customer name, customer phone, and delivery location details in one place.
**Depends on**: Nothing (first phase)
**Requirements**: [AORD-01, AORD-02, AORD-03, AORD-04, AORD-05]
**Success Criteria** (what must be TRUE):

  1. Admin order detail endpoint returns customer name, phone, and delivery address/coordinates for existing orders.
  2. Admin order detail screen renders those fields in a clear layout with fallbacks for missing fields.
  3. Admin can use the order detail page to contact customer and verify delivery destination context without leaving the page.

**Plans**: 2 plans

Plans:

- [x] 01-01-PLAN.md - Backend response enrichment for admin order detail data contract
- [x] 01-02-PLAN.md - Admin order detail UI rendering for customer identity and location context

## Progress

Execution Order:

Phases execute in numeric order: 1

| Phase                            | Plans Complete | Status   | Completed  |
| -------------------------------- | -------------- | -------- | ---------- |
| 1. Admin Order Detail Enrichment | 2/2            | Complete | 2026-04-03 |

### Phase 2: Clear stuck orders by deleting them from the server

**Goal:** Admin can safely remove stale stuck orders from the server without impacting active order flow.
**Requirements**: [AOC-01, AOC-02, AOC-03, AOC-04, AOC-05]
**Depends on:** Phase 1
**Plans:** 2 plans

Plans:

- [x] 02-01-PLAN.md - Backend stuck-order preview and bulk hard-delete APIs with safety guards
- [ ] 02-02-PLAN.md - Admin orders cleanup flow with explicit confirmation and regression tests
