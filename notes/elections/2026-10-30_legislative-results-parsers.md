# 2026-10-30 — Legislative results parsers

Phase 1 step 2 of the [electoral history plan](2026-10-30_legislator-electoral-history-plan.md). Follows the [downloaders](2026-10-30_election-downloaders.md).

## What was built

`R/elections/legislative_results/`:

- **`parsers.R`**: `parse_results_file(path, type, county)` reads one raw file and returns its State Representative and State Senator rows: county, precinct, chamber, district, party, candidate, votes (the precinct total), contest (raw label). Over and under votes are dropped; write-ins are kept as "Write-in". `detect_layout()` picks the parser from the file's contents, not its year:

  | Layout | Elections | Shape |
  |---|---|---|
  | `contest_sheets` | 2018–2026 (SpreadsheetML), 2020 general (`.xlsx`) | sheet per contest; uses the "Total Votes" columns |
  | `clarity_wide` | 2014, 2016 | row per candidate, column per county-precinct × vote type; sums Polling + Absentee |
  | `race_blocks` | 2010 primary (per county), 2010 general (statewide) | header row per contest, row per precinct |
  | `county_canvass` | 2012 | the county's printed canvass; generals have Election Day / Absentee / Total rows per precinct |

  For SpreadsheetML only the legislative sheets are expanded, so a county takes ~0.1 s (the old 2024 cleaning script parses every contest and takes ~10 minutes for 99 counties).
- **`01_parse_precinct_results.R`**: `parse_all_results()` parses every file under `data/elections/raw/precinct_results/` from 2010 on into `data/elections/processed/legislative_results_precinct.rds`. `results_summary()` counts counties, districts and candidates per election. Skips PDFs and pre-2010 files.

## Run on what's on disk

43,535 rows from the six generals on disk (about 10 minutes):

| General | Counties | House districts | Senate districts | Note |
|---|---|---|---|---|
| 2012 | 99 | 100 | 26 | even seats plus SD 49 |
| 2016 | 99 | 100 | 25 | |
| 2018 | 99 | 100 | 25 | |
| 2020 | 98 | 95 | 25 | Scott is PDF only: its 5 House districts are missing |
| 2022 | 98 | 97 | 33 | Black Hawk not downloaded yet; 2022 elected the odd seats plus some even ones after redistricting |
| 2024 | 99 | 100 | 25 | |

Primaries were tested on one sample county (Adair) per primary 2010–2022, fetched while mapping the SOS site and kept in the session scratchpad, not in the repo. Every layout parsed, and the Adair totals match each file's own total rows (e.g. 2012 general SD 10 Chapman 2,823; 2024 SD 12 Sinclair 2,777).

## Checks

- **2024 general vs `precinct_elections_2024.csv`:** all 349 legislative candidate totals identical.
- **2022 general vs the certified canvass PDF:** HD 1, 2, 45, 99 and SD 1, 21 match exactly, candidates and write-ins (SD 21: Bousselot 14,896, Brady 14,336, write-in 24).
- **Winners vs LegiScan 91st GA members:** 147 of 149 seats (2024 House, each Senate seat's 2022 or 2024 general) match the member's last name. The two others: SD 35 (Cournoyer won 2022, resigned; Zimmer won the 2025 special, not in these files) and HD 6 ("Megan Jones" on the ballot, "Megan Hess Jones" in LegiScan, a case for the crosswalk's name matching).

## Left for the race table (step 3)

- **Party in generals:** the source prints it only in 2012 and 2014, and in 2016 for every county but Adair. For 2010 and 2018–2024 it's NA. The general canvass PDF has it: `pdftotext -raw` prints each candidate as "Name," with the party on the next line.
- **Scott 2020 general:** PDF only; take Scott's county totals from the canvass PDF.
- **2010 names are all caps** ("CLEL BAUDLER").
- Re-run `01_parse_precinct_results.R` once the primaries and statewide generals are downloaded; the parsers shouldn't need changes, but check `results_summary()` for 99 counties and 100 House districts per election.
