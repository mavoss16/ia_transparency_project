# Precinct Shapefiles Download — Status Notes

Date: 2026-03-10

## Goal

Download current (2020s) precinct boundary shapefiles from the Iowa Secretary of State for all 99 counties. These will be used for precinct-level election result mapping, replacing the older `data/elections/raw/precincts_2010s/` shapefile (a single statewide file dated 2014).

Output destination: `data/elections/raw/precincts_2020s/{county}/`

## Script

`R/elections/01_download_precinct_shapefiles.R`

Loops over all 99 Iowa counties, constructs the SOS URL, downloads and unzips each county shapefile. Idempotent (skips already-downloaded counties).

## URL Pattern

```
https://sos.iowa.gov/elections/pdf/shapefiles/County%20Precincts/{County Name} County Precinct Boundaries.zip
```

Spaces encoded as `%20`; apostrophes left as literal (per O'Brien).

## Known URL Oddities

| County | Issue | URL |
|--------|-------|-----|
| O'Brien | Apostrophe must be literal (not `%27`) | `...O'Brien%20County%20Precinct%20Boundaries.zip` |
| Muscatine | Has `(1)` suffix | `...Muscatine%20County%20Precinct%20Boundaries%20(1).zip` |

Both handled via `url_overrides` named vector in the script.

## Status: Blocked

The SOS server returns **HTTP 403 Forbidden** for automated requests. Tried:
- Base R `download.file()` (default user-agent)
- `options(HTTPUserAgent = "Mozilla/5.0 ...")` browser spoof

Neither worked. Likely a WAF or bot-detection rule on the SOS site.

## Next Steps

- Try again later — the block may be time-limited or rate-based
- If still blocked, alternatives include:
  - System `curl` with full browser headers (referer, accept, etc.)
  - Manual download via browser and place zips in `data/elections/raw/precincts_2020s/`
  - Check if there's a bulk download option on the SOS site
