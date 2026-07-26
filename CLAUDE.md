# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ia_transparency_project` — an umbrella project promoting political transparency in Iowa by making publicly-available data more accessible and highlighting relationships between datasets. Domains:

- **Iowa Legislature** — bill tracking, legislator voting records, lobbyist declarations (Phase 1; migrated from `iowa_legislature` 2026-07-05 with full git history)
- **Iowa Elections** — election results and candidate data
- **Campaign Finance** — donor-candidate relationships

## Current Folder Structure

As of 2026-07-05 (legislature migration complete):

```
ia_transparency_project/
├── R/
│   ├── campaign_finance/
│   │   ├── download/
│   │   │   └── fec_contributions.R       ← download FEC bulk zips → source/federal/{cycle}/
│   │   ├── 01_build_committee_lookup.R   ← API scrape → committee_lookup.rds
│   │   ├── 02_clean_normalize.R          ← clean CSVs + merge committees → Parquet
│   │   ├── 02a_clean_normalize_federal.R ← clean FEC source files → Parquet
│   │   ├── 03_link_donors.R              ← fuzzy donor dedup (built, NOT working; nothing depends on it)
│   │   ├── 04_build_database.R           ← Parquet → DuckDB + summary views (state + FEC)
│   │   └── utils.R                       ← source discovery, column/date harmonization, normalizers
│   ├── ui_helpers.R                      ← SHARED UI components + palette (all domains)
│   ├── elections/
│   │   ├── download/                                    ← standalone acquisition scripts
│   │   │   ├── shapefile_precincts.R                    ← scrape + download 2020s county shapefiles from sos.iowa.gov
│   │   │   ├── shapefile_city_precincts.R               ← scrape + download all city precinct shapefiles (gap-fill source)
│   │   │   ├── shapefile_fix_counties.R                 ← targeted fix for counties missing/wrong shapefiles
│   │   │   ├── election_results_sos.R                   ← download precinct XLS from sos.iowa.gov (2000–2022)
│   │   │   └── election_results_2024.R                  ← download precinct XLSX from electionresults.iowa.gov
│   │   ├── precinct_matching/                           ← shapefile ↔ election precinct crosswalk pipeline
│   │   │   ├── 01_combine_precinct_shapefiles.R         ← combine per-county shapefiles → precincts_2020s.rds
│   │   │   ├── 02_enrich_precinct_shapefiles.R         ← add Census place/township overlap columns
│   │   │   ├── 03_crosswalk_precincts_2024.R           ← auto-match + manual template for 2024 election
│   │   │   ├── manual_crosswalk.R                       ← interactive console helpers (sourced repeatedly)
│   │   │   └── explore_shapefiles.R                     ← inspection helpers (DBF fields, name comparison, maps)
│   │   ├── clean_precinct_elections_2024.R              ← clean ENR XLSX downloads → precinct_elections_2024.csv
│   │   ├── _test_download_5.R
│   │   └── _test_scrape_urls.R
│   ├── exploratory/
│   │   ├── campaign_finance_explore.R
│   │   ├── elections/
│   │   │   ├── clean_precinct_election_2020.R
│   │   │   ├── election_2020_precincts.R
│   │   │   ├── precinct_elections.R
│   │   │   ├── precinct_fuzzy_matching_2020.R
│   │   │   └── precinct_places.R
│   │   └── legislature/                  ← contributions_explore, legislation_analysis, network_analysis
│   ├── legislature/
│   │   ├── 01_incremental_update.R       ← LegiScan API incremental pull (needs LEGISCAN_API_KEY)
│   │   ├── 01c_generate_csvs.R           ← JSON → legiscan/files_ga91_derived/*.csv
│   │   ├── 02_process_votes.R            ← vote summaries/records/stats (uses 02a functions)
│   │   ├── 02a_vote_analysis_functions.R
│   │   ├── 02b_legislator_similarity.R
│   │   ├── 03_bill_relationships.R       ← scrape relationships → bill groups
│   │   ├── 03a_resume_scrape_relationships.R
│   │   ├── 04_lobbyist_declarations.R
│   │   ├── 04a_legislator_lobbyist_alignment.R
│   │   ├── 05_salience_scores.R          ← bill salience index (0–100)
│   │   ├── render.R                      ← incremental site render orchestrator
│   │   ├── run_pipeline.R                ← pipeline orchestrator (01 → 03 + render)
│   │   ├── utils.R
│   │   ├── ui_helpers.R                  ← htmltools emitters for redesign components (pills, stat cards, bars, stepper)
│   │   ├── simplify_districts.R
│   │   └── archive/                      ← deprecated scripts incl. old_pipeline/
│   └── render_all.R                      ← top-level orchestrator (all domains)
├── data/
│   ├── campaign_finance/
│   │   ├── campaign_finance.duckdb       ← analytical database (derived)
│   │   ├── processed/                    ← cleaned Parquet files + committee lookup
│   │   └── source/
│   │       ├── IECDB/                    ← raw Iowa state exports, one dir per download
│   │       │   ├── 202603/               ← previous export (kept for reference)
│   │       │   └── 202607/               ← newest export; contributions split into 4 part files
│   │       └── federal/                  ← FEC bulk download outputs
│   │           ├── headers/              ← cached FEC column-name .rds files
│   │           ├── 2020/                 ← indiv_IA.txt, cm.txt, cn.txt, ccl.txt
│   │           ├── 2022/
│   │           └── 2024/
│   ├── elections/
│   │   ├── precincts_2020s.rds           ← combined shapefile (derived)
│   │   └── raw/
│   │       ├── statewide/                ← statewide precinct election CSVs
│   │       ├── precincts_2010s/          ← shapefile (single statewide)
│   │       ├── precincts_2020s/          ← shapefiles (one folder per county)
│   │       ├── precincts_2020s_cities/   ← shapefiles (one folder per city) — gap-fill for incomplete counties
│   │       ├── precinct_elections_2000/  ← county-level xlsx files (2000–2020 have 99 files each)
│   │       ├── precinct_elections_2022/  ← county-level xls files (populated by election_results_sos.R)
│   │       ├── precinct_elections_2024/  ← county-level xlsx files (populated by election_results_2024.R)
│   │       └── [precinct match files]
│   ├── general/                          (empty — for cross-domain reference data)
│   └── legislature/                      ← processed .rds: bills/, votes/, lobbying/, districts/, pipeline_internal/, analysis/, archive/
├── legiscan/                             ← raw LegiScan source data (files_ga91/, files_ga91_derived/, files_ga91_json/)
├── site/
│   ├── _quarto.yml                       ← unified site config ("Iowa Transparency Project"); campaign_finance/ excluded from project renders
│   ├── index.qmd                         ← unified home page (legislature section is the live content)
│   ├── about.qmd / status.qmd / styles.css / _vote-table.qmd
│   ├── custom.scss                       ← redesign SCSS theme (.ia-* classes; theme: [cosmo, custom.scss])
│   ├── legislation/                      ← bill browse page
│   ├── legislators/                      ← legislator browse + compare pages
│   ├── templates/                        ← bill / legislator / committee parameterized templates
│   └── campaign_finance/
│       └── templates/
│           ├── recipient_template.qmd        ← per-committee contribution report (static R/gt)
│           ├── donor_template.qmd            ← per-donor contribution report (static R/gt)
│           └── recipient_template_ojs.qmd    ← OJS experimental version with reactive year filter
├── docs/                                 ← rendered site output (GitHub Pages; gitignored artifacts re-render)
├── design_handoff_iowa_legislature/      ← redesign mockups + quarto_starter/ (source of custom.scss & ui_helpers.R)
├── .github/workflows/daily-update.yml    ← daily legislature pipeline + render
├── renv.lock / renv/ / .Rprofile         ← renv dependency management (R 4.5)
├── render_manifest.csv                   ← incremental render manifest (LegiScan content hashes)
├── notes/
│   ├── legislature/                      ← migrated session notes + plan_bill_groups_integration.md
│   ├── 2026-03-06_migration-plan.md
│   ├── 2026-03-08_file-migration-map.md
│   ├── 2026-03-10_precinct-shapefiles-download.md
│   ├── 2026-03-14_precinct-shapefiles-pipeline.md
│   ├── 2026-04-21_campaign-finance-pipeline.md
│   ├── 2026-04-22_elections-download-scripts.md
│   ├── 2026-05-09_federal-campaign-finance.md
│   ├── 2026-05-09_campaign-finance-templates-ojs.md
│   ├── 2026-07-05_legislature-migration.md
│   ├── 2026-07-08_legislature-redesign.md
│   ├── 2026-07-11_impeccable-workflow.md
│   ├── 2026-07-15_design-backlog.md
│   └── 2026-07-15_impeccable-design-pass.md
└── CLAUDE.md
```

