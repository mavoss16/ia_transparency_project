# Impeccable — usage reference (for the site design work)

Reference notes on using **Impeccable** (a design-guidance skill for AI coding
agents) to push the site design further and reduce the "AI-generated" look.
Written 2026-07-11 as a portable summary to carry into a future session.

## What it is

A design-guidance **skill** for AI coding agents (Claude Code, Cursor, etc.) that
fights "AI slop" frontend design — ~23 commands + ~46 deterministic detector
rules for AI-generated design tropes (overused fonts, generic palettes, default
spacing). It *guides* the agent; the agent still does the editing (so a
"critique → implement" loop is usually the **same** Claude Code session, first in
critique mode, then editing files). Framework-agnostic.

- Repo: https://github.com/pbakaus/impeccable
- Site: https://impeccable.style/

## Install & init

Vet before installing — `npx impeccable install` writes hooks into
`.claude/settings.local.json` and drops config files (`.impeccable/*`,
`PRODUCT.md`, `DESIGN.md`). Review what it adds before trusting it in this repo.

```
npx impeccable install
/impeccable init      # writes PRODUCT.md + DESIGN.md: audience, voice,
                      # anti-references, color/type system
```

## Key commands (`/impeccable <cmd>`)

`init`, `critique`, `audit` (feedback) · `polish`, `bolder`, `quieter`, `distill`
(refine) · `layout`, `colorize`, `typeset`, `animate` (targeted) · `live`
(in-browser variant iteration).

## How to use it

Point it at the **rendered output** (screenshots / a live browser via Playwright
MCP or its `live` mode) — it critiques the *rendered page* and doesn't need the
source. It works at multiple altitudes, not just CSS tokens:

1. Design brief (`init` → PRODUCT.md / DESIGN.md)
2. Layout / hierarchy / information-density (`critique`, `audit`, `layout`,
   `distill`) — **highest-value part for this project**
3. Component polish (`polish`, `bolder`, `quieter`)
4. Color / type tokens (`colorize`, `typeset`)

## Project-specific fit (Iowa Transparency Project)

**Stack:** Quarto + R + a cosmo/SCSS theme. A lot of the visual output is
produced by R (`gt`, `reactable`, `leaflet`, `ggparliament`) — Impeccable **can't
regenerate those**; use it to critique + guide, not to rewrite the pipeline.

**Where recommendations get implemented** (the agent edits these directly):

- `site/*/index.qmd` + `site/templates/*.qmd` — page structure (fenced-div grids,
  `.g-col-*` ratios, card / section order)
- `R/legislature/ui_helpers.R` — htmltools component emitters (stat grid, bar
  rows, profile header); a lot of "layout" actually lives here
- `site/custom.scss` — spacing, rhythm, tokens (the whole look inherits from this
  one file)

**QA loop:** rendered site is in `docs/`; `.claude/launch.json` has a
`docs-preview` static server on port 8642. Render one page with
`quarto render site/<page>.qmd` (Quarto is in the Positron bundle; set `QUARTO_R`
to the R-4.5.3 Rscript — see [[r-quarto-tool-locations]] in memory).

**Feasibility filter:** implement layout ideas that map to Quarto (reorder
sections, grid ratios, spacing, regrouping, hierarchy); skip ones that fight a
static site (scroll-driven sidebars, bespoke JS, animating R-rendered widgets).
Impeccable proposes → filter for Quarto-feasibility → implement what fits.

**Baseline already in place** (from the 2026-07-08/09 redesign — see
`notes/2026-07-08_legislature-redesign.md`): custom serif/sans pairing (Source
Serif 4 / Public Sans), warm `#f7f6f3` background, restrained R `#A8433A` /
D `#3F5B93` palette, a real `.ia-*` component system. So Impeccable would mostly
**audit and push further**, not start over.

## Related tool

**Playwright MCP** — gives the agent a live Chromium instance to navigate /
resize / screenshot, for a visual feedback loop (official Anthropic plugin:
https://claude.com/plugins/playwright). Equivalent to the browser-preview tools
already available inside a Claude Code session; useful when running Claude Code
locally in your own terminal.

## Install state & how to resume (2026-07-11)

**Installed.** Prereqs sorted this session:

- Node.js **v24.18.0** installed (`C:\Program Files\nodejs\`). PowerShell blocked
  `npx.ps1` at first (execution policy) — worked around it; permanent fix is
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- Ran `npx impeccable install`. What it wrote (vetted, clean):
  - Skill at `.claude/skills/impeccable/` (SKILL.md + `reference/*.md` + `scripts/`),
    duplicated at `.github/skills/impeccable/`.
  - `.impeccable/config.local.json` → `{"hook":{"consent":"declined"}}` —
    **hooks declined**, nothing auto-runs. **No** hooks added to
    `.claude/settings.local.json`.
  - No `PRODUCT.md` / `DESIGN.md` yet (those come from `/impeccable init`).

**To resume — restart Claude Code first** (the skill was installed mid-session, so
`/impeccable` isn't loaded as a slash command until a fresh start). Then:

```
/impeccable critique the dashboard      # or: /impeccable critique site/index.qmd
```

- `critique` is **feedback-only** — evaluates + writes a snapshot to
  `.impeccable/critique/`; does not edit `.qmd`/`.scss`. The editing commands
  (`polish`, `layout`, `quieter`, `typeset`, …) are separate and come *after*.
- Approve the read-only Node/read-file prompts it issues (`context.mjs`,
  `detect.mjs`, reading `custom.scss` etc.) — that's the skill inspecting the site.
- It runs as a **scoped critique of existing code** (no `PRODUCT.md`). Optional:
  run `/impeccable init` first for audience/voice/anti-reference-aware feedback.
- The critique flow prefers **two isolated sub-agents** (design review + detector);
  a fresh session may spawn them automatically for a stronger review. Single-context
  fallback is flagged with a `⚠️ DEGRADED` banner.
- Register: this is a **dashboard/tool** → product register (`reference/product.md`),
  not brand/marketing.
