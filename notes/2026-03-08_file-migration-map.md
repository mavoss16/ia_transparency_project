# File Migration Map

Detailed file-by-file mapping for migrating `iowa_legislature` and `iowa_elections` into `ia_politics_transparency`. Decisions made 2026-03-08.

## Decisions

- `iowa_legislature/scripts/` — skip entirely (superseded by `R/data_pipeline/`)
- `iowa_legislature/shiny_app/` — skip for now
- Exploratory scripts (`analysis/`, elections `cleaning/`) → `R/exploratory/{domain}/`
- `iowa_political_contributions` — empty repo; nothing to transfer; `R/donations/` and `data/donations/` created fresh when that phase begins

---

## iowa_legislature

### R Scripts

| Source | Destination |
|--------|-------------|
| `R/data_pipeline/01_incremental_update.R` | `R/legislature/01_incremental_update.R` |
| `R/data_pipeline/01c_generate_csvs.R` | `R/legislature/01c_generate_csvs.R` |
| `R/data_pipeline/02_process_votes.R` | `R/legislature/02_process_votes.R` |
| `R/data_pipeline/02a_vote_analysis_functions.R` | `R/legislature/02a_vote_analysis_functions.R` |
| `R/data_pipeline/02b_legislator_similarity.R` | `R/legislature/02b_legislator_similarity.R` |
| `R/data_pipeline/03_bill_relationships.R` | `R/legislature/03_bill_relationships.R` |
| `R/data_pipeline/03a_resume_scrape_relationships.R` | `R/legislature/03a_resume_scrape_relationships.R` |
| `R/data_pipeline/04_lobbyist_declarations.R` | `R/legislature/04_lobbyist_declarations.R` |
| `R/data_pipeline/04a_legislator_lobbyist_alignment.R` | `R/legislature/04a_legislator_lobbyist_alignment.R` |
| `R/render_site.R` | `R/legislature/render.R` |
| `R/run_pipeline.R` | `R/legislature/run_pipeline.R` |
| `R/utils.R` | `R/legislature/utils.R` |
| `R/simplify_districts.R` | `R/legislature/simplify_districts.R` |
| `R/data_pipeline/archive/` | `R/legislature/archive/` |
| `R/old_pipeline/` | `R/legislature/archive/old_pipeline/` |

### Exploratory Scripts

| Source | Destination |
|--------|-------------|
| `analysis/contributions_explore.R` | `R/exploratory/legislature/contributions_explore.R` |
| `analysis/legislation_analysis.R` | `R/exploratory/legislature/legislation_analysis.R` |
| `analysis/network_analysis.R` | `R/exploratory/legislature/network_analysis.R` |

### Processed Data

| Source | Destination |
|--------|-------------|
| `data/bills/` (*.rds) | `data/legislature/bills/` |
| `data/votes/` (*.rds) | `data/legislature/votes/` |
| `data/lobbying/` (*.rds) | `data/legislature/lobbying/` |
| `data/pipeline_internal/` (*.rds) | `data/legislature/pipeline_internal/` |
| `data/districts/house.rds`, `senate.rds` | `data/legislature/districts/` |
| `data/archive/` | `data/legislature/archive/` |
| `analysis/legislator_floor_vote_combinations.rds` | `data/legislature/analysis/legislator_floor_vote_combinations.rds` |

### Raw Source Data

| Source | Destination |
|--------|-------------|
| `legiscan/files_ga91/` | `legiscan/files_ga91/` |
| `legiscan/files_ga91_derived/` | `legiscan/files_ga91_derived/` |
| `legiscan/files_ga91_json/` | `legiscan/files_ga91_json/` |
| `legiscan/files_2025_json.zip` | `legiscan/files_2025_json.zip` |

### Site

| Source | Destination |
|--------|-------------|
| `site/_quarto.yml` | `site/_quarto.yml` *(merge into unified version)* |
| `site/index.qmd` | `site/index.qmd` *(replace with unified home page)* |
| `site/legislation/index.qmd` | `site/legislation/index.qmd` |
| `site/legislators/` | `site/legislators/` |
| `site/templates/bill_template.qmd` | `site/templates/bill_template.qmd` |
| `site/templates/committee_template.qmd` | `site/templates/committee_template.qmd` |
| `site/templates/legislator_template.qmd` | `site/templates/legislator_template.qmd` |
| `site/_vote-table.qmd` | `site/_vote-table.qmd` |
| `site/about.qmd` | `site/about.qmd` |
| `site/status.qmd` | `site/status.qmd` |
| `site/styles.css` | `site/styles.css` |

### Infrastructure / Config

| Source | Destination | Notes |
|--------|-------------|-------|
| `render_manifest.csv` | `render_manifest.csv` | |
| `renv.lock` | `renv.lock` | Merge with any existing |
| `.github/workflows/daily-update.yml` | `.github/workflows/daily-update.yml` | |
| `google-analytics.html` | `google-analytics.html` | |
| `session_notes/` | `notes/legislature/` | |
| `logs/` | `logs/legislature/` | Consider gitignoring |

### Skip / Do Not Transfer

- `scripts/` — superseded by `R/data_pipeline/`; skip entirely
- `shiny_app/` — skip for now
- `.Rproj.user/` — RStudio IDE state, machine-specific
- `.quarto/` — generated freeze cache, rebuilds automatically
- `docs/` — generated output, will re-render
- `archive/legislation_dashboard.*` — superseded
- `test_data_app/`, `test_gt.html` — scratch artifacts
- `iowa_legislature.Rproj` — replaced by `ia_politics_transparency.Rproj`
- `CLAUDE.md` — consolidate into monorepo CLAUDE.md

---

## iowa_elections

### Exploratory Scripts

| Source | Destination |
|--------|-------------|
| `cleaning/clean_precinct_election_2020.R` | `R/exploratory/elections/clean_precinct_election_2020.R` |
| `cleaning/election_2020_precincts.R` | `R/exploratory/elections/election_2020_precincts.R` |
| `cleaning/precinct_fuzzy_matching_2020.R` | `R/exploratory/elections/precinct_fuzzy_matching_2020.R` |
| `cleaning/precinct_places.R` | `R/exploratory/elections/precinct_places.R` |
| `scraping/precinct_elections.R` | `R/exploratory/elections/precinct_elections.R` |

### Raw Data

| Source | Destination |
|--------|-------------|
| `data/precinct_elections_2000/` through `data/precinct_elections_2020/` | `data/elections/raw/precinct_elections_YEAR/` |
| `data/precincts_2010s/` (shapefiles) | `data/elections/raw/precincts_2010s/` |
| `data/statewide/` | `data/elections/raw/statewide/` |
| `data/precinct_match_2020.csv` | `data/elections/raw/precinct_match_2020.csv` |
| `data/precinct_match_2020_data_entry.xlsx` | `data/elections/raw/precinct_match_2020_data_entry.xlsx` |
| `data/Registered_Political_Candidates__Committees_and_Entities_in_Iowa.csv` | `data/elections/raw/Registered_Political_Candidates_Iowa.csv` |

### Skip / Do Not Transfer

- `iowa_elections.Rproj` — replaced by monorepo `.Rproj`
- `.gitignore` — merge into monorepo `.gitignore`

---

## New Files to Create

These don't exist in any source repo but are needed to wire everything together:

| File | Purpose |
|------|---------|
| `R/render_all.R` | Top-level orchestrator calling each domain's `render.R` |
| `R/elections/render.R` | Elections render function |
| `R/donations/render.R` | Donations render function (stub) |
| `site/elections/index.qmd` | Elections landing page |
| `site/donations/index.qmd` | Donations landing page (stub) |
