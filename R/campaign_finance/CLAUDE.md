# Campaign Finance

Iowa state data from the Iowa Ethics and Campaign Disclosure Board (IECDB), plus FEC data for Iowa's U.S. House and Senate candidates. Raw exports are not committed (too large). **Nothing is published yet:** there is no `index.qmd`, no `R/campaign_finance/render.R`, and the navbar entry in `site/_quarto.yml` is commented out.

**Data currency (202607 export):** state contributions through **2026-07-14** (3,200,787 rows), expenditures through **2026-07-16** (652,661 rows), 8,020 committees. FEC data is from the 2026-05-10 download and has not been refreshed.

## Data sources

### Bulk exports (data.iowa.gov) — not current

The bulk CSVs come from [data.iowa.gov dataset 917](https://data.iowa.gov/catalog/dataset/917). The feed is **eventually consistent and never an as-of snapshot**: the 202607 export (pulled 2026-07-25) was missing the May 27 – July 14 period for most statewide committees (Sand's DR2, filed 2026-07-20, was absent), while 306 committees did have July data. The IECDB portal API returns the same transactions current through 2026-07-14. **Cash on hand exists only on the DR2 report PDFs** and cannot be derived from any transaction feed. Full reconnaissance: [`notes/2026-07-25_iecdb-api-data-sources.md`](../../notes/2026-07-25_iecdb-api-data-sources.md).

Exports live in `data/campaign_finance/source/IECDB/{YYYYMM}/`, **one directory per download**; the pipeline reads the newest. Each contains contributions (~3.2M rows, **may be split into numbered part files** `..._part_0001.csv`…, chronological, each with its own header), expenditures (~650k), the registered committee list (~1,700), and an other-PACs file the pipeline does not read.

**Export vintages differ** in column names and date formats; `utils.R` normalizes them:

| | through `202603` | from `202607` |
|---|---|---|
| Column names | human-readable (`"Contribution Amount"`) | machine (`amount`, `committee_cd`, `first_nm`) |
| Transaction dates | `MM/DD/YYYY` | ISO `YYYY-MM-DD` |
| Election dates | `2022 Nov 08 12:00:00 AM` | `2026-11-03 00:00:00` |

Shims (all applied in `02_clean_normalize.R`): `latest_iecdb_export()`, `find_source_files()` / `find_source_file()` (plural returns all parts, name-sorted), `rename_if_present()` with `IECDB_CONTRIBUTION_COLS` / `IECDB_EXPENDITURE_COLS` / `IECDB_REGISTERED_COLS` (maps either vintage onto the older canonical names), `parse_iecdb_date()` / `parse_iecdb_election_date()`.

**Adding a new export:** drop it in a new `IECDB/{YYYYMM}/` directory and re-run `02` → `04`. If IECDB renames columns again, extend the mapping vectors in `utils.R` rather than editing `02`.

**Committee codes** mix numeric (`5185`, ~5,600) and alphanumeric (`CTY51589`, `SWGA51409`, ~1,400) strings, with no leading zeros. **Always pass them as strings**: a numeric-looking code reaching DuckDB as a number makes it cast the whole varchar column to INT32 and fail on the alphanumeric rows.

### IECDB API — settled facts

- **No bulk dump.** `/api/search/table` returns `204` without a `primaryCommitteeId`; a committee filter is mandatory. `POST /api/publicreports/state` returns all filings with `filedOn` in one unfiltered call, so it serves as a **change feed**.
- **GUID vs `committee_code` is a non-issue.** `committee_lookup.rds` stores `committee_uuid` for 7,935 of 7,936 committees; transaction rows carry `primaryCommitteeCode`, so joins use the existing key.
- **No terms-of-service prohibition** (`robots.txt` disallows nothing; Chapter 22 open records). Permission by absence, not a licence: throttle, identify the client, cache.
- **Loans are not in the public API.** `transactionType = "CON"` returns `CON` + `INK` only (131 loan transactions across five committees, 0 returned). Hidden enum values (`LOANREC`, `LOANREP`, `VSR`) return empty; the per-schedule endpoints are filer-side (401). In-kind is also unreliable in the API.
- **The loan path is the DR2 PDFs.** The "Summary" PDFs are complete filed reports: page 1 is the Statement of Cash On Hand, Schedule F1 has lender-level detail. Digitally generated; `pdftools::pdf_text()` extracts cleanly. **Strategy:** bulk data for loan history + DR2 Schedule F1 parsing for the recency gap. `iecdb_download_filing()` fetches PDFs into `data/campaign_finance/source/dr2_filings/` (ignored; a full mirror is ~3–4 GB). Link filed reports via the filings index's `file_url`, rendered fresh each pull (amendments get new filenames).
- **`referenceDR2Id` is not period attribution**: it is the all-zeros GUID on ordinary contributions. Infer periods from `date` against filing-period boundaries.

**Migration plan is Phases A–D** in the API note. Phases A–C come **before** `render.R` / index / donor pages, because Phase D changes the data model. (The transaction-class split, originally Phase D, was done 2026-07-27.)

## Pipeline

```
iecdb_api.R                    THE ONLY thing that may call the IECDB API. Throttled (1s),
                               retrying, request-budgeted, per-endpoint schema contracts that
                               FAIL on missing fields. iecdb_health_check() = 2-request canary;
                               run it before any ingest.
01_build_committee_lookup.R    API → processed/committee_lookup.rds (~7,900 codes, party, uuid)
01b_iecdb_ingest.R             change-detection ingest (Phase B; see below)
02_clean_normalize.R           newest export + lookup → processed/{contributions,expenditures,
                               committees}.parquet (parts stacked, vintages harmonized)
02a_clean_normalize_federal.R  FEC source → processed/fec_{contributions,committees}.parquet
03_link_donors.R               fuzzy donor dedup — BUILT BUT NOT WORKING; donor_crosswalk.parquet
                               has never been produced and nothing depends on it
04_build_database.R            all Parquet → campaign_finance.duckdb + summary views
download/fec_contributions.R   FEC bulk zips per cycle → source/federal/{cycle}/
```

### Phase B ingest — `01b_iecdb_ingest.R`

Sourcing the file performs **no requests**; planning is separate from executing so the cost is visible first. Session log: [`notes/2026-08-01_phase-b-ingest.md`](../../notes/2026-08-01_phase-b-ingest.md).

```
iecdb_refresh_filings()   1 request     all ~17,900 filings → source/iecdb_api/filings_index.parquet
iecdb_plan_refresh()      0 requests    diff feed vs manifest → one row per committee, with a reason
iecdb_run_refresh(plan)   1+/committee  pull transactions, write parquet, update manifest
iecdb_ingest_status()     0 requests
iecdb_load_transactions() 0 requests    read the cache back (Phase C reconciliation)
```

`data/campaign_finance/iecdb_manifest.csv` **is committed** (small; it makes the next run cheap); `source/iecdb_api/` is not. Change signals (`reason`): `never-pulled`, `new-filing`, `refiled` (later `filed_on`, or same count/timestamp with a different filing id), `previous-error`, `forced`.

- **Resumable:** each committee's parquet and manifest row are written as the loop goes, with an `on.exit()` save. One committee's failure is recorded and skipped; budget exhaustion is fatal.
- **Timestamps are UTC throughout** (`iecdb_as_utc()`); otherwise a manifest round-trip changes `tzone` and R warns on every comparison.
- **`reported_through`** comes from `iecdb_parse_period_end()`, which splits on the **last** separator and reads the tail only (the vocabulary includes `"January 1 through December 31"`, `"Oct. 15 through Dec. 31 or Wed. Preceding General through Dec. 31"`). 91.6% of filings parse; 99.5% of committees get a date. The remainder is mostly `"… through Tuesday Preceding Primary/General"`, an election rather than a date; `NA` is correct until an election calendar exists.
- **Coverage: the feed is state filings only.** 1,403 committees, against 8,531 in `committee_summary`; it covers 80.7% of money. Every local committee type (county, city, school board, county central, local ballot) is at 0%; 1,147 of those were active in 2024+ ($50.6M). `countyReports` is the candidate second feed; a probe returned the usual `{totalCount, filteredCount, echo, results}` envelope but its record shape is unconfirmed. Until then the API supplements data.iowa.gov rather than replacing it, and Phase C should be scoped to the state slice.

**Live status (2026-08-01):** filings feed pulled (17,876 filings, latest `filed_on` 2026-07-30); 5 committees pulled clean (5,247 rows, no `LOANREC`). A full sweep is ~1,429 requests / ~24 min.

Both bugs found on the first live run produced plausible output rather than errors: an empty R `list()` serialized to `[]` where the filings endpoint wanted `{}` (HTTP 400; fixed in `iecdb_perform()` by naming the empty list), and `reported_through` was the period's *start* date. `iecdb_health_check()` doesn't exercise the filings endpoint, which is why the first one slipped past it.

> **Cutover blocker — unresolved.** Committee **`1046`** returned fewer API rows than bulk for 2007 (19 vs 81) and 2008 (23 vs 138). That is what response truncation would look like, and it bears on the untested assumption that one `iecdb_transactions()` call returns everything for a committee. Until explained, the API can't be assumed complete for historical data. The API otherwise has *more* history than bulk (back to 1996; committee `109` is absent from bulk).

### FEC

`download/fec_contributions.R` reads `cn.txt` + `ccl.txt` to find authorized committees for Iowa House/Senate candidates (`CAND_OFFICE_ST == "IA"`, `CAND_OFFICE %in% c("H","S")`), streams `indiv*.zip` via `unz()` + `read_delim_chunked()`, and writes `indiv_iowa_cands.txt`, `cm.txt`, `cn.txt`, `ccl.txt` per cycle (2020–2026). Header names are cached in `source/federal/headers/`. `02a` stacks cycles, splits `NAME`, maps `ENTITY_TP` → `donor_type`, builds `fec_donor_key`, and joins cm + cn + ccl into `fec_committees`.

## Storage

**Parquet + DuckDB** (not `.rds`) because of volume. Templates connect via `duckdb` + `dbplyr` and filter to one committee or donor before collecting.

## Key columns

**contributions.parquet**
- `committee_code` — recipient (joins to `committees.parquet`, whose key it also is)
- `donor_key` — exact-match donor ID: `IND|LAST|FIRST|CITY|STATE`, `ORG|NAME|CITY|STATE`, or `CMT|code`
- `donor_type` — `individual` / `organization` / `committee` (`unknown` when unnamed)
- `donor_attribution` — `itemized` / `unitemized` / `unidentified`
- `transaction_class` — `contribution` / `in_kind` / `loan`
- `norm_*` — uppercase stripped fields for matching. `clean_city` is title case; `norm_city` / `norm_state` are UPPERCASE, so normalize both sides of any join.

**fec_contributions.parquet:** `CMTE_ID` (joins to `fec_committees`), `fec_donor_key` (same format, same `make_donor_key()`), `donor_type`, `cycle`, `norm_*`, plus `EMPLOYER` / `OCCUPATION`. **fec_committees.parquet:** key `CMTE_ID`, with `party`, `office`, `candidate_name`.

### Donor attribution (2026-07-25)

| `donor_attribution` | What it is | Rows | Amount |
|---|---|---|---|
| `itemized` | a real named donor | 3,154,190 | $939.2M |
| `unitemized` | lump sum below the itemization threshold, under a placeholder name | 14,875 | $26.5M |
| `unidentified` | no donor name, organization, or committee | 31,722 | $13.5M |

Both non-itemized kinds are real money and stay in committee totals; neither is a donor, so both are excluded from donor-facing views. `classify_donor_attribution()` matches `UNITEMIZED_TOKENS` as a **substring** against `norm_org` / `norm_first` / `norm_last`, because the normalizers delete punctuation without a space (`Cash-Unitemized` → `CASHUNITEMIZED`). Only add tokens that can't appear inside a real name. Session log: [`notes/2026-07-25_campaign-finance-202607-refresh.md`](../../notes/2026-07-25_campaign-finance-202607-refresh.md).

### Transaction class (2026-07-27)

| Type | `transaction_class` | Meaning | Amount | Share |
|---|---|---|---|---|
| `CON` | `contribution` | cash | $819.7M | 83.7% |
| `INK` | `in_kind` | goods/services | $144.8M | 14.8% |
| `LOANREC` | `loan` | loan received (repayable, not income) | $14.6M | 1.5% |

Summing all three used to overstate receipts by ~16% and turn lenders into donors. `classify_transaction_class()` **errors on any value not in `IECDB_TRANSACTION_CLASSES`, including `NA`**: a new code is a new kind of money, so classify it deliberately.

Every state view carries `total_contributions`, `total_in_kind`, `total_loans`, and `total_donated` (contributions + in-kind), and **no bare `total`**. Donor rankings, geography and over-time charts use `total_donated`; `avg_contribution` averages cash rows only; lenders are never counted as donors but are **not filtered out** of donor views (a candidate-loan-financed committee should still show it). Check: Lahn for Governor reads cash $1,197,133 · in-kind $21,569 · loans $2,500,000. `fec_*` views have no such split. Older notes and code may use the pre-split names: `committee_summary.total_raised`, `donor_summary.total_given`, and `.total` on `committee_donor` / `committee_year` / `donor_committee` / `donor_year`.

### Reporting periods

News coverage always quotes one period. 2026 statewide periods: Jan 1 – May 14; May 15 – Tuesday before the primary (May 26); Wed. before primary – July 14. Matching the period reproduces reported figures exactly (Sand Jan 1 – May 14 cash $9,667,859 vs reported $9.68M; Lahn May 15–26 cash $60,049.96, matching the DR2 Schedule A to the cent). **A mismatch is almost always a period or transaction-class difference, not a data error.**

### Summary rows — known, deliberately deferred

Legacy rows where a report line label landed in the contributor name (`Contributions Total`, `Inkind Contributions Total`, `Total Summary`, ~22 spelling variants) are **not flagged** and rank as donors (`Contributions Total` #3 at $25.4M). Scope: 5,807 rows (0.18%), 743 committees (650 over $10k), $49.2M (5.0%), almost all 2003–2012. **Needs manual classification, not a regex:** a leading "Total" also matches real businesses (`Total Maintenance Inc`), and the rows can't be uniformly kept or dropped (603 committee-years have only the summary row). **Must be settled before the first mass render of committee pages**, where the bookkeeping row shows as a committee's top donor (Iowans for Nussle).

## DuckDB summary views

| View | Grain | Scope |
|---|---|---|
| `committee_summary` | committee | all rows (totals); itemized-only donor count |
| `committee_donor` | committee × donor | itemized only |
| `committee_year` | committee × year × donor_type | all rows; itemized-only donor count |
| `donor_summary` | donor_key | itemized only |
| `donor_committee` | donor × committee | itemized only |
| `donor_year` | donor × year × party | itemized only |

`n_unique_donors` counts itemized, non-loan keys only. FEC equivalents (`fec_committee_summary`, `fec_committee_donor`, `fec_committee_year`, `fec_donor_summary`, `fec_donor_committee`, `fec_donor_year`) are built only if `fec_*.parquet` exist.

## Templates (`site/campaign_finance/templates/`)

All query DuckDB via `duckdb` + `dbplyr`.

- `recipient_template.qmd` — param `committee_code` (coerced with `as.character()`); static R/gt
- `donor_template.qmd` — param `donor_key`; static R/gt
- `fec_recipient_template.qmd` — param `CMTE_ID`; adds Employers & Occupations tabs. **Its default `C00401224` is ActBlue, not Grassley**, and has no rows, so the default render is all empty states. Use `C00546788` (Joni for Iowa) or `C00708164` (Theresa Greenfield).
- `recipient_template_ojs.qmd` — experimental OJS version with a reactive year filter. **Stale since the 2026-07-27 split and will error:** its Arquero/Plot code reads `d.total` off `by_year` and `iowa_cities_agg` sums a `total` column that no longer exists. Fix or drop before use. Notes: [`notes/2026-05-09_campaign-finance-templates-ojs.md`](../../notes/2026-05-09_campaign-finance-templates-ojs.md).

Last verified 2026-07-27 against `SWGA51409` (Lahn for Governor) and `IND|LAHN|ZACH|BELLE PLAINE|IA`.

**Layout pattern:** summary section above a `.panel-tabset`; count columns use `fmt_integer()`. These templates still use gt deliberately (the legislature moved off it). There is no domain UI layer; templates source `R/ui_helpers.R` directly.

**Theming / project renders.** `site/_quarto.yml` excludes `campaign_finance/**` from project renders (since 2026-10-12) because CI has no `campaign_finance.duckdb`. Excluding a directory makes Quarto treat its files as standalone documents, so they render **without** `custom.scss`. The 2026-07-25 change that themed them ([`notes/2026-07-25_cf-redesign-phase1.md`](../../notes/2026-07-25_cf-redesign-phase1.md)) was including the directory; re-including it needs CI to build or skip the database first. The OJS variant should stay excluded either way (~13 MB output).

> **Rendering constraint:** give each parameterized render a **distinct `output_file`**. Quarto derives the figure directory from the output name, so two renders sharing a name share `<name>_files/` and overwrite each other's charts. `--output` is a no-op inside a Quarto project.

> **dbplyr is pinned to 2.5.0.** 2.6.0 needs `dplyr::filter_out()` (dplyr ≥ 1.2.0); the project pins dplyr 1.1.4 because the daily legislature pipeline depends on it and doesn't use dbplyr.

### OJS notes (`recipient_template_ojs.qmd`)

R passes data with `ojs_define()` (then `transpose()` to rows); shared `Inputs.range()` sliders above the tabset filter every tab.

| Import pattern | Status |
|---|---|
| `import { A, B } from "@uwdata/arquero"` | ✅ use for Arquero |
| `X = require("pkg@version")` | ✅ use for CJS libraries (Leaflet) |
| `import { A } from "npm:pkg"` | ✅ works for some packages |
| `import X from "npm:pkg"` | ⚠️ unreliable for default exports |
| `import * as X from "..."` | ❌ syntax error |

Arquero rollups: closures are fine for `op.sum(d.x)`, but `op.first('col')` / `op.array_agg('col')` need string column names; count uniques with `.derive({ n: aq.escape(d => new Set(d.arr).size) })`. Leaflet in a hidden tab: use a `ResizeObserver` to call `map.invalidateSize()` + `fitBounds()` on first real resize. AG Grid doesn't load in OJS; use `Inputs.search()` + `Inputs.table()`.

## Key packages

`vroom`, `readr`, `dplyr`, `stringr`, `lubridate`, `janitor`, `tidyr`, `arrow`, `duckdb`, `DBI`, `dbplyr` (2.5.0), `ggplot2`, `gt`, `scales`, `here`, `httr2`, `purrr`, `sf`, `tigris`, `jsonlite` (`pdftools` for DR2 parsing is not in `renv.lock` yet)
