# Chizze Admin Panel — Web Design Specification

## Design Philosophy
Premium dark-mode admin panel consistent with Chizze's mobile app brand identity.
Dense information, clean hierarchy, fast interactions.

---

## Color System

### Brand Palette
| Token | Hex | Use |
|-------|-----|-----|
| `brand-500` | `#F49D25` | Primary CTA, active nav, focus rings, badges |
| `brand-600` | `#E8751A` | Hover/pressed states |
| `brand-400` | `#F6B34E` | Light accent, chart highlights |

### Background Layers
| Token | Hex | Use |
|-------|-----|-----|
| `bg-base` | `#0D0D0D` | Page background |
| `bg-card` | `#1A1A1A` | Cards, panels, sidebar |
| `bg-elevated` | `#252525` | Modals, dropdowns, tooltips |
| `bg-input` | `#1A1A1A` | Form inputs |
| `bg-hover` | `#2A2A2A` | Table row hover, list item hover |
| `bg-muted` | `rgba(255,255,255,0.04)` | Subtle backgrounds |

### Text
| Token | Hex | Use |
|-------|-----|-----|
| `text-primary` | `#FFFFFF` | Headings, values |
| `text-secondary` | `#A0A0A0` | Labels, descriptions |
| `text-muted` | `#666666` | Placeholders, hints |
| `text-brand` | `#F49D25` | Links, active labels |

### Borders
| Token | Value | Use |
|-------|-------|-----|
| `border-default` | `rgba(255,255,255,0.08)` | Card borders, dividers |
| `border-focus` | `#F49D25` | Input focus ring |
| `border-strong` | `rgba(255,255,255,0.16)` | Emphasized separators |

### Semantic Colors
| Token | Hex | Use |
|-------|-----|-----|
| `success` | `#22C55E` | Online, delivered, verified, approved |
| `error` | `#EF4444` | Cancelled, rejected, critical alerts |
| `warning` | `#FACC15` | SLA breach amber, pending |
| `info` | `#3B82F6` | New orders, informational |
| `rating` | `#FBBF24` | Star ratings, gold features |

### Status Badge Colors
| Status | Background | Text |
|--------|-----------|------|
| placed | `#3B82F620` | `#3B82F6` |
| confirmed | `#F49D2520` | `#F49D25` |
| preparing | `#F49D2520` | `#F49D25` |
| ready | `#22C55E20` | `#22C55E` |
| pickedUp | `#22C55E20` | `#22C55E` |
| outForDelivery | `#22C55E20` | `#22C55E` |
| delivered | `#22C55E20` | `#22C55E` |
| cancelled | `#EF444420` | `#EF4444` |
| pending | `#FACC1520` | `#FACC15` |
| active | `#22C55E20` | `#22C55E` |
| inactive | `#66666620` | `#666666` |

---

## Typography

### Font Family
**Plus Jakarta Sans** — loaded via Google Fonts (`next/font/google`)
Fallback: `system-ui, -apple-system, sans-serif`

### Type Scale
| Name | Size | Weight | Line Height | Use |
|------|------|--------|-------------|-----|
| `display` | 32px | 800 | 1.2 | Page heroes, large metrics |
| `h1` | 24px | 700 | 1.3 | Page titles |
| `h2` | 20px | 600 | 1.35 | Section headers |
| `h3` | 16px | 600 | 1.4 | Card titles |
| `body` | 14px | 400 | 1.5 | Body text |
| `small` | 13px | 400 | 1.4 | Secondary info |
| `caption` | 12px | 400 | 1.4 | Labels, metadata, badges |
| `mono` | 13px | 400 | 1.4 | IDs, codes (JetBrains Mono) |

---

## Spacing System
Base unit: 4px
Scale: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96

---

## Border Radius
| Token | Value | Use |
|-------|-------|-----|
| `rounded-sm` | 6px | Badges, chips |
| `rounded` | 8px | Buttons, inputs |
| `rounded-md` | 10px | Cards |
| `rounded-lg` | 12px | Modals, panels |
| `rounded-xl` | 16px | Large cards |
| `rounded-full` | 9999px | Avatars, pills |

---

## Layout

