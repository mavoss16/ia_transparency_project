---
target: docs/index.html (home) re-run
total_score: 32
p0_count: 0
p1_count: 0
timestamp: 2026-07-14T02-50-18Z
slug: docs-index-html
---
# Critique — docs/index.html (home) · re-run after P1–P3 fixes

Method: ⚠️ DEGRADED: single-context (harness policy — sub-agents not spawned unless explicitly requested; Assessment A locked before detector ran)
Register: product · Platform: web · Fresh render verified (docs newer than scss/qmd).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | unchanged — "Last updated", active nav |
| 2 | Match System / Real World | 3 | funnel now explained upfront; legislative jargon in activity rows remains |
| 3 | User Control and Freedom | 3 | unchanged |
| 4 | Consistency and Standards | 4 | unchanged — tight `.ia-*` system |
| 5 | Error Prevention | 3 | n/a |
| 6 | Recognition Rather Than Recall | 3 | unchanged |
| 7 | Flexibility and Efficiency | 3 | unchanged |
| 8 | Aesthetic and Minimalist Design | 4 | ↑ from 3 — one kicker instead of label grammar; cleaner hierarchy |
| 9 | Error Recovery | 3 | n/a |
| 10 | Help and Documentation | 3 | counting rule now inline, above the chart |
| **Total** | | **32/40** | **Good** |

## Anti-Patterns Verdict

Passes. Detector: `[]` (clean). Exactly **one** uppercase-tracked element remains on the page (`.ia-eyebrow` hero kicker) — measured in-browser; the former label grammar is gone. No other tells.

## What Changed Since Last Run (verified in-browser)

- Full-page contrast sweep: **2 failures left, down from ~6 classes** — and both are the decorative en-dash "–" separators in the tallies (`#b5b2a8` at 2.12:1 vs 3:1 large-text requirement). Every real text element passes.
- Mobile 375px: no horizontal overflow; widest element right edge 350px; recent rows restack via grid areas; side-by-side cards span 12.
- Tally reads "R 67 – 33 D" (letters, not color-only). Hero sources are links. Funnel counting rule sits above the bars.

## Remaining Issues

- **[P3] Decorative tally dash fails large-text contrast** — `#b5b2a8` on white, 2.12:1 (needs 3:1 at 23px). One hex in the `tally()` helper in site/index.qmd; darken to ≥ #949087 or reuse $faint `#706c63`. Arguably decorative punctuation, but it's a one-character fix.
- **[P2] Legislative jargon in recent-activity rows** — "Message from House. S.J. 879.", "HSB 780", "Amendment H-8400 withdrawn" are unglossed for the non-expert primary audience. The last-action strings come straight from LegiScan. Fix: tooltip/gloss for bill-number prefixes (HF/SF/HSB/SSB) and journal citations, or a plain-language rewrite layer. Command: /impeccable clarify.
- **[P3] Funnel remains visually non-monotonic** — mitigated by the new sub; the fuller fix (separating terminal vs in-progress stages) was deliberately deferred (option b/c).
- **[P3] Card-count observation stands** — 4 stat + 2 analytical + 1 activity + 2 browse cards; no nesting, all defensible, but watch it as sections get added.

## Persona Notes

**Jordan (First-Timer):** the funnel confusion is resolved — the counting rule now precedes the bars in AA-passing text. Remaining friction is the LegiScan action strings ("S.J. 879.").
**Casey (Mobile):** clean at 375px — nothing clipped, cards stack, tap targets are full-width rows.

## Questions to Consider

- The visual-identity question (warm cream + serif: chosen or inherited?) is still open — it predates and survives these fixes.
- Recent-activity strings: gloss in place, or link "S.J. 879" to the journal PDF and let curiosity do the work?
