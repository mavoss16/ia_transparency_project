# Roadmap

The project's single list of open work. Items link to the note or file with the detail; this file says only what is left and in what order.

**Keeping it current:** add an item when work is found or deferred, and remove it when it's done (the commit and the session log are the record). Decisions waiting on a choice are marked **Decide**. Collected from the notes on 2026-10-28; older notes may still list items that are now here or done.

## Before the 92nd GA (December 2026 – January 2027)

Phase 1 of the [multi-session plan](notes/legislature/2026-10-24_multi-session-plan.md).

- [ ] Freeze the 91st: after CI's last 91st pull, add `91L` to `FROZEN_GAS` in `R/legislature/session.R`. The daily run then does nothing (no pull, no re-renders, no commit) until `CURRENT_GA = 92`. **Decide** when.
- [ ] Legislator pages across sessions: career pages and `legislators/ga91/` archive pages are built ([session log](notes/legislature/2026-10-31_career-pages-electoral-history.md)), but the "Earlier sessions" list, archive rendering and redirect stubs have only run against one session. Check them on the first two-session render (the 92nd switch, or the 90th backfill). The legislators index lists `CURRENT_GA` members only, so after the switch, members who left have pages that nothing links to (part of "Link past sessions" below).
- [ ] Link past sessions: the weekly activity archive (`site/activity/index.qmd`) and the index pages list `CURRENT_GA` only, so 91st week pages would be orphaned.
- [ ] When LegiScan creates the session, set `CURRENT_GA = 92` (the ID fills itself via `legiscan_session_id()`), bulk-download the first load, then run incremental updates.
- [ ] Check the daily runs after legislator and committee pages were gated on data digests (2026-11-01). The first night renders all 191 once (new hash format); after that a quiet night should render none. If they keep re-rendering, compare `legislator_data_digests()` between two days. Once it's steady, consider raising `RENDER_TIME_BUDGET_MINUTES` in `daily-update.yml` (150 was sized for ~115 min of forced renders).
- [ ] Check `classify_district_turnover()` at the start of the new session; expect heavy turnover after the 2026-11-03 election.
- [ ] **Decide** whether salience indicators appear on 92nd GA pages.

## Site and hosting

