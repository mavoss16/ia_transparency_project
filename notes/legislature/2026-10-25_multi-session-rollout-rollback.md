# Multi-session + shared maps: rollout and rollback (2026-10-25)

What the first CI run after pushing this work will do, what to check, and
how to undo it. Covers two changes that ship together:

1. **Session refactor + session URLs** (commit `4b6b2d20`): data moved to
   `legiscan/ga91/` and `data/legislature/ga91/`, bill pages to
   `docs/legislation/ga91/`, committee pages to `docs/committees/ga91/`,
   manifest keys `ga91/HF1`.
2. **Shared district maps + OSM basemap** (the commit after it): Leaflet maps
   draw `data/legislature/districts/web/plan2021_{senate,house}.js`, which
   Quarto copies to `docs/site_libs/ia-districts-plan2021-*-1.0.0/`;
   `addTiles()` replaces the CARTO basemap, which now serves "API KEY
   REQUIRED" tiles.

The maps change depends on the refactor (`maps.R` sources `session.R`; the
bill template moved to `site/templates/session/`), so it can't be pushed
alone.

**Restore point:** `origin/main` before the push was `2e94fae8`. Tag it
before pushing so every command below has a fixed name:

```bash
git tag pre-multisession 2e94fae8
git push origin pre-multisession
```

## What the first CI run will do

Pipeline steps (`download` → `weekly_activity`) read and write the new
`ga91/` paths. All offline steps were verified to reproduce identical
outputs; `download` needs the API and was not run locally. Its session ID
comes from the committed cache `data/legislature/legiscan_sessions.csv`
(91 → 2177), and its hash cache from
`data/legislature/ga91/pipeline_internal/bill_hash_cache.rds`.

Render, in order:

| Step | What happens |
|---|---|
| Index pages | Re-rendered. Bill links now point at `legislation/ga91/…`. The legislators index uses the shared maps. |
| Weeks | Only weeks whose fingerprint changed re-render. |
| Bills | **All 4,231 show as needing render** (new manifest keys). The 150-minute budget covers roughly 1,200 at ~8/min, so it takes **about 4 nights** (or several back-to-back manual runs). |
| Legislators | All 155 re-render every run, linking to `ga91/` bill URLs, with the shared map. |
| Committees | All re-render into `docs/committees/ga91/`. |

**Expected side effect, not a failure:** until the bills finish, links from
the index, legislator, committee and newer week pages to bills not yet
rendered at `ga91/` return 404. The old flat pages (`docs/legislation/HF1.html`)
stay in place and reachable by their old URLs. To shorten the window, run
the workflow manually (Actions → Daily Pipeline Update → Run workflow, with
`force_render` **off**) a few times back to back; the concurrency group
queues them.

Once every bill has rendered (`render_status()` shows 0 bills needing
render), remove the old flat pages and manifest rows:

```r
source("R/legislature/render.R")
remove_unsessioned_pages()                  # dry run: expect 4231 / 36 / 2 / 4267
remove_unsessioned_pages(dry_run = FALSE)
```

then commit `docs/` and `render_manifest.csv`.

## What to check after the run

1. **Did it finish?** Actions run status, and the `pipeline-logs` artifact
   (`logs/legislature/pipeline_*.log`). Each step logs `completed` or `FAILED`.
2. **Status page:** `status.html` / `status.json`: rendered and failed counts.
   Failed bills link to `legislation/ga91/…`.
3. **Folders exist in the bot's commit:** `docs/legislation/ga91/`,
   `docs/committees/ga91/`, `docs/site_libs/ia-districts-plan2021-senate-1.0.0/`
   and `…-house-1.0.0/`.
4. **A bill page with votes** (e.g. `legislation/ga91/SJR11.html` once rendered,
   or any bill in the night's batch): open Votes → Individual Votes; the maps
   show colored districts on OpenStreetMap tiles. Open the browser console:
   `IA district map: geometry not loaded for plan2021_…` means the site_libs
   script is missing.
5. **A legislator page:** the district map shows the legislator's district
   highlighted, neighbours faded.
6. **The legislators index:** both maps colored by party; clicking a district
   opens a popup with a working profile link.

## Rollback

Check that no workflow run is in progress first (Actions tab); a run that
starts mid-rollback will push on top of it.

### A. Only the maps are broken (pipeline and URLs fine)

Symptoms: maps blank or missing districts, console error about geometry,
everything else fine.

```bash
git revert --no-edit <maps-commit-sha>
git push
```

Pages already rendered with the broken maps don't re-render by themselves:
legislators and the index do (forced every run), but bills only re-render on
a hash change. Drop this session's bill rows so they render again:

```r
source("R/legislature/render.R")
m <- load_manifest()
save_manifest(m[!(m$type == "bill" & startsWith(m$id, "ga91/")), ])
```

Commit `render_manifest.csv`. The next runs re-render the bills over ~4
nights, as on the first rollout.

### B. Full rollback (pipeline step fails, paths wrong, or anything else)

Revert everything since the restore point, **including the bot's automated
commits**, newest first. That restores the old data paths, the flat pages,
the old manifest and the CARTO basemap in one consistent state:

```bash
git fetch
git revert --no-edit pre-multisession..origin/main
git push
```

- The bot's commits contain that night's LegiScan updates; reverting them
  drops those updates, and the next run fetches them again (the hash cache is
  reverted along with them).
- Reverting the refactor moves ~7,600 files back from `ga91/` folders. Git
  records them as renames, so the revert is large but mechanical. If it stops
  on a conflict, `git revert --abort` and use the fallback below.
- Afterwards the site is the pre-push site again, including CARTO's
  watermarked tiles (that problem predates this work).

Fallback if the revert won't apply cleanly: restore the tree to the restore
point as one new commit (history kept, nothing force-pushed):

```bash
git fetch
git checkout -B rollback origin/main
git rm -r -q --cached .
git checkout pre-multisession -- .
git clean -fd -- docs/legislation/ga91 docs/committees/ga91 legiscan/ga91 data/legislature/ga91
git commit -m "Roll back multi-session work to pre-multisession"
git push origin rollback:main
```

(`git clean` removes the new folders, which `checkout` alone leaves behind
as untracked files.)

### After either rollback

- Re-run the workflow manually to confirm a green run on the restored code.
- The local `main` still has the reverted commits underneath; fix forward on
  a branch rather than resetting history that CI has already built on.
