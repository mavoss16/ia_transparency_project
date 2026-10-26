# Multi-session plan — 92nd GA rollover + historical backfill (2026-10-24)

Assessment session, no code changed. Two goals:

1. **Collect the 2027 session (92nd GA)**, which convenes January 2027.
2. **Backfill earlier General Assemblies** so legislator records and
   donor ↔ legislator relationships span careers, not one session.

Both depend on the same groundwork, so they are one plan in phases.

## Findings

### Blocker for both: site size vs GitHub Pages' 1 GB limit

Measured 2026-10-24:

| Path | Size |
|---|---|
| `docs/` total | **916 MB** |
| `docs/legislation/` (4,231 bill pages) | **742 MB**, ~175 KB per page on average |
| `docs/legislators/` | 151 MB |
| `docs/committees/` | 8.6 MB |
| `docs/site_libs/` | 13 MB |
| Largest bill pages (HF2676, HF2739, SF603, SJR11) | 3.6–4.4 MB each |
| `docs/legislation/index.html` | 7.7 MB |

GitHub Pages limits a published site to about 1 GB. The heavy bill pages carry
embedded htmlwidgets, probably the per-roll-call Leaflet district vote maps,
each embedding the House or Senate district geometry again. **Not yet
confirmed:** profile one heavy page (e.g. SJR11) to find what takes the bytes.

**Consequence:** one more session of bill pages at today's weight probably
pushes the site past 1 GB. Eight back sessions at today's weight would be
about 6 GB. This must be fixed before the 92nd GA starts, not just before any
backfill.

The daily CI bot also commits `docs/` every day, so `.git` grows with every
re-render. Not measured here.

### The pipeline is hardcoded to the 91st GA

About 70 references, in five kinds:

| Kind | Where |
|---|---|
| LegiScan session ID `2177` | `01_incremental_update.R` (default argument) |
| `legiscan/files_ga91_{json,derived}` paths | 12 R scripts (`01`, `01c`, `02`, `02b`, `03`, `03a`, `04`, `04a`, `05`, `render.R`, `run_pipeline.R`, `utils.R`) and 7 `.qmd` files (`index`, `about`, `legislation/index`, `legislators/index`, `legislators/compare`, all three templates) |
| `*_91st_ga.rds` outputs | `02_process_votes.R` writes them; `02b`, `04a`, `05` and the templates read them |
| `ga = 91` scraper defaults | `scrape_bill_relationships()` (`03`), `scrape_lobbyist_declarations()` (`utils.R`), `04_lobbyist_declarations.R` |
| Page copy | "91st General Assembly" / "2025–2026" in home, legislation, legislators, compare, about |

### Bill URLs collide across sessions

Bill numbers restart each General Assembly. `render.R` writes
`docs/legislation/{bill_number}.html`, so the 92nd's HF 1 would overwrite the
91st's `HF1.html`. Three other things are keyed by bill number alone:

- `render_manifest.csv`
- `data/legislature/pipeline_internal/bill_hash_cache.rds`
- the per-bill JSON directory

### Things that carry over cleanly

- **LegiScan `people_id` is the same across sessions**, so a legislator's
  identity already links up between sessions.
- **The 2021 district maps (Plan2) stay in force through the 92nd GA**, so
  maps need no change for 2027.
- **`01c_generate_csvs.R` already carries `session_id`** into `bills.csv`.
- **The bulk-download path already exists:**
  `R/legislature/archive/01_download_legiscan_data.R` (`getDatasetRaw`, JSON + CSV).

### Gaps that matter for 2027 regardless

- **Lobbying (`04`/`04a`) and salience (`05`) aren't in `run_pipeline.R`.**
  `lobbyist_declarations.rds` stops at 2026-02-13. During a live session,
  lobbying needs to run daily.
- **The 92nd GA's LegiScan session ID isn't known yet.** LegiScan creates it
  around December or January. Look it up with `getSessionList` rather than
  hardcoding it.

### Historical availability

