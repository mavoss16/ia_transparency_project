# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ia_transparency_project` promotes political transparency in Iowa by making public data more accessible and showing how datasets relate. Live at **https://iowatransparencyproject.org**.

| Domain | State | Read before working on it |
|---|---|---|
| **Iowa Legislature** — bills, votes, legislators, committees, weekly activity, lobbyist declarations | **Live**, updated daily by CI | [`R/legislature/CLAUDE.md`](R/legislature/CLAUDE.md) |
| **Campaign Finance** — IECDB state data + FEC for Iowa's federal candidates | Pipeline + DuckDB built; **nothing published** | [`R/campaign_finance/CLAUDE.md`](R/campaign_finance/CLAUDE.md) |
| **Elections** — precinct results and shapefiles | Download + crosswalk scripts; **no pipeline or site section** | [`R/elections/CLAUDE.md`](R/elections/CLAUDE.md) |

Those files load automatically when you work inside their folders, but **not** when you're editing their templates under `site/`, so read the domain file first for template work too. Cross-domain links live in `data/general/`. The only one so far is legislator `people_id` ↔ election candidate (`candidate_legislators.csv`, built by `R/elections/legislative_results/03_match_legislators.R`); campaign committees and lobbying clients aren't linked yet.

## Current focus and tasks

**[`ROADMAP.md`](ROADMAP.md) is the single list of open work.** Read it at the start of a task. Keep it current as part of the work, not as a separate chore: add an item when you find or defer something, remove it when it's done (the commit and session log are the record), and mark choices waiting on the user with **Decide**. Don't put task lists in this file or the domain CLAUDE.md files.

Now (late October 2026): prepare the legislature's 92nd GA rollover (January 2027); the `ga91/` URL rollout finished 2026-10-30. Campaign finance is blocked on the IECDB API cutover; elections should pull 2026 general results.

## Layout

```
R/{domain}/            pipeline scripts, numbered by stage; download/ for unnumbered one-off fetchers;
                       archive/ for deprecated code
R/exploratory/         analysis scripts, not production
R/ui_helpers.R         shared UI components + palette (all domains)
R/render_all.R         top-level render orchestrator (legislature only so far)
data/{domain}/         processed data; raw sources kept strictly separate
legiscan/ga{N}/        raw LegiScan data per session
site/                  Quarto project (output → docs/)
docs/                  rendered site, committed; GitHub Pages serves it
notes/{legislature,campaign_finance,elections,site,project}/
                       session logs and plans; site/ = design, hosting; project/ = cross-cutting
ROADMAP.md             open work, by milestone and domain
PRODUCT.md             product and design strategy
.impeccable/critique/  design critique snapshots
render_manifest.csv    incremental-render manifest (legislature)
```

Not committed: `data/campaign_finance/{source,processed}/` and the `.duckdb`, `data/elections/raw/`, `data/legislature/archive/{Floor Votes,Journals}/` (PDFs for the archived old pipeline), `logs/`, and Quarto output under `site/`.

## Tech stack and hosting

- **R** (4.5.1 in `renv.lock` and CI) for pipelines and site generation; **renv** for dependencies. Tidyverse style with the base pipe `|>`.
- **Quarto** static site via parameterized templates. `site/_quarto.yml`: `theme: [cosmo, custom.scss]`, `page-layout: full`, navbar title "Iowa Transparency Project". Campaign finance is excluded from project renders (see its CLAUDE.md).
- **GitHub Pages** serves `docs/` from `main` at the custom domain since 2026-10-28 (Cloudflare DNS, records DNS-only). `site/CNAME` is copied into `docs/` via `resources` so a full render can't drop the domain. Setup log: [`notes/site/2026-10-24_custom-domain-setup.md`](notes/site/2026-10-24_custom-domain-setup.md). Pages limits a site to about 1 GB.
- **CI:** `.github/workflows/daily-update.yml` runs the legislature pipeline at 06:00 UTC on `ubuntu-24.04` (pinned: PPM has no binary for the locked `later` on 26.04), then commits `docs/`, `data/`, `legiscan/` and the manifest. The bot commits daily, so **`git pull --ff-only` before starting work.**
- **APIs:** `LEGISCAN_API_KEY` env var (never hardcode credentials). IECDB is reached only through `R/campaign_finance/iecdb_api.R`.

