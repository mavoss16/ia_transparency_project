# Elections

Precinct-level election results and precinct shapefiles. **No production pipeline or site section yet** (`R/elections/render.R` and `site/elections/` are still to be built). The race table does reach the live site, through the Elections tab on legislator pages (`site/templates/legislator_template.qmd`). Raw downloads in `data/elections/raw/` are not committed; `data/elections/processed/` is.

## Scripts

```
download/                               standalone acquisition (no numbers)
  shapefile_precincts.R                 scrape + download 2020s county shapefiles (sos.iowa.gov)
  shapefile_city_precincts.R            all city precinct shapefiles (gap-fill source)
  shapefile_fix_counties.R              targeted fix for Jasper / Polk / Kossuth / Lyon
  election_results.R                    precinct results, every election in RESULT_SOURCES (SOS 2006–2022, ENR 2024 on):
                                        download_all_results(), download_results(year, type), results_inventory()
precinct_matching/                      shapefile ↔ election-precinct crosswalk
  01_combine_precinct_shapefiles.R      per-county shapefiles → precincts_2020s.rds
  02_enrich_precinct_shapefiles.R       Census place/township overlap columns
  03_crosswalk_precincts_2024.R         auto-match + manual template for 2024
  manual_crosswalk.R                    interactive console helpers (sourced repeatedly)
  explore_shapefiles.R                  inspection helpers
legislative_results/                    House and Senate results for legislator electoral history
  parsers.R                             parse_results_file(): one parser per file layout, picked from contents
  01_parse_precinct_results.R           every raw results file → legislative_results_precinct.rds
  02_build_race_table.R                 candidate totals per race (votes, %, winner, party) → legislative_results.rds;
                                        also reads the hand-entered specials (legislative_results_special.csv,
                                        county rows; sources in data/elections/raw/special_results/sources.csv)
  03_match_legislators.R                candidates ↔ LegiScan people_id → data/general/candidate_legislators.csv;
                                        adds people_id, incumbent, open_seat to legislative_results.rds
legislator_history.R                    a legislator's races from the race table (legislator_races(), tenure_text(),
                                        block_notes(), election_digest()), for legislator pages
ui_helpers.R                            elections markup (race results, the legislator page Elections tab and
                                        district-card line); sources R/ui_helpers.R and legislator_history.R
clean_precinct_elections_2024.R         2024 general (ENR SpreadsheetML) → precinct_elections_2024.csv
_test_download_5.R, _test_scrape_urls.R scratch
archive/election_results_2024.R         old one-election ENR downloader
```

`01_parse_precinct_results.R` takes ~10 minutes, mostly the 2020 general (`.xlsx`, 29 sheets per county). Scott's 2020 general is a PDF, read with Poppler's `pdftotext -raw` (on PATH in Git Bash, not an R package). Generals list each candidate's party only in 2012, 2014, 2016 (except Adair) and Scott 2020; `02_build_race_table.R` fills the rest from the primary the candidate won that year, and records which in `party_source`. Candidate names are all caps in 2010 (the race table title-cases them).

**Run `02` then `03`:** `02_build_race_table.R` rewrites `legislative_results.rds` without the columns `03` adds. When `03` writes `data/general/candidate_legislators_review.csv` with rows, decide each one: copy it into `candidate_legislators_manual.csv` with a `people_id` (same person) or an empty one (not), plus a note.

Raw results live in `data/elections/raw/precinct_results/{year}_{type}/{county}.{ext}` (statewide files as `statewide.{ext}`). The extension is the real format read from the first bytes, not what the server called it: `xls` (BIFF), `xlsx`, `xml` (SpreadsheetML, or ENR's `detail.xml` report: readxl can't open either, use xml2) or `pdf` (Scott 2020 general is PDF only). Statewide files with **county** rows (SOS's "results by county" downloads, kept as cross-checks and for counties ENR lacks) go in `data/elections/raw/county_results/{year}_{type}.{ext}`, never under `precinct_results/`, which `01` reads in full and would double-count. `data/elections/raw/precinct_elections_2014/` holds superseded per-county 2014 general files; the 2014 general source is the statewide file.

Older exploratory scripts (2020 precinct cleaning and fuzzy matching) are in `R/exploratory/elections/`. Session notes: `notes/elections/2026-03-10_precinct-shapefiles-download.md`, `notes/elections/2026-03-14_precinct-shapefiles-pipeline.md`, `notes/elections/2026-04-22_elections-download-scripts.md`.

## Iowa Secretary of State (sos.iowa.gov)

Returns 403 without browser-like headers, and runs Akamai bot detection: a full Chrome UA string (`... Chrome/122.0.0.0 Safari/537.36`) is **blocked**, while the short string below passes. The same headers are needed for page scraping (`resp_body_string()`) and downloads (`resp_body_raw() |> writeBin(path)`). Template: `download/shapefile_precincts.R`. **As of 2026-10-30 R's httr2 gets 403 from sos.iowa.gov with these headers** while command-line curl with the same User-Agent gets 200; not resolved.

A missing file redirects (302) to an HTML page that returns 200, so check a download's first bytes (BIFF `D0 CF`, ZIP `PK`, `<?xml`), not the status (`sniff_format()` in `download/election_results.R`). Per-county precinct files exist only for 2010–2022; earlier years and all specials are PDFs. Which source and format each election uses: [`notes/elections/2026-10-30_legislator-electoral-history-plan.md`](../../notes/elections/2026-10-30_legislator-electoral-history-plan.md).

```r
request(url) |>
  req_headers(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer`    = "https://sos.iowa.gov/"
  ) |>
  req_perform()
