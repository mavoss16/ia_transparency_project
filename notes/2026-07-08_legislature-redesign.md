# Legislature Site Redesign — Implementation Plan

Assessment written 2026-07-08. A visual/UX redesign of the five main legislature
pages was delivered as a design handoff in `design_handoff_iowa_legislature/`
(not yet committed — it sits in the working tree as an untracked folder). This
note records the plan for wiring that handoff into the live Quarto site so the
work is captured permanently before implementation starts.

**Status: foundation complete (2026-07-08).** Step 0 and the foundation color
swaps were executed and verified the same day — see the "Executed 2026-07-08"
session log at the bottom of this note. Remaining: Phase 2 (index pages),
Phase 3 (detail templates), Phase 4 (polish), and the full force render before
publishing.

## What the handoff contains

- `Iowa Legislature Redesign.dc.html` — browser-viewable mockup of all five
  screens (ids 1a Home, 1b Bill detail, 2a Legislation overview, 2b Legislators
  overview, 2c Legislator detail). A design reference, **not** production code.
- `quarto_starter/custom.scss` — complete Quarto SCSS theme (~230 lines, all the
  `.ia-*` classes). Drop-in quality.
- `quarto_starter/ui_helpers.R` — htmltools component emitters: `clean_bill_title()`,
  `ui_pill()`/`status_pill()`/`vote_pill()`, `ui_stat_card()`/`ui_stat_grid()`,
  `ui_bar_list()`, `ui_paired_bars()`, `ui_stepper()`, `ui_share_bar()`,
  `ui_profile_header()`, `legislator_table()` (reactable), `gt_theme_ia()`.
- `README.md` (bundle root) — design spec, tokens, per-screen breakdown.
- `quarto_starter/README.md` — per-page wiring code keyed to real repo variable
  names (`stage_counts`, `bill_types`, `status_summary`, `group_status_summary`,
  `recent_bills`, `all_bills`, `active_people`).

Net split: ~60% mechanical wiring against well-built helpers, ~40% genuine R
logic (former-legislator detection ported to templates, new home-page counts,
optional stepper dates).

## Design tokens (from bundle README, for reference)

- Fonts: **Source Serif 4** (headings/numerals, 700), **Public Sans** (body/UI).
  Loaded client-side via `@import url(...)` in `custom.scss` — no render-time
  network dependency.
- Party colors change: **R `#A8433A`**, **D `#3F5B93`** (current site uses
  `#C0392B` / `#232066`).
- Status colors: signed green `#256a43` on `#e3efe6`; vetoed red `#8f3a31` on
  `#f4e3e1`; in-progress amber `#7d5c17` on `#f0e9d8`; neutral `#55524a` on
  `#eeede7`. Low-participation (<60%) amber `#b07d24` bar / `#7d5c17` text.
- Full-width layout (~1280–1360px), no right TOC rail on index pages.

## Step 0 — Setup (low effort)

1. `design_handoff_iowa_legislature/quarto_starter/custom.scss` → `site/custom.scss`
2. `design_handoff_iowa_legislature/quarto_starter/ui_helpers.R` → `R/legislature/ui_helpers.R`
3. `site/_quarto.yml`: change `theme: cosmo` → `theme: [cosmo, custom.scss]`; add
   `page-layout: full`; set `toc: false` on the index pages (keep `toc: true` in
   the detail templates if desired).
4. **`reactable` is already in `renv.lock` (line ~3406)** — the handoff's "add
   reactable to renv" step is already satisfied. `htmltools`, `scales`, `stringr`
   all present too. No renv changes needed.
5. Source the helpers at the top of each qmd, after the existing utils source:
   `source(here::here("R/legislature/ui_helpers.R"))`

## Per-page wiring

Effort and target files:

| Page | File | Effort |
|---|---|---|
| Home | `site/index.qmd` | Medium |
| Legislation overview | `site/legislation/index.qmd` | Medium |
| Legislators overview | `site/legislators/index.qmd` | Low–Med |
| Bill detail | `site/templates/bill_template.qmd` | High |
| Legislator detail | `site/templates/legislator_template.qmd` | High |

`site/templates/committee_template.qmd` is out of redesign scope but inherits the
new theme — sanity-check it still renders acceptably.

### Home (1a) — `site/index.qmd`

- Quick Stats bullets → `ui_stat_grid()` of 4 `ui_stat_card()`s.
- Bill Progress bullets → `ui_bar_list(highlight = "Signed by Governor")` fed by
  `stage_counts`.
