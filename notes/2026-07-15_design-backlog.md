# Design backlog — deferred findings (2026-07-15)

Found during the Impeccable critique/fix cycle (see `.impeccable/critique/` snapshots
and `notes/2026-07-11_impeccable-workflow.md`). All are source fixes + re-render.

## Bill detail pages (pre-existing, exposed by post-fix spot-check)

1. ~~**Share-bar legend contrast**~~ — **FIXED 2026-07-15.** `ui_share_bar()`
   legend now renders the ● dot in the category color and label text in ink
   (16.07:1, was 1.61:1). Residual note: the pale Undecided dot itself
   (`#cfccc2`) is a non-text swatch below the 3:1 non-text guideline; meaning
   is carried by the adjacent label, but darkening the Undecided palette color
   would clear it fully (touches the bar segment too).

2. ~~**Progress stepper clips on mobile**~~ — **FIXED 2026-07-15.** `.ia-stepper`
   stacks vertically ≤600px (dot + label rows, short vertical connector lines);
   verified all 6 steps visible at 375px (right edge 225px, was 781px clipped),
   desktop row layout unchanged.

## Home page (P3s from the 2026-07-14 critique re-run)

3. **Tally dash contrast** — decorative "–" in `tally()` (`site/index.qmd`)
   is `#b5b2a8` = 2.12:1 (needs 3:1 at that size). Darken to `$faint` `#706c63`.

4. **Funnel structure (deferred by choice)** — "Where bills stand" is still
   visually non-monotonic; option (b)/(c) from the fix plan (separate terminal
   vs in-progress stages, or true unique-bill funnel) remains open.

5. **LegiScan jargon glossing (P2)** — recent-activity strings ("Message from
   House. S.J. 879.", "HSB 780") unglossed for non-experts. Candidate:
   `/impeccable clarify` pass over activity rows + bill-prefix tooltips.

## Index-page critiques, 2026-07-15 (see `.impeccable/critique/` snapshots)

Legislation index scored 32/40, legislators index 34/40. Fixed same day:
the `.g-col-*` mobile collapse gap (was only `.g-col-6`) and the FORMER chip
contrast/size (`$ink-soft`, 0.7rem). Remaining:

6. **Mobile map treatment (P2, legislators index)** — inside card + tabset
   padding the visible Leaflet map is a ~233px-wide, 444px-tall sliver at
   375px. Options: shorter mobile height, reduced card padding, or full-bleed
   map inside the card ≤600px. Candidate: `/impeccable adapt`.

7. **Browse-table font (P3, legislation index)** — 12px + 4px row padding is
   aggressive for a broad non-expert audience; consider 13px.

8. **Asterisk convention (P3, legislation index)** — "* = group progressed
   further than this bill" lives only in the card sub; the Group Status column
   header carries no hint (tooltip candidate).

9. **Senate default tab (P3, legislators index)** — arbitrary; consider House
   first (100 districts, the more common lookup).

10. **Feature idea: address/town lookup** — "enter your town → your two
    legislators." Highest-leverage feature for the non-expert audience (Jordan
    doesn't know their district number). Scope via `/impeccable shape`.

## Reminder

- Theme fixes (`$faint`, breakpoints, label demotions) are verified on test-rendered
  pages but reach the full site only after the pending `render_site(force = TRUE)`.
