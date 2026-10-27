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

## Vote maps at phone width (found 2026-10-25)

On a 375 px viewport the bill page's vote map is only ~198 px wide (nested
card + tab padding), so Iowa is small and the legend covers much of it.
Predates the shared-geometry change. Options: let the map break out of the
card padding on mobile, shrink or collapse the legend below ~600 px.

## Weekly activity summary, after the P1 fixes (2026-10-26, critique 28/40)

- **`ia_reactable_theme()`** (P2, sitewide): reactable's cool header rule, 3px
  search/page buttons and default pagination don't match the site. Fold the new
  `:focus-visible` rules into it. Applies to `legislator_table()` too.
- **Resolutions lead busy weeks** (P2): at equal stage, sort substantive bills
  (salience `bill_class`) before resolutions/commemoratives.
- **Phones hide "Status now"** on the week page (P2): show the status pill
  under the title after the event chip.
- **"✓ Vetoed"** stepper step is drawn in success green (P3): give
  `ui_stepper()` an end-state class.
- Week-page footnote runs ~184 chars per line; empty search still shows reactable's
  "No rows found".

## Tables: gt → `ui_table()` / reactable (started 2026-10-27)

Decision: legislature pages drop gt. Small tables become static HTML from
`ui_table()` (`R/ui_helpers.R`, styled by `.ia-table`, which shares its base
rules with the week archive's `.ia-week-table`); large tables that need
sorting or search become reactable once `ia_reactable_theme()` exists.
Empty states use `ui_empty()` instead of `cat()`, which knitr printed as a
monospace code block. Campaign finance keeps gt for now.

- **Done — bill page** (`site/templates/session/bill_template.qmd`): History,
  Votes, Lobbyist declarations and Calendar tabs; no gt left in the template.
  Votes tab: one empty state when there are no floor votes (no orphan
  headings); summary table with party columns as yea–nay; each roll call
  panel opens with the question and a one-line result in words (replaces the
  per-vote party gt table); the full roll call sits in a collapsed
  `<details>`, names linking to legislator pages. SJR11 0.66 → 0.35 MB.
- **Done — legislator page** (`site/templates/legislator_template.qmd`,
  2026-10-27): all 7 gt tables → `ui_table()`, no gt left. Bill titles go
  through `clean_bill_title()`; the voting record is newest first; vote
  analysis and similarity show one empty state instead of a heading per
  table. Fixed the "Similar legislators" 404 (links were `../{name}.html`).
  Pages roughly halve: Jacoby 802 → 409 KB, Bossman 720 → 371 KB.
- **reactable candidates once the theme exists:** the legislator voting
  record (up to 833 rows, static for now) and sponsored bills (up to ~190).
- **Next:** committee template (3 `opt_interactive()` tables → reactable),
  legislation index (the 6.4 MB per-row JS), then `ia_reactable_theme()`.
- **Phone width:** the 10-column vote summary scrolls sideways inside a
  ~232 px box (nested card + tab padding, same cause as the vote maps above).
  Candidates: hide Not voting / Pattern below 600 px, or let tab content
  break out of the card padding.
- **Rollout:** bill pages re-render only when their LegiScan hash changes, so
  pages rendered before this change keep the gt tables until a forced render.
