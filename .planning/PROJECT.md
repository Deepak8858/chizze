# Chizze Admin Order Details

## What This Is

This planning track defines the next admin improvement for the Chizze platform: complete order-detail visibility for operations. It focuses on the admin order detail experience so admins can inspect customer identity and delivery location context without switching tools.

## Core Value

When an admin opens an order detail page, they can immediately see all critical customer and delivery context needed to support, investigate, and resolve the order.

## Requirements

### Validated

- The admin panel can list orders and open an order detail page.
- The backend exposes admin order list and admin order detail endpoints.

### Active

- [ ] Admin can see customer name and phone on order detail pages.
- [ ] Admin can see delivery location details on order detail pages.
- [ ] Admin order detail API returns enriched customer and address fields in a stable response contract.
- [ ] UI handles missing identity/location data safely with clear fallbacks.

### Out of Scope

- Editing customer profile data from order detail.
- Building new map infrastructure beyond using existing stored coordinates/address.

## Context

The current admin order detail view in admin/app/(admin)/orders/[id]/page.tsx shows customer ID but not customer name, customer phone, or full address context. Backend handler backend/internal/handlers/admin_handler.go currently returns raw order documents from Appwrite without enriching customer and address records.

## Constraints

- Tech stack: Must preserve existing Next.js admin + Go backend + Appwrite data model.
- Security: Expose only required customer contact/location fields for admin operations.
- Compatibility: Keep existing order response keys working while adding new enriched fields.
- Delivery speed: Keep changes scoped to the admin order detail flow.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Enrich admin order detail from backend instead of client-side multi-fetch | Keeps API contract centralized and avoids UI N+1 calls | Pending |
| Preserve existing fields and add optional enriched fields | Reduces regression risk in admin UI | Pending |
| Phase targets order detail visibility only | Fast, high-value operational improvement | Pending |

---
Last updated: 2026-04-03 after phase bootstrap for admin order detail planning