- "Where bills stand" + "Who holds the chambers" side-by-side cards; keep the two
  ggparliament hemicycles but swap `party_colours` to `c("R"="#A8433A","D"="#3F5B93")`
  and drop in-plot titles (card heading replaces them).
- Recent activity → card with row pattern [bill link | cleaned title + meta |
  status pill | date].
- Two browse cards (one dark navy `#2b354c`) + data-sources footnote.

### Legislation overview (2a) — `site/legislation/index.qmd`

- The two side-by-side status gt tables → single `ui_paired_bars()` (individual
  `#55524a` vs group `#c5c1b4`), fed by `status_summary` left-joined to
  `group_status_summary`.
- Bills-by-type gt table → `ui_bar_list()` fed by `bill_types` (compact abbrevs +
  key footnote).
- Recent bills → same card row pattern as home (includes a "Vetoed by Governor"
  pill case).
- Browse card: search input + filter chips (All / Chamber / Status / Sponsor /
  Bill type); keep the interactive table beneath (`opt_interactive` or reactable).

### Legislators overview (2b) — `site/legislators/index.qmd`

- `senators |> legislator_table()` — near drop-in. The existing `senators` /
  `representatives` dataframes already carry the exact columns the helper wants
  (`name_link`, `party`, `district`, `bills_sponsored`, `sole_sponsored`,
  `votes_cast`, `with_party_pct`, `participation_rate`). **Stop calling
  `fmt_percent` on the two pct columns — the helper expects 0–1 proportions.**
- Header party-split stacked bars (House 67R/33D, Senate 33R/17D) top right.
- Keep the leaflet map; add a House/Senate segmented toggle; recolor district
  fills to the two new party hexes (`party_fill()` at `legislators/index.qmd:138`).

### Bill detail (1b) — `site/templates/bill_template.qmd`

- Header card: red eyebrow + status pill; `clean_bill_title()` for a serif H1 with
  boilerplate stripped; meta row (Sponsor · Effective · Formerly · Last action).
