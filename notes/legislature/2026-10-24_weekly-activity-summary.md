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

## Phase 2 result (2026-10-24, done)

`R/legislature/06_weekly_activity.R` → `data/legislature/bills/bill_actions.rds` (27,547 rows, 291 KB, committed daily by CI with the rest of `data/`). It is added to `run_pipeline.R` as step `weekly_activity`, between `bill_relationships` and `render`.

- **Columns:** `bill`, `bill_group_id`, `date`, `week_start` (Monday), `chamber`, `sequence`, `action`, `milestone` (factor), `floor_chamber`, `committee_originated`, `renumbered_from`, `counts_as_introduction`.
- **Helpers in the same file** (sourcing it builds nothing): `period_milestone_counts(ba, from, to)` returns distinct groups per milestone with zeros included. `weekly_activity_summary(ba)` returns one row per week with any action; `active` = at least one counted milestone. `latest_active_week(ba)` and `counted_milestones(ba)` are the other two.
- **Refuses to build** if any bill has history but no group, since it would silently drop out of the counts.
- **`classify_action()` now also matches "Resolution filed…" as introduced.** That is how HR/HCR are introduced: 50 resolutions had no "Introduced" row. It cannot change any status, which was re-verified: status rebuilt from `bill_actions` = `groups.rds` for all 4,231 bills.

Checks: row count = `history.csv`; all weeks start Monday; 1,308 committee-originated bills; every one of the 2,208 groups has exactly one counted-introduction week or more; signed groups across the session = 368 = `groups.rds`.

Findings:
- **The default week is 2026-09-28**, the Oct 2 special session (HF 2801 / HSB 785 / SF 2508, SCR 103–104, HCR 105–106). That is real activity, not noise. 2026-10-05 has only procedural actions, so it is `active = FALSE`.
- **29 committee renumberings cross groups.** The relationship scrape did not link the study bill to the bill it became (e.g. HSB 674 → HF 2466). Those introductions are kept, or 27 groups would never be introduced. The cost is that the committee step shows as two groups, mostly in the week of 2026-02-16 (introduced 156 instead of ~130). **Proper fix: add renumbering edges to the graph in `03`**, since "renumbered as" is the strongest relationship there is. That would merge those pairs, and the exclusion rule then covers them automatically. *Done the same day; see below.*
- **Spot-check against legis.iowa.gov (HF 2801):** every action and date matches, except that the official page has "Signed by Governor. H.J. 1197." (Oct 2) and our LegiScan JSON (last changed 2026-10-13) does not. Either LegiScan hasn't recorded it or the incremental pull missed it. Until it arrives, the special-session week shows 0 signed.

### Renumbering edges in `03` (same day)

`build_bill_groups()` now adds every committee renumbering as a graph edge, read from the same JSON pass that computes status (`get_all_bill_statuses()` returns a `renumbered_to` list column). This happens at graph time only; `relationship_edges.rds`, the scrape cache, is unchanged. `parse_renumbered_target()` moved to `utils.R`, shared by 03 and 06.

What merged:
- **Groups:** 2,208 → 2,179. 29 new groups formed from 58 old ones, covering 78 bills. No group split, and **no bill's own status changed**.
- **Group status:** 36 bills got a higher group status. 18 of those bills now sit in groups that read "Signed by Governor"; their old groups had read "Passed Committee" or "Introduced". Typically a member bill was replaced by a committee bill that became law, e.g. HF 2036 → HF 2526, and HSB 674 → HF 2466.
- **`salience.rds`:** indicators changed for exactly the 78 merged bills and no others. Lobby bands shifted on 13 (e.g. 4 Leaning → Divided), because the merged groups now pool their declarations.
- **`bill_actions.rds`:** 0 renumberings cross groups, and every group has an introduction. Week of 2026-02-16: introduced 156 → **130** (the double count is gone), committee 266 → 260.

Week of 2026-02-16 for reference: introduced 130 · subcommittee 154 · committee 260 · floor 2 · signed 0.

## Phase 3 result (2026-10-24, done; not committed)

`site/templates/week_template.qmd` (param `week_start`) → `render_week()` in `render.R` → **`docs/activity/YYYY-MM-DD.html`**. This changes the planned `legislation/week/` path: Quarto writes `../site_libs` paths relative to `docs/templates/`, so output has to stay one level below `docs/`.

