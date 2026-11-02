# CI workflows plan: split the daily job by cadence (2026-11-01)

Plan, partly built. Update in place as pieces land. **Built (2026-11-01):**
the render backlog workflow, the shared setup action, and the lobbying
workflow; organization pages are off the daily path; legislator and committee
pages are digest-gated. All four steps are built; what's left is checking the
first runs (`ROADMAP.md`).

One workflow, `.github/workflows/daily-update.yml`, runs everything on one
06:00 UTC schedule. It is close to its limits, and lobbying (now with 1,003
organization pages) doesn't fit in it. This plan splits CI into three workflows
grouped by how often the work needs to run.

## Why split

The daily job mixes work with very different costs and cadences:

| Work | Needs to run | Cost |
|---|---|---|
| LegiScan pull, processing (`01`–`03`, `06`), changed bills, weeks, index pages | Daily | ~10 min setup + pipeline, plus changed pages (~8 bills/min) |
| Legislator and committee pages | Only when their data changes | ~115 min, **forced every night** |
| Lobbying scrape (`04`) and derived data (`04a`, `04b`, `05`, `04c`) | Weekly in session, rarely otherwise | ~3 h scrape (4,231 bills at ~2.5 s) |
| Organization pages | When lobbying data changes | ~23 s each; ~6½ h for all 1,003 |

- The job has `timeout-minutes: 300` and `RENDER_TIME_BUDGET_MINUTES: 150`; the
  budget was tuned to leave ~25 min of slack.
- A 3-hour scrape can't join the job, and lobbying pages that share the bills'
  budget delay bill pages whenever a scrape changes hundreds of organizations.
- Lobbying has its own rhythm: declarations cluster around bill deadlines and
  stop between sessions. `04` can't tell when a new declaration lands on an
  idle bill (the LegiScan `change_hash` doesn't move), so it needs periodic full
  scrapes, not daily incremental ones.
- One-off backlogs (a full re-render after a template change, the first render
  of 1,003 organization pages) have nowhere to run except inside the daily
  job's budget.

## The three workflows

### 1. Daily update (existing, made lighter)

`daily-update.yml`, daily plus manual run. Scheduled 06:17 UTC since
2026-11-02 (was 06:00; runs at :00 started 4½–9½ h late).

- LegiScan pull and processing, as now (`run_pipeline.R`).
- Renders changed bills, weeks and index pages.
- **Change:** gate legislator and committee renders on a digest of their
  inputs, like `week_digests()`, instead of forcing them. This is the biggest
  single saving (~115 min a night to near zero on a quiet day) and stops ~65 MB
  of rewritten HTML entering git history daily. Already a roadmap item.
- ~~**Change:** drop `render_all_organizations()` from the daily
  `render_site()` path.~~ Done 2026-11-01 with the lobbying workflow.
- While a session is in `FROZEN_GAS` the run does nothing, as now.

### 2. Lobbying (new)

**Built 2026-11-01.** `lobbying-update.yml`, Mondays 12:43 UTC plus manual
run (a `scrape` checkbox; off rebuilds from the saved filings), calling
`run_lobbying()` in `R/legislature/run_lobbying.R`. It returns at once while
the current GA is frozen, so between sessions it stops on its own. One time
budget (`RENDER_TIME_BUDGET_MINUTES`, 300, counted from the start, scrape
included) inside a 350-minute timeout; it renders organizations, the lobbying
index, then bills. The scrape from GitHub's runners is untested: if
legis.iowa.gov blocks them (as sos.iowa.gov blocks httr2), the scrape step
fails and nothing else changes.

1. Full scrape: `update_lobbyist_declarations()` with every bill, then retry
   failures with `rescrape_lobbyist_declarations()`.
2. `04a` (alignment), `04b` (clients), `05` (salience), `04c` (organization
   tables), in that order: `04c` reads `05`'s stages.
3. Render: organization pages (`render_all_organizations()`, incremental on
   `organization_digests()`), the lobbying index, and bill pages whose
   declarations changed (the bill hash already includes `lobby_digests()`).
4. Commit `data/legislature/ga{N}/lobbying/`, `docs/` and the manifest.

Own timeout: the scrape is ~3 h before any rendering. If that's too tight,
split scrape and render into two jobs in the workflow, passing the data as an
artifact, or give rendering its own time budget and let the next run finish.

Open: the scrape makes ~4,200 requests to legis.iowa.gov at ~1.5 s spacing.
Weekly is gentle; daily full scrapes would not be.

### 3. Render backlog (new, manual only)

**Built 2026-11-01.** `render-backlog.yml`, `workflow_dispatch` only, calling
`render_backlog()` in `render.R`. Inputs:

- `target`: everything / bills / organizations / weeks / legislators /
  committees. `everything` renders the index pages first, then each type in
  that order (weeks before bills, as in `render_site()`).
- `force`: clear that page type from the manifest first
  (`clear_manifest_type()`; legislators clears `legislator_archive` too)
- `budget_minutes`: stop starting pages after this long (default 300, job
  timeout 350). Legislators, committees and weeks now take a `deadline` like
  bills and organizations, so one budget covers every type.

Commits `docs/` and the manifest only. The `force_render` input is gone from
the daily workflow; a full re-render is `target: everything, force: on`, then
follow-up runs with force off.

Re-run until the backlog is empty; each run commits its progress, and the
manifest records what's done. First uses:

- The initial 1,003 organization pages (~6½ h, so two or three runs).
- The forced re-render waiting on 2026-11-01 template changes (ochre Against
  bar and organization links on bill pages, the Lobbying navbar entry on every
  page).
- Moves the `force_render` input off the daily workflow.

## Shared pieces

- **One concurrency group.** All three use `concurrency: group: pipeline`
  (already on the daily job, `cancel-in-progress: false`), so they queue
  instead of running at once and never commit to `main` at the same time.
- **One setup.** R 4.5.1, the system libraries, Quarto and the renv cache are
  ~10 min of identical steps. Put them in a composite action
  (`.github/actions/setup-site/action.yml`) that each workflow calls. Keep the
  `ubuntu-24.04` pin and its comment there.
- **One commit step.** The existing `git add` / commit / `pull --rebase -X
  theirs` / push block, shared the same way, with each workflow adding only the
  paths it writes.
- **Logs.** Each workflow uploads `logs/` as an artifact, as now.

## Related decision: deploy with `actions/deploy-pages`

Open **Decide** in `ROADMAP.md`. More workflows rendering more pages makes it
more pressing: every render commits HTML into git history (`.git` ~900 MB and
growing). Deploying `docs/` as a Pages artifact would remove the commit step
for HTML and the rebase dance, but the render manifest assumes the previous
output is on disk, so each run would need the last deployed site (or a cache)
to render incrementally. Not required for this split; the two fit together.

## Order

1. ~~**Render backlog workflow**~~ (built 2026-11-01).
2. ~~**Lobbying workflow**, then remove organization pages from the daily
   path~~ (built 2026-11-01).
3. ~~**Digest-gate legislator and committee renders**~~ (built 2026-11-01:
   `legislator_data_digests()` and `committee_data_digests()` hash each page's
   own rows of every input; ~10 s for both. Tested stable across R sessions,
   and changing one bill's status changed exactly its 100 sponsors and voters
   and its 2 committees).
4. ~~Composite setup action~~ (built with 1: `.github/actions/setup-site/`).
   The shared commit step is still copied into each workflow.