- **LegiScan:** Iowa sessions go back to the **83rd GA (2009–10)**, per
  [legiscan.com/IA/datasets](https://legiscan.com/IA/datasets) (CC BY 4.0).
  That's 8 earlier General Assemblies (83rd–90th), each one bulk zip in the
  same JSON format we use now. Not yet checked: how complete the older
  sessions are (roll calls, committee votes, sponsors). Even the 91st has an
  empty `amendments[]`.
- **Before 2009:** not in LegiScan. Floor votes would have to be parsed from
  journal PDFs, as `archive/old_pipeline/` did. Not recommended.
- **legis.iowa.gov scrapers:** the bill-history pages take a `ga=` parameter.
  Not yet checked: how far back lobbyist declarations go
  (`/lobbyist/reports/declarations?ga=…`).
- **District maps change across sessions:**

  | Sessions | District plan |
  |---|---|
  | 83rd (2009–10) | 2001 plan |
  | 84th–89th (2011–22) | 2011 plan |
  | 90th onward (2023–) | 2021 plan (Plan2, the one we have) |

  District numbers point to different places under each plan, so maps for
  older sessions need the right plan's shapefiles (from Iowa LSA), simplified
  as in `simplify_districts.R`.

### Cost estimates for a full backfill (83rd–90th)

| Item | Estimate |
|---|---|
| LegiScan API calls | ~16 (one `getDatasetList` + one `getDatasetRaw` per session); fine on the free tier |
| Bill-relationship scraping | ~4,000 requests per session, ~30,000 total; hours with throttling |
| Bill pages | ~34,000 |
| Rendering at the measured ~8 pages/min | ~70 hours |
| Site size at today's page weight | ~6 GB |

## Phases

### Phase 0 — make sessions a setting (now through December; 91st GA only)

Goal: identical 91st GA output, with no 91 left in the code.

1. **Add a session config**, e.g. `R/legislature/session.R`:
   - `CURRENT_GA`
   - a `ga_paths(ga)` helper returning the JSON, derived and processed-data
     paths for a session
   - a GA → LegiScan `session_id` lookup, filled from `getSessionList` and
     cached
2. **Move raw data into session folders**, e.g. `legiscan/ga91/json`,
   `legiscan/ga91/derived`, and processed data into
   `data/legislature/ga91/…` (or keep flat folders with a `_ga91` suffix,
   but apply it everywhere).
3. **Thread `ga` through every script and template.** Templates take a
   `ga` parameter next to `bill_num` / `people_id`.
4. **Put the session in bill URLs** (`docs/legislation/91/HF1.html`), and key
   the render manifest and hash cache by (ga, bill_number).
5. **Cut page weight.** First profile a heavy page. Then serve one shared
   district GeoJSON file per chamber and plan, loaded in the browser,
   instead of embedding it in each widget. Fallback: static SVG vote maps.
   Also slim `legislation/index.html` (7.7 MB).
6. **Done when** `test_render()` and a full render reproduce the current
   pages, `docs/` is well below 1 GB, and grepping the code for `ga91` /
   `91st` / `2177` finds nothing outside `archive/`.

### Phase 1 — freeze the 91st GA, start the 92nd (December–January)

1. Do a final 91st GA pull once it is settled, then mark it frozen so the
   daily run skips it.
2. When LegiScan creates the 92nd session: record its ID, set
   `CURRENT_GA = 92`, and run the bulk download for the first load, then
   incremental updates.
3. Add `04` lobbying (and `05` salience, if it's ready to show) to
   `run_pipeline.R`, keeping CI inside its time budget. Related: legislators
   and committees are re-rendered every run even with no changes (~115–145
   min), which is the biggest CI cost.
4. Home and index pages show the current session. Pages for the 91st stay
   reachable under their session URLs.
5. Expect heavy legislator turnover from the 2026-11-03 election. New
   members appear in LegiScan once seated.
   `classify_district_turnover()` works within one session; check it at the
   start of a new one.

### Phase 2 — backfill the 90th GA (2023–24) as the multi-session test

Same district maps and many returning legislators, so this is the cheapest
real test of multiple sessions.

1. Bulk download → `01c` → `02` → `03` (scrape) → `04` (scrape, if
   declarations exist for GA 90) → `05`.
2. Check data quality against the 91st: roll-call counts, sponsors, history
   completeness.
3. Build whatever legislator view Decision 2 picks, and confirm
   cross-session `people_id` joins.
4. Render the 90th's bill pages and measure the added site size and render
   time against the Phase 0 numbers.

### Phase 3 — deeper backfill (83rd–89th), data first

1. Bulk-download and process every session into the data layer (cheap).
2. Source and simplify the 2001 and 2011 district plans; key maps by
   (chamber, plan).
3. Use the history in legislator career views and in campaign finance
   linking (IECDB data goes back to 2003), before rendering any older
   bill pages.
4. Render older bill pages only if Decision 4 leaves room. Options: a
   lighter archive template, render once outside CI, or skip them.

## Open decisions

1. **URL scheme and existing links.** Use `legislation/{ga}/HF1.html` (or
   `/ga91/`)? For current 91st links: move them once (the site has only been
   live since 2026-10-15, so few links point at it yet), or leave redirect
   stubs (e.g. Quarto `aliases`)?
2. **Legislator pages.** One career page per person (`people_id` is the same
   across sessions) with a tab per session, or one page per person per
   session? Career pages fit the "connections over collections" principle
   better, but each page grows with every session.
3. **How far back.** Only the 90th GA? Back to the 84th (2011 maps, a single
   extra district plan)? Or all the way to the 83rd?
4. **Hosting.** If full bill pages for older sessions are wanted, Pages'
   1 GB limit decides it: lighter archive pages, a different host, or older
   sessions as data only.
5. **Committees.** Per-session pages (recommended; membership and IDs are
   tied to the session) or merged across sessions?
6. **Salience on the site.** Phase 1 is a natural point to decide whether
   salience (redesigned 2026-10-24, see `2026-10-24_salience-precedents.md`)
   appears on pages for the 92nd GA.

## Phase 0 progress (2026-10-25)

Decided: session **folders** (not suffixes); bill URLs `legislation/ga91/HF1.html`
(`ga91` rather than `91`, so the number reads as a session); existing links
are moved once, no redirect stubs; legislator URLs stay session-agnostic;
committee URLs are per session. Order agreed: code refactor and URL change
now, page weight next, then **one** full render carrying both (each forces a
full re-render and a ~900 MB `docs/` rewrite in git history).

Done (steps 1–4):

- `R/legislature/session.R`: `CURRENT_GA`, `ga_paths()`, `ga_csv()`,
  `ga_label()` / `ga_years()` / `ga_slug()`, `bill_dir_href()`,
  `session_item_id()`, and `legiscan_session_id()` (cache:
  `data/legislature/legiscan_sessions.csv`, seeded with 91 → 2177).
- Data moved with `git mv` (pure renames): `legiscan/ga91/{json,derived,csv}`,
  `data/legislature/ga91/{votes,bills,lobbying,pipeline_internal}`. Vote files
  lost their `_91st_ga` suffix. `districts/` and `pipeline_runs.rds` stay shared.
- Every pipeline function takes `ga` (default `CURRENT_GA`); the five offline
  steps (`01c`, `02`, `02b`, `03` groups, `04a`, `05`, `06`) reproduce
  outputs `identical()` to the committed ones.
- Templates take a `ga` param; page copy comes from `ga_label()` /
  `ga_years()`.
- Bill and committee templates moved to `site/templates/session/`, render to
  `docs/templates/session/{ga91-HF1}.html` and move to
  `docs/legislation/ga91/` / `docs/committees/ga91/`. The nested template
  folder is what makes the `../../site_libs` paths right; a page must end up
  exactly as deep as it rendered.
- Manifest keys for bills and committees are `ga91/HF1` / `ga91/7087`, so
  every bill and committee shows as needing render until the full render.
  `remove_unsessioned_pages()` (dry run by default) then removes the flat
  pages, old template outputs and old manifest rows.

**Do not push this before the page-weight work** unless a double full render
is acceptable: the daily CI run would start re-rendering all 4,231 bills at
the new URLs under its time budget.

Remaining for Phase 0: step 5 (page weight), then the single full render +
`remove_unsessioned_pages(dry_run = FALSE)`. Grep check: `ga91` / `91st` /
`2177` now appear only in `session.R` doc examples, the session-ID cache,
and comments recording facts about the 91st GA's data.

## Page-weight profile (2026-10-25)

Measured on the committed flat render (`docs/legislation/*.html`, 4,231
bill pages, 756 MB).

| Where the bytes go | Size | Share |
|---|---|---|
| Leaflet vote-map **district geometry** | 440 MB | 58% |
| gt per-table `<style>` blocks | 130 MB | 17% |
| Other page HTML (navbar, scripts, text) | 113 MB | 15% |
| `<table>` markup | 60 MB | 8% |
| Map styling and labels (rest of widget JSON) | ~13 MB | 2% |

- **Maps.** 1,422 maps on 668 pages; pages without maps average 55 KB
  (median page 61 KB). Every map embeds the full chamber geometry again:
  Senate 11,298 points (~264 KB of widget JSON), House 15,094 (~353 KB), at
  6-decimal precision. SJR11 (4.4 MB) has 11 maps but only 2 distinct
  geometries. The color and label data a map actually needs is 2–4 KB.
- **gt styles.** Each gt table emits a ~9.2 KB `<style>` block scoped to its
  random table id. SJR11's 25 blocks reduce to 4 distinct ones once the id
  is removed. Bill pages carry one per roll call (summary + full roll call
  tables), so this grows with votes too.
- **`legislation/index.html` (7.7 MB)** is one reactable widget (gt
  `opt_interactive()`). The data is 1.2 MB; the other **6.4 MB is
  generated per-row JavaScript**: the `tab_style(cell_text(whitespace =
  "nowrap"), cells_body(...))` calls emit an `if (rowIndex === n)` branch for
  every row. A column-level style does the same thing in a few bytes.

Options for the maps, by Senate/House widget size per map:

| Option | Senate | House | Saving on bill pages |
|---|---|---|---|
| Current (0.0002° simplify) | 264 KB | 353 KB | — |
| `st_simplify` 0.002° | 92 KB | 130 KB | ~280 MB |
| `st_simplify` 0.005° | 52 KB | 76 KB | ~345 MB, visible coarsening likely |
| **Shared GeoJSON per (plan, chamber)**, fetched by the browser | ~2 KB | ~4 KB | **~435 MB** |

Note `st_simplify` simplifies each district on its own, so neighbours can
open slivers at coarse tolerances; `rmapshaper::ms_simplify` (not installed)
keeps shared borders. A shared GeoJSON also fits Phase 3, since older
sessions just point at a different plan's file.
Rounding coordinates to 4 decimals (~11 m) was not measured: setting
`TOJSON_ARGS` digits on the widget didn't change its size, so leaflet
probably serializes the coordinates on its own path.

Estimate if the shared GeoJSON, a shared gt stylesheet and the index fix all
land: bill pages ~756 → ~195 MB, index 7.7 → ~1.3 MB, `docs/` ~916 → ~350 MB.
Legislator pages (151 MB) were not profiled; they use the same gt tables and
a district map, so expect the same two causes there.

## Shared-geometry map prototype (2026-10-25)

Chosen over a tile grid (unfamiliar for newcomers) and over coarser
simplification. Test files only; the production templates are unchanged:

- `R/legislature/_test_shared_district_maps.R`: `write_district_scripts()`
  writes `data/legislature/districts/web_test/plan2021_{senate,house}.js`
  (286 / 386 KB, 5-decimal GeoJSON registered on `window.IA_DISTRICTS`).
  `vote_map_shared()` builds a polygon-free Leaflet map, attaches the
  chamber's script as an `htmlDependency` (Quarto copies it once to
  `site_libs/ia-districts-plan2021-{chamber}-0.1.0/`), and passes only
  district / fill / label arrays to an `onRender` hook that draws the shared
  GeoJSON. The initial view is set from R with `fitBounds()`.
- `site/templates/session/_test_shared_maps.qmd`: reproduces a bill's
  "Individual Votes" tabset. Underscore files render standalone (no
  `site_libs`), so the runner renders a temporary non-underscore copy to
  get real bill-page depth.

Results:

| | Current | Prototype |
|---|---|---|
| SJR11 page (maps only on the test page) | 4.4 MB, maps ~3.8 MB | 93 KB |
| Per map | ~356 KB | 4–6 KB |
| HF1021 (1 map) | — | 29 KB |

- All 11 SJR11 maps draw (50 Senate / 100 House districts) when their tab
  opens, at full size and centred on Iowa, with the legend; Leaflet defers
  hidden-tab maps until they are shown, and the R-side `fitBounds()` gives
  them the right view.
- Fill colors and tooltip labels match the current page's map **exactly**,
  district by district, on all 11 maps.
- Hover tooltips bind to the right district; a page with only House votes
  loads only the House script; no console errors.
- Not checked: mobile widths, and a bill page with the full production
  layout around the maps (outer tabsets).

**Separate, pre-existing problem found:** CARTO's free basemap
(`providers$CartoDB.Positron`, `basemaps.cartocdn.com/light_all`) now returns
an "API KEY REQUIRED" image for every tile, whatever the referer (checked
with none, localhost and github.io). Every Leaflet map on the live site is
probably showing that watermark: bill vote maps, the legislators index maps,
and the legislator district maps. Options: another provider (Esri gray
canvas needs no key; Stadia needs a free domain registration), or no
basemap at all, since the vote choropleths don't need one.
**Fixed 2026-10-25:** the three site maps (bill vote maps, legislators index,
legislator district map) and the prototype now use `addTiles()`
(OpenStreetMap standard tiles, attribution included). Verified loading in
the browser on the SJR11 test page and a legislator page. Live pages pick it
up on their next render (legislator pages and the index re-render every CI
run; bill pages at the full render). The two elections console helpers in
`R/elections/precinct_matching/` still use CARTO.

## Shared maps in production (2026-10-25)

Prototype promoted: `R/legislature/maps.R` (`district_map()` with per-district
fill / opacity / stroke / weight / label / popup / front columns and optional
hover restyle; `vote_map()` for roll calls), geometry scripts committed in
`data/legislature/districts/web/`, `ga_district_plan()` + `DISTRICT_PLANS` in
`session.R`. Switched: bill vote maps, legislator district map, legislators
index maps. Prototype files deleted.

Verified: SJR11 4.4 → 0.66 MB, HF1021 → 0.12 MB, legislator page 0.84 →
0.58 MB, legislators index 0.80 → 0.19 MB, every map 5–7 KB. Vote map colors
and labels match the old pages district by district (12 maps). In the
browser: all SJR11 maps draw inside the real nested tabsets; legislator
highlight drawn on top; index popups link to profiles and hover restyles and
resets; a project render (`render_index_pages()`) leaves the `site_libs`
script folders in place. Found and fixed on the way: `render_bill()` /
`render_committee()` didn't create their `ga91/` folder and ignored a failed
move, so a direct call could leave the page in `docs/templates/session/`
and report success.

Rollout and rollback for the first CI run:
[`2026-10-25_multi-session-rollout-rollback.md`](2026-10-25_multi-session-rollout-rollback.md).

## Minor

- `R/legislature/archive/get_data.R` has a LegiScan dataset `access_key`
  committed in it. It's a per-dataset download key returned by
  `getDatasetList`, not the API key, so it's low risk. But the repo is
  public; remove it whenever that file is touched next.
