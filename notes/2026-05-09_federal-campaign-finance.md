# Federal Campaign Finance Data Plan

*2026-05-09*

Plan for integrating FEC federal campaign finance data to complement the Iowa state data. In an ideal world, donor pages show both federal and state contributions; donor matching between the two datasets is acknowledged as genuinely difficult.

## Data Source: FEC Bulk Downloads

The FEC publishes free bulk data at `fec.gov/data/browse-data/?tab=bulk-data`, organized by 2-year election cycle (folder = even year). No API key needed.

Files needed per cycle:

| File | Contents | Size |
|---|---|---|
| `indiv{YY}.zip` | All individual contributions — filter to `STATE = "IA"` | ~3–4 GB compressed |
| `cm{YY}.zip` | Committee master (names, party, type) | Small |
| `cn{YY}.zip` | Candidate master | Small |
| `ccl{YY}.zip` | Candidate–committee linkage | Small |

Start with cycles 2020, 2022, 2024. The national individual contributions file is ~3–4 GB compressed / ~12–15 GB unzipped; filtering to Iowa donors yields ~1–2% of national volume. The script reads directly from the zip using an `unz()` connection to avoid extracting the full file to disk.

Column names are not included in the FEC data files — they come from separate header CSV files (`data_dictionaries/*_header_file.csv`) fetched once and cached locally.

## Pipeline Scripts

```
R/campaign_finance/download/fec_contributions.R
    downloads indiv/cm/cn/ccl bulk zips per cycle
    streams indiv zip through readr::read_delim_chunked(), filters STATE == "IA"
    saves filtered output; deletes zips
    → data/campaign_finance/source/federal/{cycle}/indiv_IA.txt
    → data/campaign_finance/source/federal/{cycle}/cm.txt
    → data/campaign_finance/source/federal/{cycle}/cn.txt
    → data/campaign_finance/source/federal/{cycle}/ccl.txt

R/campaign_finance/02a_clean_normalize_federal.R   (not yet built)
    parses NAME field ("LAST, FIRST") → split fields
    creates fec_donor_key analogous to state donor_key: IND|LAST|FIRST|CITY|STATE
    joins cm + cn + ccl → unified fec_committees
    adds norm_* columns for potential fuzzy matching
    → data/campaign_finance/processed/fec_contributions.parquet
    → data/campaign_finance/processed/fec_committees.parquet
```

## Schema Notes

FEC individual contributions key fields:

| FEC field | Notes |
|---|---|
| `NAME` | "LAST, FIRST" format (needs parsing; orgs may have no comma) |
| `CITY`, `STATE`, `ZIP_CODE` | direct equivalents in state data |
| `EMPLOYER`, `OCCUPATION` | not present in state data; useful for disambiguation |
| `CMTE_ID` | joins to committee master for name, party, candidate |
| `TRANSACTION_AMT` | contribution amount |
| `TRANSACTION_PCD` | date as MMDDYYYY |
| `ENTITY_TP` | `IND` / `ORG` / `COM` etc. → maps to `donor_type` |
| `TRAN_ID` | transaction identifier |

A `fec_donor_key` column should mirror the state `donor_key` format (`IND|LAST|FIRST|CITY|STATE`) for potential exact matching downstream.

## DuckDB Integration

Extend `04_build_database.R` to add:
- `fec_contributions`, `fec_committees` tables
- Parallel summary views: `fec_committee_summary`, `fec_donor_summary`, `fec_donor_committee`, `fec_donor_year`

These mirror the state views so Quarto templates can query both with the same pattern.

## Donor Matching (Deferred, Hard)

No shared key exists between the state and federal datasets — only name + geography. Recommended phased approach:

1. **Exact key match** — construct `fec_donor_key` in the same `IND|LAST|FIRST|CITY|STATE` format and join directly. Zero false positives; captures donors with consistent name/city registration.

2. **Fuzzy match** — using `reclin2` (already planned for state-only step 03), compare name + city across datasets with Jaro-Winkler. `EMPLOYER`/`OCCUPATION` can break ties on common names.

3. **Output**: `donor_crosswalk_federal.parquet` — each row is a proposed state `donor_key` ↔ FEC donor pair with a confidence score.

Known failure modes:
- Common Iowa names (Smith, Miller, Johnson) generate many candidate pairs with similar scores
- Address/city changes over time reduce exact-match rate
- Organizations are easier (names are more distinctive)
- No SSN or EIN linking available

**Site display**: show federal contributions in a clearly labeled separate section — "Federal contributions (probable match)" — with a note about matching uncertainty. Don't silently merge the two datasets.

## Suggested Sequencing

1. Build `fec_contributions.R` download script (straightforward, no matching needed)
2. Build `02a_clean_normalize_federal.R`, get FEC data into DuckDB as standalone tables
3. Build state-only step 03 donor deduplication — the `reclin2` infrastructure carries over
4. Cross-dataset matching as a separate step once both dedup pipelines exist
