# Campaign Finance Templates — Redesign and OJS Experiment

**Date:** 2026-05-09

## Overview

Two work streams in this session: (1) a layout and formatting redesign of both Quarto templates, and (2) an experimental OJS (Observable JavaScript) version of the recipient template with reactive year-range filtering.

---

## Template Redesign — Both Templates

### Summary section pulled above the tabset

Both `recipient_template.qmd` and `donor_template.qmd` were restructured so the summary information lives directly below the committee/donor name rather than inside a "Summary" tab. The Summary tab was removed. This means the most important information is immediately visible without any tab click.

**Recipient template summary section** now has four subsections:
- **Contributions Received** — total raised, transaction count, unique donors, average, date range
- **Expenditures Made** — total spent, expenditure count
- **Top Donors** — top 10 donors by total (all types), with type, city, state
- **Donor Type Breakdown** — individual / organization / committee split with share %

**Donor template summary section** now has three subsections:
- Summary stats (total donated, transactions, committees, average, date range)
- **Top Recipients** — top 10 recipient committees by total
- **Party Breakdown** — party totals with share %

### Donor Geography tab redesigned (recipient template)

Replaced the all-states table and Iowa city bar chart with:

1. **Iowa vs. Outside Iowa** — two-row summary table with total, share %, transactions, unique donors
2. **Iowa Deep Dive** — county choropleth + city dot map (using `tigris` + `sf` + `ggplot2`) and a top-20 Iowa cities table

The map uses:
- `tigris::counties(state = "IA")` for county polygon outlines
- `tigris::places(state = "IA")` for city centroids (via `st_centroid()`)
- `inner_join` to match donor cities to tigris place names
- `st_join` to assign each city point to its county
- County fill = sum of donations from all cities in that county (blue gradient)
- City dots = total from that city (orange, sized)

**Key bug fixed:** `clean_city` is title-cased (`str_to_title()`), but the matching code was only uppercasing the tigris `NAME` side, so every join silently produced zero matches and the map rendered blank gray. Fix: add `mutate(city_upper = str_to_upper(str_trim(city)))` to the donations side so both sides are uppercased before joining on `city_upper`.

### Integer formatting

Added `fmt_integer()` to all count columns (transactions, donors, committees, unique donors) across every `gt` table in both templates. Previously only currency columns had formatting.

---

## OJS Experiment — `recipient_template_ojs.qmd`

A new file created as an experimental copy of the recipient template, converting selected sections to Observable JavaScript for client-side reactivity. The R data loading and static summary section remain unchanged; the tabset content is progressively replaced.

### Architecture

**Data flow:**
```
R (build time)          →   ojs_define()   →   OJS (client, reactive)
────────────────────────────────────────────────────────────────────
by_year (aggregated)    →   by_year_ojs    →   by_year_rows (transpose)
all_contributions       →   contributions_ojs →  contributions_rows (transpose)
ia_counties GeoJSON     →   county_geojson →   L.geoJSON() fill
city centroids (lat/lon) →  city_coords_ojs →  city_dot_data
city → county lookup    →   city_county_ojs →  city_to_county (Map)
```

**Shared year range filter:**
Two `Inputs.range()` sliders (`shared_start`, `shared_end`) are defined once above the `:::  {.panel-tabset}` div. OJS reactivity is document-global, so all tabs reference the same variables — there is no per-tab slider.

`ojs_define()` sends R data frames as column-major JSON; `transpose()` converts them to row-major arrays of objects, which is what Arquero and Observable Plot expect.

### Libraries in use

| Library | Import pattern | Purpose |
|---|---|---|
| Arquero | `import { aq, op } from "@uwdata/arquero"` | Reactive data aggregation |
| Leaflet | `L = require("leaflet@1.9.4")` | Interactive Iowa map with tiles |
| Observable Plot | built-in | Bar charts |
| d3 | built-in | Color scales, min/max helpers |

### Tabs converted to OJS

**Contributions Over Time:**
- `by_year_tbl` filtered via `ot_tbl = by_year_tbl.filter(aq.escape(...))`
- Rolled up to yearly totals via `.groupby("year").rollup({total: d => op.sum(d.total)})`
- Observable Plot `Plot.barY` bar charts for totals and donor type breakdown

**Top Donors:**
- `range_tbl` = `contribs_tbl.filter(aq.escape(d => d.year >= shared_start && d.year <= shared_end))`
- `aggregateDonors()` helper groups by `donor_display`, sums `contribution_amount`, collects first city/state, takes top 25
- Displayed via `Inputs.table()` with currency and integer formatters

**Donor Geography:**
- **Iowa vs. Outside Iowa:** re-rolled from `range_tbl` using `.derive({region: aq.escape(...)})` + groupby
- **Iowa Deep Dive map:** R computes county GeoJSON + city centroid coordinates + city→county lookup at build time; OJS re-aggregates totals reactively and drives Leaflet
  - County choropleth: `L.geoJSON()` with `d3.interpolateBlues` fill color
  - City dot layer: `L.circleMarker()` with orange fill, radius scaled by `Math.sqrt(total/maxCity) * 20`
  - Iowa cities table: `iowa_city_totals.slice(0, 20)` displayed via `Inputs.table()`

**All Contributions:**
- `ac_filtered = range_tbl.objects()` — full filtered row array
- `Inputs.search()` for cross-column text filtering within the year range
- `Inputs.table()` with reactive row count display

### New R dependencies in OJS version
- `sf`, `tigris`, `jsonlite` — spatial join + GeoJSON export for Iowa map R computations

---

## OJS Debugging — Lessons Learned

