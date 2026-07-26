# Campaign Finance Redesign — Shared Components, Theming, Recipient Page

**Date:** 2026-07-25

First pass of bringing campaign finance pages under the site's visual system.
Scope agreed up front: **recipient template only**, **neutral palette** (no party
colors on money), **redesign first** with manual renders rather than building
`render.R` up front. The table-weight decision stays deferred.

---

## Why the pages weren't themed

Not the templates' front matter — `recipient_template.qmd` declared nearly the
same block as `bill_template.qmd`. The cause was one line in `site/_quarto.yml`:

```yaml
render:
  - "**/*.qmd"
  - "!campaign_finance/"
```

Excluding a directory makes Quarto treat those files as **standalone documents**
rather than project members, so they got stock Bootstrap and no `custom.scss`.
The legislature templates live in `site/templates/`, which isn't excluded, which
is why they inherit the theme automatically.

Evidence, before and after, from the rendered pages:

| | Before | After | Legislature page |
|---|---|---|---|
| Bootstrap | `bootstrap-efbb37e9…` (stock) | `bootstrap-90b44afb…` | `bootstrap-90b44afb…` |
| `styles.css` | absent | present | present |

Now only the OJS variant stays excluded — it's experimental and its output is
~13 MB, not worth regenerating on every project render.

Output lands in `docs/campaign_finance/templates/`, mirroring the source path
(the legislature equivalents go to `docs/templates/`). `render.R` will move
per-entity pages to their final location, the same way `render_bill()` does.

---

## Shared component split

New top-level `R/ui_helpers.R`, beside `R/render_all.R`:

| Shared (`R/ui_helpers.R`) | Legislature (`R/legislature/ui_helpers.R`) |
|---|---|
| `ui_pill` | `clean_bill_title` |
| `ui_stat_card`, `ui_stat_grid` | `status_pill`, `vote_pill` |
| `ui_bar_list` | `ui_paired_bars` (legend names bills) |
| `ui_stepper` | `ui_profile_header` (hardcodes DEMOCRAT/REPUBLICAN) |
| `ui_share_bar` | `legislator_table` |
| `IA_PALETTE`, `ia_ramp()` | |
| `theme_ia()`, `gt_theme_ia()` | |

The domain file **sources** the shared one, so the five existing templates that
`source("R/legislature/ui_helpers.R")` needed no changes at all.

**Split rule:** if a campaign finance page and a legislation page could both call
it without either reading oddly, it's shared. `ui_paired_bars` looks generic but
its legend says "Individual bill" / "Bill group", so it stayed behind.

Two components gained a `format_value` argument, because they were built for
counts and are now also used for money — `ui_bar_list()` and `ui_share_bar()`.
Defaults reproduce the original comma-grouped integer output exactly, verified
byte-for-byte before re-rendering anything.

`IA_PALETTE` and `theme_ia()` are new. HTML components inherit color from
`custom.scss`, but ggplot and leaflet can't reach SCSS variables, so the values
are duplicated in R. **They are literals, not derived — keep them in sync.**

### Regression gate

Rendered before touching campaign finance: 3 index pages, 5 bills, legislators,
3 committees — **0 failures**. That exercises every moved and every retained
component (`ui_bar_list` and `ui_paired_bars` on the index pages, `ui_stepper`
and `ui_share_bar` on bills, `ui_profile_header` and `vote_pill` on legislators).

---

## Recipient page

Restructured the top of the page to the legislature detail-page vocabulary:
breadcrumb → header card (eyebrow + serif title + meta row) → 4-up stat grid →
a two-card grid (largest donors as a bar list, source-of-funds as a share bar) →
existing tabset. The long `gt` tables are untouched pending the table decision.

Chart colors: nine uses of `#2C5F8A` plus `#E07B2A`, `#FF8C00`, `#C04A2A`, and
the blue map ramp all replaced with `IA_PALETTE` values and `theme_ia()`. The
Iowa map now uses the neutral `ia_ramp()` with green city dots. Zero hardcoded
hex colors remain in the template.

Per the neutral-palette decision, party appears as a **text label in the meta
row**, never as a fill color.

### Two bugs the render surfaced

**Share-bar legend printed raw numbers.** `ui_share_bar()` was built for
lobbyist counts and formatted with `sprintf("%d")`, so the funding split read
`31248989 Individual`. Fixed by the `format_value` argument; now reads
`$31,248,989 Individual`.

