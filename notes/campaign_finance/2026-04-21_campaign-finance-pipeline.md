# Campaign Finance Pipeline — Initial Build

**Date:** 2026-04-21

## Overview

Built the initial data pipeline and Quarto page templates for the campaign finance domain. Work covered: Quarto report templates for recipients and donors, a data cleaning/normalization script, and a DuckDB database build script.

---

## Files Created

### Quarto Templates

**`site/campaign_finance/templates/recipient_template.qmd`**
Parameterized template for a committee or candidate that receives contributions. Parameter: `committee_code` (the numeric string from IECDB, e.g. `"1654"`), plus optional `committee_name` for the page title. Tabs: Summary, Contributions Over Time, Top Donors (individuals and organizations separately), Donor Geography, All Contributions, Expenditures.

**`site/campaign_finance/templates/donor_template.qmd`**
Parameterized template for an individual or organizational donor. Parameters: `donor_name`, `donor_type` (`"individual"` or `"organization"`), optional `donor_city`/`donor_state` for disambiguation when two unrelated people share a name. Tabs: Summary, Donations Over Time (with party-colored breakdown), Recipients (by committee, by party, by office sought), All Contributions.

Both templates are modeled on the legislator_template.qmd pattern from the `iowa_legislature` repo: `echo: false` format block, tabbed layout with `panel-tabset`, `gt` tables, `ggplot2` charts, graceful degradation when data is absent.

> **TODO:** Update both templates to query the DuckDB database (via `duckdb` + `dbplyr`) rather than reading source CSVs directly. The summary views built in step 04 cover all tabs.

### Pipeline Scripts

**`R/campaign_finance/02_clean_normalize.R`**
Reads the three raw IECDB source CSVs and writes cleaned Parquet files to `data/campaign_finance/processed/`. Key steps:

- Reads all columns as character (via `vroom`) to avoid type-inference failures on large files; parses dates with `mdy()` and amounts with `parse_number()`
- Classifies each contribution row as `individual`, `organization`, or `committee` transfer (committee code takes priority)
- Normalizes name/org/city/state fields to uppercase stripped strings (`norm_*` columns) — used as input to the future fuzzy-matching step 03
- Builds a `donor_key`: a readable pipe-delimited string (`IND|SMITH|JOHN|DES MOINES|IA`) used for exact deduplication; step 03 will collapse fuzzy near-duplicates across keys
- Merges the registered committees CSV (~1,600 rows) with `committee_lookup.rds` from step 01 (~7,900 rows) via a **full join** on `committee_code`, COALESCEing conflicting fields with API data taking priority for party. Degrades gracefully if step 01 has not been run.
- Party vocabulary aligned across both sources: "Democratic" (not "Democrat"), nonpartisan/not-available → `NA`

Output Parquet files:
- `contributions.parquet` — all individual contribution transactions, cleaned + normalized
- `expenditures.parquet` — all expenditure transactions, cleaned + normalized
- `committees.parquet` — merged committee registry (registered CSV ∪ API lookup)

**`R/campaign_finance/04_build_database.R`**
Ingests the three Parquet files into a self-contained DuckDB database (`data/campaign_finance/campaign_finance.duckdb`) and creates six pre-aggregated summary views:

| View | Grain | Used by |
|---|---|---|
| `committee_summary` | 1 row / committee | Recipient page header |
| `committee_donor` | 1 row / committee × donor | Top donors tables |
| `committee_year` | 1 row / committee × year × donor_type | Over-time charts |
| `donor_summary` | 1 row / donor_key | Donor page header |
| `donor_committee` | 1 row / donor × committee | Recipients tab |
| `donor_year` | 1 row / donor × year × party | Over-time + party charts |

All views join `contributions` to `committees` on `committee_code`. The merging of party/office data is done once in step 02; step 04 views need only a single join. Logs party coverage (% of contributing committees matched to a party) on each run.

---

## Run Order

```
01_build_committee_lookup.R   # API lookup — run first for full party coverage
02_clean_normalize.R          # clean CSVs + merge committee data → Parquet
  [03_link_donors.R]          # fuzzy donor deduplication — not yet built
04_build_database.R           # ingest Parquet → DuckDB + summary views
```

---

## Design Decisions

**DuckDB + Parquet.** Parquet provides ~5–10× compression vs. CSV (the contributions CSV alone is 476 MB) and is readable by `arrow`/`dplyr` independently of DuckDB. DuckDB ingests the Parquet files into its own columnar store for fast analytical queries; the `.duckdb` file is self-contained. Quarto templates filter to one committee or donor before pulling into memory, so the full dataset never loads per render.

**Aggregation strategy.** Transaction-level data lives in DuckDB as the source of truth. The six summary views cover all queries needed by the current Quarto templates; new analytical needs can be added as additional views without re-running the pipeline.

**Donor key design.** `donor_key` is a human-readable string rather than a hash, making debugging straightforward and eliminating collision risk. Exact-match deduplication (same name + city + state) is handled in step 02; fuzzy near-duplicate merging (typos, address variants) is reserved for the planned step 03 using `reclin2`.

**Committee code as primary key.** All three source files use the same numeric string as the committee identifier (`Committee Code` in contributions/expenditures, `Committee Number` in the registered CSV, `committeeCode` in the API). Renamed to `committee_code` universally in step 02.

---

## Known Gaps / Next Steps

- **Step 03 (fuzzy donor linking):** The `norm_*` columns in `contributions.parquet` are ready as input. Still needs: blocking strategy, `reclin2` comparison/classification, production of a `donor_crosswalk` table, and a manual review workflow for ambiguous pairs.
- **Quarto template wiring:** Both templates currently reference source CSVs. Update to use `duckdb` + `dbplyr` queries against the summary views.
- **Render script:** `R/campaign_finance/render.R` not yet built. Should follow the same pattern as `R/legislature/render.R` (manifest-based incremental rendering).
- **`find_source_file()` duplication:** The helper is defined in both `02_clean_normalize.R` and the Quarto templates. Worth extracting to a shared `R/campaign_finance/utils.R`.
