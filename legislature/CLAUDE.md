# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Iowa Legislature tracker for the 91st General Assembly (2025). Pulls legislative data from LegiScan API, stores in R data formats, and generates a static Quarto website with individual bill and legislator pages.

## Directory Structure

```
iowa_legislature/
├── site/                      # Quarto source files
│   ├── _quarto.yml
│   ├── index.qmd
│   ├── legislation/index.qmd
│   ├── legislators/index.qmd
│   └── templates/
│       ├── bill_template.qmd
│       └── legislator_template.qmd
├── R/                         # All R scripts
│   ├── render_site.R          # Main rendering orchestrator
│   ├── utils.R                # Helper functions
│   ├── data_pipeline/         # LegiScan data fetching
│   │   └── download_data.R
│   └── daily/                 # Daily update scripts
├── legiscan/                  # Raw LegiScan data
│   ├── files_ga91/            # CSV files
│   └── files_ga91_json/       # JSON files
├── data/                      # Processed RDS files
├── docs/                      # Rendered website (GitHub Pages)
├── shiny_app/                 # Legacy Shiny dashboard
└── archive/                   # Deprecated files
```

## Data Flow Architecture

```
LegiScan API → R/data_pipeline/download_data.R → legiscan/files_ga91/
                                                        ↓
                                    site/templates/ (bill_template.qmd, legislator_template.qmd)
                                                        ↓
                                              R/render_site.R (incremental rendering)
                                                        ↓
                                              Static website in docs/
```

## Common Commands

All commands run in R from the project root:

```r
source("R/render_site.R")

# Check what needs rendering
render_status()

# Incremental render (only changed items)
render_site()

# Force full re-render
render_site(force = TRUE)

# Test with 5 bills and 5 legislators
test_render()

# Render only index pages (no individual bill/legislator pages)
render_index_pages()

# Clear manifest to force re-render next time
clear_manifest()
```

Preview site locally: `quarto preview site/` from terminal.

## Incremental Rendering System

The `render_manifest.csv` tracks rendered items using LegiScan hashes:
- Bills: `change_hash` from JSON files
- Legislators: `person_hash` from JSON files

Only items with changed hashes are re-rendered. Use `clear_manifest()` to force full re-render.

## Key Files

| File | Purpose |
|------|---------|
| `R/render_site.R` | Main rendering orchestrator |
| `R/utils.R` | Helper functions (`scrape_lobbyist_declarations`, `items_to_df`) |
| `R/data_pipeline/download_data.R` | Downloads LegiScan data (requires API key) |
| `site/templates/bill_template.qmd` | Template for individual bill pages (param: `bill_num`) |
| `site/templates/legislator_template.qmd` | Template for legislator pages (param: `people_id`) |
| `site/index.qmd` | Home page with recent activity |
| `site/legislation/index.qmd` | Browse all bills |
| `site/legislators/index.qmd` | Browse all legislators |

## Data Sources

**LegiScan CSV files** (`legiscan/files_ga91/`):
- `bills.csv` - Bill metadata
- `people.csv` - Legislator info
- `sponsors.csv` - Bill-sponsor relationships
- `votes.csv` - Individual vote records
- `history.csv` - Bill action history

**LegiScan JSON files** (`legiscan/files_ga91_json/`):
- `bill/{bill_number}.json` - Detailed bill data
- `people/{people_id}.json` - Legislator profiles
- `vote/{roll_call_id}.json` - Roll call details

## Environment Variables

- `LEGISCAN_API_KEY` - Required for `download_data.R`

## Output

Website renders to `docs/` directory (configured for GitHub Pages):
- `docs/legislation/{bill_number}.html` - Individual bill pages
- `docs/legislators/{people_id}.html` - Individual legislator pages

## R Package Dependencies

Core: `readr`, `dplyr`, `tidyr`, `stringr`, `purrr`, `jsonlite`, `gt`, `quarto`, `here`, `rvest`
