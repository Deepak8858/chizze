# Requirements: Chizze Admin Order Details

Defined: 2026-04-03
Core Value: Admin sees complete customer and delivery context on each order detail view.

## v1 Requirements

### Admin Order Details

- [x] AORD-01: Admin order detail view displays customer name for the selected order.
- [x] AORD-02: Admin order detail view displays customer phone number for the selected order.
- [x] AORD-03: Admin order detail view displays delivery location details, including resolved address and coordinates when available.
- [x] AORD-04: Admin backend endpoint GET /api/v1/admin/orders/:id returns enriched customer and address fields while preserving current order payload fields.
- [x] AORD-05: UI and API behavior include safe fallback states for missing customer/location fields without page breakage.

## v2 Requirements

### Extended Admin Operations

- AORDV2-01: Admin can copy location to map app with one click.
- AORDV2-02: Admin can view customer order history from order detail.

## v3 Requirements

### Admin Order Cleanup

- [ ] AOC-01: Admin API provides a way to preview stuck-order candidates with filters for status and age.
- [ ] AOC-02: Admin API supports bulk hard deletion of eligible stuck orders and returns deleted/failed counts.
- [ ] AOC-03: Cleanup API enforces safety guards so active in-progress statuses cannot be deleted.
- [ ] AOC-04: Admin Orders UI exposes a guarded cleanup flow with explicit confirmation before deletion.
- [ ] AOC-05: Automated backend and admin tests cover cleanup eligibility rules and deletion result reporting.

## Out of Scope

| Feature                              | Reason                                                            |
| ------------------------------------ | ----------------------------------------------------------------- |
| In-place customer profile editing    | Not required for current support visibility goal                  |
| Full geospatial map widget redesign  | Larger UI initiative; not needed for immediate detail visibility  |

## Traceability

| Requirement | Phase   | Status   |
| ----------- | ------- | -------- |
| AORD-01     | Phase 1 | Complete |
| AORD-02     | Phase 1 | Complete |
| AORD-03     | Phase 1 | Complete |
| AORD-04     | Phase 1 | Complete |
| AORD-05     | Phase 1 | Complete |
| AOC-01      | Phase 2 | Complete |
| AOC-02      | Phase 2 | Complete |
| AOC-03      | Phase 2 | Complete |
| AOC-04      | Phase 2 | Pending  |
| AOC-05      | Phase 2 | Complete |

Coverage:

- v1/v3 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0

---
Requirements defined: 2026-04-03
Last updated: 2026-04-03 after phase 2 requirement definition