- [ ] Split CI into three workflows by cadence ([plan](notes/project/2026-11-01_ci-workflows-plan.md)). The manual render-backlog workflow, the weekly lobbying workflow (`run_lobbying.R`) and the shared setup action are built (2026-11-01). Check the first scheduled lobbying run (Monday 2026-11-02): whether legis.iowa.gov lets GitHub's runners scrape, and whether the 300-minute budget fits. Digest-gating legislators and committees is built too (check item above).
- [ ] Scheduled runs start late: at minute `:00`, every daily run from 2026-10-15 to 11-02 began 4½–9½ h after its 06:00 UTC cron (created late by GitHub's scheduler, not held by the concurrency group). The crons moved off the hour on 2026-11-02 (daily 06:17, lobbying Mondays 12:43). If runs are still hours late by the 92nd GA, trigger them from a Cloudflare Worker cron calling the `workflow_dispatch` API (needs a fine-grained GitHub token with Actions write).
- [ ] **Decide** deploying with `actions/deploy-pages` instead of committing `docs/`. `.git` is ~900 MB and grows daily, and campaign finance pages won't fit in a committed `docs/`.
- [ ] `ia_reactable_theme()` for the four reactable tables (legislation index, committee lists, `legislator_table()`, week page), with the `:focus-visible` rules folded in. Then make the legislator voting record and sponsored bills reactable. Re-check the legislation index's font size once themed (the backlog flagged 12px).
- [ ] Legislator and committee bill lists show LegiScan's `status_desc` ("Engrossed") instead of the site's status scale; use the `groups.rds` status.
- [ ] Phone width, all from nested card + tab padding: vote maps (~198 px, legend covers them), the 10-column vote summary (scrolls in a ~232 px box), the legislators index map (~233 px sliver).
- [ ] Week page: status hidden on phones; resolutions lead busy weeks (sort substantive bills first at equal stage); the "✓ Vetoed" stepper step is green (give `ui_stepper()` an end-state class); footnote line length; empty search shows "No rows found".
- [ ] Home: tally dash `#b5b2a8` fails contrast (`site/index.qmd`); gloss LegiScan jargon in activity rows; funnel restructure (deferred by choice).
- [ ] Legislators index: Senate is the default tab; consider House.
- [ ] The Undecided lobbying swatch `#cfccc2` (`IA_PALETTE$lobby_undecided`) is below 3:1 on the background.
- [ ] Pages render only when their own data changes, so three site-wide template changes from 2026-11-01 reach most live pages only on a forced re-render: the ochre Against share bar and organization links on bill pages, and the Lobbying navbar entry on every page. Weeks are re-rendered (2026-11-01), organization pages already have both changes, and legislator and committee pages re-render on the first gated night. Left: bills. Run the Render Backlog workflow with `target: bills`, `force` on, then repeat with `force` off until done (~9 h at ~8/min, so two or three runs). Not on Monday, when the lobbying run needs the queue.
- [ ] **Decide** analytics: the live site has none. Wire `google-analytics.html` (repo root) into `_quarto.yml` or delete it.
- [ ] Write `DESIGN.md` once the visual direction is settled.
- [ ] Feature idea: "enter your town → your two legislators" (highest-leverage feature for newcomers; scope with `/impeccable shape`).

Detail for the design items: [design backlog](notes/site/2026-07-15_design-backlog.md), [tables note](notes/legislature/2026-10-27_tables-off-gt.md).

## Legislature data

- [ ] Phase 2: backfill the 90th GA (2023–24) as the multi-session test. Phase 3: the 83rd–89th, data first. **Decide** how far back and how older sessions are hosted (open decisions 3–4 in the plan).
- [ ] Show legislator–lobbyist alignment (`04a`) on legislator pages.
- [ ] Lobbying pages are built (2026-11-01): `site/lobbying/index.qmd` and `site/templates/session/organization_template.qmd`, rendered by `render_all_organizations()` inside `render_site()`. CI had rendered 792 of the 1,003 organization pages by 2026-11-01; the rest render in the weekly lobbying workflow (or the backlog workflow, `target: organizations`). The 19 personal-interest clients get pages too, labelled as such; **Decide** whether to keep them. Then run `/impeccable critique` on an organization page and the index.
- [ ] Maybe later: lobbyist comments. The declarations page's Comments cell is a count (`<a class="viewDecComments" data-decid="…">2</a>`), so `lobbyist_filings.rds` `comments` holds "1"–"4", not text (834 filings have any). The text comes from a POST to `declarations?action=getDeclarationComments&declarationID={decid}&col=7` (comment, updated by, date). Store `data-decid` as `declaration_id` and the count as an integer `comment_count`, then fetch the text (about 30 min). Some are argumentative, so think about neutrality before showing them.
- [ ] Seven 2026 Senate committee-report roll calls have LegiScan's placeholder date `0000-00-00` (read as NA; e.g. roll call 1634991), so committee pages show them undated and `min(date)` without `na.rm` returns NA. Check whether LegiScan fills them in; otherwise take the date from the bill's history.
- [ ] **Decide** whether to raise `MIN_SHARED_BILLS` above 5 in the similarity scores (0% scores at the minimum may be noise).

## Campaign finance

Order matters: the IECDB migration (Phases A–C) comes before any published pages, because Phase D changes the data model. Detail: [API note](notes/campaign_finance/2026-07-25_iecdb-api-data-sources.md), [Phase B log](notes/campaign_finance/2026-08-01_phase-b-ingest.md).

- [ ] **Cutover blocker:** explain why committee `1046` returns fewer API rows than bulk for 2007–08 (start with the `(date, amount)` diff). It may mean responses are truncated.
- [ ] Confirm the `countyReports` record shape; if it matches, add a second change feed for local committees (0% covered today).
- [ ] Run the full sweep (~1,429 requests, ~24 min) and re-reconcile on a representative sample including a large active committee.
- [ ] Phase C: compare per-committee totals side by side (state slice), cut over, keep data.iowa.gov as an audit.
- [ ] Phase D: reporting-period attribution from `date`; show `reported_through` on committee pages; parse DR2 Schedule F1 for loans and cash on hand (add `pdftools` to renv).
- [ ] Classify the legacy summary rows (`Contributions Total` etc.) by hand. Must happen before committee pages are mass-rendered.
- [ ] Re-run `01_build_committee_lookup.R` (stale since 2026-04-19; party coverage 71%).
- [ ] Refresh FEC data (clear `source/federal/2026/` first; keep `headers/`).
- [ ] Templates: finish the donor template restyle; fix `fec_recipient_template.qmd`'s default `CMTE_ID` (it's ActBlue); fix or drop the stale OJS template.
- [ ] Build `R/campaign_finance/render.R` (distinct `output_file` per page; pass `committee_name` so the browser tab isn't the code), an `index.qmd`, and the navbar entry. **Decide** how CI gets the database, or render outside CI.
- [ ] `03_link_donors.R` (fuzzy donor dedup) doesn't run; nothing depends on it yet.

## Elections

- [ ] **2026 general (November 3):** once ENR posts it, add a `2026, "general", "enr", "<id>"` row to `RESULT_SOURCES` in `download/election_results.R` and run `download_results(2026, "general")`.
- [ ] **Blocker for the downloads:** R's httr2 gets 403 from sos.iowa.gov (command-line curl with the same User-Agent gets 200). Until that's resolved, `download_all_results()` can fetch only the ENR elections. Missing now: primaries 2010–2020 (2022 was downloaded by hand), the 2006/2008/2010/2014 statewide generals, Black Hawk in the 2022 general, and the general canvass PDFs (party for 2018–2020 generals). safeconduct didn't get the files either ([trial](notes/elections/2026-11-02_safeconduct-trial.md)). Downloading by hand in a browser works; save county files as `precinct_results/{year}_{type}/{county}.{real ext}`, and a statewide county-level file in `county_results/`. Then delete `data/elections/raw/precinct_elections_2014/` (superseded by the statewide file).
- [ ] Confirm the three named write-ins `02` now flags (`write_in`) against the certified canvasses: Jed Ganzer (2022 SD 35 Dem primary, Jackson), Kayla Koether (2024 HD 63 general, Winneshiek), Carrie Trevino (2026 HD 95 Dem primary, Louisa). The flag can't see a write-in reported by name in a single-county race; if one turns up, add a manual override.
- [ ] Electoral history on legislator pages (generals, primaries and specials, SOS only): [plan](notes/elections/2026-10-30_legislator-electoral-history-plan.md). Phase 1 steps 1–5 are built; the Elections tab, tenure line and district-card result are built into the [career pages](notes/legislature/2026-10-31_career-pages-electoral-history.md). Next: run `/impeccable critique` on a legislator page; at phone width the tab bar now stacks five rows. Incumbency is unknown for 2012 and 2016 (the 2010 and 2014 generals aren't downloaded). The 2025 specials (SD 35, HD 100, HD 78, SD 1, HD 7) are in the race table as `type = "special"` from the hand-entered `data/elections/processed/legislative_results_special.csv`; earlier specials aren't, so members first elected in one before 2025 show as not incumbent. Renee Hardman (SD 16) is the one 91st GA member with no matched win: she succeeded Claire Celsi between sessions (Celsi's last vote 2025-05-14, Hardman's first 2026-01-21), and the SOS results site lists no special for the seat. Find out how she took it (the Polk County Auditor's results, or her legislature biography); if it was an appointment, the Elections tab needs a line saying so instead of a race. The race table lacks party for most 2018 and 2020 general candidates (and ~35 each in 2022 and 2024) until the canvass PDFs or primaries download (see the SOS blocker above). The tab's [design direction and mock](notes/site/2026-10-31_elections-tab-design.md) are written; it lists the columns step 3 must carry. Phase 1 is 2010–2026 from Excel plus the page (~4–5 sessions); Phase 2 is 2000–2008 canvass PDFs and specials (~2.5–3). **Decide** the four open questions in the plan (offices in scope, which people, pre-2000, timing).
- [ ] City precinct shapefiles (coverage and schemas in [`R/elections/CLAUDE.md`](R/elections/CLAUDE.md#precinct-shapefile-coverage-as-of-2026-05-02)):
  - [ ] In `01_combine`, extend the `LONGNAME` fallback from `c("Name", "NAME")` to `c("LONGNAME", "Name", "NAME", "name", "PRECINCT", "Precinct", "PCT", "DIST_NAME", "Ward_2020", "WardID", "Ward")`, matching the `name` variants case-insensitively.
  - [ ] Drop "Unassigned" rows in the combine step, and drop the two Rock Rapids folders (no precinct names).
  - [ ] Confirm Iowa City's `DIST_NAME` values are usable precinct names.
  - [ ] **Decide** how city files join the county set: copy each into its county folder, read both folders with a city → county lookup at combine time, or nest them as `precincts_2020s/{county}/{city}/`. The lookup can come from `tigris::places()` + `tigris::counties()`.
- [ ] Build `R/elections/render.R` and a site section.

## Cross-domain

- [ ] Entity crosswalk in `data/general/`: legislator `people_id` ↔ IECDB candidate committee ↔ election candidate ↔ lobbying client. This is the "connections" pillar. The `people_id` ↔ election candidate piece is built (`data/general/candidate_legislators.csv`, 91st GA members only); IECDB committees and lobbying clients are next.
- [ ] **Decide** whether lobbyist registrations and client reports (keyed by lobbyist/client, not bill) become their own domain. Bill declarations stay in legislature.
- [ ] When `R/campaign_finance/render.R` is built, move the manifest helpers out of `R/legislature/render.R` into shared code.

## Housekeeping

- [ ] Archive the old `iowa_legislature` GitHub repo and delete `../iowa_legislature-filtered`.
