# Iowa Legislature

Bill tracking, legislator voting records, committees, weekly activity, and lobbyist declarations, currently for the 91st General Assembly (2025–2026). This is the live domain and the architectural reference for the others. Templates live in `site/templates/` and `site/templates/session/`; this file covers them too.

Migrated from the standalone `iowa_legislature` repo on 2026-07-05 via `git filter-repo` + merge, so full history is here (`git log --follow` works across the move). **Still open from the migration:** archive the old `iowa_legislature` GitHub repo, and delete the throwaway `../iowa_legislature-filtered` clone.

## Data flow

```
LegiScan API → 01_incremental_update.R → legiscan/ga{N}/json/
               01c_generate_csvs.R     → legiscan/ga{N}/derived/*.csv
                                              ↓
               02_process_votes.R           → data/legislature/ga{N}/votes/*.rds   (functions in 02a)
               02b_legislator_similarity.R  → data/legislature/ga{N}/votes/similarity_*.rds
               03_bill_relationships.R      → data/legislature/ga{N}/bills/groups.rds   (03a resumes the scrape)
               04_lobbyist_declarations.R   → data/legislature/ga{N}/lobbying/*.rds      (04a: legislator–client alignment)
               05_salience_scores.R         → data/legislature/ga{N}/bills/salience.rds
               06_weekly_activity.R         → data/legislature/ga{N}/bills/bill_actions.rds
                                              ↓
               site/templates/*.qmd + site/templates/session/*.qmd (each takes `ga`)
                                              ↓
               render.R (incremental) → docs/
```

`run_pipeline.R` runs 01 → 03, then 06, then render; logs to `logs/legislature/`. `.github/workflows/daily-update.yml` runs it daily. **`04`/`04a` (lobbying) and `05` (salience) are not in `run_pipeline.R`**; run them by hand. Lobbying was fully re-scraped 2026-10-24 (42k declarations through 2026-10-05). `04` decides what to re-scrape from the LegiScan `change_hash`, which doesn't change when a declaration is filed on an idle bill, so re-scrape everything for a complete snapshot.

Other files: `session.R` (session settings, below), `maps.R` (Leaflet maps), `utils.R` (status rules, turnover, scrapers), `ui_helpers.R` (legislature UI layer), `simplify_districts.R` (district geometry from `data/legislature/archive/Districts/`), `archive/` (deprecated, incl. `old_pipeline/`).

## Sessions are a setting

`session.R` holds `CURRENT_GA` and `ga_paths(ga)`; every pipeline function and template takes a `ga` argument (templates: `ga: null` = current session). Data lives in `legiscan/ga91/` and `data/legislature/ga91/`; the folder carries the session. `legiscan_session_id(ga)` reads `data/legislature/legiscan_sessions.csv` and fills it from `getSessionList` on a miss. Shared across sessions: `data/legislature/districts/` (keyed by district plan) and `pipeline_internal/pipeline_runs.rds`.

**URLs:** bills at `docs/legislation/ga91/HF1.html`, committees at `docs/committees/ga91/…`, legislators unchanged at `docs/legislators/…` (`people_id` spans sessions). The bill and committee templates live in `site/templates/session/` so Quarto's relative `site_libs`/navbar paths come out `../../`: **a page must end up exactly as deep as it rendered.** Build links with `bill_dir_href(ga, up)`. Manifest keys for bills and committees are `ga91/HF1`.

**Rollout (pushed 2026-10-25, in progress):** every bill's manifest key changed, so CI re-renders all 4,231 bills at ~1,200 per night; 2,708 were done on 2026-10-28. Until it finishes, links to not-yet-rendered `ga91/` pages 404, and `docs/` holds both the old flat pages (~741 MB) and the new ones (1.1 GB total, above GitHub Pages' ~1 GB limit). **When every bill has rendered, run `remove_unsessioned_pages(dry_run = FALSE)`**, which drops the flat pages, old template outputs and old manifest rows. What CI does, what to check, and how to roll back (tag `pre-multisession` on `2e94fae8`): [`notes/legislature/2026-10-25_multi-session-rollout-rollback.md`](../../notes/legislature/2026-10-25_multi-session-rollout-rollback.md).