- `ui_stepper(stages, reached = match(bill_status, stages))` replaces the current
  `render_bill_progress_bar()` (see gap #4 for optional dated steps).
- Lobbyist declarations → `ui_share_bar(c(For=..,Against=..,Undecided=..), ...)` —
  `lobby_for`/`lobby_against`/`lobby_undecided` are already computed.
- Related legislation → row list with status pills (existing `related_df` has
  `status`).
- Tabbed card (History | Votes | Lobbyist declarations | Calendar items) — the
  panel-tabset already exists; restructure/rename to match.

### Legislator detail (2c) — `site/templates/legislator_template.qmd`

- `ui_profile_header(...)` with 4px party-colored left border, party pill, meta
  line, and the amber "No longer serving — succeeded by …" notice (see gap #2).
- 2×2 `ui_stat_grid()` (Bills Sponsored / Party Alignment / Participation / Floor
  Votes) beside the district map. All source values exist: `total_sponsored`,
  `leg_stats$with_party_pct` / `participation_rate` / `votes_with_party` /
  `votes_against_party`, `total_votes`.
- Vote pills via `vote_pill()` on a `vote_html` column rendered with `fmt_markdown`.

## Real data/logic gaps (not just cosmetic)

1. **Home stat cards need new counts.** Mockup shows "Signed by Governor 364" and
   "Awaiting Governor 24". `index.qmd` currently computes only bill totals and
   chamber composition — derive `n_signed` and `n_passed_both` from `stage_counts`
   / `bill_groups`, plus `n_R` / `n_D`.

2. **Former-legislator detection must move to the detail template.** The mockup's
   legislator detail (Rocky De Witt) shows an amber "succeeded by Catelin Drey"
   notice. That former/successor logic currently lives **only** in the two index
   pages (`legislators/index.qmd:47-89` and duplicated in `index.qmd:42-66`);
   `legislator_template.qmd` has none of it. Port the duplicate-district logic into
   the template — ideally factor it into a shared helper in `utils.R` and call it
   from all three places instead of a third copy.

3. **"FORMER" chip on the legislators table.** Mockup lists both De Witt and Drey
   under SD-001 with a gray chip on the former. `legislator_table()` doesn't take
   an `is_former` flag — extend it and pass former IDs through.

4. **Bill stepper dates (optional / phase 2).** Mockup 1b shows a date under each
   completed step. `ui_stepper()` accepts an optional `dates` vector, but deriving
   which history action marks each of the 6 stages is real parsing work. The
   stepper renders fine without dates — treat dated steps as an enhancement.

5. **Bill header meta row assembly.** "Sponsor · Effective · Formerly · Last
   action" — `clean_bill_title()` supplies Effective/Formerly; sponsors/history
   supply the rest. New assembly, straightforward.

## Config / theming fiddly bits

- **Navbar brand.** Mockup wants a serif "Iowa Legislature" brand + a
  "91ST GENERAL ASSEMBLY" uppercase sub-label. A two-line brand with an eyebrow
  isn't a native Quarto navbar feature — expect a small `include-in-header` or
  navbar-tools HTML snippet. Also decide whether the brand actually changes from
  the current site title "Iowa Political Transparency" or just adds the label.
- **Breadcrumbs** on detail pages ("Legislation / HF 1023") are manual markup in
  the templates.
- **Color swaps** appear in several places beyond the two index pages: the vote
  maps inside `bill_template.qmd:342-370` and the district map in
  `legislator_template.qmd:127` use their own hardcoded party hexes.
- **`render_bill_progress_bar()`** in `R/legislature/utils.R:116-173` becomes dead
  code once `ui_stepper()` replaces it (it hardcodes a blue `#1a56db` theme).
  Remove or archive it.

## Risks / verification

- **Full re-render required.** The theme touches every page, so this needs
  `render_site(force = TRUE)`, not incremental. `docs/` currently holds only
  partial test-render output (see the migration follow-ups), so a full render +
  visual QA pass is needed regardless.
- Handoff caveat: helper column names were written "as of July 2026; templates may
  need minor renames." Spot-checked — the index/table columns line up; the two
  detail templates are where surprises would surface.
- Confirm Google Fonts render correctly in the GitHub Pages output.

## Suggested sequencing

1. **Foundation** — drop in SCSS + helpers, wire `_quarto.yml`, swap chart/map
   colors, full render to confirm nothing breaks. Shifts the whole site to the new
   look on its own. ✅ **Done 2026-07-08** (see session log below)
2. **Index pages** (home, legislation, legislators) — mostly mechanical helper
   wiring; highest visual payoff, lowest risk.
3. **Detail templates** — profile-header/former-successor logic and the bill
   stepper/meta row are the substantive work; do last.
4. **Polish** — navbar brand, breadcrumbs, dated stepper steps, FORMER chip.

---

## Executed 2026-07-08 — Step 0 + foundation session log

### Files placed

- `design_handoff_iowa_legislature/quarto_starter/custom.scss` → `site/custom.scss`
  (verbatim copy)
- `design_handoff_iowa_legislature/quarto_starter/ui_helpers.R` →
  `R/legislature/ui_helpers.R` (verbatim copy)

### Config changes

- `site/_quarto.yml`: `theme: cosmo` → `theme: [cosmo, custom.scss]`; project-wide
  `toc: false` and `page-layout: full` (was `toc: true` / `toc-expand: 2`).
- The three index pages (`site/index.qmd`, `site/legislation/index.qmd`,
  `site/legislators/index.qmd`) each had `toc: true, toc-location: right,
  toc-depth: 2` in their own front matter, which would have overridden the project
  default — each switched to `toc: false`. The bill/legislator/committee templates
  keep their own `toc: true` (detail pages keep the right rail).
- No renv changes — `reactable`, `htmltools`, `scales` all confirmed installed via
  `requireNamespace()`.

### Party color swaps (old → new: R `#C0392B`→`#A8433A`, D `#232066`→`#3F5B93`)

| File | What changed |
|---|---|
| `site/index.qmd` | `party_colours` for the ggparliament hemicycles |
| `site/legislators/index.qmd` | `party_fill()` + both leaflet `addLegend` color vectors |
| `site/templates/legislator_template.qmd` | district-map `party_color` (was `#2320E6`/`#DC0309`) |
| `site/templates/bill_template.qmd` | vote-map fills + legend inside the knit_child template string |

Vote maps needed Nay tints in the new palette: Yea = full party hex; Nay = 60%
white mix of the same hue — **R Nay `#DCB4B0`**, **D Nay `#B2BDD4`** (replacing
`#EE8181` / `#A4A3F6`). Absent/NV stays `#CCCCCC`.

After the swaps, a site-wide grep confirmed the only remaining old party hexes are
in `site/campaign_finance/templates/donor_template.qmd` (`#DC0309`/`#2320E6`) —
out of redesign scope and excluded from project renders; recolor whenever the
campaign finance section gets built out.

Parliament chart in-plot titles were **kept** for now — the handoff says to drop
them, but the card headings that replace them arrive with the Phase 2 home-page
rewrite. Drop the titles when the cards land.

### Verification

- `ui_helpers.R` sources cleanly; `clean_bill_title()` smoke test produces
  `"School funding"` + `"Formerly HF 1 · Effective 07/01/2026"` from a full
  boilerplate title.
- `test_render()` — **5 bills / 5 legislators / 3 committees, 0 failures**
  (`docs/status.json` 2026-07-09T02:39Z). Compiled Bootstrap CSS in
  `docs/site_libs/` contains Public Sans, `#f7f6f3`, and the `.ia-*` classes.
  Rendered legislators index contains the new hexes and none of the old ones.
- Visual check in a browser (fonts, warm background, serif headings all correct;
  user reviewed the test-rendered pages and approved). For this, a static preview
  server config was added at `.claude/launch.json` (`py -m http.server 8642 -d docs`)
  — handy for future visual QA of `docs/` without re-rendering.
- Pre-existing Quarto warning surfaced (not caused by this work): rendering warns
  `Refusing to remove directory ...docs\index_files since it is not a subdirectory
  of the main project directory` — a consequence of `output-dir: ../docs`. Render
  output is still correct.

### State at session end

All changes uncommitted in the working tree, to be committed together (including
the `design_handoff_iowa_legislature/` bundle, this note, and the CLAUDE.md
updates). `docs/` contains only the test-render output — the full
`render_site(force = TRUE)` is still pending before publishing.

**Next session: start Phase 2 with the home page** (`site/index.qmd`): stat-card
grid (derive `n_signed` / `n_passed_both` / `n_R` / `n_D`), bar list, `.ia-card`
wrappers, recent-activity rows with cleaned titles + status pills, browse cards,
and drop the in-plot parliament titles.

---

## Executed 2026-07-09 — Phase 2 (all three index pages)

All three index pages wired to the redesign helpers and rendered individually for
QA (`quarto render site/<page>/index.qmd --to html`; Quarto from the Positron
bundle, `QUARTO_R` = R-4.5.3). The pre-existing `index_files` "Refusing to remove
directory" WARN persists and is harmless. Each page switched front matter from
`title:` to `pagetitle:` so the custom serif hero replaces Quarto's title banner.

### `custom.scss` additions

New "Home / index page layout" section: `.ia-hero-row` / `.ia-eyebrow` /
`.ia-lead` / `.ia-updated`, `.ia-card-head`, recent-activity rows
(`.ia-recent-*`), `.ia-browse-grid` / `.ia-browse-card` (+ `.dark` navy variant),
parliament `.ia-tally-*`, `.ia-sources` / `.ia-footnote`, chamber
`.ia-split-*` bars, and `.ia-chip-former`.

### `R/legislature/ui_helpers.R` change

`legislator_table()` extended: optional `is_former` logical column renders a gray
**FORMER** chip after the name (mockup gap #3, done now rather than deferred to
Phase 4); `pct_bar()` now renders NA as a muted "—" instead of "NA%". Pass the df
with an `is_former` column; it is stripped from the displayed columns via
`select(-party, -any_of("is_former"))`.

### Home — `site/index.qmd`

Hero (red eyebrow + serif H1 + lead + right-aligned last-updated) → 4
`ui_stat_card`s (Total Bills / Signed by Governor / Awaiting Governor /
Legislators, with `n_signed` = 218 and `n_passed_both` = 113 derived from
`stage_counts`) → two side-by-side `.ia-card`s: "Where bills stand"
(`ui_bar_list(highlight = "Signed by Governor")`, stage order Introduced→Signed)
and "Who holds the chambers" (the two ggparliament hemicycles combined into one
faceted figure with `facet_wrap(~chamber)`, titles/legends dropped, HTML tally
numbers "67 – 33" / "33 – 17" below, shared R/D legend in the card head) →
recent-activity rows via htmltools (`clean_bill_title()` + `status_pill()`) →
browse cards (navy legislation + white legislator) + data-sources footnote.
**Parliament in-plot titles are now dropped** (the deferred Phase 1 item).

### Legislation — `site/legislation/index.qmd`

Header (H1 + bill-count lead) → two cards: "Bills by type" (`ui_bar_list` with
compact abbrev labels HF/SF/HSB/… + key footnote, `.g-col-5`) and "Status
summary" (`ui_paired_bars` of individual `status_summary` vs `group_status_summary`,
`.g-col-7`) → "Recent bills" htmltools rows → "Browse all bills" card keeping the
functional `opt_interactive` gt table with `gt_theme_ia()` applied. The two old
side-by-side status gt tables and the plain recent/type gt tables are gone.

### Legislators — `site/legislators/index.qmd`

Hero + chamber party-split stacked bars (House 67R/33D, Senate 33R/17D from
`active_people`) in the header → single "Find your legislator" `.ia-card` with a
Senate/House `panel-tabset`; **each tab holds that chamber's leaflet map above
its `legislator_table()` reactable** (revised from the first pass, which had a
maps-only tabset followed by two stacked full tables). Leaflet calls factored
into a `chamber_map()` helper (height 460, recolored in Phase 1). The old gt
"Party Composition by Chamber" table and the bulleted former-legislator note were
removed — the header bars and FORMER chips convey both. `senators` /
`representatives` now carry an `is_former` flag; the two pct columns stay 0–1
(no more `fmt_percent`, as the helper expects proportions). Districts are
zero-padded (`SD-001`) so the reactable's `defaultSorted = "district"` sorts
correctly; `with_party_pct` / `participation_rate` confirmed 0–1 with no NAs
across all 155 members.

### Verification

Grepped each rendered file for the redesign classes: home had the stat grid, bar
list, faceted hemicycles + tallies, 8 recent rows, navy browse card; legislation
had 2 bar lists, the 6-row paired-status bars with legend, 8 recent rows, and the
reactable browse table; legislators had the 2 split bars (67 R / 33 R), 5 FORMER
chips (2 Sen + 3 Rep, matching the data), 155 party dots (103 R + 52 D), both
reactables, and both leaflet maps. No stray `:::` fences or unrendered inline R.
Home + legislation visually reviewed and approved by the user.

### State at session end

Phase 2 changes are uncommitted in the working tree. `docs/` now holds freshly
rendered index pages (home / legislation / legislators) plus the earlier
test-render of a few detail pages; a full `render_site(force = TRUE)` is still
pending before publishing. **Next: Phase 3 detail templates** —
`site/templates/bill_template.qmd` (clean_bill_title H1 + meta row, `ui_stepper`
replacing `render_bill_progress_bar()`, `ui_share_bar` for lobbyists, related-bill
pills) and `site/templates/legislator_template.qmd` (`ui_profile_header` with the
former/successor notice ported from the index logic, 2×2 `ui_stat_grid`,
`vote_pill` on vote tables).

---

## Executed 2026-07-09 — Phase 3 (detail templates)

Both detail templates rewritten to the redesign and rendered with `-P` params for
QA. **Both switched to `toc: false`** (were `toc: true` with a right rail) — the
mockups are full-width card layouts with no rail, and after the rewrite almost
every heading lives inside a tabset (so a TOC would be near-empty anyway). This
revises the Phase 1 decision to keep the detail TOCs.

### Shared helper (gap #2, DRY)

`classify_district_turnover(people, votes, rollcalls)` added to
`R/legislature/utils.R` — returns one row per person in a duplicated role+district
with `is_former` and `counterpart_id`. It replaced the ~25-line inline
former-legislator block in **both** `site/index.qmd` and
`site/legislators/index.qmd` (re-rendered, output identical: home still 150
active legislators, legislators page still 5 FORMER chips) and powers the new
succession notice in the legislator template. This avoids the "third copy" the
plan warned about. The dead `render_bill_progress_bar()` (old blue stepper) was
removed from `utils.R`.

### `custom.scss` additions

New "Detail pages" section: `.ia-breadcrumb`, `.ia-bill-eyebrow-row` /
`.ia-bill-eyebrow` / `.ia-bill-title` / `.ia-bill-meta`, `.ia-related-list` /
`.ia-related-row`, `.ia-profile-actions` (external-link buttons), and
`.ia-stats-2col` (forces the legislator stat grid to 2×2 beside the map).

### Bill template — `site/templates/bill_template.qmd`

Breadcrumb → header `.ia-card`: red eyebrow (spelled-out type + number, e.g.
"HOUSE FILE 856") + `status_pill`, `clean_bill_title()` serif H1 (boilerplate
stripped), meta row (Sponsor · Effective · Formerly · Last action · Full-text
link), and `ui_stepper(status_order, match(bill_status, status_order))`. Then a
two-card grid: lobbyist `ui_share_bar` (For green / Against red / Undecided gray,
with a filed-count sub) and a "Related legislation" htmltools row list (bill link
+ cleaned note + `status_pill`). The old standalone Status/Sponsors/Related
sections and the `render_bill_progress_bar()` call are gone. The tabset
(renamed **History / Votes / Lobbyist declarations / Calendar items**) is wrapped
in an `.ia-card`; `gt_theme_ia()` applied to the history/lobby/calendar tables.
**The Votes tab's `knit_child` vote-map machinery is preserved verbatim.**
Meta "Last action" now takes the latest history row by date (the old
`history$action[1]` was actually the *oldest* — JSON history is ascending).
Verified: HF856 → 6/6 stepper + green "Signed by Governor" pill + one related
bill; HCR1 → 1/6 stepper + neutral "Introduced" pill + both empty-state messages.

### Legislator template — `site/templates/legislator_template.qmd`

Breadcrumb → `ui_profile_header()` (name + party pill, "Senator · District … ·
Iowa" meta, amber succession notice, external-link buttons via the `links` slot).
Below: `::: .grid` with a 2×2 `ui_stat_grid` (Bills Sponsored / Party Alignment /
Participation / Floor Votes) in `.g-col-7` wrapped in `.ia-stats-2col`, and the
district-map leaflet in a `.g-col-5` `.ia-card` (height 340). Tabset wrapped in a
card: **Sponsored bills / Voting record / Vote analysis / Similar legislators**;
the old "Legislative Summary" tab was dropped (its counts moved to the stat
cards). Voting record now renders `vote_pill()` on a `vote_html` column via
`fmt_markdown`; `gt_theme_ia()` applied across the tab tables. Succession detection
uses `classify_district_turnover()` + a fresh `people_full` (with `people_id`)
read before the votes/bills join. Verified: De Witt (24516, former) → Republican
pill + amber "succeeded by Catelin Drey (D)" (link `sen-catelin-drey-26571.html`)
+ stat cards 3 / 98.7% / 81.0% / 290 (matches the overview + mockup); a current
member (19548) → no notice, all four stat cards present; no escaped anchors or
stray fences in either.

### State at session end

Phases 2 + 3 changes are uncommitted in the working tree. `docs/` holds the
re-rendered index pages and the QA renders of a few detail templates (in
`docs/templates/`, since I rendered the templates directly rather than via
`render_bill()`/`render_legislator()`). **Remaining: Phase 4 polish** — navbar
brand ("Iowa Legislature" + "91ST GENERAL ASSEMBLY" eyebrow), optional dated
stepper steps — then a full `render_site(force = TRUE)` before publishing. The
`test_render()`/`render_*` interfaces are unchanged (templates still take
`bill_num` / `people_id` params). Pre-existing harmless WARN unrelated to this
work: bills with no floor votes emit "No tabs found in tabset" from the empty
nested Individual-Votes tabset.

---

## Executed 2026-07-09 — Phase 4 (polish)

**Navbar brand.** Asked the user how to resolve the umbrella-vs-mockup tension;
they chose to **rebrand to "Iowa Transparency Project", serif, no eyebrow**
(neither the mockup's "Iowa Legislature" nor the old "Iowa Political
Transparency"). Changed `website.title` in `site/_quarto.yml` and the `pagetitle`
in `site/index.qmd`; bumped `.navbar-brand` to `font-size: 1.35rem` / `color:
$ink` in custom.scss (the serif family/weight were already set in Phase 1). No
`91ST GENERAL ASSEMBLY` eyebrow — so no `include-in-header` HTML snippet was
needed; the plain Quarto navbar title carries it. Verified the rendered
`docs/index.html` navbar shows `<span class="navbar-title">Iowa Transparency
Project</span>` and `<title>Iowa Transparency Project</title>`, with zero
remaining "Iowa Political Transparency" references.

**Dated stepper.** User chose to **skip** it — deriving per-stage dates from
history text is fuzzy and a wrong date reads worse than none. `ui_stepper()` still
accepts an optional `dates` arg if this is revisited.

Breadcrumbs (Phase 3) and FORMER chips (Phase 2) covered the rest of the original
Phase 4 list. With this, the redesign implementation is complete across all five
pages + the shared theme/helpers.

**Only remaining step before publishing: a full `render_site(force = TRUE)`**
(re-renders all ~4194 bills, 155 legislators, committees, and the index pages
against the new theme — long-running, not yet run this session). A
`test_render()` (5 bills / 5 legislators / 3 committees + index pages) was run as
the end-to-end pipeline smoke test — it exercises `render_bill()` /
`render_legislator()` / `render_committee()` (param passing + file move) and the
committee template under the new theme, which the direct `-P` QA renders did not.
