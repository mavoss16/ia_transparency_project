# Weekly activity summary — plan

2026-10-24. Replaces the home page's "Recent activity" list (the 8 bills with the latest `last_action_date`) with a weekly summary that the reader can step backwards through. **Nothing built yet.**

## Decided

- **Unit is the week (Mon–Sun), with days inside it.** Daily counts are too uneven to be the main view: session days run 100–466 actions, weekends 0.
- **The default is the most recent week with activity**, not the calendar week. Most of the year the calendar week is empty (one action in July 2026; the latest action is 2026-10-05). "Activity" here should mean **at least one milestone action**. Otherwise a week holding only an October fiscal note would lead the home page with four zeros.
- **Reuse the existing classification, not LegiScan's `progress` events.** The regexes in `get_bill_status_from_history()` (`R/legislature/03_bill_relationships.R`) already drive the site-wide funnel, so the weekly numbers will agree with it.
- **No raw action list.** A bill table goes in its place, and each row expands to show the actions behind it.

## Design

### Data — `classify_action()` + `06_weekly_activity.R`

`get_bill_status_from_history()` answers *how far did this bill get*, one value per bill. The weekly view needs *what happened on each dated action*. That is the same regexes applied to each action instead of collapsed to a maximum:

1. **Move the classifier into `R/legislature/utils.R` as `classify_action(action)`.** It is vectorized and returns `introduced` / `subcommittee` / `committee` / `floor` / `signed` / `NA`. It belongs in utils because sourcing `03` drags in rvest + igraph, and templates shouldn't load those.
2. **Rewrite `get_bill_status_from_history()` as a max over `classify_action()`.** Keep the one non-local rule: "Passed Both Chambers" requires *both* a `^Passed House` and a `^Passed Senate`. **Verify the funnel is unchanged:** recompute every bill's status and diff it against `groups.rds$status`. The expected diff is 0.
3. **Add a new step, `06_weekly_activity.R` → `data/legislature/bills/bill_actions.rds`.** It holds one row per action: `bill`, `date`, `week_start`, `chamber`, `sequence`, `action`, `milestone`, `bill_group_id`, `committee_originated`. It is cheap and the site needs it daily, so it goes **in `run_pipeline.R`** (unlike `04`/`05`).

### Counting rules (what the headline numbers mean)

Measured against the 91st GA history, these are the cases that would otherwise produce wrong-but-plausible numbers:

| Case | Size | Rule |
|---|---|---|
| Committee bills counted twice | 1,319 `renumbered as HF/SF #` actions; 995 bills whose first action is "Introduced, placed on calendar" | A study bill that passes committee is *re-introduced* under a new number, so one committee step looks like committee passage + an introduction. Parse the `renumbered as` target, flag the new bill `committee_originated`, and **leave it out of "Introduced"**. It already counts under "Passed committee". |
| Same milestone repeated on one bill | 650 bills have >1 committee report (one in each chamber); 389 bills have >1 floor passage (second chamber, re-passage) | Headline numbers count **distinct bills per milestone in the period**, never actions. A bill that passes the House Monday and the Senate Thursday counts once in that week's "Passed a chamber" and shows twice in its expansion. |
| Item vetoes | 5 "Item vetoed, signed by Governor" | Already caught by the `Signed by Governor` regex. Keep it that way: the bill is law. |
| Full vetoes | 7 "Vetoed by Governor" | Not in the current classifier. Add a `vetoed` milestone and show it as a count only in weeks where it is nonzero. |
| Resolutions | 74 "Resolution adopted" actions on 61 resolutions | Not counted anywhere today, so those 61 sit at "Introduced" in the funnel. Count adoption as floor passage (decision 2). |

Days within a week use the same rules. A week's numbers are **not** the sum of its days, because a bill can hit "committee" on two days. Say so in a footnote next to the counts, the way the funnel card states its own rule.

### Pages

