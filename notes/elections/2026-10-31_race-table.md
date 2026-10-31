# 2026-10-31 — Race table

Phase 1 step 3 of the [electoral history plan](2026-10-30_legislator-electoral-history-plan.md). Follows the [parsers](2026-10-30_legislative-results-parsers.md).

## What was built

- **`02_build_race_table.R`**: `build_race_table()` sums `legislative_results_precinct.rds` into `data/elections/processed/legislative_results.rds`, one row per candidate per race (2,709 rows). Columns follow the [Elections tab design](../site/2026-10-31_elections-tab-design.md): election date (computed: first Tuesday in June, Tuesday after the first Monday in November), district map (`2001` / `2011` / `2021`), votes, share of all votes including write-ins, rank, winner, margin (top two named candidates, votes and share), `unopposed`, `no_candidate`, `convention` (primary top under 35%), counties, source URL (the SOS index page or ENR election). `race_summary()` and `check_race_table()` report coverage and problems.
- **Scott 2020 general**: a fifth layout, `canvass_pdf` in `parsers.R`, reads the county canvass PDF with `pdftotext -raw`. Each contest's precinct totals are checked against its printed county total. All 100 House districts are now present in 2020.
- **2024 primary** downloaded from ENR (98 counties; Black Hawk returns 404).

## Decisions

- **Primary write-ins never "win".** 175 of the 2024 primaries had no filer; the results only show write-in totals, and whether anyone was nominated by write-in is in the canvass. Those races have `no_candidate = TRUE` and no winner.
- **Party in generals** comes from the results file (`party_source = "results"`), else from the primary the candidate won that year (`"primary"`), else NA. Nothing is inferred from other years: a party label on the page must be the ballot's.

## Results

| General | Candidates | Party missing | Note |
|---|---|---|---|
| 2012, 2016 | 227, 236 | 0 | printed in the files |
| 2018, 2020, 2022 | 235, 224, 224 | 235, 211, 224 | 2020 has Scott's from the PDF |
| 2024 | 224 | 34 | 190 filled from the primary |

The 34 in 2024 are convention nominees after an empty or 35%-short primary (David Blom HD 52; Lisa Ossian SD 44; Doug Campbell SD 30, after primary winner Waylon Brown withdrew), independents, and Black Hawk candidates (no primary file).

## Checks

- No race with more or fewer than one winner, other than conventions and no-filer primaries; no general won by a write-in; no surname shared by two candidates in one race.
- Winners vs LegiScan 91st GA: all 150 seats match by last name except mid-session replacements (2025 specials), "Megan Jones" / "Hess Jones" and "Brown-Powers" casing. Party agrees with LegiScan on all 124 seats where the table has it.
- HD 23 2024 matches the design mock: Sorensen 72.1%, margin 7,898 (44.3 points). SD 21 2022 matches the canvass (Bousselot 14,896, Brady 14,336, write-ins 24).
- One flag left: HD 63 2024, Kayla Koether appears in one of the district's three county files (984 votes). Likely a withdrawn or write-in candidate printed by one county; check the canvass.

## Not done

- The general canvass PDFs, which give party for 2018–2022, couldn't be fetched this session: a curl download from sos.iowa.gov was refused by the permission check as bot-detection circumvention. They need the downloader 403 fixed or a manual download.
- Incumbent, open seat and `people_id` come from the crosswalk (step 4).