**Next (Phase 1, December–January):** freeze the 91st GA, set `CURRENT_GA = 92` once LegiScan creates the session, decide legislator pages across sessions (one career page vs per-session; today a page shows `CURRENT_GA` only), link past sessions' weeks and index pages (the activity archive lists `CURRENT_GA` only), and put lobbying in the daily run. LegiScan has Iowa back to the 83rd GA (2009–10). Phases 0–3 and open decisions: [`notes/legislature/2026-10-24_multi-session-plan.md`](../../notes/legislature/2026-10-24_multi-session-plan.md).

## Page weight and maps

Profiled 2026-10-25: bill pages were 756 MB, 58% of it Leaflet district geometry re-embedded in every vote map. All maps now draw shared geometry via `maps.R` (`district_map()`, `vote_map()`); per-plan scripts are committed in `data/legislature/districts/web/` and Quarto copies them once to `docs/site_libs/ia-districts-*`. Each map is 5–7 KB (was ~264–353 KB). Regenerate with `write_district_scripts()` and bump `DISTRICT_SCRIPT_VERSION` if the lines change. `ga_district_plan()` maps a GA to its plan (only plan2021, in force from the 90th GA, is set up). Basemap is `addTiles()` (OSM); CARTO's free tiles now require an API key.

## Rendering

```r
source("R/legislature/render.R")
render_status()             # what needs rendering
render_site()               # incremental render (only changed items)
render_site(force = TRUE)   # full re-render
test_render()               # 5 bills, 5 legislators, 3 committees, 2 weeks
render_all_weeks()          # weekly activity pages → docs/activity/ (incremental)
render_index_pages()        # only the index pages (includes the activity archive)
clear_manifest()            # force full re-render next time
```

- `render_manifest.csv` (repo root) tracks LegiScan `change_hash` (bills) and `person_hash` (legislators). Weeks use `week_digests()`: a fingerprint of the week's actions, its groups' lead/status/title, its neighbour links, and (newest week) the data-through date. `render_site()` renders weeks after the index pages and before the bills.
- **Legislators and committees are force-rendered every run** (~115 min in CI, even with no changes): the biggest CI cost, and a daily rewrite of their HTML into git history.
- CI stops starting bill pages after `RENDER_TIME_BUDGET_MINUTES` (150); unreached bills render next run.
- `.claude/launch.json` has a `docs-preview` static server on port 8642 for visual QA of `docs/`. The port is hardcoded, so if 8642 is taken the preview tool picks a port nothing listens on; browse to `http://localhost:8642` directly.
- Preview the Quarto project with `quarto preview site/`.

## Bill status rules

All in one place: `classify_action()` / `get_bill_status_from_history()` / `STATUS_LEVELS` in `utils.R`. `Resolution adopted` counts as floor passage; "Committee report, recommending amendment and passage." counts as committee passage; item-vetoed bills ("Item vetoed, signed by Governor.") count as "Signed by Governor" (bill pages still show the raw text). The scale is sentence case and ends in three states: "Vetoed", "Signed by Governor", and "Adopted" (HR/SR once their chamber adopts, HCR/SCR once both do; `get_bill_status_from_history()` takes the bill number to tell them apart). Joint resolutions stop at "Passed both chambers". `names(STATUS_LEVELS)` is the display order everywhere; `status_track()` gives the bill-page stepper its per-type steps. The home card "Passed, Not Signed" counts HF/SF only.

Bill groups link every committee renumbering ("renumbered as HF 123") at graph-build time, since the scraped related-bills list misses some. Mid-session member replacement logic is one helper, `classify_district_turnover()` in `utils.R` (works within one session; check it at the start of a new one).