- **One page per week, pre-rendered:** `site/templates/week_template.qmd` (param `week_start`) → `docs/legislation/week/2026-02-16.html`. Each page has ← previous / next → links that skip empty weeks. Date-based URLs can't collide when the 92nd GA arrives, unlike bill URLs.
- **Week archive:** `legislation/week/index.html` lists every active week with its four counts. Reverse chronological, grouped by session year, interim gaps visible as gaps.
- **Inside a week page:**
  - A header ("Week of February 16, 2026 · 2026 session, week 6"), plus "data through <latest action date>" on the current week. LegiScan lags by about a day and backfills.
  - A `panel-tabset`: **Whole week** | one tab per day *with activity*. Each tab holds its own count cards and its own table. The data is duplicated roughly 2× (week + day). That is acceptable at this page size, and it needs no JavaScript.
  - **Count cards:** Introduced · Passed subcommittee · Passed committee · Passed a chamber · Signed by Governor, reusing `ui_stat_grid()`. Counts are of distinct **groups**, to match the table rows.
  - **Bill table:** reactable, as `legislator_table()` already uses. Columns: bill (link), short title (`clean_bill_title`), what happened this period (milestone pills), current status (`status_pill`). The default sort is furthest milestone first (signed → floor → committee → introduced), so the busiest week opens on the most consequential rows.
  - **Row expansion:** this period's actions for the bill *and its group members*, labelled by bill number, with procedural actions included but visually de-emphasized. It ends with a link to the full bill page. **Showing only this period's actions keeps the page small.** Full group history on a week like Feb 16 (~800 bills) would embed something like 2 MB, and the bill page already has full history.
- **Home page card** replaces "Recent activity": the latest active week's four counts, the top ~8 table rows (static htmltools rows, the current `ia-recent-row` styling), and links to the week page and to the archive.

### Rendering

- `render.R` gains `render_weeks()`, called from `render_site()`. Past weeks change only when LegiScan backfills or corrects an action, so the manifest stores a hash of each week's `bill_actions` rows (type `week`). Daily CI re-renders the current week and the home page, plus any week whose hash moved.
- `test_render()` adds 2 weeks: one committee-heavy (2026-02-16) and one floor/governor-heavy (2026-04-27 or 2026-05-04).
- **Page weight:** check the busiest week's size before rendering all ~70. `docs/` is at 916 MB against the ~1 GB Pages limit (see the multi-session plan), so these pages must not carry maps or full histories.

## Other considerations

- **Neutrality:** counts and facts only. No "big week", no ranking of bills by importance in the copy.
- **Connections (later, not v1):** floor-passage rows could show the tally and party split from `rollcalls`, and the lobby/vote heat indicators from `05`, which aren't displayed anywhere yet. The week page is the obvious first place for both.
- **Accessibility:** milestone pills need text, not color alone. The reactable expand control must be keyboard-reachable and announced, and on ≤600px the table drops the status column.
- **Multi-session:** `06` inherits the same `ga91` hardcoding as everything else. Write it with the session as a parameter from the start so it isn't one more of the ~70 places to fix.
- **Interim behavior:** from June to December the home card shows a past week. Its header must make that obvious ("The Legislature is out of session. Most recent activity: week of …"), so nobody reads May's counts as this week's.

## Decisions on the open questions (2026-10-24)