- **Page layout:**
  - Breadcrumb, then a hero ("Week of February 16, 2026"; "Feb 16 – Feb 22 · 1,419 actions on 476 bill groups"; "data through …" on the newest week) with ← / → links to the neighbouring weeks that have any action.
  - Bootstrap tabs built in htmltools rather than a Quarto `panel-tabset` heading, because widgets printed from an `asis` loop lose their dependencies: **Whole week** + one tab per day with any action.
  - Each tab has its own count cards (`period_milestone_counts()`; Vetoed appears only when nonzero) and its own table.
  - A footnote states the counting rule.
- **`period_group_rows()` (06):** one row per group with any action in the period. It carries the active members (lead first), pill labels ("Passed House", "Adopted in Senate", "Signed by Governor", …; "Other activity" for procedural-only groups), the current group status, and the period's actions.
- **`activity_table()` (legislature `ui_helpers.R`):** reactable.
  - The data columns are plain text, so search matches bill numbers, titles and milestones; cells render links and pills.
  - Titles are clamped to 3 lines.
  - Rows expand to the period's actions for every member (milestones in full ink, procedural muted) plus "Full history" links. These are real `<a>` tags: an `HTML()` string inside reactable details is rendered as escaped text.
- **Phones (≤600px):** the This-week and Status columns hide and the pills move under the title. reactable's inline `min-width` (the sum of all columns, hidden ones included) is overridden, so the table fits 375px with no sideways scroll.

**Verified in the browser** (docs-preview) on 2026-02-16 (committee-heavy: 130 / 154 / 260 / 2 / 0) and 2026-04-27 (floor-heavy: 10 / 11 / 22 / 80 / 26):
- tab switching sets `active` and `aria-selected`;
- expanding a row sets `aria-expanded` and shows the actions and links;
- search finds `SF 492` by number and by title words;
- prev/next links are right, and the asset paths resolve;
- phone layout fits with no horizontal page scroll; desktop is unchanged.

**Page weight:** 2.71 MB / 1.51 MB on disk, **203 KB / 110 KB gzipped** (what Pages serves). Week + day tabs roughly double the embedded data. At ~48 weeks per GA that is roughly 40–60 MB on disk, against the ~1 GB Pages limit; acceptable, but this is the knob if the budget tightens (e.g. drop details from the day tabs).

**Classifier gap found while testing:** `"Committee report, recommending amendment and passage."` (390 actions, 388 bills) is **not** matched by the committee rule (`recommending passage|approving bill`). Effects:
- Bill status: only 10 bills would move (Passed Subcommittee → Passed Committee), because the rest got further anyway.
- **Weekly counts:** 338 groups are missing a "Passed committee" in the week it happened.
- **Fixed the same day:** the committee rule is now `recommending (amendment and )?passage|approving bill`.
  - **Exactly 10 bills moved** (Passed Subcommittee → Passed Committee): HF2068, HF2161, HF2403, HF47, HF621, HSB31, HSB533, HSB551, SF172, SF2167. 13 bills changed group status.
  - Group membership is identical, and `salience.rds` changed only `stage` on those 13.
  - Committee milestones went 2,628 → 3,018, and every changed milestone is an amended-passage report.
  - Committee counts: week of 2026-02-16 260 → **292**; week of 2026-04-27 22 → **25**.

The two test pages in `docs/activity/` were re-rendered but are **not committed**. Nothing links to them yet, and their "Weekly activity" breadcrumb points at an archive page phase 4 builds. CI will render them once `render_weeks()` is wired into `render_site()`.

## Phase 4 result (2026-10-25, done)

**First CI run after the push (2026-10-25) succeeded.** The new `weekly_activity` step built 27,547 actions in under a second, and the project render included `week_template.qmd`. The run took 4h54m (usually 1.5–2.5h), but not because of this work. The lobbying refresh (`b609773c`) landed after the Oct 24 run, so this was the first run with the new declarations: 1,532 bills' lobbying fingerprints changed, the 150-minute budget stopped at 1,056, and 476 bills carry over to the next run.

- **Archive: `site/activity/index.qmd` → `docs/activity/index.html`**, built by the normal project render (`render_index_pages()`).
  - Hero with a "Most recent: week of …" link.
  - One card per year, newest week first: a row per week with a page, showing the five counts plus the total actions.
  - Procedural-only weeks are marked "Procedural actions only", and gaps longer than a week get a row ("No recorded actions · Jul 20 – Sep 27"). Vetoes are noted beside the week.
  - On phones: short headers (Intro / Subcmte / Cmte / Floor / Signed), "Week of" dropped, the veto note on its own line, and the actions column hidden. All counts fit at 375px.
  - Quarto's JS adds `table-striped` to every table and Bootstrap paints the stripes as an inset `box-shadow`, so `.ia-week-table` overrides it.
