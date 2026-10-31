# Legislator electoral history — plan (2026-10-30)

Plan doc, updated in place as decisions land. Assessment session; no code changed.

**Goal:** each legislator page shows the person's electoral history, modeled on Ballotpedia's: every state legislative race they ran in, generals and primaries, wins and losses, with official Iowa Secretary of State (SOS) results as the only source.

## What the page shows

- One block per election year, newest first.
- **General:** every candidate, party, votes, %, winner mark, incumbent mark. One-candidate races show "Unopposed".
- **Primaries:** each party's primary for that seat that year, not only the legislator's own (Ballotpedia does the same).
- **Specials:** shown like generals, with their date.
- Source line linking the SOS file, plus "More on Ballotpedia" from the `ballotpedia` slug LegiScan already gives in `legiscan/ga{N}/derived/people.csv` (it also has `followthemoney_eid` and `votesmart_id`).
- Neutral presentation: candidates by votes, margin in points, no characterizing words ("landslide").
- District shown as it was that year. Maps changed for the 2002, 2012 and 2022 elections, so the same number means different places across eras; note the change.

Electoral history is career-level, which favors one page per `people_id` in the open legislator-page decision in `ROADMAP.md`.

## Findings

### Most local raw result files before 2012 are not data

The downloaded files in `data/elections/raw/precinct_elections_{year}/` were checked by first bytes on 2026-10-30:

