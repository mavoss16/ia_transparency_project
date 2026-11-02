# 2026-11-01 — Black Hawk 2024 primary from the county file

Part of Phase 1 of the [electoral history plan](2026-10-30_legislator-electoral-history-plan.md).

ENR returns 404 for Black Hawk's 2024 primary precinct file, so the race table had 97 House districts for that primary: HD 61, 62 and 75 lie entirely in Black Hawk and had no rows at all. The statewide county file (`data/elections/raw/county_results/2024_primary.xml`) has Black Hawk's totals and matches the 98 ENR files for every other county ([2026-10-31 log](2026-10-31_2026-primary-enr.md)).

## Changes

- `parsers.R`: `parse_results_file(county_rows = TRUE)` reads a "results by county" file, moving its first column into `county` with `precinct` NA (the shape `02` already uses for the specials).
- `01_parse_precinct_results.R`: `fill_missing_counties()` reads every file in `county_results/` (named `{year}_{type}.{ext}`) and adds rows only for the counties that election's precinct files lack, with `source = "county_results/..."`. Today that is Black Hawk 2024 primary only (the 2026 primary has all 99). It would also pick up Black Hawk's 2022 general if a county file for it lands there.

## Result

- `01`: 76,699 rows (+37: 26 House, 11 Senate). 2024 primary: 100 House, 25 Senate districts.
- `02`: 3,756 race rows (+12, the three Black Hawk-only districts); 25 existing rows in partly-Black Hawk districts gained its votes; none removed. Three 2024 general winners now get their party from the primary (Timi Brown-Powers HD 61, Jerome Amos Jr HD 62, Bob Kressig HD 75); 2024 general candidates without a party went from 34 to 31.
- `03`: 789 matches (was 786), none to review.
- `check_race_table()` `missing_counties`: Jed Ganzer (2022 SD 35 Dem primary) and Kayla Koether (2024 HD 63 general, Winneshiek only, 984 votes).

## Write-ins reported by name (decided 2026-11-02)

The user chose to keep the names with a write-in flag, over folding them into "Write-in" (which would hide Koether's 984-vote campaign) or a manual list.

- `02`: `race_counties` counts every county with a row in the race, write-in rows included (the old check compared named candidates only, so it missed Trevino, the one named Democrat in her primary). `write_in` = a named candidate in fewer counties than `race_counties`, in a multi-county race. Such a name keeps its votes but is not "named" for `unopposed`, `no_candidate`, `margin`, `top_pct` or a primary win. New output columns `write_in`, `race_counties`; `missing_counties` became `named_write_ins`; `write_in_won` includes named write-ins.
- Flagged: Ganzer, Koether, Trevino. Changed: Joe Brown (2022 SD 35 Dem primary) and Michael Bergan (2024 HD 63 general) are now unopposed; the 2026 HD 95 Dem primary now has no ballot candidate. No other race changed; `03` still 789 matches.
- Elections tab (`ui_race()`): the unopposed and no-candidate lines name them ("1,272 write-ins (984 for Kayla Koether)"); in a contested table a named write-in gets its own row marked "(write-in)" and the total becomes "Other write-ins". `legislator_races()` sorts named write-ins before the total.
- `election_digest()` didn't cover the flag, so Bergan's page would not have re-rendered (his votes and winner didn't move). It now appends "write-in" to flagged rows only, leaving other pages' digests unchanged. Against the committed race table, 10 of 155 legislator pages' digests change: the eight in partly or wholly Black Hawk districts (Zumbach, Brown-Powers, Ingels, Meggers, Wulf, Amos, Sires, Kressig), Bergan and Collins.

## Also found

- **Renee Hardman (SD 16):** succeeded Claire Celsi between sessions (Celsi's last vote 2025-05-14, Hardman's first 2026-01-21). The user found no special for SD 16 on the SOS results site. Open in `ROADMAP.md`.
- **Undated roll calls:** seven 2026 Senate committee-report roll calls carry LegiScan's `0000-00-00` date (the recurring readr "parsing issues" warning on `rollcalls.csv`). Open in `ROADMAP.md`.