### Shell Structure
```
┌─────────────────────────────────────────────────┐
│  Header (60px) — Logo | Live Stats Bar | User   │
├──────────┬──────────────────────────────────────┤
│          │  Breadcrumbs (40px)                  │
│ Sidebar  │──────────────────────────────────────│
│ (240px   │                                      │
│ expand / │  Page Content                        │
│  72px    │  (scrollable, padding 24px)          │
│ collapse)│                                      │
│          │                                      │
└──────────┴──────────────────────────────────────┘
```

### Sidebar
- Width: 240px expanded / 72px collapsed (icon only)
- Background: `#1A1A1A`
- Border-right: `1px solid rgba(255,255,255,0.06)`
- Logo area: 60px height, orange wordmark "chizze" + "admin" badge
- Nav groups with labels (Real-time, Management, Analytics, Platform, Admin)
- Active item: left orange bar + orange text + subtle orange bg
- Hover: `#2A2A2A` bg
- Collapse toggle at bottom

### Header
- Height: 60px
- Background: `#1A1A1A`
- Border-bottom: `1px solid rgba(255,255,255,0.06)`
- Left: Hamburger (mobile) + breadcrumb
- Center: **Live Stats Bar** — 🟢 X Orders Active | 🏍️ Y Riders Online | 👥 Z Users Live (updates via SSE every 5s, subtle pulse animation on change)
- Right: Notifications bell (admin alerts) + Admin avatar + dropdown

### Content Area
- Background: `#0D0D0D`
- Padding: 24px
- Max content width: 1440px (centered for very wide screens)

---

## Component Specifications

### KPI Cards
```
Background:     #1A1A1A
Border:         1px solid rgba(255,255,255,0.08)
Border-radius:  12px
Padding:        20px 24px
Structure:
  - Top row: Icon (32px, colored bg circle) + Label
  - Middle: Large metric value (display size, white)
  - Bottom: Trend indicator (△/▽ % vs yesterday, green/red) + sparkline
```

### Data Tables
```
Background:         #1A1A1A
Header row:         #252525 bg, #A0A0A0 text, 13px
Body row:           14px, #FFFFFF text, 48px height
Row hover:          #2A2A2A bg
Border:             1px solid rgba(255,255,255,0.06) between rows
Sorted column:      Subtle orange tint header
Pagination:         Bottom, standard prev/next + page numbers
Selected row:       Left orange border 3px + subtle orange bg
```

### Buttons
| Variant | Background | Text | Border |
|---------|-----------|------|--------|
| Primary | `#F49D25` | `#0D0D0D` | none |
| Secondary | `transparent` | `#FFFFFF` | `rgba(255,255,255,0.16)` |
| Destructive | `#EF444420` | `#EF4444` | `1px solid #EF444440` |
| Ghost | `transparent` | `#A0A0A0` | none |
| Success | `#22C55E20` | `#22C55E` | `1px solid #22C55E40` |
- Height: 36px (default), 40px (lg), 28px (sm)
- Border-radius: 8px
- Font: 13px SemiBold

### Form Inputs
```
Height:           40px
Background:       #1A1A1A
Border:           1px solid rgba(255,255,255,0.1)
Border-radius:    8px
Focus border:     #F49D25 (2px)
Text:             #FFFFFF, 14px
Placeholder:      #666666
Prefix icon:      #666666
Label:            #A0A0A0, 13px, above input
```

### Status Badges
```
Height:        22px
Padding:       0 8px
Border-radius: 4px
Font:          12px SemiBold uppercase
Background:    color at 12% opacity
Text:          color at full opacity
```

### Cards (general)
```
Background:    #1A1A1A
Border:        1px solid rgba(255,255,255,0.08)
Border-radius: 12px
Padding:       20px
```

### Modal / Sheet
```
Overlay:       rgba(0,0,0,0.7)
Background:    #1A1A1A
Border:        1px solid rgba(255,255,255,0.1)
Border-radius: 16px (modal) / right-side sheet
Max-width:     560px (modal) / 480px (sheet)
```

### Toast Notifications (Sonner)
```
Background:    #252525
Border:        1px solid rgba(255,255,255,0.1)
Text:          #FFFFFF
Icon: colored by type (green success, red error, orange warning)
```

---

## Map Design (Live Map, Zones, Surge)

### Mapbox Style
- Base style: `mapbox://styles/mapbox/dark-v11` (dark, matches app theme)