## Site components

`ui_helpers.R` here is the legislature UI layer (it sources the shared `R/ui_helpers.R`): `clean_bill_title`, `status_pill`, `vote_pill`, `ui_paired_bars` (its legend names bills), `ui_profile_header` (hardcodes DEMOCRAT/REPUBLICAN), and the `legislator_table()` reactable.

- **Redesign** (2026-07-08/09) of home, legislation, legislators, bill and legislator pages, from the handoff now in `notes/legislature/design_handoff_iowa_legislature/`; `site/custom.scss` and `ui_helpers.R` came from its `quarto_starter/`. Party colors R `#A8433A` / D `#3F5B93` (vote-map Nay tints R `#DCB4B0`, D `#B2BDD4`). Plan and logs: `notes/2026-07-08_legislature-redesign.md`, `notes/2026-07-15_impeccable-design-pass.md`.
- **Tables (2026-10-27): no legislature page uses gt.** Small tables use `ui_table()`, empty states `ui_empty()`; never `cat()` in a normal chunk (knitr prints it as a code block). Searchable tables use plain `reactable()`: committee lists and the legislation index, which draws links, pills and dates with one JS renderer per column (8.0 → 0.97 MB). **`status_pill_js` there mirrors `status_pill()`; keep them in step.** Pages rendered before 2026-10-27 keep gt until they re-render. Log: [`notes/2026-10-27_tables-off-gt.md`](../../notes/2026-10-27_tables-off-gt.md).
- **Weekly summary** (critique 28/40, no P1s): period events render with `event_chips()` (outlined, furthest first, "+ N earlier steps"); filled pills mean current status only. `custom.scss` gives every reactable visible `:focus-visible` rings and a 32px expander (only the week page was tested). Design: [`notes/legislature/2026-10-24_weekly-activity-summary.md`](../../notes/legislature/2026-10-24_weekly-activity-summary.md).
- **Not done:** `ia_reactable_theme()` (reactable still looks like its defaults; deferred, P2). Open items: `notes/2026-07-15_design-backlog.md`.

**Known bugs:** vote maps are cramped at phone width (~198 px, legend covers them; in the design backlog). The "Similar legislators" 404 is fixed in the template (2026-10-27); live pages keep the broken links until they re-render.

## Salience indicators

`05_salience_scores.R` → `salience.rds`: **separate, citable indicators, deliberately not blended into one number** (the old weighted composite is `archive/05_salience_scores_composite.R`). All at the **bill group level**:

- **Lobby heat** — UHERO's Heat Score (Gordner & Moore 2025): minority-side share, 0–0.5, on **For + Against only** (Undecided is ~54% of declarations); no band below `MIN_POSITIONED` (5). UHERO's cutoffs (<0.10 / 0.10–0.30 / ≥0.30) but **our labels: One-sided / Leaning / Divided**, because a low score means lobbyists didn't disagree with each other, not that the bill was uncontroversial. One-sided bills carry `lobby_lean`.
- **Vote heat** — the same formula on the group's most contested passage vote, plus its party-division label.
- **Stage** — furthest step on the six-step status scale.
- **Bill class** — `resolution` / `commemorative` (narrow title pattern) / `substantive`, after the SLES commemorative tier.
- **Attention** — organizations declaring, hearings, amendments, fiscal note (`Fiscal Note` and `Fiscal Note/Analysis`).

`most_contested_bills()` gives the two-axis ordering with no weights. **Not displayed anywhere on the site yet.** Sources: `notes/legislature/2026-10-24_salience-precedents.md`, `notes/legislature/2026-05-17_salience-score.md`.

## Key packages

`readr`, `dplyr`, `tidyr`, `stringr`, `purrr`, `jsonlite`, `reactable`, `leaflet`, `quarto`, `here`, `rvest`, `httr2`, `ggparliament`
