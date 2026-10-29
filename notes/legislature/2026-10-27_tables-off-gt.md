# Tables off gt — session log (2026-10-27)

Moved every legislature page off gt. Pushed to `origin/main` as four commits:

| Commit | Page |
|---|---|
| `003a2632` | bill pages (`site/templates/session/bill_template.qmd`) |
| `8065fd6d` | legislator pages (`site/templates/legislator_template.qmd`) |
| `4acce818` | committee pages (`site/templates/session/committee_template.qmd`) |
| `87096269` | legislation index (`site/legislation/index.qmd`) |

## Why drop gt

Raised by two bill-page screenshots: the History table floated mid-card, and
the empty Votes / Lobbyist / Calendar tabs printed monospace text.

- **Per-table CSS.** gt writes ~9 KB of `<style>` into every table, identical
  apart from the table id — 17% of bill-page weight in the 2026-10-25 profile.
- **Centered by default** (`table.align`), which is why History floated.
- **`opt_interactive()` is reactable underneath**, with worse control:
  `tab_style(cell_text(whitespace = "nowrap"), cells_body(...))` turned into
  per-row JavaScript, 6.4 MB of the 7.7 MB legislation index.
- The legislature pages barely used gt's strengths (number formatting,
  spanners, footnotes). Campaign finance does, so it stays on gt for now.

## The rule

- **Small tables → `ui_table()`** (`R/ui_helpers.R`): static HTML, styled by
  `.ia-table` in `custom.scss`. `.ia-table` shares its base rules with the
  week archive's `.ia-week-table` rather than replacing it, because
  already-rendered archive pages carry only the old class. Cells can be text,
  numbers or htmltools tags (a list column); `NA` shows as "—".
- **Tables that need search → plain `reactable()`**, until
  `ia_reactable_theme()` exists.
- **Empty states → `ui_empty()`**, never `cat()` in a normal chunk: knitr
  prints that as a code block. In a `results: "asis"` chunk, wrap raw HTML in a
  ```` ```{=html} ```` fence (`cat_html()` in the bill template) so pandoc
  doesn't read indented markup as code.

## Per page

**Bill.** History, Lobbyist and Calendar → `ui_table()` with readable dates
("Mar 18, 2025", "3:00 PM"). Votes tab rebuilt in one asis chunk: no floor
votes → one empty state, with no orphan headings or empty nested tabset;
otherwise a summary table (party columns as yea–nay; absent + NV merged as
"Not voting", as the Iowa journals record them), then one panel per roll call
with the question, a one-line result in words, the map, and the full roll call
collapsed in `<details>` with names linked to legislator pages. The per-vote
party gt table was dropped as redundant. Lobbyist tab now says "none filed"
for zero rows (it used to say "unavailable"). SJR11 0.66 → 0.35 MB.

**Legislator.** All 7 tables → `ui_table()`. Titles via `clean_bill_title()`
(it is not vectorized: map it), voting record newest first, one empty state
for the vote-analysis and similarity tabs. **Fixed** the "Similar legislators"
404 (`../{name}.html` → `{name}.html`). Jacoby 802 → 409 KB.

**Committee.** 3 tables → `reactable()` (search, 25 per page, newest first;
the bill column holds "HF 123" so search matches what readers see). Got the
redesign it had missed: header card, tabset in a card, `toc: false`.
**Fixed:** every committee page was titled "committee_template" (H1 and
browser tab) and showed an internal Committee ID; Senate Ways & Means matched
0 of its 67 votes ("&" in the people record, "And" in vote descriptions —
the pattern now accepts either). House Education 590 → 166 KB.

**Legislation index.** 4,231-row table → `reactable()` keeping search,
per-column filters and page-size options. Links, status pills and dates are
drawn by one JS function per column, so the page carries data, not markup:
**8.0 → 0.97 MB**. `status_pill_js` mirrors `status_pill()` — change both.

## Verification

Each page test-rendered locally (bills HF856 / HCR105 / SJR11; legislators
6970 / 19548 / 22687; committees 7061 / 7132 / 13762 / 7077; the index) and
checked in the browser: no `<pre>` or `.gt_table` left, empty states, links
resolving, reactable search and filters, no page overflow at 375 px.
Local 404s on some `ga91/` bill links were bills the nightly rollout hadn't
rendered yet, not link bugs. The rendered `docs/` files were not committed.

## Rollout

Index pages re-render every CI run, so the legislation index updates on the
first run after push. Bill, legislator and committee pages re-render only when
their LegiScan hash changes, so already-rendered pages keep gt (and the 404,
the "committee_template" title, the missing Ways & Means votes) until a forced
render. Bills still awaiting their first `ga91/` render get the new template.

## Open

- `ia_reactable_theme()` for the four reactable tables (legislation index,
  committee lists, `legislator_table()`, the week page).
- Legislator voting record (up to 833 rows) and sponsored bills (up to ~190)
  are static `ui_table()`s; candidates for reactable once themed.
- Legislator and committee bill lists show LegiScan's `status_desc`
  ("Engrossed", "Enrolled"), not the site's status scale.
- Vote summary scrolls sideways at phone width (~232 px box).
- Campaign finance templates still use gt; `site/_vote-table.qmd` is an
  unused empty stub.
