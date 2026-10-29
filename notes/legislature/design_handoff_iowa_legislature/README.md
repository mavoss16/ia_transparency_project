# Handoff: Iowa Legislature Site Redesign

## Overview

A visual/UX redesign of the Iowa Political Transparency site (https://mavoss16.github.io/iowa_legislature/, source repo: `mavoss16/ia_transparency_project`), a Quarto website built from `.qmd` files in `site/`, rendered by an R data pipeline. Five pages were redesigned as high-fidelity mockups:

1. **Home** (`site/index.qmd`) — mockup id `1a`
2. **Bill detail** (`site/legislation/<bill>.html`, templated) — mockup id `1b`
3. **Legislation overview** (`site/legislation/index.qmd`) — mockup id `2a`
4. **Legislators overview** (`site/legislators/index.qmd`) — mockup id `2b`
5. **Legislator detail** (templated) — mockup id `2c`

## About the Design Files

`Iowa Legislature Redesign.dc.html` is a **design reference created in HTML** — a prototype showing intended look, not production code. The implementation target is **Quarto**: recreate these designs by editing the `.qmd` files, adding the provided `custom.scss` theme, and using the provided R helper functions (`ui_helpers.R`) that emit HTML via htmltools. The `quarto_starter/` folder in this bundle contains ready-to-use implementation files; its README maps each mockup component to the exact qmd code blocks in the repo.

## Fidelity

**High-fidelity.** Colors, typography, spacing, and copy treatments are final and should be matched. Data values shown are real values scraped from the live site (June 2026 session data) — the real pages compute these from the pipeline.

## Design Tokens

Typography:
- Headings / large numerals: **Source Serif 4**, 700 (Google Fonts)
- Body / UI: **Public Sans**, 400/500/600/700 (Google Fonts)
- Page H1: 34–40px; card titles: 17–18px serif; body/table text: 13–14px; stat numerals: 32–36px serif; uppercase labels: 12px, letter-spacing 0.04–0.08em

Colors:
- Ink `#23211d` · soft ink `#55524a` · muted `#6d6a62` · faint `#8a877e`
- Page background `#f7f6f3` · card `#ffffff` · border `#e4e2da` · row divider `#efeee8`
- Republican red `#A8433A` (also nav active-tab underline / brand accent)
- Democrat blue `#3F5B93` (also link color)
- Signed green `#256a43` on `#e3efe6` · vetoed red `#8f3a31` on `#f4e3e1`
- In-progress amber `#7d5c17` on `#f0e9d8` · neutral pill `#55524a` on `#eeede7`
- Bar fill `#8f8b80` · bar track `#f0efe9` · group-status bar `#c5c1b4` · low-participation amber `#b07d24`

Shape & spacing:
- Cards: white, 1px `#e4e2da` border, 10px radius, ~24px padding, 16px gaps
- Pills: 99px radius, 12px/600 text, 4px×10px padding
- Bars: 4px radius (14–18px tall lists), 99px radius (7px table cell bars)
- Content: full-width layout (~1280–1360px), no right TOC rail on index pages

## Screens

### 1a Home
- Nav: white bar, serif brand "Iowa Legislature" + "91ST GENERAL ASSEMBLY" label; active tab has 2px `#A8433A` underline.
- Hero: red uppercase session eyebrow, 40px serif H1, one-line description, "Last updated" right-aligned.
- 4 stat cards: TOTAL BILLS 4,224 / SIGNED BY GOVERNOR 364 / AWAITING GOVERNOR 24 / LEGISLATORS 150, each with uppercase label, serif numeral, muted sub-line.
- Two cards side by side: **"Where bills stand"** — horizontal bar list of the 6 statuses (Introduced 1,528 · Passed Subcommittee 434 · Passed Committee 1,604 · Passed One Chamber 270 · Passed Both Chambers 24 · Signed by Governor 364, green fill on Signed only, right-aligned labels, counts right of bars); **"Who holds the chambers"** — two hemicycle (parliament) dot charts, House 67R–33D, Senate 33R–17D, with large serif "67 – 33" counts beneath and a dot legend.
- **Recent activity** card: rows of [bill link | cleaned title + muted meta line | status pill | right-aligned date], hairline dividers, "All legislation →" link.
- Two browse cards (one dark navy `#2b354c` with white text, one white) + data-sources footnote.

### 1b Bill detail (HF 1023)
- Breadcrumb "Legislation / HF 1023".
- Header card: "HOUSE FILE 1023" red eyebrow + green "Signed by Governor" pill; cleaned title as serif H1 (boilerplate stripped); one meta row (Sponsor · Effective · Formerly · Last action); 6-step progress stepper (green ✓ circles, connecting green lines, labels + dates beneath).
- Two cards: **Lobbyist declarations** — single stacked bar (For green 12 / Against red 0 / Undecided gray 10) with colored legend; **Related legislation** — rows with bill link, note, status pill.
- Tabbed card (History | Votes | Lobbyist declarations | Calendar items): history rows [date | chamber tag colored red/blue | action].

### 2a Legislation overview
- H1 + count sentence.
- **Bills by type** card: bar list with compact abbreviations (HF 1,855 … SCR 6) + abbreviation key footnote.
- **Status summary** card: paired bars per status — dark `#55524a` bar = individual status, light `#c5c1b4` bar = group status, legend on top, sub-line "Group status reflects the furthest progress of any related bill". Replaces the two side-by-side gt tables.
- **Recent bills** card: same row pattern as 1a (includes a red "Vetoed by Governor" pill example).
- **Browse** card: search input + filter chips (All / Chamber / Status / Sponsor / Bill type) replacing per-column filter inputs; keep the interactive table beneath (gt `opt_interactive` or reactable).

### 2b Legislators overview
- Header: H1 + party-split stacked bars for House (67R/33D) and Senate (33R/17D) at top right.
- **Find your legislator** card: district map (existing leaflet) with House/Senate segmented toggle.
- **Senate table** card (House identical): columns Name | District | Sponsored | Sole | Votes | Party Alignment | Participation. Name has 9px party dot; replaced legislators get a small gray "FORMER" chip (De Witt + Drey both listed under SD-001). Alignment/Participation cells are inline bars (7px, pill radius) + right-aligned %; values < 60% render amber (`#b07d24` bar, `#7d5c17` text) — e.g. Rowley 49.3%, Garrett 41.3%. Sortable headers.

### 2c Legislator detail (Rocky De Witt)
- Breadcrumb; profile header card with 4px party-colored left border: name (serif 32px) + solid party pill on one line; meta line "Senator · District SD-001 · Sioux City area, Iowa"; amber notice "No longer serving — succeeded by Catelin Drey (D)…" linking to successor; outline buttons (Email, Ballotpedia ↗, VoteSmart ↗) top right.
- 2×2 stat cards (Bills Sponsored 3 / Party Alignment 98.7% / Participation 81.0% / Floor Votes 290) with district map card (380px) beside them.
- Tabbed card (Sponsored bills | Voting record | Vote analysis | Similar legislators): sponsored rows [bill | title | status pill | role | date].
- **Voting record** card: rows [bill | title | vote type | date | vote pill] — Yea green / Nay red / Absent gray.

## Interactions & Behavior

- Table sorting via reactable (legislator tables); search + filters on browse tables.
- Tabs via Quarto `::: {.panel-tabset}`.
- Row hover: subtle background tint; no zebra striping.
- All bill numbers and legislator names are links to their detail pages.
- Bill titles: strip "A bill for an act relating to …" boilerplate; move "(Formerly …)" and "Effective date: …" into a muted meta line (see `clean_bill_title()` in `ui_helpers.R`).

## Implementation Files (`quarto_starter/`)

- `custom.scss` — complete Quarto SCSS theme (use `theme: [cosmo, custom.scss]`). Class names: `.ia-card`, `.ia-stat-*`, `.ia-pill-*`, `.ia-bar-*`, `.ia-step*`, `.ia-share-*`, `.ia-cellbar*`, `.ia-dot-*`, `.ia-profile-header`, `.ia-notice`.
- `ui_helpers.R` — htmltools emitters: `clean_bill_title()`, `ui_pill()`/`status_pill()`/`vote_pill()`, `ui_stat_card()`/`ui_stat_grid()`, `ui_bar_list()`, `ui_paired_bars()`, `ui_stepper()`, `ui_share_bar()`, `ui_profile_header()`, `legislator_table()` (reactable), `gt_theme_ia()`.
- `README.md` — per-page wiring guide with code blocks keyed to the repo's actual variable names (`stage_counts`, `bill_types`, `status_summary`, `group_status_summary`, `recent_bills`, `all_bills`, `active_people`).

Repo integration notes:
- Helpers were written against `site/index.qmd` and `site/legislation/index.qmd` column names as of July 2026; the bill/legislator template qmds may need minor renames.
- Parliament charts: keep ggparliament, change `party_colours` to `c("R" = "#A8433A", "D" = "#3F5B93")`, drop in-plot titles (card headings replace them).
- Leaflet maps: recolor district fills to the same two party hexes.
- Add `reactable` to renv.
- Set `toc: false` on index pages (or `page-layout: full`) to reclaim the right rail.

## Assets

No image assets. Fonts from Google Fonts (imported in `custom.scss`). Hemicycle charts and maps are generated by the existing R pipeline.

## Files in this bundle

- `Iowa Legislature Redesign.dc.html` — the design reference (all five mockups on one canvas; ids 1a, 1b, 2a, 2b, 2c). Open in a browser to view.
- `quarto_starter/` — implementation starter kit described above.