**`District 0` on statewide committees.** The registry stores district `"0"` as
a placeholder for statewide offices, which passed the empty-value guard. The
`field()` helper now also drops whitespace-only values and the literal string
`"NA"` (which survives some IECDB exports), and district `"0"` is suppressed at
the call site.

### Verified

| Committee | Type | Result |
|---|---|---|
| 5185 Rob Sand for Iowa | Governor (statewide) | eyebrow GOVERNOR, no district shown, $32,628,827 / 90,855 donors / 223,225 contributions matching `committee_summary` |
| 2408 Sorensen For Iowa | State House | eyebrow STATE HOUSE, District 23 and County Adair both shown |

Page loads the themed navbar, breadcrumb, and all `.ia-*` components
(`ia-stat-grid` ×1, `ia-stat-card` ×4, `ia-bar-list`, `ia-share-bar`,
`ia-footnote`). 580 KB — essentially unchanged, since the weight is the
deferred 1,000-row table, not the new components.

---

---

## Third committee: Lahn for Governor (SWGA51409)

Rendered as a spot-check because the code is alphanumeric — the exact shape that
caused the original `Could not convert string 'CTY51640' to INT32` failure. It
passed straight through, confirming the `as.character()` coercion holds in the
redesigned template.

$3,718,702 raised across 733 contributions from 577 donors, Nov 2025 – May 2026.
Notably 68% self-funded: Zach Lahn is his own largest donor at $2,521,569.
Funding is 98.7% individual with no committee transfers at all.

### Artifact collision — a constraint on `render.R`

The page initially displayed a chart showing ~$30M spread over 2016–2026, which
contradicted its own $3.7M topline. Cause was **not** the template: an earlier
`quarto render ... -P committee_code:5185 --output recipient_5185.html` had been
run to test a conditional. `--output` is a **no-op inside a Quarto project**, so
that render discarded its HTML — but still regenerated the shared
`recipient_template_files/figure-html/*.png`. The result was Lahn's HTML pointing
at Rob Sand's charts. Timestamps gave it away: HTML at 16:39, several figures at
18:51.

**Constraint for `R/campaign_finance/render.R`:** every parameterized render must
be given a distinct `output_file`, or they share one `_files` directory and
silently clobber each other's figures. `render_bill()` already does this
(`output_file = basename(output_file)` → `HCR1.html` + `HCR1_files/`), so the
pattern carries over — it was the manual workflow that was anomalous. Note the
failure is silent and produces a page whose numbers contradict its own charts,
which is worse than an error.

### Fixed: fractional year axis

With only two years of data, `scales::breaks_pretty()` emitted `2024.5`,
`2025.0`, `2025.5` on the x axis. Added `ia_year_breaks()` to `R/ui_helpers.R`:
uses the actual years when there are ≤10, thins with `pretty()` beyond that.
Verified at 2, 10, 30 years and on empty input. Both charts in the Contributions
Over Time tab now use it, and bar width is capped at 0.7 so two-year series
don't render as slabs.

---

## Follow-ups

- **`pagetitle` falls back to the committee code**, so the browser tab reads
  "5185" rather than the committee name. YAML front matter is evaluated before
  the R chunks, so it can't see the looked-up name; `render.R` should pass
  `committee_name` explicitly, as the parameter comment already anticipates.
- **`bill_template.qmd` still hardcodes** `#256a43` / `#A8433A` / `#cfccc2` in
  its `ui_share_bar` call. Now that `IA_PALETTE` exists these should reference
  it. Legislature-side cleanup, deliberately not bundled into this pass.
- Donor template, FEC template, and the OJS variant are all still on the old
  styling — out of scope by choice.
- Table-weight decision still open, as agreed.

## What comes after this pass

Sequencing changed later the same day. See
[`2026-07-25_iecdb-api-data-sources.md`](2026-07-25_iecdb-api-data-sources.md):
the data source is moving from data.iowa.gov to the IECDB API, and that
migration's Phase D changes the data model these pages are built on — splitting
loans and in-kind out of "total raised", adding reporting-period attribution,
and adding a per-committee `reported_through` date the page must display.

So the order is: **finish the donor template restyle**, then the IECDB
migration (Phases A–C), then `render.R` / index / donor pages against the
settled model. Building the page set first would mean rebuilding it after —
the trap the legislature domain is currently in.
