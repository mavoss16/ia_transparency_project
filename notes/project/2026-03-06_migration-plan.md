# Migration Plan: iowa_legislature → ia_politics_transparency

## Decision: Unified Quarto Site (Option A)

One `site/` with sections for each domain (legislature, elections, donations). Chosen because the core goal is highlighting relationships *between* datasets — a unified site makes cross-domain pages (e.g., legislator + their donors) possible.

## Proposed Directory Structure

```
ia_politics_transparency/
├── R/
│   ├── legislature/          ← from iowa_legislature/R/
│   │   ├── data_pipeline/
│   │   ├── daily/
│   │   ├── render_site.R     (becomes render_legislature.R)
│   │   └── utils.R
│   ├── elections/
│   └── donations/
├── data/
│   ├── legislature/          ← from iowa_legislature/data/
│   ├── elections/
│   └── donations/
├── legiscan/                 ← from iowa_legislature/legiscan/
├── site/
│   ├── _quarto.yml
│   ├── index.qmd             (new unified home page)
│   ├── legislation/          ← from iowa_legislature/site/legislation/
│   ├── legislators/          ← from iowa_legislature/site/legislators/
│   ├── elections/
│   ├── donations/
│   └── templates/
│       ├── bill_template.qmd
│       └── legislator_template.qmd
├── docs/                     ← rendered output (GitHub Pages)
├── renv.lock
└── ia_politics_transparency.Rproj
```

## What to Migrate vs. Leave Behind

| Migrate | Leave in iowa_legislature |
|---|---|
| `R/data_pipeline/`, `R/daily/`, `R/utils.R`, `R/render_site.R` | `shiny_app/` (legacy) |
| `site/` (all `.qmd` files and templates) | `archive/` |
| `data/` (processed `.rds` files) | `test_data_app/` |
| `legiscan/` (raw source data) | `session_notes/` |
| `.github/` workflows | |
| `renv.lock` | |

## Migration Steps

1. **Preserve git history (decided 2026-07-05)** — use `git filter-repo` on a copy of `iowa_legislature` to rewrite paths to `legislature/`, then merge that history into this repo:
   ```bash
   # Work on a fresh clone, not the working iowa_legislature repo, since
   # filter-repo rewrites history in place and is destructive to that clone
   git clone ../iowa_legislature ../iowa_legislature-filtered
   cd ../iowa_legislature-filtered
   git filter-repo --to-subdirectory-filter legislature/

   # In ia_transparency_project:
   git remote add legislature ../iowa_legislature-filtered
   git fetch legislature
   git merge legislature/main --allow-unrelated-histories
   git remote remove legislature
   ```
   Only files on the migration map get merged in the working tree afterward — filter-repo brings over the whole repo's history under `legislature/`, but files on the "skip" list still get deleted from the working tree post-merge (history remains, just no longer checked out).

2. **Set up repo skeleton** — `.Rproj`, `renv`, `_quarto.yml`

3. **Migrate legislature files** into the new structure

4. **Refactor render orchestration** — each domain gets its own render function; top-level orchestrator calls all of them:
   ```r
   source("R/legislature/render.R")
   source("R/elections/render.R")
   # render_all() calls each
   ```

5. **Update `_quarto.yml`** — top-level navbar spanning all domains; legislature sections slot in as-is

6. **Restore renv** — `renv::init()` then restore from migrated `renv.lock`; use `renv::snapshot()` as new packages are added

7. **Verify** legislature site renders correctly from new repo

8. **Deprecate** `iowa_legislature` repo once stable

## Status

- [x] Repo initialized
- [x] Migration executed (2026-07-05 — history merged via filter-repo, files reorganized per migration map)
- [x] Legislature site verified in new repo (2026-07-05 — test_render(): 5 bills, 5 legislators, 3 committees, 0 failures)
- [ ] iowa_legislature repo archived
