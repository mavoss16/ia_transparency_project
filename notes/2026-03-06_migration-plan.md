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

1. **Preserve git history (optional)** — use `git filter-repo` to extract iowa_legislature history and merge into this repo:
   ```bash
   # In iowa_legislature clone:
   git filter-repo --to-subdirectory-filter legislature/

   # In ia_politics_transparency:
   git remote add legislature ../iowa_legislature
   git fetch legislature
   git merge legislature/main --allow-unrelated-histories
   git remote remove legislature
   ```
   If history doesn't matter, a straight file copy is fine.

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

- [ ] Repo initialized
- [ ] Migration executed
- [ ] Legislature site verified in new repo
- [ ] iowa_legislature repo archived