```

## Iowa ENR (electionresults.iowa.gov)

An Angular SPA: county data is not in the HTML; county metadata comes from a JSON file at runtime. The `Referer` header is required for downloads (503 without it); the full Chrome UA is fine here, and curl's default UA gets 403 from CloudFront. `electionsettings.json` is served gzip-encoded (httr2 decodes it; curl needs `--compressed`). Find an election's ID in the "Precinct Results by County - Excel Format" link on the SOS results page. Template: `download/election_results.R`.

```r
# 1. Current data version
current_ver <- request("https://electionresults.iowa.gov/IA/{electionID}/current_ver.txt") |>
  req_headers(`Referer` = "https://electionresults.iowa.gov/") |>
  req_perform() |> resp_body_string() |> str_trim()

# 2. County metadata (pipe-delimited: "CountyName|ElectionID|VersionID|Timestamp|16")
settings <- request(paste0("https://electionresults.iowa.gov/IA/{electionID}/", current_ver,
                           "/json/en/electionsettings.json")) |>
  req_headers(`Referer` = "https://electionresults.iowa.gov/") |>
  req_perform() |> resp_body_string()

# 3. County file
# https://electionresults.iowa.gov/IA/{CountyName}/{ElectionID}/{VersionID}/reports/detailxls.zip
```

Not every election has the Excel report: the 2026 primary has only `reports/detailxml.zip` (`detailxlsfilesize` is `"-"` in the county's `electionsettings.json`). That holds `detail.xml`, a different format from SpreadsheetML (`<ElectionResult>`, `<Contest>`, `<Choice party="REP">`, a `<VoteType>` per vote type with `<Precinct>` rows). `download_enr()` falls back to it, and `parsers.R` reads it as layout `clarity_xml`.

## Precinct shapefile coverage (as of 2026-05-02)

The 2024 crosswalk covers 99 county shapefiles plus 153 city precinct shapefiles from the SOS site. Coverage is uneven and column schemas vary.

### Problem counties (`download/shapefile_fix_counties.R`)

| County | Issue | Status |
|---|---|---|
| **Jasper** | Uses `Name` instead of `LONGNAME` (the `(2)` revision too) | `01_combine` remaps `Name` → `LONGNAME`; works |
| **Polk** | The SOS "Polk County Precinct Boundaries.zip" is a 5-row legislative-district file with empty `NAME`, not precincts | Partial coverage from 13 Polk-area city shapefiles; rural precincts need `no_match()` |
| **Kossuth** | No county shapefile on SOS | Partial via Algona; others need `no_match()` |
| **Lyon** | No county shapefile; the two city files (Rock Rapids 3 & 4) have only an `Id` column | `no_match()` all Lyon precincts |

### City shapefile schemas (`data/elections/raw/precincts_2020s_cities/`)

- **138 of 153** use the standard schema with `LONGNAME`.
- **~10** use other columns: `PCT` (Le Claire), `PRECINCT` (Pleasant Hill, Tiffin), `Ward_2020` (Tipton), `Ward` (Waukon), `WardID` (Dubuque Ward), `DIST_NAME` (Iowa City), lowercase `name` (Harlan).
- **2 unusable:** Rock Rapids Precinct 3 & 4 (`Id` only).

`LONGNAME` conventions: city-prefixed ("Adel 1", "CB 01"; already unique), generic ("Precinct 1", "Ward 1"; **collide** when merged into one county, so `01_combine` prefixes `source_label`), compound ("Precinct 7 - W2"). Many files include "Unassigned" placeholder rows.
