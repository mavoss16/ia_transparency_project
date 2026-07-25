---
target: docs/legislation/index.html
total_score: 32
p0_count: 0
p1_count: 1
timestamp: 2026-07-15T23-01-02Z
slug: docs-legislation-index-html
---
# Critique — docs/legislation/index.html (legislation browse)

Method: ⚠️ DEGRADED: single-context (harness policy — sub-agents not spawned unless explicitly requested; Assessment A locked before detector ran)
Register: product · Platform: web · Fresh render (2026-07-15 test-render cycle).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | "Most recent activity · date" in card head; active nav |
| 2 | Match System / Real World | 3 | Type abbreviations glossed (HF House File …); raw LegiScan action strings remain |
| 3 | User Control and Freedom | 3 | Search, filters, pagination all reversible |
| 4 | Consistency and Standards | 4 | Same `.ia-*` system as home |
| 5 | Error Prevention | 3 | Filters constrain input; n/a mostly |
| 6 | Recognition Rather Than Recall | 3 | Group-status asterisk convention lives only in the card sub |
| 7 | Flexibility and Efficiency | 4 | Search + 7 column filters + page-size select — genuinely good |
| 8 | Aesthetic and Minimalist Design | 3 | Clean; 12px table density is aggressive for the audience |
| 9 | Error Recovery | 3 | n/a static |
| 10 | Help and Documentation | 3 | Abbreviation glossary + explanatory subs — real contextual help |
| **Total** | | **32/40** | **Good** |

## Anti-Patterns Verdict
Passes. Detector: 1 warning (monotonous spacing, ~4px × 73%) — **false positive**: it's the gt table's deliberate `data_row.padding = px(4)` across rows, not layout spacing. Zero uppercase-tracked labels; zero contrast failures (the token fix propagated).

## What's Working
1. **The abbreviation glossary footnote** ("HF House File · SF Senate File · …") is the "legible to the newcomer" principle in action — teaching at the exact point of need.
2. **Paired bars have a real legend** (Individual bill / Bill group) plus an explanatory sub — the group-status concept is handled better here than the home funnel was pre-fix.
3. **The browse table earns its density**: search + per-column filters + page size, 0 contrast failures at 12px.

## Priority Issues
- **[P1] `.g-col-5` / `.g-col-7` don't collapse on mobile.** At 375px "Bills by type" is crushed to 120px and "Status summary" to 179px — unusable. The 2026-07-13 fix only covered `.g-col-6`. Fix: extend the media query to all `.g-col-*` spans (e.g. `[class*="g-col-"] { grid-column: span 12 }` under 768px). One-line change in site/custom.scss.
- **[P3] 12px table font + 4px row padding** for the primary browse surface. Legal (contrast passes), product register allows density, but small for a broad non-expert audience. Consider 13px.
- **[P3] Asterisk convention** ("* = group progressed further") explained only in the sub above the table; the Group Status column header itself carries no hint.
- **[P3] Raw LegiScan action strings** in recent rows (same backlog item as home).

## Persona Notes
**Casey (Mobile):** the two summary cards are unreadable at phone width (P1 above); the table itself scrolls correctly inside its container.
**Alex (Power User):** well served — filters, search, page-size select, sortable columns.

## Questions to Consider
- Is "Recent bills" on this page redundant with home's "Recent activity" (same 8 bills)? Could this page lead with the browse table instead?
