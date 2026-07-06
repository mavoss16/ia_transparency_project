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
│   │   └── 04_build_database.R           ← Parquet → DuckDB + summary views (state + FEC)
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
│   │   ├── simplify_districts.R
│   │   └── archive/                      ← deprecated scripts incl. old_pipeline/
│   └── render_all.R                      ← top-level orchestrator (all domains)
├── data/
│   ├── campaign_finance/
│   │   ├── campaign_finance.duckdb       ← analytical database (derived)
│   │   ├── processed/                    ← cleaned Parquet files + committee lookup
│   │   └── source/
│   │       ├── [IECDB CSV exports]       ← raw Iowa state contribution/expenditure files
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
│   ├── _quarto.yml                       ← unified site config ("Iowa Political Transparency"); campaign_finance/ excluded from project renders
│   ├── index.qmd                         ← unified home page (legislature section is the live content)
│   ├── about.qmd / status.qmd / styles.css / _vote-table.qmd
│   ├── legislation/                      ← bill browse page
│   ├── legislators/                      ← legislator browse + compare pages
│   ├── templates/                        ← bill / legislator / committee parameterized templates
│   └── campaign_finance/
│       └── templates/
│           ├── recipient_template.qmd        ← per-committee contribution report (static R/gt)
│           ├── donor_template.qmd            ← per-donor contribution report (static R/gt)
│           └── recipient_template_ojs.qmd    ← OJS experimental version with reactive year filter
├── docs/                                 ← rendered site output (GitHub Pages; gitignored artifacts re-render)
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
│   └── 2026-07-05_legislature-migration.md
└── CLAUDE.md
```

## Iowa Legislature

Tracker for the 91st General Assembly (2025–2026). Migrated from the standalone `iowa_legislature` repo on 2026-07-05 via `git filter-repo` + merge, so full git history is in this repo (`git log --follow` works across the move). Verified with `test_render()` (5 bills / 5 legislators / 3 committees, 0 failures). See `notes/2026-07-05_legislature-migration.md` for the full session log. This domain is the architectural reference for the others.

**Post-migration follow-ups (open as of 2026-07-05):**
- Archive the old `iowa_legislature` GitHub repo; delete the throwaway `../iowa_legislature-filtered` clone
- `docs/` holds only partial test-render output — run `render_site(force = TRUE)` before publishing
- No git remote configured yet (GitHub repo + Pages setup pending)

(The renv out-of-sync issue flagged during verification was resolved by a `renv::snapshot()` the same day.)

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

Data sourced from the Iowa Ethics and Campaign Disclosure Board (IECDB). Raw CSV exports live in `data/campaign_finance/source/` and are not committed to git (too large).

### Source Files
- `Iowa_Campaign_Contributions_Received_*.csv` — individual contribution transactions (~476 MB)
- `Iowa_Campaign_Expenditures_*.csv` — expenditure transactions (~106 MB)
- `Registered_Political_Candidates,_Committees_and_Entities_in_Iowa_*.csv` — active committee registry (~1,600 rows)

Filenames include export dates. `find_source_file(pattern)` (defined in each script) selects the most recently modified match, so re-downloading a fresh export requires no code changes.

### Pipeline

#### Iowa state data (IECDB)

```
01_build_committee_lookup.R       POST requests to IECDB web API
                                  → processed/committee_lookup.rds
                                    (~7,900 committee codes, party affiliation, metadata)

02_clean_normalize.R              reads source CSVs + committee_lookup.rds
                                  → processed/contributions.parquet
                                    processed/expenditures.parquet
                                    processed/committees.parquet
                                    (registered CSV full-joined with API lookup;
                                     party resolved, committee_code key unified)

[03_link_donors.R]                fuzzy donor deduplication — NOT YET BUILT
                                  will use reclin2 + norm_* columns from contributions.parquet
                                  → processed/donor_crosswalk.parquet
```

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
- `norm_*` columns — uppercase stripped fields for fuzzy matching input

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

| View | Grain |
|---|---|
| `committee_summary` | 1 row / committee |
| `committee_donor` | 1 row / committee × donor |
| `committee_year` | 1 row / committee × year × donor_type |
| `donor_summary` | 1 row / donor_key |
| `donor_committee` | 1 row / donor × committee |
| `donor_year` | 1 row / donor × year × party |

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

`site/campaign_finance/templates/recipient_template.qmd` — parameter: `committee_code`; static R/gt output
`site/campaign_finance/templates/donor_template.qmd` — parameter: `donor_key`; static R/gt output
`site/campaign_finance/templates/recipient_template_ojs.qmd` — experimental OJS version of the recipient template with reactive year-range filtering (see notes below and `notes/2026-05-09_campaign-finance-templates-ojs.md`)

> **TODO:** `R/campaign_finance/render.R` (manifest-based incremental rendering, same pattern as legislature) still needs to be built.

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