- **`render.R`:**
  - `week_digests()` fingerprints each week from plain text: its actions, each active group's lead, title and *current* status, its prev/next neighbours, and for the newest week the data-through date.
  - `render_all_weeks(weeks, force)` re-renders weeks whose fingerprint moved (manifest `type = week`).
  - `render_site()` runs it after the index pages and before the bills (outside the bill time budget), and passes `weeks` through.
  - `test_render()` adds 2026-02-16 and 2026-04-27. `render_status()` and `status.json` report weeks.
- **Week template:** "1 bill group" / "2 actions" plurals fixed.

**Verified locally:**
- All 48 weeks rendered in 29.6 min with 0 failures. A second `render_all_weeks()` found **0** to render, so the fingerprint is stable.
- Disk: 51.8 MB total, max 2.74 MB.
- Archive checked at desktop and 375px.
- Edge weeks: 2025-01-13 has a disabled "← Earlier"; 2026-10-05 has a disabled "Later →" and "data through October 5, 2026"; procedural-only 2026-10-05 lists HF 2801 / SF 2508 as "Other activity".
- The June 2025 "procedural only" weeks are genuinely procedural: interim referrals and vote explanations.

**Not committed:** local renders, their Bootstrap builds, and the 48 manifest rows. CI renders all 48 weeks on its next run (~30 min, ahead of the bills). Until phase 5 adds the home card, nothing links to the archive except the week pages themselves.

## Phase 5 result (2026-10-25, done)

The home page's "Recent activity" card (8 bills with the latest `last_action_date`) is replaced by a **weekly summary card** in `site/index.qmd`:
- **Header:** "Week of September 28, 2026" plus an "All weeks →" link to the archive.
- **Sub-line:** if no bill has reached a stage for more than 7 days (judged against the render date), it says so plainly ("No bill has reached a new stage since October 2, 2026; this is the most recent week with activity"). Otherwise it reads "Feb 16 – Feb 22 · bill groups reaching each stage this week".
- **The five counts:** borderless tiles on the page tint, to avoid nested boxes, and a Vetoed tile when nonzero.
- **Rows:** the first 8 groups from `period_group_rows()` (furthest stage first) in the existing `.ia-recent-row` style. Each shows every active member's bill link, the clamped title, the stage labels as the meta line, the current group status, and the group's last action date that week.
- **Footer link** to the full week page ("See all N bill groups from this week →", or "See every action…" when all fit).
- **Phones:** two tiles per row (the auto-fit minimum missed two columns by 3px), tighter card padding, and the "All weeks →" link kept on one line.

Verified locally at desktop and 375px against the 2026-09-28 special-session week: cards 4 / 1 / 1 / 3 / 0; HF 2801 + HSB 785 + SF 2508 in one row; links resolve to `legislation/HF2801.html`, `activity/2026-09-28.html` and `activity/index.html`. HCR 106 shows "Passed Both Chambers" despite only being introduced that week, because the Legislature's related-bills list groups it with HCR 104 (2025's adjournment resolution). That is the group status, consistent with the week pages.

**Rollout:** CI renders the home page, archive and all 48 weeks in the same `render_site()` run (index pages first, then weeks), so the card's links resolve once that run commits. Local renders were again left uncommitted.

## Phases

1. **Classifier refactor:** `classify_action()` in utils, recognizing `Resolution adopted` (as floor passage) and `Vetoed by Governor`. `03` is rewritten on top of it and `groups.rds` regenerated. The funnel diff must be exactly the 61 adopted resolutions moving up from "Introduced" and nothing else.
2. **`06_weekly_activity.R`:** `bill_actions.rds`, the committee-originated flag, added to `run_pipeline.R`. Spot-check one week's counts against legis.iowa.gov.
3. **Week template:** render 2026-02-16 and one floor-heavy week with `-P`, then check page size, mobile, and expansion.
4. **Archive page + `render_weeks()` + manifest.**
5. **Home card** replaces "Recent activity".
6. **QA:** `test_render()`, then `/impeccable critique` on the home and week pages.