## Iowa Legislature

Tracker for the 91st General Assembly (2025–2026). Migrated from the standalone `iowa_legislature` repo on 2026-07-05 via `git filter-repo` + merge, so full git history is in this repo (`git log --follow` works across the move). Verified with `test_render()` (5 bills / 5 legislators / 3 committees, 0 failures). See `notes/2026-07-05_legislature-migration.md` for the full session log. This domain is the architectural reference for the others.

**Post-migration follow-ups (open as of 2026-07-05):**
- Archive the old `iowa_legislature` GitHub repo; delete the throwaway `../iowa_legislature-filtered` clone
- `docs/` holds only partial test-render output — run `render_site(force = TRUE)` before publishing
- No git remote configured yet (GitHub repo + Pages setup pending)

(The renv out-of-sync issue flagged during verification was resolved by a `renv::snapshot()` the same day.)

**Site redesign (implementation complete 2026-07-09; full publish render pending):** A high-fidelity visual/UX redesign of the five main pages (home, legislation overview, legislators overview, bill detail, legislator detail), delivered as a design handoff in `design_handoff_iowa_legislature/`. All four phases are done: **P1 foundation** — `site/custom.scss` (SCSS theme, `.ia-*` classes) + `R/legislature/ui_helpers.R` (htmltools component emitters), `_quarto.yml` uses `theme: [cosmo, custom.scss]` with `page-layout: full`, party colors swapped site-wide to R `#A8433A` / D `#3F5B93` (vote-map Nay tints R `#DCB4B0`, D `#B2BDD4`). **P2 index pages** — home/legislation/legislators rewritten with `ui_stat_grid`, `ui_bar_list`, `ui_paired_bars`, htmltools recent-activity rows, and the `legislator_table()` reactable (with FORMER chips); the legislators page uses one Senate/House `panel-tabset` (map above table per tab). **P3 detail templates** — `bill_template.qmd` (breadcrumb, header card with red eyebrow + `status_pill` + `clean_bill_title` H1 + meta row + `ui_stepper`, lobbyist `ui_share_bar`, related-bill list, renamed tabset) and `legislator_template.qmd` (`ui_profile_header` with succession notice, 2×2 `ui_stat_grid`, `vote_pill`, restructured tabset); both detail templates are now `toc: false`. The mid-session replacement logic lives in one shared helper, `classify_district_turnover()` in `R/legislature/utils.R`, used by both index pages and the legislator template; the dead `render_bill_progress_bar()` was removed. **P4 polish** — navbar rebranded to **"Iowa Transparency Project"** (serif, no eyebrow; `_quarto.yml` title + `index.qmd` pagetitle + `.navbar-brand` in scss); dated stepper steps intentionally skipped. Verified via `test_render()` (5 bills / 5 legislators / 3 committees, 0 failures) plus per-page `-P` renders. **Remaining: a full `render_site(force = TRUE)` before publishing** (re-renders all bills/legislators/committees against the new theme; long-running, not yet run). Plan + full P1–P4 executed session logs are in `notes/2026-07-08_legislature-redesign.md`. `.claude/launch.json` has a `docs-preview` static server (port 8642) for visual QA of rendered output.

**Design QA pass (2026-07-11 → 2026-07-15, complete):** first full Impeccable cycle — `PRODUCT.md` written, all three index pages critiqued (home 31→32/40, legislation 32, legislators 34; snapshots in `.impeccable/critique/`), and every P1 fixed and probe-verified: `$faint` darkened to `#706c63` (WCAG AA), a ≤600px mobile block in `custom.scss` (recent rows, browse grid, bar rows, stepper vertical stack, `.g-col-*` collapse ≤767px), uppercase-tracked labels reserved for the hero `.ia-eyebrow` only, funnel counting rule stated above the bars, tally/split de-color-coded ("R 67 – 33 D"), FORMER chip and `ui_share_bar()` legend contrast fixed. Session log: `notes/2026-07-15_impeccable-design-pass.md`; open items: `notes/2026-07-15_design-backlog.md`. **The pending full `render_site(force = TRUE)` is now also the gate for these fixes** — theme CSS is hash-referenced per page, so already-rendered detail pages still use the old stylesheet until then.

