# 2026-11-02 — 2018 primary, incremental parse

## 2018 primary

The user downloaded all 99 county files by hand from `precinct-results-county-2018-primary`. Checked by first bytes and filed as `precinct_results/2018_primary/{county}.{ext}`: 98 SpreadsheetML (`.xml`) and Dickinson as BIFF `.xls`. The staging folder is deleted.

- **Dickinson** is Clarity's county summary export (one row per candidate: `line number`, `contest name`, `choice name`, `party name`, `total votes`), not precinct results. New layout `clarity_summary` in `parsers.R` reads it with precinct NA. Its contest names end in "(Vote For 1)", which the reader strips so the "- REP" suffix gives the primary's party.
- **Write-ins listed by name.** 2018 county files itemize write-in votes as if they were candidates, and some label the write-in tally "Scattering" (Story), "Blank" or "No Name". Those three now read as `Write-in`. In multi-county races the existing county-count rule flags the names (149 rows). In one-county races it can't, and a ballot candidate written into another party's primary for the same seat (Skyler Wheeler HD 4 Dem/Lib, Zach Whiting SD 1 Lib, Quirmbach SD 23 Rep) made two "nominees" for one person, which broke `02`'s many-to-one join. `02` now flags a primary name as `write_in` when the same name has more votes in another party's primary for the seat, and nominees exclude write-ins.
- **Spellings across counties.** "Matt W. Windschitl" / "Matt. W. Windschitl" / "Matt W Windschitl" were three candidates, each in fewer counties than the race, so all were flagged write-ins and HD 17 Rep had no candidate. `02` now merges spellings that differ in case or punctuation (it already merged case only). No other election changed.
- **Left as is:** write-in names in one-county races that aren't crossovers. Sioux HD 4 Dem, Story HD 46 Rep and HD 53 Rep come out as conventions (no name over 35%); Libertarian HD 4, 45, 71 ("Smith") and 99 show one- or two-vote "winners". No legislator is affected. The canvass would settle them.

## Results

- `01`: 91,783 rows; 2018 primary 99 counties, 100 House and 25 Senate districts.
- `02`: 4,577 race rows. 2018 primary: 294 ballot candidates, 147 primaries nobody filed for, 5 conventions. Party for 2018 general candidates from the primary: 214 (was 0); 21 still missing, all nominees picked after the primary (Nunn SD 15, Bertrand SD 7, Robinson SD 49, Lohse HD 30) or by convention (Osmundson HD 56, Shipley HD 82), plus third-party and independent candidates. `check_race_table()`: no winner or write-in-won problems; no 2018 primary write-in has 25+ votes.
- `03`: 861 matches. Five to review, all decided in `candidate_legislators_manual.csv` like the same people's general rows: Srinivas (HD 9) is the legislator; Louis Zumbach, Jake Thompson, Karen Campbell and Tim Moore are not. 2018 incumbents 78, open seats 21 (was 22).

## Incremental `01`

`parse_all_results()` stores a fingerprint per election in `attr(, "digests")`: a hash of its file names and MD5s, its `county_results/` file, and `01` and `parsers.R`. A run re-parses only elections whose fingerprint changed and keeps the rest from the existing output; `force = TRUE` / `--force` re-parses all. Rows are now ordered by election, each election's county-filled rows after its precinct rows.

Checked: the new full run equals the old one's rows as a set (after mapping the new write-in labels); an unchanged rerun took 16 s and re-parsed 0 of 10; removing one 2022 general file re-parsed only that election; restoring it gave output identical to the full run, order included.

An earlier full run was edited mid-run: Rscript reads the script as it executes, so it hit garbled lines after saving. The saved output was complete.
