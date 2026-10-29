# Design backlog — deferred findings (2026-07-15)

> **Open items moved to [`ROADMAP.md`](../../ROADMAP.md) on 2026-10-28.** This note keeps the detail behind them (measurements, options considered); add new design tasks to the roadmap, not here.

Found during the Impeccable critique/fix cycle (see `.impeccable/critique/` snapshots
and `notes/site/2026-07-11_impeccable-workflow.md`). All are source fixes + re-render.

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
rules with the week archive's `.ia-week-table`); tables that need sorting or
search become plain `reactable()` (themed later by `ia_reactable_theme()`).
Full session log: `notes/legislature/2026-10-27_tables-off-gt.md`.
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
- **Done — committee page** (`site/templates/session/committee_template.qmd`,
  2026-10-27): the 3 `opt_interactive()` gt tables → plain `reactable()`
  (search, 25 per page, sorted newest first; search matches "HF 123" as
  shown). The page also got the redesign it had missed: header card
  (eyebrow, serif name, counts), tabset in a card, `toc: false`. Fixed: every
  live committee page was titled "committee_template" (H1 and browser tab)
  and showed an internal Committee ID; Senate Ways & Means matched 0 of its
  67 committee votes ("&" in the name, "And" in vote descriptions). Pages
  shrink 60–75%: House Education 590 → 166 KB, Commerce 363 → 94 KB.
- **Status vocabulary:** the legislator and committee bill lists still show
  LegiScan's `status_desc` ("Engrossed", "Enrolled"), not the site's status
  scale used by bill pages and pills. Swap in the `groups.rds` bill status.
- **Done — legislation index** (`site/legislation/index.qmd`, 2026-10-27):
  the 4,231-row `opt_interactive()` gt table → plain `reactable()` with
  search, per-column filters and page-size options, as before. Bill links,
  status pills and dates are drawn by one JS function per column
  (`status_pill_js` mirrors `status_pill()`, so keep them in step), so the
  page carries data, not per-row markup: **8.0 MB → 0.97 MB**. Status is now
  a pill; titles go through `clean_bill_title()`. Index pages re-render on
  every CI run, so this reaches the live site on the first run after push.
- **No gt left on the legislature side.** Campaign finance still uses gt.
- **Next:** `ia_reactable_theme()` for the four reactable tables
  (legislation index, committee lists, `legislator_table()`, the week page),
  then the legislator voting record and sponsored bills as reactable.
- **Phone width:** the 10-column vote summary scrolls sideways inside a
  ~232 px box (nested card + tab padding, same cause as the vote maps above).
  Candidates: hide Not voting / Pattern below 600 px, or let tab content
  break out of the card padding.
- **Rollout:** bill pages re-render only when their LegiScan hash changes, so
  pages rendered before this change keep the gt tables until a forced render.
