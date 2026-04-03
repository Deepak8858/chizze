# Requirements: Chizze Admin Order Details

Defined: 2026-04-03
Core Value: Admin sees complete customer and delivery context on each order detail view.

## v1 Requirements

### Admin Order Details

- [ ] AORD-01: Admin order detail view displays customer name for the selected order.
- [ ] AORD-02: Admin order detail view displays customer phone number for the selected order.
- [ ] AORD-03: Admin order detail view displays delivery location details, including resolved address and coordinates when available.
- [ ] AORD-04: Admin backend endpoint GET /api/v1/admin/orders/:id returns enriched customer and address fields while preserving current order payload fields.
- [ ] AORD-05: UI and API behavior include safe fallback states for missing customer/location fields without page breakage.

## v2 Requirements

### Extended Admin Operations

- AORDV2-01: Admin can copy location to map app with one click.
- AORDV2-02: Admin can view customer order history from order detail.

## Out of Scope

| Feature | Reason |
|---------|--------|
| In-place customer profile editing | Not required for current support visibility goal |
| Full geospatial map widget redesign | Larger UI initiative; not needed for immediate detail visibility |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AORD-01 | Phase 1 | Pending |
| AORD-02 | Phase 1 | Pending |
| AORD-03 | Phase 1 | Pending |
| AORD-04 | Phase 1 | Pending |
| AORD-05 | Phase 1 | Pending |

Coverage:
- v1 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
Requirements defined: 2026-04-03
Last updated: 2026-04-03 after phase bootstrap
