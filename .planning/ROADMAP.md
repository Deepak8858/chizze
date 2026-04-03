# Roadmap: Chizze Admin Order Details

## Overview

This roadmap delivers complete order-detail visibility for admins by enriching backend order responses and rendering customer identity plus location data in the admin order detail screen.

## Phases

Phase Numbering:
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] Phase 1: Admin Order Detail Enrichment - Show complete customer and location context in admin order detail.

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
- [ ] 01-01-PLAN.md - Backend response enrichment for admin order detail data contract
- [ ] 01-02-PLAN.md - Admin order detail UI rendering for customer identity and location context

## Progress

Execution Order:
Phases execute in numeric order: 1

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Admin Order Detail Enrichment | 0/2 | Not started | - |
