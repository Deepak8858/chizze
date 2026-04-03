# Phase 1: Admin Order Detail Enrichment - Research

Researched: 2026-04-03
Domain: Next.js admin order detail + Go admin API enrichment
Confidence: HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Backend admin order detail endpoint must enrich the order response with customer identity and delivery address/location fields.
- D-02: Existing order response keys must remain intact while adding optional enriched fields.
- D-03: Admin order detail page at /orders/:id must render customer name, customer phone, and location details in the Customer section.
- D-04: UI must provide safe fallbacks when enriched fields are missing.
- D-05: This phase is focused on detail visibility only, not customer profile editing.

### the agent's Discretion
- Naming of added enriched fields.
- Exact placement and minor UI styling details.
- Optional quick actions like tel: and map links if already consistent with admin patterns.

### Deferred Ideas (OUT OF SCOPE)
- Embedded map widget redesign.
- Customer profile drill-down/history panel.

</user_constraints>

<research_summary>
## Summary

Current admin order detail flow fetches GET /api/v1/admin/orders/:id through admin/lib/api.ts and renders in admin/app/(admin)/orders/[id]/page.tsx. The page currently shows customer_id only and has no direct rendering for customer_name, customer_phone, or resolved address fields.

Backend handler backend/internal/handlers/admin_handler.go currently returns the raw order document from Appwrite in GetOrder. Appwrite service already provides GetUser and GetAddress helpers, so enrichment can be implemented in handler layer without changing route wiring.

Primary recommendation: enrich GET /admin/orders/:id in backend with joined customer and address fields, keep existing order keys unchanged, then extend admin Order typing and UI card rendering with explicit fallback behavior.
</research_summary>

<standard_stack>
## Standard Stack

### Existing stack used for this feature
| Library | Purpose | Why it should be used here |
|---------|---------|----------------------------|
| Next.js App Router + React Query | Admin order detail data fetching and rendering | Already used by order detail page; no new fetch architecture needed |
| Go Gin handlers | Admin API contract and response shaping | Existing admin route and handler pattern |
| Appwrite collections (orders, users, addresses) | Source of customer and location data | Existing persistence and IDs already linked from order |

### Alternatives considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Backend enrichment | Client-side multi-fetch from admin app | Higher latency, more API calls, weaker contract control |
| Extend via separate endpoint | Keep GET /admin/orders/:id unchanged + extra endpoint | Additional complexity and coordination overhead |

</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended response shape pattern
- Keep original order payload fields.
- Add optional enriched fields in same payload:
  - customer_name
  - customer_phone
  - customer_email
  - delivery_address_line
  - delivery_city
  - delivery_latitude
  - delivery_longitude

### Backend composition pattern
1. Load order by id.
2. If customer_id exists, fetch user document and map safe identity fields.
3. If delivery_address_id exists, fetch address document and map location fields.
4. Return merged payload via utils.Success.

### UI rendering pattern
- Update Order type with optional enriched fields.
- Render customer name and phone first-class in Customer card.
- Render address text and map coordinates (or map link) in same card.
- Show explicit fallback labels such as Not available.

### Anti-patterns to avoid
- Do not replace or rename existing keys already used by admin screens.
- Do not assume every order has complete address coordinates.
- Do not expose unnecessary PII beyond operational need.

</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Do not build | Use instead | Why |
|---------|--------------|-------------|-----|
| Multi-endpoint client orchestration | New client aggregator layer | Existing backend handler enrichment | Fewer requests, centralized contract |
| New customer search pipeline | Additional lookup services | Existing Appwrite GetUser and GetAddress | Already available and sufficient |

Key insight: this is a contract-completeness problem, not a new subsystem problem.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Breaking existing admin typing
What goes wrong: replacing current fields causes runtime undefined reads.
How to avoid: add optional enriched fields and preserve existing keys.

### Pitfall 2: Missing-data crashes
What goes wrong: UI assumes customer or address fields always exist.
How to avoid: null-safe rendering with clear fallback text.

### Pitfall 3: Unbounded PII exposure
What goes wrong: backend returns full user profile unnecessarily.
How to avoid: map only name, phone, email, and delivery-location fields needed for operations.

</common_pitfalls>

## Validation Architecture

- Backend contract check should verify enriched fields exist for known seeded order IDs.
- Admin UI check should verify customer and location rows render with fallback when fields absent.
- Regression check should confirm existing fields in order payload remain unchanged.

Suggested automated checks:
- Go focused tests: go test ./internal/handlers -run Admin
- Admin lint/type check: npm run lint (admin)

</metadata>

Phase: 01-admin-order-detail-enrichment
Research completed: 2026-04-03
Ready for planning: yes