### Tech Stack
- **R** — primary language for data pipelines and site generation
- **Quarto** — static site generation via parameterized templates
- **LegiScan API** — legislative data source (`LEGISCAN_API_KEY` env var)
- **GitHub Pages** — hosting (`docs/` output directory)
- **renv** — R dependency management

### Data Flow
```
LegiScan API → 01_incremental_update.R → legiscan/files_ga91_json/
               01c_generate_csvs.R     → legiscan/files_ga91_derived/*.csv
                                              ↓
               02_process_votes.R           → data/legislature/votes/*.rds
               02b_legislator_similarity.R  → data/legislature/votes/similarity_*.rds
               03_bill_relationships.R      → data/legislature/bills/groups.rds
               04_lobbyist_declarations.R   → data/legislature/lobbying/*.rds
               05_salience_scores.R         → data/legislature/bills/salience_scores.rds
                                              ↓
               site/templates/*.qmd (parameterized bill/legislator/committee pages)
                                              ↓
               R/legislature/render.R (incremental rendering) → docs/
```

`R/legislature/run_pipeline.R` orchestrates steps 01→03 plus render; logs to `logs/legislature/`. `.github/workflows/daily-update.yml` runs it daily (paths already updated for the monorepo).

### Rendering Commands
```r
source("R/legislature/render.R")
render_status()             # what needs rendering
render_site()               # incremental render (only changed items)
render_site(force = TRUE)   # full re-render
test_render()               # quick test: 5 bills, 5 legislators, 3 committees
render_index_pages()        # only the index pages
clear_manifest()            # force full re-render next time

source("R/render_all.R")    # top-level: render_all() spans all domains
```

- `render_manifest.csv` (repo root) tracks LegiScan `change_hash` (bills) and `person_hash` (legislators); only changed items re-render
- Preview locally with `quarto preview site/` from the terminal

### Salience Score
`05_salience_scores.R` produces a 0–100 index of how contested/impactful each bill is, computed at the **bill group level** (signals pooled across companion bills; every group member shares the score). Components: lobby volume (0.20), lobby opposition (0.20), floor vote (0.15), party division (0.15), hearings (0.12), amendments (0.08), fiscal note (0.05), co-sponsors (0.03), companion count (0.02). See `notes/legislature/2026-05-17_salience-score.md` for design rationale.

### Key R Packages (Legislature)
`readr`, `dplyr`, `tidyr`, `stringr`, `purrr`, `jsonlite`, `gt`, `quarto`, `here`, `rvest`, `ggparliament`

## Campaign Finance

Data sourced from the Iowa Ethics and Campaign Disclosure Board (IECDB). Raw CSV exports are not committed to git (too large).

