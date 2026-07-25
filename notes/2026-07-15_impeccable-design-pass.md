# Impeccable design pass — critique + accessibility fixes (2026-07-11 → 2026-07-15)

Session log for the first full Impeccable cycle: project context capture, scored
critiques of the three index pages, and the fixes that came out of them. Companion
files: [`PRODUCT.md`](../PRODUCT.md) (strategic brief), `.impeccable/critique/`
(scored snapshots), [`2026-07-15_design-backlog.md`](2026-07-15_design-backlog.md)
(open items), [`2026-07-11_impeccable-workflow.md`](2026-07-11_impeccable-workflow.md)
(how to use the skill).

## What happened, in order

1. **`/impeccable init` (2026-07-11)** — wrote `PRODUCT.md`: register `product`,
   platform `web`, broad-public audience, "accessible + connected" positioning,
   WCAG 2.1 AA target, 5 design principles. Added a **Design Context** section to
   `CLAUDE.md`. DESIGN.md deliberately deferred — the `custom.scss` visual system
   (fonts/colors) is not locked in yet.
2. **Critique: home** (`docs/index.html`) — **31/40**, detector clean, 2 P1s.
3. **Fix phases 1–3** (approved plan, executed 2026-07-13):
   - **P1a contrast:** `$faint` `#8a877e` → `#706c63` in `site/custom.scss`
     (was 3.32–3.59:1 on its backgrounds; now 5.23:1 on white / 4.84:1 on `$bg`).
   - **P1b mobile:** new `@media (max-width: 600px)` block — `.ia-recent-row`
     restacks via grid areas, `.ia-browse-grid` → 1 column, `.ia-bar-row` labels
     go full-width; `.ia-hero-row` got `flex-wrap: wrap`; `.g-col-*` collapse
     added at ≤767px.
   - **P2 funnel:** "Where bills stand" card sub now states the counting rule
     ("each bill counted once, at the furthest stage reached") above the bars
     (`site/index.qmd`).
   - **P2 typography:** uppercase-tracked treatment reserved for the hero
     `.ia-eyebrow` only; `.ia-stat-label`, `.ia-tally-label`, `.ia-split-label`
     demoted to sentence case with small size bumps.
   - **P3s:** tally reads "R 67 – 33 D" (not color-only); hero data sources are
     links.
4. **Re-critique: home** — **32/40**, P1 count 2 → 0. Trend started.
5. **Test render** (5 bills / 5 legislators / 3 committees, 0 failures) +
   `render_index_pages()` — verified the theme changes propagate to detail and
   index pages with no regressions. Spot-checks exposed two pre-existing
   bill-page defects (item 6 below).
6. **Critiques: legislation index 32/40, legislators index 34/40** (2026-07-15).
   New finds fixed same day:
   - `.g-col-5/7` didn't collapse on mobile (the 07-13 fix only covered
     `.g-col-6`) → media query now matches `[class*="g-col-"]`.
   - FORMER chip 4.46:1 → `$ink-soft` at 0.7rem = **6.65:1** (matches
     `.ia-pill-neutral` on the same background).
   - `ui_share_bar()` legend colored its *text* with the swatch color
     ("● 0 Undecided" at 1.61:1) → dot keeps the color, text is ink (16.07:1)
     (`R/legislature/ui_helpers.R`).
   - `.ia-stepper` clipped at 375px (fixed 108px nodes ran to ~781px, silently
     cut) → vertical stack ≤600px; all 6 stages visible, desktop unchanged.

## Files changed

| File | Changes |
|---|---|
| `site/custom.scss` | `$faint` token; mobile breakpoint block (recent rows, browse grid, bar rows, stepper, `.g-col-*`); hero flex-wrap; label case demotions; FORMER chip color/size |
| `site/index.qmd` | funnel card sub/footnote copy; `tally()` R/D letters; hero source links |
| `R/legislature/ui_helpers.R` | `ui_share_bar()` legend: swatch dot + ink text |
| `PRODUCT.md` | new (strategic design brief) |
| `CLAUDE.md` | Design Context section; redesign-status update |
| `notes/2026-07-15_design-backlog.md` | new (open items 3–10 + fixed-item log) |

## Verification method

Screenshots time out in this harness environment, so verification was DOM-probe
based via the `docs-preview` server (port 8642): WCAG luminance-ratio sweeps over
every text-bearing element, computed-style checks (grid templates, flex direction,
text-transform), bounding-rect overflow checks at 375px/1280px, and Leaflet
tile/visibility checks for the tabbed maps. The Impeccable detector (`detect.mjs`)
ran on all three rendered pages: clean, except one false positive on the
legislation page (gt table row padding read as "monotonous spacing").

## State + open items

- Scores: home 31→32 · legislation 32 · legislators 34. **Zero P1s open** across
  all critiqued pages; all fixes verified on freshly rendered output.
- Remaining backlog (details in `2026-07-15_design-backlog.md`): home P3s (tally
  dash contrast, funnel restructure option b/c, LegiScan jargon glossing), mobile
  map sliver on legislators (~233px), 12px browse-table font, group-status
  asterisk tooltip, Senate-vs-House default tab, address/town lookup feature idea.
- **Gate to publishing: `render_site(force = TRUE)`** — every `custom.scss` and
  `ui_helpers.R` change here reaches the ~4,000 already-rendered detail pages
  only after the full re-render (Quarto hashes the compiled theme CSS per render;
  old pages reference the old hash).
