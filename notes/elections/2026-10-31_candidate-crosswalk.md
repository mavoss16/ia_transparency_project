# 2026-10-31 — Candidate ↔ legislator crosswalk

Phase 1 step 4 of the [electoral history plan](2026-10-30_legislator-electoral-history-plan.md). Follows the [race table](2026-10-31_race-table.md).

## What was built

`R/elections/legislative_results/03_match_legislators.R`:

- **`match_legislators()`** links race-table candidates to LegiScan `people_id` for the 155 people in the 91st GA (`legiscan/ga91/derived/people.csv`; the file's other 36 rows are committees). Output `data/general/candidate_legislators.csv`, one row per matched candidate in a race.
  - **Name key:** first + last name (`name_key()` from `02`). A legislator's keys use LegiScan's first name, nickname, the first word of `name`, and a small `NICKNAMES` table (Dan/Daniel, Pat/Patrick, Bill/William…).
  - **Home counties:** the seat's counties from the 2024 House general. Senate district *n* is House districts 2n−1 and 2n, which avoids the missing Black Hawk 2022 file.
  - **seat** (236): the legislator won their current seat in 2022 or 2024. **name** (325): the same key in a race sharing a county with the home counties (losses, primaries, the other chamber, the 2011 map). **manual** (1).
  - Anything else with the same key, or the same surname inside the home counties, goes to `candidate_legislators_review.csv`. Decisions go in `candidate_legislators_manual.csv` (`people_id` to accept, empty to reject, with a note).
- **`add_incumbency()`** adds `people_id`, `incumbent` and `open_seat` to `legislative_results.rds`. A candidate is incumbent if they won a general for that chamber whose term covers the election (House 2 years, Senate 2 or 4), matched by `people_id`, or by name key for non-members. So an incumbent counts under a new district number after redistricting. `open_seat` is per chamber × district × year, across the general and the primaries.

## Review decisions (13 rows in the manual file)

- **Accepted:** Megan L. Srinivas, 2018 HD 9 (Fort Dodge), the same person, who later moved to Des Moines.
- **Rejected:** same surname, different first name (not a nickname). Jerry Behn (Chad Behn's seat), William Johnson, Louis J. Zumbach, Jake Thompson, Danny Graber, Toya Johnson, Pat Shipley.

## Results

- 150 of 155 people match at least one race. The other five won 2025 special elections and have no earlier races in the data: Zimmer, Watkins, Ramirez, Drey, Hardman. Dotzler has no seat match because his 2022 SD 31 race is all Black Hawk (not downloaded); his older races matched by name.
- All 41 ballot names that differ from LegiScan's are the same person: middle initials, nicknames, "Megan Jones" / "Megan Hess Jones", "Ray Bubba Sorensen".
- Incumbents in generals: 78 (2018), 104 (2020), 82 (2022), 105 (2024). 2012 and 2016 are NA.
- Spot checks: 2018 HD 20 is an open seat (Baudler retired); Sorensen is incumbent in HD 23 in 2022 after moving from HD 20; 2022's defeated incumbents include Chapman, Kinney, Jackie Smith and Gobble. In 2024 SD 30 Waylon Brown is the incumbent (he won the primary, then withdrew), so the seat isn't open.

## Limits

- Current members only. Older sessions need their `people.csv` downloaded and listed in `LEGISCAN_SESSIONS`.
- Specials aren't in the data, so a member first elected in a special is not incumbent at their next general, and the person they replaced still counts as holding the seat.
- Re-running `02` drops the `03` columns: run both.
