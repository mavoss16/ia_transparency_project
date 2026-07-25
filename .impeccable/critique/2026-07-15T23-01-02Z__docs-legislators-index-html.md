---
target: docs/legislators/index.html
total_score: 34
p0_count: 0
p1_count: 0
timestamp: 2026-07-15T23-01-02Z
slug: docs-legislators-index-html
---
# Critique — docs/legislators/index.html (legislators browse)

Method: ⚠️ DEGRADED: single-context (harness policy — sub-agents not spawned unless explicitly requested; Assessment A locked before detector ran)
Register: product · Platform: web · Fresh render (2026-07-15 test-render cycle).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Active tab state; district hover highlight; last-updated in footer |
| 2 | Match System / Real World | 4 | "Find your legislator" + a clickable district map = the user's own mental model |
| 3 | User Control and Freedom | 3 | Tabs, sortable/searchable table |
| 4 | Consistency and Standards | 4 | Same system; FORMER chip convention explained in footer |
| 5 | Error Prevention | 3 | n/a mostly |
| 6 | Recognition Rather Than Recall | 3 | Map requires knowing your district; table parity mitigates |
| 7 | Flexibility and Efficiency | 4 | Two full paths to every profile (map click, table search/sort) |
| 8 | Aesthetic and Minimalist Design | 4 | Confident map+table pairing; detector clean; zero uppercase |
| 9 | Error Recovery | 3 | n/a static |
| 10 | Help and Documentation | 3 | Footer explains alignment/participation stats + chip |
| **Total** | | **34/40** | **Good — strongest page so far** |

## Anti-Patterns Verdict
Passes. Detector: `[]` clean. Zero uppercase-tracked labels. The map+table pairing is a real product decision, not template scaffolding.

## What's Working
1. **Map + table parity** — every profile reachable by clicking a district *or* searching/sorting the table. Mouse-free and map-blind users get full equivalence; this quietly satisfies both the "connections" pillar and accessibility.
2. **Hidden-tab Leaflet init works** — House map renders correctly on tab reveal (verified: 1044×444, tiles loaded). The classic htmlwidgets-in-tabset bug isn't present.
3. **Split bars carry R/D letters** ("67 R · 33 D") — not color-only.

## Priority Issues
- **[P2] FORMER chip misses AA by a hair** — `#706c63` on `$neutral-bg` `#eeede7` = **4.46:1** (needs 4.5). The new `$faint` passes on white/page-bg but not on this darker chip background. Fix: chip text to `$muted` `#6d6a62`, or lighten the chip bg. One token in site/custom.scss (`.ia-chip-former`).
- **[P2] Map is a 233px sliver on phones** — card + tabset padding chain leaves ~233px for a 444px-tall map; Iowa renders as a skinny strip with zoom controls eating into it. Consider a mobile treatment: shorter height, reduced card padding, or letting the map bleed to card edges under 600px.
- **[P3] Chip font is 10.5px** — below the 11px floor; bump with the contrast fix.
- **[P3] Senate tab is the default** — arbitrary; most visitors are looking for their House rep (100 vs 50 districts). Consider House first.

## Persona Notes
**Jordan (First-Timer):** "Find your legislator" is the clearest entry point on the site; but Jordan doesn't know their district number — the map labels help only if they can locate themselves geographically. A future address/town search would close this.
**Sam (Accessibility):** table parity saves the page — but verify reactable keyboard sort and the FORMER chip contrast (P2).

## Questions to Consider
- Address or town lookup ("enter your town → your two legislators") — the single highest-leverage feature for the stated audience?
- Should the map default to House (more localized districts) rather than Senate?