### Rider Pins
- Size: 32px × 32px
- Idle (online, no order): green circle with bike/scooter/car icon
- On delivery: orange circle with route icon
- Offline: grey (not shown on live map by default)
- Tooltip on hover: name, phone, order ID, last seen

### Order Route Lines
- Color by status:
  - preparing/ready: `#FACC15` dashed
  - outForDelivery: `#22C55E` solid with arrow
- Width: 2px (regular), 3px (hovered/selected)

### Restaurant Pins
- Size: 28px × 28px
- Online: orange fork+knife icon
- Offline: grey

### Zone Polygons
- Fill: `rgba(244,157,37,0.1)` (active), `rgba(100,100,100,0.1)` (inactive)
- Stroke: `#F49D25` (active), `#666` (inactive), width 1.5px

### Surge Zone Polygons
- Fill: `rgba(250,204,21,0.15)`
- Stroke: `#FACC15`, width 2px, dashed

---

## Charts (Recharts)

### Color Sequence for multi-series
1. `#F49D25` (brand orange)
2. `#22C55E` (green)
3. `#3B82F6` (blue)
4. `#A855F7` (purple)
5. `#EF4444` (red)
6. `#FBBF24` (amber)

### Grid Lines
- Stroke: `rgba(255,255,255,0.06)`
- Horizontal only (mostly)

### Axes
- Tick color: `#666666`, 12px
- No axis border lines (borderless style)

### Tooltip
- Background: `#252525`
- Border: `1px solid rgba(255,255,255,0.12)`
- Border-radius: 8px
- Text: `#FFFFFF`

---

## Kanban Board (Live Order Board)

### Column
- Background: `#1A1A1A`
- Border: `1px solid rgba(255,255,255,0.08)`
- Border-radius: 12px
- Header: status badge + count chip

### Order Card
- Background: `#252525`
- Border-left: 3px solid — colored by status
- Border-radius: 8px
- Padding: 12px
- SLA-normal: `border-left: 3px solid #3B82F6`
- SLA-warning (2× expected time): `border-left: 3px solid #FACC15`
- SLA-critical: `border-left: 3px solid #EF4444` + subtle red bg tint

---

## Animations & Micro-interactions
- Page transition: 150ms fade
- Table row hover: 100ms bg transition
- Live counter update (header stats): number "flip" animation, brief orange pulse
- Kanban card move: 300ms slide + fade between columns
- Rider pin move on map: smooth interpolated movement
- Button press: scale 0.97, 100ms
- Toast slide-in: 250ms from bottom-right
- Sidebar collapse: 200ms width transition
- Skeleton loaders on all data-fetching states (shimmer from left to right, `#252525` base)

---

## Sidebar Navigation Groups & Icons

### Real-time
- 🗺️ Live Map (`/live-map`)
- 👥 Live Users (`/live-users`)
- 📋 Live Orders (`/live-orders`)

### Dashboard
- 🏠 Overview (`/`)

### Management
- 👤 Users (`/users`)
- 🍽️ Restaurants (`/restaurants`)
- 📦 Orders (`/orders`)
- 🏍️ Delivery Partners (`/delivery-partners`)
- 💸 Payouts (`/payouts`)
- ✅ Approvals → Restaurant, Rider (`/approvals/*`)
- 🧾 Disputes (`/disputes`)

### Marketing
- 🎟️ Coupons (`/coupons`)
- ⭐ Gold (`/gold`)
- 🔗 Referrals (`/referrals`)
- 🔔 Notifications (`/notifications`)
- 🖼️ Content (`/content`)

### Analytics
- 📊 SLA Monitor (`/sla`)
- 📈 Reports (`/reports`)
- 🏆 Leaderboards (`/leaderboards`)
- 🍕 Items (`/analytics/items`)
- 🏙️ Cities (`/analytics/cities`)
- 🔄 Retention (`/analytics/retention`)
- ⭐ Reviews (`/reviews`)

### Platform
- 🗺️ Zones (`/zones`)
- ⚡ Surge Pricing (`/surge`)
- 🚩 Feature Flags (`/feature-flags`)
- 📋 Audit Log (`/audit-log`)
- 🎫 Support (`/support`)

### Settings
- ⚙️ Settings (`/settings`)
- 👮 Admins (`/settings/admins`)
