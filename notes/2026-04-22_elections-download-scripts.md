# 2026-04-22 — Elections Download Scripts & Folder Reorganization

## Summary

Audited the existing elections scripts, added download scripts for 2022 and 2024 precinct election results, and reorganized the `R/elections/` folder to separate one-off download scripts from pipeline scripts.

---

## Script Audit

### What existed

| Script | Purpose | Output |
|--------|---------|--------|
| `01_download_precinct_shapefiles.R` | Download 2020s precinct boundary shapefiles from sos.iowa.gov | `data/elections/raw/precincts_2020s/{county}/` |
| `02_combine_precinct_shapefiles.R` | Combine county shapefiles into single `sf` object | `data/elections/precincts_2020s.rds` |
| `_test_download_5.R` | Scratch: tested shapefile download for 5 counties; superseded by `01_` | — |
| `_test_scrape_urls.R` | Scratch: prototype of URL scraping logic now in `01_`; superseded | — |

### What was missing

- **2022 election results** — `data/elections/raw/precinct_elections_2022/` existed but was empty, no download script.
- **2024 election results** — no folder or script.
- No download scripts for 2000–2020 (data already present, provenance unknown).
- No processing scripts for election result XLS files (reading, normalizing across years, joining to shapefiles).
- No equivalent of `combine_precinct_shapefiles.R` for the 2010s shapefile.

---

## New Scripts

### `R/elections/download/election_results_sos.R`

Downloads precinct-level election results from the Iowa Secretary of State website.

**Source:** `https://sos.iowa.gov/precinct-results-county-{year}-{type}-{n}`  
**File pattern:** `https://sos.iowa.gov/elections/pdf/precinctresults/{year}{type}/{county}.xls`  
**Output:** `data/elections/raw/precinct_elections_{year}/{county}_{year}.xls`

The script exposes a `download_sos_election(year, type)` function — parameterized so it can be reused for other elections on the same site. Called as `download_sos_election("2022", "general")` to fill the 2022 gap.

Key decisions:
- **Scrapes the index page** rather than constructing URLs from a pattern. Some counties use `%20`-encoded spaces, at least one uses a literal space (`black  hawk.xls` with a double space) — scraping avoids having to know this in advance.
- **Filters to the target election.** The 2022 general page contains stray links to 2020 primary and 2022 primary files. Filter: keep only hrefs containing the `{year}{type}` slug (e.g. `2022general`).
- **Short User-Agent required.** The SOS site runs Akamai bot detection. A full Chrome User-Agent string (`Mozilla/5.0 ... Chrome/122.0.0.0 Safari/537.36`) returns 403. The shorter string used in `shapefile_precincts.R` (`Mozilla/5.0 ... AppleWebKit/537.36`) passes through. This matches the pattern already established in the shapefile download script.
- Output files are `.xls` (not `.xlsx`) — the SOS site serves legacy XLS format for this election year.

### `R/elections/download/election_results_2024.R`

Downloads precinct-level election results for the 2024 General Election from the Iowa Secretary of State's Election Night Reporting (ENR) system.

**Source:** `https://electionresults.iowa.gov/IA/122322/web.345435/#/reporting`  
**Output:** `data/elections/raw/precinct_elections_2024/{county}_2024.xlsx`

The ENR site is an Angular SPA — county links are rendered via JavaScript and not accessible from a static HTML fetch. The approach was to use the JSON data files the app loads at runtime.

**How county data is located:**

1. Fetch `https://electionresults.iowa.gov/IA/{stateID}/current_ver.txt` → statewide data version (e.g. `356043`)
2. Fetch `https://electionresults.iowa.gov/IA/{stateID}/{version}/json/en/electionsettings.json`
3. Parse all pipe-delimited county strings embedded in the JSON:
   ```
   "CountyName|ElectionID|VersionID|Timestamp|16"
   ```
   e.g. `"Benton|122328|354411|11/12/2024 3:09:56 PM CST|16"`

**Download URL pattern:**
```
https://electionresults.iowa.gov/IA/{CountyName}/{ElectionID}/{VersionID}/reports/detailxls.zip
```

Each county's files are delivered as a ZIP. The script downloads, extracts the XLS, renames to `{county}_2024.xlsx`, and removes the ZIP.

Key decisions:
- **Referer header required.** The ENR server returns 503 without a `Referer: https://electionresults.iowa.gov/` header. The full Chrome UA works fine here (unlike sos.iowa.gov) — only the Referer matters.
- **99 counties via JSON, not HTML.** The HTML reporting page uses virtual scrolling and only renders ~40 counties at a time. All 99 are available in `electionsettings.json`.
- County names in the URL use underscores for spaces (`Black_Hawk`, `Buena_Vista`) and literal apostrophes for O'Brien. `URLencode(county_url_name, reserved = FALSE)` handles encoding for the download URL.

---

## Folder Reorganization

Download scripts are one-off data acquisition tools, not steps in an ordered pipeline. Numbered prefixes (`01_`, `02_`, etc.) implied a sequential dependency that didn't exist between the download scripts and the shapefile pipeline.

**Before:**
```
R/elections/
├── 01_download_precinct_shapefiles.R
├── 02_combine_precinct_shapefiles.R
├── 03_download_precinct_elections_sos.R
├── 04_download_precinct_elections_2024.R
├── _test_download_5.R
└── _test_scrape_urls.R
```

**After:**
```
R/elections/
├── download/
│   ├── shapefile_precincts.R
│   ├── election_results_sos.R
│   └── election_results_2024.R
├── combine_precinct_shapefiles.R
├── _test_download_5.R
└── _test_scrape_urls.R
```

`combine_precinct_shapefiles.R` stays at the top level — it's a processing script that belongs alongside future processing/cleaning scripts, and it does depend logically on `download/shapefile_precincts.R` having been run first.

---

## Follow-up / Open Questions

- **2000–2020 downloads:** Data exists but no scripts. Worth checking if earlier elections follow the same sos.iowa.gov URL pattern (`/elections/pdf/precinctresults/{year}{type}/{county}.xls`) — if so, `election_results_sos.R` could backfill any missing years.
- **2012 and 2018 have 198 files** (double the usual 99) — likely both primary and general results. Worth verifying before building a processing pipeline that assumes one file per county per year.
- **2022 files are `.xls`, 2000–2020 are `.xlsx`** — processing scripts will need to handle both formats.
- **2024 files are delivered as zipped XLSX** via the ENR system; format differs from the SOS `.xls` files. A future `combine_election_results.R` will need to account for all three formats.
- **CLAUDE.md** folder structure section needs updating to reflect the new `R/elections/download/` layout.