| Folder | Contents |
|---|---|
| 2000–2010 | all 99 files are the SOS HTML error page (~34 KB each) saved as `.xlsx` |
| 2012 | 99 real `.xls`; the 99 `.xlsx` are error pages |
| 2018 | ~100 real SpreadsheetML files; ~98 error pages |
| 2014, 2016, 2020, 2022 | real (2020's single `.pdf` is an error page) |

So the "198 files" in 2012 and 2018 were duplicates, not primary + general. Cause: the per-county URL pattern doesn't exist before 2010, and SOS redirects (302) a missing file to an HTML page that returns 200, so `download_sos_election()` saved it. The downloader must check the file's first bytes (BIFF `D0 CF`, ZIP `PK`, or `<?xml`), not just the status.

### What SOS publishes, by election

Index pages: `https://sos.iowa.gov/iowans/election-results-statistics` (2000–2026 and specials) and `https://sos.iowa.gov/archived-election-results-and-statistics` (pre-2000). Both need the short User-Agent in `R/elections/CLAUDE.md`.

| Elections | Source | Format | Notes |
|---|---|---|---|
| 2024, 2026 | ENR (`electionresults.iowa.gov`) | SpreadsheetML per county | IDs: 2024 primary `121508`, 2024 general `122322`, 2026 primary `126082`. Parser exists (`clean_precinct_elections_2024.R`). |
| 2018–2022 | `precinctresults/{year}{type}/{county}.xls` | SpreadsheetML (2020 general: real `.xlsx`, same layout) | Same layout as ENR: table of contents, then a sheet per contest. The 2024 parser should mostly carry over. **Scott 2020 general is PDF only.** |
| 2014–2016 | `precinctresults/{year}{type}/{county}.xlsx`; 2014 general is only linked as one statewide `statewide.xlsx` (same layout, every precinct as a column) | `.xlsx`, one sheet | Columns `RaceTitle`, `CandidateName`, `PoliticalPartyName`, then one column per precinct × vote type. Race titles like "State Rep. Dist. 20 - Rep". |
| 2010–2012 | `precinctresults/{year}{type}/{county}.xls`; 2010 general is one statewide `precinctresults/2010general/statewidepct.xlsx` | BIFF `.xls` | Blocks per race: race, county, precinct, a column per candidate. 2012 files open with a "COUNTY ELECTION CANVASS SUMMARY" header. |
| 2006–2008 general | `results/2006genstatewidepct.xlsx`, `precinctresults/2008general/statewidegenpct.xlsx` | `.xlsx`, one statewide sheet | Party-level columns only (DEM / REP / OTH / scattering for Iowa Senate and Iowa House, with district numbers per precinct). Candidate names must come from the canvass PDF. |
| 2000–2008 primaries, 2000–2004 generals | canvass and precinct PDFs | PDF | Text-extractable (`pdftotext -layout` works on every sample). Layouts vary; 2000 splits all-caps names across lines and columns drift, so it needs word coordinates (`pdftools::pdf_data()`). 2002 has one PDF per office (`2002/results/PRI_StateRep.pdf`, `PRI_StateSenate.pdf`). |
| Specials | one PDF per election | PDF, mostly one page | About 50 since 2000, all linked from the results page (a few 2012–2013 specials also have `.xls`). |

Every regular election also has a certified **canvass summary** PDF (county totals per race), e.g. `elections/pdf/{year}/{type}/canvsummary.pdf` for 2012–2024; earlier years use one-off names (listed on the results page). Use it to check the Excel totals.

Each primary also has a "List of Offices for which No Candidate was Nominated" (`elections/pdf/{year}/primary/nonominee.pdf`), which covers Iowa's 35% convention rule and seats with no filer.

## Plan

### Phase 1 — 2010–2026 from Excel, plus the page (~4–5 sessions)

1. **Downloaders.** *Written 2026-10-30* ([session log](2026-10-30_election-downloaders.md)): `R/elections/download/election_results.R` covers every election in `RESULT_SOURCES`, checks each file's first bytes, and saves to `data/elections/raw/precinct_results/{year}_{type}/`. Error-page files deleted; real generals 2012–2024 moved in. **Not yet run against SOS:** httr2 gets 403 there (curl doesn't).
2. **Parsers.** *Written 2026-10-30* ([session log](2026-10-30_legislative-results-parsers.md)): `R/elections/legislative_results/` parses the four layouts into `data/elections/processed/legislative_results_precinct.rds`. Run on the 2012–2024 generals on disk and tested on one sample county per primary 2010–2022. Re-run after the downloads; nothing in the parsers should need to change.
3. **Race table.** *Built 2026-10-31* ([session log](2026-10-31_race-table.md)): `R/elections/legislative_results/02_build_race_table.R` → `data/elections/processed/legislative_results.rds`, with votes, %, winner, margin, unopposed / no candidate / convention flags, election date, district map and source URL. Scott 2020 is parsed from its PDF. Party in generals comes from the results file, else from the primary the candidate won (only the 2024 primary is downloaded so far). **Still open:** party for 2018–2022 generals and for 2024 convention nominees, independents and Black Hawk; it needs the general canvass PDFs (`elections/pdf/{year}/general/canvsummary.pdf`, not downloaded: the SOS 403 again) or the primaries. Incumbent, open seat and `people_id` (the [tab design](../site/2026-10-31_elections-tab-design.md) needs them) come from step 4.
4. **Candidate ↔ `people_id` crosswalk** in `data/general/`. Auto-match winners to seats LegiScan says they held (chamber + district + term + last name); then find each person's other races (losses, other chamber) by normalized name; manual override CSV for name variants. ~1 session plus the user's review.
5. **Template:** an "Elections" tab on `site/templates/legislator_template.qmd`, plus a tenure line in the profile header and the latest result in the district card. Design direction and a mock: [`notes/site/2026-10-31_elections-tab-design.md`](../site/2026-10-31_elections-tab-design.md). Election data becomes an input to the legislator render digest. ~1 session.

Covers the full elected career of every member first elected in 2010 or later; earlier members show "Results before 2010 not yet included".

### Phase 2 — 2000–2008 and specials (~2.5–3 sessions)

6. **Canvass PDFs, 2000–2008** (5 primaries, 3 generals, about 4 layouts). Only each race's total and candidate names are needed, not county rows. 2006–2008 generals: join names from the PDF to the party-level statewide spreadsheet. ~1.5–2 sessions.
7. **Specials:** a committed CSV with a source URL per row and a sum check, likely faster than a parser for ~50 one-page PDFs. ~0.5–1 session.

**Total: about 7–9 sessions.**

## Open decisions

- **Offices in scope:** legislative races only (default), or every office a legislator ran for (Congress, county, school board)? Matching outside a district is much harder.
- **Which people:** current members only for Phase 1, or everyone in LegiScan back to the 83rd GA (2009)? Sets the crosswalk's size.
- **Pre-2000 careers:** stop at 2000, or extend through the archived canvass PDFs (back to the 1940s) for the few long-serving members?
- **Timing:** land Phase 1 with the 92nd GA switch (January 2027) so the 2026 class has its primary and general from the start?
