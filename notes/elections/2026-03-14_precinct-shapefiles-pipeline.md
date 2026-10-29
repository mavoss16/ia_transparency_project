# 2026-03-14 — Precinct Shapefiles Pipeline

## Summary

Built the initial pipeline to download and combine Iowa precinct boundary shapefiles from the Iowa Secretary of State website.

## Scripts Created

### `R/elections/01_download_precinct_shapefiles.R`
Downloads per-county precinct boundary shapefiles from the SOS website.

Key decisions:
- **Scrapes download URLs** from `https://sos.iowa.gov/shapefiles-county-precincts` using `httr2` + `rvest`, rather than constructing URLs from a pattern. This was necessary because URL formats vary slightly across counties (discovered after seeing 404 errors from the pattern-based approach).
- **Browser headers required.** The SOS website blocks requests without a browser-like `User-Agent` and `Referer` header. Base R `download.file()` returns 403. The fix is to use `httr2::request() |> req_headers(...) |> req_perform()`. See `CLAUDE.md` for the reusable template.
- County names are extracted from scraped link text via `sub(" County.*", "", text)`.
- Downloads are skipped if the output directory already exists and is non-empty.
- `Map()` is used to apply `download_county_shapefile(county, url)` over the scraped named vector.

### `R/elections/02_combine_precinct_shapefiles.R`
Reads all downloaded per-county shapefiles and combines them into a single `sf` dataset.

Key decisions:
- Finds `.shp` files dynamically within each county subdirectory, accommodating varied file naming across counties.
- Adds a `county` column to each dataset derived from the directory name.
- All non-geometry columns are coerced to character before binding to avoid type conflicts across counties.
- CRS is standardized before `bind_rows()`: the first dataset's CRS is used as the reference, and any differing datasets are transformed with `st_transform()`.
- Output saved to `data/elections/precincts_2020s.rds`.

## Test Scripts

- `R/elections/_test_scrape_urls.R` — isolated test for the URL scraping logic; prints all scraped zip links to confirm they resolve correctly before running the full download.

## Known Issues / Follow-up

- Some counties are missing from the downloaded data. Likely due to additional URL variations not captured by the scraper. To be investigated.
- A few subdirectories in `data/elections/raw/precincts_2020s/` have unexpected names (e.g., `City_of_Maquoketa_Wards__Precincts_9_13___1__zip`, `Buena_Vista_Precinct_Boundaries_zip`) — these appear to be non-standard entries from the SOS page and may need to be handled separately.