> **Source under review (2026-07-25):** the current bulk CSVs come from [data.iowa.gov dataset 917](https://data.iowa.gov/catalog/dataset/917) and are **not current**. The 202607 export (pulled 2026-07-25) was missing the May 27 – July 14 reporting period for statewide committees — Sand's DR2 was filed 2026-07-20, five days before the pull, and still absent. Freshness varies by committee (306 committees *did* have July data), so the feed is eventually-consistent and must never be treated as an as-of snapshot. IECDB's own portal API returns the same transactions current through 2026-07-14, with in-kind pre-labelled via `transactionType`. Full API reconnaissance, contracts, plan, and cautions: [`notes/2026-07-25_iecdb-api-data-sources.md`](notes/2026-07-25_iecdb-api-data-sources.md). **Cash on hand exists only on the DR2 report PDFs and cannot be derived from any transaction feed.**
>
> Settled while investigating:
> - **No bulk dump exists.** `/api/search/table` returns `204 No Content` without a `primaryCommitteeId`, with or without a date window — a committee filter is mandatory. Instead `POST /api/publicreports/state` is a single unfiltered call returning all 17,873 filings with `filedOn`, so it serves as a **change feed**: re-pull only committees whose latest filing moved.
> - **GUID vs `committee_code` is a non-issue.** `/api/search/committee` returns both, and `committee_lookup.rds` already stores `committee_uuid` for 7,935 of 7,936 committees (verified against the live API). Transaction rows come back carrying `primaryCommitteeCode`, so joins use our existing key unchanged.
> - **No terms-of-service prohibition.** IECDB's `robots.txt` is `User-agent: *` / `Disallow:` (nothing restricted) and the Iowa.gov policies page has no automated-access or rate-limit clause; this is Chapter 22 open-record data. That is permission-by-absence, not a licence — throttle, identify the client, cache.
> - **Migration plan is Phases A–D** in the note. Phases A–C come **before** `render.R` / index / donor pages, because Phase D changes the data model those pages would be built on.
> - **Phase A is built:** [`R/campaign_finance/iecdb_api.R`](R/campaign_finance/iecdb_api.R) — the only thing that may call the API. Throttled (1s default), retrying, request-budgeted, with per-endpoint schema contracts that **fail** on missing required fields. `iecdb_health_check()` is a 2-request canary; run it before any ingest.
> - **Open blocker before cutover: the API does not return loans.** `transactionType = "CON"` is a category returning `CON` + `INK` rows only; no `LOANREC`. Verified across five committees of four types: **131 loan transactions, 0 returned**. The decisive test is a same-date pair — Henderson for House (2570) has both a $20 `CON` and a $180 `LOANREC` on 2026-07-06, and querying the API for that single date returns only the contribution. That rules out any date-coverage explanation. One committee (CTY51589, whose only two transactions are loans) returns empty entirely despite being findable via committee search. In-kind is also unreliable — one committee's `INK` rows came back, another's didn't. **data.iowa.gov remains the only complete source for loans**; switching without resolving this silently drops them.
> - **`referenceDR2Id` is not period attribution** despite the name — it is the all-zeros GUID on every ordinary contribution. Period attribution must be inferred from `date` against the filing-period boundaries.

**Current data currency (as of the 202607 export):** state contributions run through **2026-07-14** (3,200,787 rows), expenditures through **2026-07-16** (652,661 rows), 8,020 committees. FEC data is still from the 2026-05-10 download and has not been refreshed.

### Source Files

Exports live in `data/campaign_finance/source/IECDB/{YYYYMM}/` — **one directory per download**, named for the export month (`202603`, `202607`, …). Older exports are kept for reference; the pipeline always reads the newest directory.

Each export contains:
- contributions received — individual contribution transactions (~3.2M rows). **May arrive split across several numbered part files** (`..._part_0001.csv` … `_0004.csv`); the parts are chronological, non-overlapping, and each carries its own header row.
- expenditures — expenditure transactions (~650k rows)
- registered political candidates/committees — active committee registry (~1,700 rows)
- other state/federal PACs filing in Iowa — **not currently read by the pipeline** (exploratory scripts only)

**Export vintages differ in both column names and date formats**, so `utils.R` normalizes them:

| | through `202603` | from `202607` |
|---|---|---|
| Column names | human-readable (`"Contribution Amount"`) | machine (`amount`, `committee_cd`, `first_nm`) |
| Transaction dates | `MM/DD/YYYY` | ISO `YYYY-MM-DD` |
| Election dates | `2022 Nov 08 12:00:00 AM` | `2026-11-03 00:00:00` |

`utils.R` provides the shims, all applied in `02_clean_normalize.R`:
- `latest_iecdb_export()` — newest `YYYYMM` directory
- `find_source_files(pattern)` / `find_source_file(pattern)` — case-insensitive match within that export; the plural form returns all parts, name-sorted so they stack in order
- `rename_if_present(df, mapping)` with `IECDB_CONTRIBUTION_COLS` / `IECDB_EXPENDITURE_COLS` / `IECDB_REGISTERED_COLS` — maps either vintage onto the canonical (older) column names the DuckDB views and templates expect
- `parse_iecdb_date()` / `parse_iecdb_election_date()` — accept either format, per element

**Adding a new export:** drop it in a new `IECDB/{YYYYMM}/` directory and re-run `02` → `04`. No code change is needed unless IECDB renames columns again — in which case extend the mapping vectors in `utils.R` rather than editing `02`.

Committee codes are a mix of numeric (`5185`, ~5,600 codes) and alphanumeric (`CTY51589`, `SWGA51409`, ~1,400 codes) strings, with no leading zeros. **Always pass them as strings** — a numeric-looking code reaching DuckDB as a number makes it cast the whole varchar column to INT32 and fail on the alphanumeric rows.

### Pipeline

#### Iowa state data (IECDB)

```
01_build_committee_lookup.R       POST requests to IECDB web API
                                  (already an IECDB API consumer — uses
                                   /api/publicreports/statements and
                                   /api/search/committee; stores committee_uuid,
                                   which is the GUID the transaction API needs)
                                  → processed/committee_lookup.rds
                                    (~7,900 committee codes, party affiliation, metadata)

02_clean_normalize.R              reads newest IECDB export + committee_lookup.rds
                                  (stacks contribution part files; harmonizes
                                   column names + date formats across vintages)
                                  → processed/contributions.parquet
                                    processed/expenditures.parquet
                                    processed/committees.parquet
                                    (registered CSV full-joined with API lookup;
                                     party resolved, committee_code key unified)

[03_link_donors.R]                fuzzy donor deduplication — BUILT BUT NOT WORKING
                                  stringdist + igraph connected components
                                  (not reclin2, as originally planned)
                                  → processed/donor_crosswalk.parquet  ← never produced
```

`03_link_donors.R` exists but does not run to completion, and `donor_crosswalk.parquet` has never been produced. **Nothing downstream depends on it** — `04_build_database.R` contains no reference to a crosswalk or `canonical_key`, so the donor views use exact-match `donor_key` only. Refreshing data does not require fixing it.

#### Federal data (FEC)

```
download/fec_contributions.R      downloads FEC bulk zips per cycle (2020, 2022, 2024, 2026)
                                  reads cn.txt + ccl.txt to derive authorized committee IDs
                                  for Iowa House and Senate candidates (CAND_OFFICE_ST == "IA",
                                  CAND_OFFICE %in% c("H","S")); streams indiv*.zip via
                                  unz() + read_delim_chunked(), filters by CMTE_ID
                                  → source/federal/{cycle}/indiv_iowa_cands.txt
                                    source/federal/{cycle}/cm.txt
                                    source/federal/{cycle}/cn.txt
                                    source/federal/{cycle}/ccl.txt
                                  Column names fetched from FEC header files; cached in source/federal/headers/

02a_clean_normalize_federal.R     reads all cycle source files, stacks across cycles
                                  parses NAME ("LAST, FIRST") into split fields
                                  maps ENTITY_TP → donor_type; builds fec_donor_key
                                  joins cm + cn + ccl → unified fec_committees with party + office
                                  → processed/fec_contributions.parquet
                                    processed/fec_committees.parquet
```

#### Database build (both sources)

```
04_build_database.R               ingests all Parquet → DuckDB
                                  → data/campaign_finance/campaign_finance.duckdb
                                  always creates 6 state summary views;
                                  creates 6 FEC summary views if fec_*.parquet exist
```

### Data Storage Pattern (Campaign Finance)

Campaign finance uses **Parquet + DuckDB** rather than `.rds` because of data volume:

- **Parquet** (`processed/*.parquet`) — columnar, compressed intermediate files. Open format; readable with `arrow`/`dplyr` without DuckDB.
- **DuckDB** (`campaign_finance.duckdb`) — self-contained analytical database. Quarto templates connect via `duckdb` + `dbplyr` and filter to one committee or donor before pulling into memory — the full dataset never loads per render.

### Key Columns

**contributions.parquet** primary keys/join fields:
- `committee_code` — recipient committee (joins to `committees.parquet`)
- `donor_key` — pipe-delimited string (`IND|LAST|FIRST|CITY|STATE` or `ORG|NAME|CITY|STATE` or `CMT|code`); stable exact-match donor ID; fuzzy step 03 will collapse near-duplicates
- `donor_type` — `"individual"`, `"organization"`, or `"committee"`
- `donor_attribution` — `"itemized"` / `"unitemized"` / `"unidentified"`; see below
- `norm_*` columns — uppercase stripped fields for fuzzy matching input

#### Donor attribution (added 2026-07-25)

Not every contribution row describes a gift from an identifiable donor. IECDB files two kinds of report-level bookkeeping as ordinary transaction rows:

| `donor_attribution` | What it is | Rows | Amount |
|---|---|---|---|
| `itemized` | a real named donor | 3,154,190 | $939.2M |
| `unitemized` | lump sum for everyone below the itemization threshold, filed under a placeholder name | 14,875 | $26.5M |
| `unidentified` | filed with no donor name, organization, or committee at all (`donor_type == "unknown"`) | 31,722 | $13.5M |

Both non-itemized kinds are **real money** and stay in committee totals. Neither is a donor, so both are excluded from donor-facing views. Without this, a largest-donors ranking puts `Unitemized Unitemized` and `(Unknown)` in the top five.

Session log for this and the 202607 export migration: [`notes/2026-07-25_campaign-finance-202607-refresh.md`](notes/2026-07-25_campaign-finance-202607-refresh.md).

`classify_donor_attribution()` in `utils.R` matches `UNITEMIZED_TOKENS` as a **substring** (not a word boundary) against `norm_org` / `norm_first` / `norm_last`. The normalizers delete punctuation without inserting a space, so `Cash-Unitemized` collapses to `CASHUNITEMIZED` with no boundary to anchor to. Only add tokens with the same confidence that they can't appear inside a real name.

#### Transaction types — "total raised" is currently overstated (open, 2026-07-25)

`transaction_type` carries three values, and **the pipeline sums all three into `total_raised`**:

| Type | Meaning | Transactions | Amount | Share |
|---|---|---|---|---|
| `CON` | cash contribution | 3,129,935 | $819.7M | 83.7% |
| `INK` | in-kind (goods/services, never touches cash) | 66,327 | $144.8M | 14.8% |
| `LOANREC` | loan received (repayable, not income) | 4,525 | $14.6M | 1.5% |

Neither in-kind nor a loan is a donation, so any page that says "raised" or ranks "donors" is currently wrong by up to 16%. The failure is most visible on committees financed by candidate loans: **Lahn for Governor** shows Zach Lahn as its largest donor at $2,521,569, which is actually a $2.5M repayable loan (two draws, 2025-12-31 and 2026-05-22) plus $21,569 in-kind — he has contributed **no** cash. Iowa Capital Dispatch reports these separately for exactly this reason.

Fix is the same shape as `donor_attribution`: split the types in `02_clean_normalize.R` and have the donor-facing views in `04` use `CON` only, while committee totals report contributions, in-kind and loans as distinct figures. Not yet done.

#### IECDB reporting periods

Useful when comparing our figures to news coverage, which always quotes a single period. 2026 statewide periods, confirmed from the filings index:

| Period | Notes |
|---|---|
| January 1 – May 14 | |
| May 15 – Tuesday preceding the primary | = May 26 (primary June 2) |
| Wed. preceding primary – July 14 | = May 27 – July 14 |

Our figures reproduce reported ones exactly when the period is matched: Sand Jan 1 – May 14 = $9,675,454 against a reported $9.68M; Lahn May 15–26 `CON` only = $60,050 against a reported "a little over $60,000", with the $500,000 loan the article lists separately sitting in `LOANREC`. Mismatches are almost always a period or transaction-type definition difference, not a data error — check both before assuming a bug.

#### Summary rows — known, scoped, deliberately deferred (2026-07-25)

Legacy **summary rows** are *not* flagged and still rank as donors: `Contributions Total` is the #3 largest "donor" at $25.4M, `Total Summary` the #8 at $6.3M.

**What they are:** rows with no contributor at all, where a line label off a filed disclosure report landed in the contributor name field. The raw record is unmistakable — `organization_nm = "Contributions Total"` (or `first_nm = "total"`, `last_nm = "Summary"`), with `N/A` or `00000` in address/city/zip, no check number, and no contributing committee.

**Scope:**

| | |
|---|---|
| Transactions | 5,807 (**0.18%** of all rows) |
| Committees | 743 — of which **650 clear $10k** and 268 are still active in 2024+ |
| Dollars | $49.2M (**5.0%** of all money) |
| Era | 2003–2012; only 2 transactions after 2012 |

Three distinct labels (`Contributions Total`, `Inkind Contributions Total`, `Total Summary`) plus ~22 spelling variants (`Total_a`, `Total, Contributions`, `Total Schedule A`). `Total Summary` runs to 2018; the other two stop in 2012 and 2007.

**Why it needs eyes, not a regex.** Two reasons. First, matching on a leading "Total" catches **real businesses** — `Total Maintenance Inc`, `Total Tax Service`, `Total Detailing` are genuine Iowa donors. "Unitemized" is a term of art that never appears in a real name; "Total" is an ordinary word. Second, the rows can't be uniformly deleted or kept: across affected committee-years, 603 have a summary row and *no* itemized detail (the summary is the only surviving record), 465 have a larger summary, and 429 have larger itemized. Period-by-period testing on Iowans for Nussle was inconsistent — May 2006 matches the itemized total almost exactly ($1,181,239 vs $1,195,094) while October 2006 is off by 2× ($1,441,757 vs $2,962,921).

**When it stops being ignorable:** the first mass render of committee pages. It is not only a leaderboard problem — on an affected committee's own page the bookkeeping row ranks as its top donor (Iowans for Nussle shows `Contributions Total` at $6.0M above its real top donor at $1.4M). Harmless while nothing is published; visible on 650 pages the moment they are. The label list is short and finite, so an afternoon of manual classification would settle it permanently.

**committees.parquet** primary key: `committee_code` (unified from both sources)

**fec_contributions.parquet** primary keys/join fields:
- `CMTE_ID` — FEC recipient committee ID (joins to `fec_committees.parquet`); scoped to Iowa H/S candidate committees only
- `fec_donor_key` — same pipe-delimited format as state `donor_key`; built with the same `make_donor_key()` helper from `utils.R`; donors may be from any state
- `donor_type` — `"individual"`, `"organization"`, or `"committee"` (mapped from FEC `ENTITY_TP`)
- `cycle` — 4-digit election cycle year (2020 / 2022 / 2024 / 2026)
- `norm_*` columns — same normalization as state data; used for cross-dataset fuzzy matching (step deferred)
- `EMPLOYER`, `OCCUPATION` — FEC-only fields; useful for disambiguating common names during matching

**fec_committees.parquet** primary key: `CMTE_ID`; includes `party`, `office`, `candidate_name` resolved from cm + cn + ccl join

### DuckDB Summary Views

Pre-aggregated views cover all Quarto template queries — no full-table scans at render time.

**State (Iowa IECDB) — always present:**

Views marked **itemized-only** filter to `donor_attribution = 'itemized'`. Money totals (`total_raised`, `total`) in the committee-level views stay inclusive of all rows; only donor identity is filtered. `n_unique_donors` counts itemized keys only, in both `committee_summary` and `committee_year`.

| View | Grain | Scope |
|---|---|---|
| `committee_summary` | 1 row / committee | all rows (totals); itemized-only donor count |
| `committee_donor` | 1 row / committee × donor | **itemized-only** |
| `committee_year` | 1 row / committee × year × donor_type | all rows (totals); itemized-only donor count |
| `donor_summary` | 1 row / donor_key | **itemized-only** |
| `donor_committee` | 1 row / donor × committee | **itemized-only** |
| `donor_year` | 1 row / donor × year × party | **itemized-only** |

**Federal (FEC) — present only if `fec_*.parquet` files exist:**

| View | Grain |
|---|---|
| `fec_committee_summary` | 1 row / CMTE_ID |
| `fec_committee_donor` | 1 row / CMTE_ID × fec_donor_key |
| `fec_committee_year` | 1 row / CMTE_ID × year × donor_type |
| `fec_donor_summary` | 1 row / fec_donor_key |
| `fec_donor_committee` | 1 row / fec_donor_key × CMTE_ID |
| `fec_donor_year` | 1 row / fec_donor_key × year × party |

### Quarto Templates

All four templates query the DuckDB database via `duckdb` + `dbplyr` (this wiring is **done** — earlier notes describing them as reading source CSVs are stale).

**Theming (fixed 2026-07-25).** These pages previously rendered with stock Bootstrap and no `custom.scss`. The cause was `- "!campaign_finance/"` in the `_quarto.yml` render list: excluding a directory makes Quarto treat those files as standalone documents rather than project members, so they never saw the site theme. The directory is now included (only the ~13 MB OJS variant stays excluded), and CF pages render into `docs/campaign_finance/templates/` carrying the same themed Bootstrap hash and `styles.css` as legislature pages. As with the legislature templates, a project-wide render emits a default-parameter copy there; real per-entity pages come from explicit `-P` renders. Session log, including the shared-component split and the recipient-page redesign: [`notes/2026-07-25_cf-redesign-phase1.md`](notes/2026-07-25_cf-redesign-phase1.md).

`site/campaign_finance/templates/recipient_template.qmd` — parameter: `committee_code`; static R/gt output. Coerces the parameter with `as.character()` before querying, so numeric-looking codes passed via `-P` don't trigger the INT32 cast failure described above.
`site/campaign_finance/templates/donor_template.qmd` — parameter: `donor_key`; static R/gt output
`site/campaign_finance/templates/fec_recipient_template.qmd` — parameter: `CMTE_ID`; static R/gt output over the FEC views; adds Employers & Occupations tabs (FEC-only fields)
`site/campaign_finance/templates/recipient_template_ojs.qmd` — experimental OJS version of the recipient template with reactive year-range filtering (see notes below and `notes/2026-05-09_campaign-finance-templates-ojs.md`)

Verified rendering against the 202607 data: `recipient_template` (committee 5185, Rob Sand for Iowa) and `donor_template` (default donor key) both render clean, with page figures matching `committee_summary` exactly.

> **Known issue:** `fec_recipient_template.qmd` defaults to `CMTE_ID: "C00401224"`, commented as "Chuck Grassley for Senate" — that ID is actually **ActBlue**, which has zero rows in the Iowa-filtered FEC dataset, so the checked-in render is entirely empty-state. The template has never been exercised against a committee that has data. Use `C00546788` (Joni for Iowa) or `C00708164` (Theresa Greenfield) instead.

> **dbplyr is pinned to 2.5.0.** dbplyr 2.6.0 requires `dplyr::filter_out()` (dplyr ≥ 1.2.0) while the project pins dplyr 1.1.4; the mismatch made every campaign finance template fail at `library(dbplyr)`. Downgrading dbplyr was chosen over upgrading dplyr because the legislature pipeline (which runs daily in CI) depends on dplyr and does not use dbplyr at all.

> **Rendering constraint:** each parameterized render **must** be given a distinct `output_file`. Quarto derives the figure directory from the output name, so two renders sharing a name share `<name>_files/` and silently overwrite each other's charts — producing a page whose plots belong to a different committee than its numbers. `render_bill()` already avoids this by passing `basename(output_file)` per bill; `render.R` for campaign finance must do the same. Note also that `--output` is a **no-op inside a Quarto project**, so it can't be used to separate them.

> **TODO:** `R/campaign_finance/render.R` (manifest-based incremental rendering, same pattern as legislature) still needs to be built. Nothing under `site/campaign_finance/` is published — there is no `index.qmd`, no `docs/campaign_finance/` output, and the navbar entry in `_quarto.yml` is still commented out. The only rendered artifacts are one-off HTML files sitting next to the templates.

### Template layout pattern (as of 2026-05-09)

Both static templates follow the same structure:
- Inline summary section **above** the tabset (not inside a Summary tab): key stats + top donors/recipients + type/party breakdown
- `:::{ .panel-tabset }` below with domain-specific tabs
- All count columns use `fmt_integer()` in `gt` tables (not just currency columns)
- City name fields: `clean_city` is title-cased ("Des Moines"); `norm_city` / `norm_state` are UPPERCASE ("DES MOINES", "IA"). Critical for any joins — both sides must be normalized to the same case.

### OJS reactive template (`recipient_template_ojs.qmd`)

An experimental version that adds client-side year-range filtering using Observable JavaScript. The R data-loading and static summary sections are unchanged; the tabset content is driven by OJS.

**Architecture:**
- R passes data to OJS via `ojs_define()` (column-major → `transpose()` → row-major arrays)
- Arquero tables (`contribs_tbl`, `by_year_tbl`) created once; `range_tbl` is the reactively filtered view
- Shared `Inputs.range()` sliders (`shared_start`, `shared_end`) defined above the tabset; OJS global scope means all tabs share the same filter
- Leaflet interactive map for Iowa (county choropleth + city dots), loaded via `require("leaflet@1.9.4")`

**OJS import compatibility rules (important — see full details in notes file):**

| Pattern | Status |
|---|---|
| `import { A, B } from "@uwdata/arquero"` | ✅ Use for Arquero |
| `X = require("pkg@version")` | ✅ Use for CJS libraries (Leaflet, etc.) |
| `import { A } from "npm:pkg"` | ✅ Works for some packages |
| `import X from "npm:pkg"` | ⚠️ Unreliable; avoid for default exports |
| `import * as X from "..."` | ❌ Hard syntax error — NOT supported |

**Arquero rollup pattern:**
```javascript
.rollup({
  total:        d => op.sum(d.contribution_amount),  // closure OK for sum
  transactions: op.count(),
  city:         op.first('city'),                    // string col name required
  donors:       op.array_agg('donor_display')        // string col name required
})
.derive({ donors: aq.escape(d => new Set(d.donors).size) })  // unique count
```

**Leaflet + tabset fix:** Map initializes while hidden (zero div dimensions). Use `ResizeObserver` to call `map.invalidateSize()` + `map.fitBounds()` on first real resize (when tab becomes visible).

**What doesn't work in OJS:** AG Grid — neither `import { createGrid } from "npm:ag-grid-community@31"` nor `require("ag-grid-community@31")` load correctly in OJS. Use `Inputs.search()` + `Inputs.table()` as a native fallback.

### Key R Packages (Campaign Finance)
`vroom`, `readr`, `dplyr`, `stringr`, `lubridate`, `janitor`, `tidyr`, `arrow`, `duckdb`, `DBI`, `ggplot2`, `gt`, `scales`, `here`, `httr2`, `purrr`, `sf`, `tigris`, `jsonlite`

---

## Target Monorepo Structure

The legislature migration (2026-07-05) realized most of this layout. Still to be built: `R/elections/render.R`, `R/campaign_finance/render.R`, `site/elections/`, and a campaign finance section in the site navbar (currently commented out in `site/_quarto.yml`).

```
ia_transparency_project/
├── R/
│   ├── legislature/          ← from iowa_legislature/R/data_pipeline/ + utils
│   ├── elections/            ← production pipeline (to be built)
│   ├── campaign_finance/     ← production pipeline (to be built)
│   └── exploratory/          ← analysis/exploratory scripts (not production)
│       ├── legislature/      ← from iowa_legislature/analysis/
│       └── elections/        ← from iowa_elections/cleaning/ + scraping/
├── data/
│   ├── legislature/          ← from iowa_legislature/data/
│   ├── elections/
│   │   └── raw/              ← from iowa_elections/data/
│   ├── campaign_finance/
│   │   └── source/           ← raw CSVs (already present)
│   └── general/              ← cross-domain reference data
├── legiscan/                 ← raw LegiScan source data (from iowa_legislature)
├── site/
│   ├── _quarto.yml           (unified navbar across all domains)
│   ├── index.qmd             (unified home page)
│   ├── legislation/
│   ├── legislators/
│   ├── elections/
│   ├── campaign_finance/
│   └── templates/
├── docs/                     ← rendered output (GitHub Pages)
├── notes/
├── renv.lock
└── ia_transparency_project.Rproj
```

Each domain has its own render function under `R/{domain}/render.R`; a top-level `R/render_all.R` orchestrator calls all of them. See `notes/2026-03-06_migration-plan.md` for architecture decisions and `notes/2026-03-08_file-migration-map.md` for the detailed file-by-file migration map.

## Iowa Secretary of State Website (sos.iowa.gov)

The SOS website blocks requests without browser-like headers, returning 403. Use `httr2` with explicit `User-Agent` and `Referer` headers. Use the pattern in `R/elections/download/shapefile_precincts.R` as the template:

```r
library(httr2)

request(url) |>
  req_headers(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer`    = "https://sos.iowa.gov/"
  ) |>
  req_perform()
