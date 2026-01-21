# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Iowa Legislature tracker for the 91st General Assembly (2025). Pulls legislative data from LegiScan API, stores in R data formats, and generates a static Quarto website with individual bill and legislator pages.

## Data Flow Architecture

```
LegiScan API → download_data.R → JSON/CSV files (legiscan/files_ga91/)
                                        ↓
                              Quarto Templates (bill_template.qmd, legislator_template.qmd)
                                        ↓
                              render_site.R (incremental rendering)
                                        ↓
                              Static website in docs/
```

## Common Commands

All commands run in R from the project root:

```r
source("render_site.R")

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

Preview site locally: `quarto preview` from terminal.

## Incremental Rendering System

The `render_manifest.csv` tracks rendered items using LegiScan hashes:
- Bills: `change_hash` from JSON files
- Legislators: `person_hash` from JSON files

Only items with changed hashes are re-rendered. Use `clear_manifest()` to force full re-render.

## Key Files

| File | Purpose |
|------|---------|
| `render_site.R` | Main rendering orchestrator |
| `bill_template.qmd` | Template for individual bill pages (param: `bill_num`) |
| `legislator_template.qmd` | Template for legislator pages (param: `people_id`) |
| `index.qmd` | Home page with recent activity |
| `legislation/index.qmd` | Browse all bills |
| `legislators/index.qmd` | Browse all legislators |
| `legiscan/download_data.R` | Downloads LegiScan data (requires API key) |
| `utils.R` | Helper functions (`scrape_lobbyist_declarations`, `items_to_df`) |

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