1. **A table row is a bill group.** HSB → HF and HF/SF companions collapse into one row, which shows every member's bill number so a reader searching by number still finds it. Expanding the row shows that period's actions for all members, labelled by bill.
2. **Resolutions are included, the same way the overall numbers include them.** They are already in the funnel's totals (all 4,231 bills), but the classifier has never recognized `Resolution adopted`. As a result, **61 adopted resolutions sit at "Introduced" in the live funnel** (HR 28, SR 19, HCR 10, SCR 4). Joint resolutions (HJR/SJR) use `Passed House/Senate` and are already counted correctly. Fix in phase 1: `Resolution adopted` counts as a floor passage in that chamber, and a concurrent resolution adopted in both chambers reaches "Passed Both Chambers". The funnel diff check becomes "exactly these 61 bills change, nothing else". This also moves the home and legislation funnels, which is the point.
3. **Every group with any action in the period gets a row**, not only groups that hit a milestone. That includes amendment filed, fiscal note, subcommittee meeting scheduled, referral, withdrawal and placed on calendar. Consequences:
   - Rows are sorted by furthest milestone in the period (signed → floor → committee → subcommittee → introduced), and **groups with only procedural actions sort last**. Their "this period" cell shows a neutral "Other activity" label instead of a milestone pill.
   - The table has more rows than the cards count. The footnote under the cards says so ("Counts include only bills that reached a stage; the table lists every bill with any action").
   - Page weight goes up. Busy weeks run ~1,400 actions in total, which is still fine without full histories, but measure it in phase 3.
   - "Most recent week with activity" (the default) still means a week with a **milestone**. A week whose only action is a fiscal note shouldn't lead the home page, even though it would get a page and rows.
4. **Subcommittee passage gets its own count card.** That makes five cards: Introduced · Passed subcommittee · Passed committee · Passed a chamber · Signed by Governor. Subcommittee work is most of what happens in the early weeks (2,084 bills), so leaving it out would make those weeks look empty.

## Phase 1 result (2026-10-24, done)

- `STATUS_LEVELS`, `classify_action()`, `floor_chamber()` and `get_bill_status_from_history()` now live in `R/legislature/utils.R`. `03_bill_relationships.R` sources utils and keeps only the JSON readers, scraping and grouping. `classify_action()` returns `signed` / `vetoed` / `floor` / `committee` / `subcommittee` / `introduced` / `NA`. "Passed Both Chambers" means floor actions in two distinct chambers, with the chamber read from the text ("Passed House") or, for `Resolution adopted`, from the history row.
- `groups.rds` was regenerated with `save_bill_groups()`, with no re-scrape. **Exactly 61 bills changed status, all resolutions:** HR 28 and SR 19 → Passed One Chamber; HCR 10 and SCR 4 → Passed Both Chambers. 0 non-resolutions moved and group membership is identical. Group status moved for 76 bills: the 61, plus resolution-group partners, including 9 study bills (HSB/SSB) renumbered into concurrent resolutions.
- `classify_action()` on all 27,547 actions: introduced 4,181 · subcommittee 2,150 · committee 2,628 · floor 1,258 · signed 364 · vetoed 7 · procedural 16,959.
- **Item vetoes now count as signed (fixed the same day).** HF2782, HF2783, HF2800, SF2484 and SF647 have only "Item vetoed, signed by Governor." (lowercase *signed*) and no separate "Signed by Governor." row, so the old case-sensitive match left them at "Passed Both Chambers" although they became law. `classify_action()` now matches `^Item vetoed, signed by Governor` as `signed`. On regenerating, **exactly those 5 bills moved**, plus 15 group partners at group level. Bill-page History tabs still show the raw "Item vetoed…" text, so the distinction is kept where the actions are listed. Net change against the original `groups.rds`: 66 bills (61 resolutions + 5 item vetoes).
- `classify_action()` counts after the fix: signed 369 (was 364), procedural 16,954.
- `salience.rds` stage values for these resolutions are stale until `05_salience_scores.R` is re-run. It is manual, as noted in CLAUDE.md.

## Phases

1. **Classifier refactor:** `classify_action()` in utils, recognizing `Resolution adopted` (as floor passage) and `Vetoed by Governor`. `03` is rewritten on top of it and `groups.rds` regenerated. The funnel diff must be exactly the 61 adopted resolutions moving up from "Introduced" and nothing else.
2. **`06_weekly_activity.R`:** `bill_actions.rds`, the committee-originated flag, added to `run_pipeline.R`. Spot-check one week's counts against legis.iowa.gov.
3. **Week template:** render 2026-02-16 and one floor-heavy week with `-P`, then check page size, mobile, and expansion.
4. **Archive page + `render_weeks()` + manifest.**
5. **Home card** replaces "Recent activity".
6. **QA:** `test_render()`, then `/impeccable critique` on the home and week pages.
