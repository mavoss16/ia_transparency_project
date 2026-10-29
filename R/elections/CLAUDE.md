# Elections

Precinct-level election results and precinct shapefiles. **No production pipeline or site section yet** (`R/elections/render.R` and `site/elections/` are still to be built). Raw downloads in `data/elections/raw/` are not committed; `data/elections/processed/` is.

## Scripts

```
download/                               standalone acquisition (no numbers)
  shapefile_precincts.R                 scrape + download 2020s county shapefiles (sos.iowa.gov)
  shapefile_city_precincts.R            all city precinct shapefiles (gap-fill source)
  shapefile_fix_counties.R              targeted fix for Jasper / Polk / Kossuth / Lyon
  election_results_2022.R               precinct XLS from sos.iowa.gov (2000–2022), download_sos_election(year, type)
  election_results_2024.R               precinct XLSX from electionresults.iowa.gov (ENR)
precinct_matching/                      shapefile ↔ election-precinct crosswalk
  01_combine_precinct_shapefiles.R      per-county shapefiles → precincts_2020s.rds
  02_enrich_precinct_shapefiles.R       Census place/township overlap columns
  03_crosswalk_precincts_2024.R         auto-match + manual template for 2024
  manual_crosswalk.R                    interactive console helpers (sourced repeatedly)
  explore_shapefiles.R                  inspection helpers
clean_precinct_elections_2024.R         ENR XLSX → precinct_elections_2024.csv
_test_download_5.R, _test_scrape_urls.R scratch
```

Older exploratory scripts (2020 precinct cleaning and fuzzy matching) are in `R/exploratory/elections/`. Session notes: `notes/elections/2026-03-10_precinct-shapefiles-download.md`, `notes/elections/2026-03-14_precinct-shapefiles-pipeline.md`, `notes/elections/2026-04-22_elections-download-scripts.md`.

## Iowa Secretary of State (sos.iowa.gov)

Returns 403 without browser-like headers, and runs Akamai bot detection: a full Chrome UA string (`... Chrome/122.0.0.0 Safari/537.36`) is **blocked**, while the short string below passes. The same headers are needed for page scraping (`resp_body_string()`) and downloads (`resp_body_raw() |> writeBin(path)`). Template: `download/shapefile_precincts.R`.

```r
request(url) |>
  req_headers(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer`    = "https://sos.iowa.gov/"
  ) |>
  req_perform()
```

## Iowa ENR (electionresults.iowa.gov)

An Angular SPA: county data is not in the HTML; county metadata comes from a JSON file at runtime. The `Referer` header is required for downloads (503 without it); the full Chrome UA is fine here. Template: `download/election_results_2024.R`.

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