```

**Important:** The SOS site runs Akamai bot detection. A full Chrome UA string (e.g. `... Chrome/122.0.0.0 Safari/537.36`) triggers a 403; the shorter `AppleWebKit/537.36` string above passes through. The same headers are required for both page scraping (`resp_body_string()`) and file downloads (`resp_body_raw() |> writeBin(path)`).

## Iowa ENR Website (electionresults.iowa.gov)

The Election Night Reporting site is an Angular SPA — county data is not in the HTML. It loads all county metadata (names, election IDs, version IDs) from a JSON file at runtime. Use the pattern in `R/elections/download/election_results_2024.R`:

```r
# 1. Get current data version
current_ver <- request("https://electionresults.iowa.gov/IA/{electionID}/current_ver.txt") |>
  req_headers(`Referer` = "https://electionresults.iowa.gov/") |>
  req_perform() |> resp_body_string() |> str_trim()

# 2. Fetch county metadata (pipe-delimited: "CountyName|ElectionID|VersionID|Timestamp|16")
settings <- request(paste0("https://electionresults.iowa.gov/IA/{electionID}/", current_ver,
                           "/json/en/electionsettings.json")) |>
  req_headers(`Referer` = "https://electionresults.iowa.gov/") |>
  req_perform() |> resp_body_string()