This section documents compatibility issues hit in Quarto's OJS runtime (Observable's JavaScript engine) so we don't re-discover them.

### Import syntax rules for Quarto OJS

OJS does NOT support all ES module import patterns that standard JavaScript supports:

| Pattern | Status | Notes |
|---|---|---|
| `import { A, B } from "@..."` | ✅ Works | Named import from Observable CDN |
| `import { A } from "npm:..."` | ✅ Works | Named import via esm.sh |
| `X = require("pkg@version")` | ✅ Works | CJS modules; Observable's require() CDN |
| `import X from "npm:..."` | ⚠️ Unreliable | Default imports; works sometimes |
| `import * as X from "..."` | ❌ Syntax Error | Namespace imports NOT supported |

**Rule:** For well-known libraries, prefer the patterns that are known to work. If unsure, use `require()`.

**Cascade failure:** A syntax error in one `{ojs}` block prevents all variables in that block from being defined, causing "X is not defined" errors in downstream cells. Keep library imports in their own dedicated `{ojs}` blocks, separate from data setup, to limit the blast radius.

### Arquero API gotchas

The `op` aggregate functions have two call forms in `rollup()`. Only some work in the arrow-function form:

```javascript
// ✅ Arrow function form (closure) — works only for select aggregates
.rollup({ total: d => op.sum(d.contribution_amount) })

// ✅ String column name form — works for ALL aggregates
.rollup({
  total:        d => op.sum(d.contribution_amount),  // sum: closure OK
  transactions: op.count(),                           // count: direct OK
  city:         op.first('city'),                    // first: MUST use string
  donors:       op.array_agg('donor_display')        // array_agg: MUST use string
})

// ❌ Fails: "Table expressions do not support closures"
.rollup({
  city:   d => op.first(d.city),
  donors: d => op.array_agg_distinct(d.donor_display)
})
```

**`op.array_agg_distinct` may not exist** in the Arquero version loaded by `@uwdata/arquero`. Use `op.array_agg` + `new Set()` instead:

```javascript
.rollup({ donors: op.array_agg('donor_display') })
.derive({ donors: aq.escape(d => new Set(d.donors).size) })
```

### Leaflet in Quarto tabsets

When a Leaflet map initializes in a non-visible tab, the container div has zero dimensions and `fitBounds()` does nothing. Fix with a `ResizeObserver` that fires when the tab becomes visible:

```javascript
let fitted = false;
new ResizeObserver(() => {
  map.invalidateSize();
  if (!fitted && div.offsetWidth > 0) {
    map.fitBounds([[40.3, -96.7], [43.5, -90.1]]);
    fitted = true;
  }
}).observe(div);
```

The `yield div` generator pattern (required for Leaflet to find a real DOM node) must come before `L.map(div)`.

### City case mismatch (R ↔ OJS)

The `contributions_ojs` data uses `clean_city` (title-cased: "Des Moines"), while the R spatial lookup tables (`city_coords_ojs`, `city_county_ojs`) use `city_upper` (UPPERCASE: "DES MOINES"). OJS lookups must normalize before comparing:

```javascript
// county choropleth lookup
city_to_county.get(d.city ? d.city.toUpperCase() : null)

// city dot matching
iowa_city_totals.find(c => c.city && c.city.toUpperCase() === d.city)
```

`norm_state` in `contributions_ojs` is already UPPERCASE ("IA"), so `d.state === "IA"` works without normalization.

---

## External JS Libraries Evaluated

### Currently integrated

| Library | Import | Purpose | Notes |
|---|---|---|---|
| **Arquero** | `import { aq, op } from "@uwdata/arquero"` | Data aggregation | Stable; dplyr-like API |
| **Leaflet** | `L = require("leaflet@1.9.4")` | Interactive map | CSS via `include-in-header` from unpkg |

### Tried and abandoned

| Library | Issue |
|---|---|
| AG Grid Community | `require("ag-grid-community@31")` fails with "invalid module" — no UMD build available via Observable's require CDN. Named `npm:` import also fails. |

### Promising alternatives not yet tried

| Category | Library | Notes |
|---|---|---|
| **Tables** | **Tabulator** | Lighter than AG Grid. Try `require("tabulator-tables@5")`. Column filters, pagination, tree view. |
| **Tables** | Grid.js | Minimal. Try `require("gridjs")`. May need esm.sh URL directly. |
| **Tables** | DataTables | jQuery-based but very mature. Reliable UMD via `require("datatables.net@2")`. |
| **Charts** | Vega-Lite | `import { vl } from "@vega/vega-lite-api"` — Observable CDN. Declarative spec; better interactivity than Observable Plot. |
| **Charts** | ECharts | Try `require("echarts@5")`. Polished, good accessibility, animation. |
| **Charts** | Plotly.js | Try `require("plotly.js-dist@2")`. Statistical chart types, rich hover tooltips. |
| **Maps** | MapLibre GL JS | WebGL vector tiles; better than Leaflet for very large point datasets. Complex setup. |
| **Maps** | Deck.gl | WebGL for millions of points. Very complex; overkill for this use case. |
| **Data** | DuckDB-wasm | SQL in browser; could query raw Parquet directly. Complex setup, large WASM bundle. |
| **Search** | Fuse.js | Fuzzy search for `Inputs.search()` replacement. Small, no dependencies. |

### Priority integrations if AG Grid is needed again

Try loading AG Grid from a direct esm.sh URL rather than `npm:` or `require()`:
```javascript
{ createGrid } = await import("https://esm.sh/ag-grid-community@31/dist/ag-grid-community.esm.js")
```
Or try Tabulator first — it's lighter and more likely to load cleanly via `require()`.