## Shared UI components

`R/ui_helpers.R` holds the **domain-neutral** pieces: `ui_pill`, `ui_stat_card`, `ui_stat_grid`, `ui_bar_list`, `ui_stepper`, `ui_share_bar`, `ui_table`, `ui_empty`, `IA_PALETTE`, `ia_ramp()`, `theme_ia()` (ggplot), `gt_theme_ia()` (gt). `R/{domain}/ui_helpers.R` holds anything with domain vocabulary and sources the shared file, so templates source only their own domain's helpers. **Split rule:** if a campaign finance page and a legislation page could both call it without either reading oddly, it's shared; anything mapping domain values to styles or hardcoding domain labels is not. `ui_bar_list()` and `ui_share_bar()` take `format_value` (default: comma-grouped integers) so they work for money too.

`IA_PALETTE` duplicates the color literals at the top of `site/custom.scss` (ggplot and Leaflet can't read SCSS variables). **If the SCSS variables change, change `IA_PALETTE` too.**

## Conventions

- Raw source files strictly separate from processed data. Processed formats: legislature `.rds`; campaign finance Parquet + DuckDB; elections `.rds` for combined shapefiles.
- Pipeline scripts numbered by stage (`01_`, `02_`, …) within `R/{domain}/`; one-off downloaders in `R/{domain}/download/` without numbers. When a script's first-line comment or usage example names its own file, update it on a rename.
- Each domain gets its own `R/{domain}/render.R`, called from `R/render_all.R`. Original monorepo plan: `notes/project/2026-03-06_migration-plan.md`.
- Prefix test/scratch scripts with `_` (e.g. `_test_download_5.R`).
- Archive deprecated code in an `archive/` subdirectory rather than deleting it.
- Strong preference for tidyverse functions, with the base R pipe `|>`.
- Notes go in the matching `notes/{domain}/` folder. Two kinds: **session logs** (`YYYY-MM-DD_topic.md`, written once and not revised) and **plans or decision docs** (updated in place as decisions land). Link them from `ROADMAP.md` items rather than copying their detail.
- Keep this file and the domain CLAUDE.md files to rules, gotchas, how-to-run and current state. A line belongs here only if Claude would get something wrong without it and it will still be true next month; history goes in notes, tasks in `ROADMAP.md`.

## Design context

From `/impeccable init` (2026-07-11); full strategy in [`PRODUCT.md`](PRODUCT.md), which design work reads first.

- **Register:** `product` (a data tool; design serves the data). **Platform:** `web` (Quarto static site).
- **Audience:** broad Iowa public, mostly non-experts on low-commitment visits.
- **Positioning:** public Iowa political data made genuinely accessible, and showing how bills, votes, legislators and money connect.
- **Personality:** neutral, authoritative, trustworthy; restraint signals impartiality.
- **Anti-references:** partisan/campaign styling · generic SaaS/AI-slop dashboards · dated `.gov` drab · overwhelming data dumps.
- **Accessibility:** WCAG 2.1 AA (R-generated tables, charts and maps are the likely weak spots). `$faint` is `#706c63` for AA contrast; uppercase-tracked labels are reserved for the hero `.ia-eyebrow`; a ≤600px mobile block lives in `custom.scss`.
- **Principles:** (1) neutrality is a design constraint; (2) legible to the newcomer; (3) connections over collections; (4) trust through restraint; (5) hierarchy over volume.
- **Visual system:** Public Sans / Source Serif 4, background `#f7f6f3`, `.ia-*` components in `custom.scss`. DESIGN.md is not written yet; write it once the direction is settled.
- **Critique state:** snapshots in `.impeccable/critique/` (home 32/40, legislation 32, legislators 34 as of 2026-07-15; weekly summary 28). Re-run `/impeccable critique <page>` after changes. Open design items are in `ROADMAP.md`; finding details in [`notes/site/2026-07-15_design-backlog.md`](notes/site/2026-07-15_design-backlog.md).