# 3. Download county file
# https://electionresults.iowa.gov/IA/{CountyName}/{ElectionID}/{VersionID}/reports/detailxls.zip
```

The `Referer` header is required for file downloads (returns 503 without it). The full Chrome UA works fine here — only the Referer matters.

## Precinct Shapefile Coverage Notes (as of 2026-05-02)

The 2024 precinct crosswalk pipeline covers 99 county shapefiles plus 153 city precinct shapefiles downloaded from the SOS site. The coverage is uneven and the column schemas vary considerably. Notes for future integration work:

### Counties with shapefile problems

| County | Issue | Status |
|---|---|---|
| **Jasper** | SOS shapefile uses `Name` column instead of standard `LONGNAME`. SOS has no other version (the `(2)` revision uses the same schema). | `01_combine_precinct_shapefiles.R` remaps `Name` → `LONGNAME` automatically; existing file works. |
| **Polk** | SOS-published "Polk County Precinct Boundaries.zip" is actually a 5-row legislative-district redistricting file with an empty `NAME` column — not a precinct map at all. | Partial coverage assembled from 13 individual Polk-area city shapefiles (Des Moines, Ankeny, West Des Moines, etc.). Unincorporated/rural precincts will need `no_match()`. |
| **Kossuth** | No county shapefile on SOS. | Partial coverage via Algona city file. Non-Algona precincts need `no_match()`. |
| **Lyon** | No county shapefile on SOS. The two available city files (Rock Rapids Precinct 3 & 4) contain only an `Id` column — no precinct names. | No usable shapefile data exists; `no_match()` all Lyon precincts. |

`R/elections/download/shapefile_fix_counties.R` handles Jasper/Polk/Kossuth/Lyon specifically.

### City precinct shapefile schemas

Of the 153 city files in `data/elections/raw/precincts_2020s_cities/`:

- **138 (90%)** use the standard SOS schema with a usable `LONGNAME` column.
- **~10** use alternative columns: `PCT` (Le Claire), `PRECINCT` (Pleasant Hill, Tiffin), `Ward_2020` (Tipton), `Ward` (Waukon), `WardID` (Dubuque Ward), `DIST_NAME` (Iowa City), lowercase `name` (Harlan).
- **2 unusable**: Rock Rapids Precinct 3 & 4 — only `Id` column.

### LONGNAME naming patterns within city files

Most city files use one of these conventions:

- **City-prefixed** ("Adel 1", "CB 01", "1W-2P") — Adel, Council Bluffs, Marshalltown. Already unique; no conflict.
- **Generic numbered** ("Precinct 1", "District 1", "Ward 1") — most files. **Will collide** if multiple files merge into the same county folder. The combine script's `source_label` prefix disambiguates these.
- **Compound** ("Precinct 7 - W2", "Precinct 1 - Ward 1") — Ames, Estherville.

Many city files include placeholder "Unassigned" rows for land not assigned to any precinct — these should be filtered out before matching.

### Possible next steps for city shapefile integration

These are all deferred — recorded here so we don't lose context.

1. **Extend the LONGNAME-fallback list** in `01_combine_precinct_shapefiles.R` from `c("Name", "NAME")` to: `c("LONGNAME", "Name", "NAME", "name", "PRECINCT", "Precinct", "PCT", "DIST_NAME", "Ward_2020", "WardID", "Ward")`. This picks up the ~10 alternative-schema files automatically. Use case-insensitive matching for `name`/`Name`/`NAME` collisions.

2. **Filter out "Unassigned" rows** — add `filter(LONGNAME != "Unassigned")` in the combine step.

3. **Drop the 2 Rock Rapids folders** from `precincts_2020s_cities/` — they have no precinct name at all and just add unlabeled geometry.

4. **Decide how to integrate `precincts_2020s_cities/` with `precincts_2020s/`**. Options:
   - (a) Copy/symlink each city shapefile into the appropriate `precincts_2020s/{county}/` folder (requires a city → county lookup). Existing combine pipeline picks them up automatically.
   - (b) Modify `01_combine_precinct_shapefiles.R` to read both folders and use a city → county lookup at combine time (cleaner separation, but requires the lookup).
   - (c) Modify the combine script to recurse into subdirectories of `precincts_2020s/{county}/` and store city files as `precincts_2020s/{county}/{city}/...`.
   - The city → county mapping can be derived from `tigris::places()` + `tigris::counties()` (already used by `02_enrich_precinct_shapefiles.R`) or hardcoded.

5. **Verify Iowa City** — the file uses `DIST_NAME` and the explorer didn't sample it during inspection; confirm the values are usable precinct names before relying on it.

## Shared UI Components

Added 2026-07-25 when campaign finance pages were brought under the site theme.

`R/ui_helpers.R` (top level, beside `R/render_all.R`) holds the **domain-neutral** pieces: `ui_pill`, `ui_stat_card`, `ui_stat_grid`, `ui_bar_list`, `ui_stepper`, `ui_share_bar`, `IA_PALETTE`, `ia_ramp()`, `theme_ia()` (ggplot), `gt_theme_ia()` (gt).

`R/{domain}/ui_helpers.R` holds anything carrying domain vocabulary and **sources the shared file**, so templates only ever source their own domain's helpers and get both halves. The legislature layer keeps `clean_bill_title`, `status_pill`, `vote_pill`, `ui_paired_bars` (its legend names bills), `ui_profile_header` (hardcodes DEMOCRAT/REPUBLICAN), and `legislator_table`.

**The split rule:** if a campaign finance page and a legislation page could both call it without either reading oddly, it's shared. Anything that maps domain values to styles, or hardcodes domain labels, is not.

Two components take a `format_value` argument because they were originally built for counts and are now also used for money: `ui_bar_list()` and `ui_share_bar()`. Defaults preserve the original comma-grouped integer behavior, so legislature callers were unaffected.

`IA_PALETTE` duplicates the color literals from the top of `site/custom.scss` — HTML components inherit those via CSS, but ggplot and leaflet can't reach SCSS variables. **If the SCSS variables change, change `IA_PALETTE` too.**

Campaign finance has no domain UI layer yet; its templates source `R/ui_helpers.R` directly.

## Conventions

- Raw source files kept strictly separate from processed/derived data
- Processed data format by domain:
  - **Legislature** — `.rds` files (LegiScan JSON → derived CSVs → `.rds`)
  - **Campaign Finance** — Parquet (intermediate) + DuckDB (analytical database)
  - **Elections** — `.rds` for combined shapefiles; raw data as downloaded
- Pipeline scripts numbered by stage (`01_`, `02_`, ...) within `R/{domain}/`; standalone one-off download scripts live in `R/{domain}/download/` without numbers
- Prefix test/scratch scripts with `_` (e.g., `_test_download_5.R`) so they sort separately and are clearly non-production
- Archive deprecated code in an `archive/` subdirectory rather than deleting it
- Environment variables for API keys (e.g., `LEGISCAN_API_KEY`); never hardcode credentials
- R code should have a strong preference for using functions from the tidyverse, but use the base R pipe, `|>`

## Design Context

Captured by `/impeccable init` (2026-07-11). Full strategic doc: [`PRODUCT.md`](PRODUCT.md). The Impeccable design skill (and any design work) reads PRODUCT.md first.

- **Register:** `product` (a data tool — design serves the data, not marketing). **Platform:** `web` (Quarto static site).
- **Audience:** broad Iowa public, no single primary persona; mostly non-experts, low-commitment visits.
- **Positioning:** public Iowa political data made genuinely accessible — and showing how bills, votes, legislators, and money connect (accessibility + relationships, the umbrella project's two pillars).
- **Personality:** neutral, authoritative, trustworthy; restraint signals impartiality.
- **Anti-references:** partisan/campaign styling · generic SaaS/AI-slop dashboards · dated `.gov` drab · overwhelming data dumps.
- **Accessibility:** target WCAG 2.1 AA (R-generated tables/charts/maps are the likely weak spots).
- **Design principles:** (1) neutrality is a design constraint; (2) legible to the newcomer; (3) connections over collections; (4) trust through restraint; (5) hierarchy over volume.
- **DESIGN.md not yet written** — the `custom.scss` visual system (Public Sans / Source Serif 4, `#f7f6f3`, `.ia-*` components) is not locked in; author/generate DESIGN.md once a visual direction is settled.
- **Critique state:** scored snapshots + trends live in `.impeccable/critique/` (home 32/40, legislation 32, legislators 34 as of 2026-07-15; re-run `/impeccable critique <page>` after changes). Open design items: `notes/2026-07-15_design-backlog.md`.
