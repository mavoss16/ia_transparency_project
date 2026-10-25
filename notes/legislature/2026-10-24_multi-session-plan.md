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

## Minor

- `R/legislature/archive/get_data.R` has a LegiScan dataset `access_key`
  committed in it. It's a per-dataset download key returned by
  `getDatasetList`, not the API key, so it's low risk. But the repo is
  public; remove it whenever that file is touched next.
