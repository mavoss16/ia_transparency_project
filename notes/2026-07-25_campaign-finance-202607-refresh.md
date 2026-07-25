# Campaign Finance — 202607 IECDB Refresh

**Date:** 2026-07-25

Integrated a new IECDB export (July 2026) into the campaign finance pipeline. The
export arrived in a reorganized source layout with renamed columns and changed
date formats, so most of the work was making the pipeline vintage-agnostic
rather than a straight re-run.

---

## What changed in the source data

The user reorganized raw exports into one directory per download:

```
data/campaign_finance/source/IECDB/
├── 202603/   ← previous export (was previously loose in source/)
└── 202607/   ← new export
```

The new export differs from `202603` in three ways:

**1. Contributions split across four part files.** `iowa_campaign_contributions_received_917_rows_part_0001.csv` … `_0004.csv`.
Verified before ingesting:

| Part | Rows | Date range |
|---|---|---|
| 0001 | 912,874 | 1930-10-01 → 2013-12-31 |
| 0002 | 692,426 | 2013-12-31 → 2018-09-16 |
| 0003 | 665,798 | 2018-09-16 → 2022-03-28 |
| 0004 | 929,708 | 2022-03-28 → 2026-07-14 |

Parts are chronological and each carries its own header. Boundary dates are
shared between adjacent parts (the split lands mid-day), so overlap was checked
explicitly with a DuckDB `INTERSECT` on each boundary date — **0 overlapping rows
at all three boundaries**. Safe to stack.

The `917_rows` in the filename is an export-tool artifact, not a row count.

**2. Every column renamed** from human-readable to machine names:

| Old (after `clean_names()`) | New |
|---|---|
| `date` | `contribution_received_date` |
| `committee_code` | `committee_cd` |
| `committee_name` | `committee_nm` |
| `contributing_committee_code` | `contr_committee_cd` |
| `contributing_organization` | `organization_nm` |
| `first_name` / `last_name` | `first_nm` / `last_nm` |
| `contribution_amount` | `amount` |

Expenditures the same, plus `date`→`calendar_date`, `state`→`state_cd`,
`zip`→`zip_code`, `receiving_*`→`rec_committee_cd` / `organization_nm`. The
registered-committees file is snake_case throughout but otherwise unchanged.
All fields survived the rename — nothing was dropped or added.

**3. Date formats changed** from `MM/DD/YYYY` to ISO `YYYY-MM-DD`, and election
dates from `2022 Nov 08 12:00:00 AM` to `2026-11-03 00:00:00`. The old
`mdy()` and `parse_date_time(..., orders = "Ybd")` calls would have silently
produced all-`NA` dates rather than erroring — the most dangerous part of this
export.

**4. ~19 malformed rows** at the head of part 1 (oldest records): blank or
field-shifted lines with no date, committee, or amount. Dropped explicitly in
`02` rather than allowed to become `"unknown"` donors.

---

## Code changes

**`R/campaign_finance/utils.R`**
- `iecdb_root()` / `latest_iecdb_export()` — resolve the newest `YYYYMM` export directory
- `find_source_files(pattern)` — case-insensitive match within that export, returns all matches name-sorted (so parts stack in order); `find_source_file()` kept as the single-file form, now erroring if the pattern is ambiguous
- `IECDB_CONTRIBUTION_COLS` / `IECDB_EXPENDITURE_COLS` / `IECDB_REGISTERED_COLS` + `rename_if_present()` — map either vintage onto the canonical older names. Mappings whose source column is absent are skipped, so both vintages read cleanly through the same code path.
- `parse_iecdb_date()` / `parse_iecdb_election_date()` — detect ISO vs legacy per element

The old `find_source_file()` would have failed three ways on this export: it
searched `source/` non-recursively (files are now a level deeper), matched
case-sensitively (`"Contributions_Received"` vs lowercase filenames), and
returned a single file via `which.max(file.mtime())` (would have silently
ingested 1 of 4 parts).

**`R/campaign_finance/02_clean_normalize.R`** — reads via the new helpers,
applies the rename maps after `clean_names()`, uses the tolerant date parsers,
and drops the fully-empty rows. Logic downstream of the parse is unchanged.

**`site/campaign_finance/templates/recipient_template.qmd`** — coerces
`params$committee_code` with `as.character()` once, and all six queries use the
coerced value. See "committee code types" below.

**`R/campaign_finance/download/fec_contributions.R`** — fixed a startup crash
unrelated to this refresh: line 241 referenced an undefined `FILTER_STATE`, a
leftover from when the script filtered by donor state instead of by Iowa
candidate committee. The script died before downloading anything, so any FEC
refresh was blocked. Replaced with the actual filter description.

---

## Verification

Ran `02` → `04`, then compared against the pre-refresh database:

| | Before (202603) | After (202607) | Δ |
|---|---|---|---|
| Contributions | 3,074,875 | 3,200,787 | +125,912 |
| — individual | 2,769,065 | 2,890,559 | +121,494 |
| — committee | 178,053 | 179,996 | +1,943 |
| — organization | 97,544 | 98,510 | +966 |
| — unknown | 30,213 | 31,722 | +1,509 |
| Expenditures | 635,619 | 652,661 | +17,042 |
| Committees | 7,970 | 8,020 | +50 |
| Latest contribution | 2026-01-26 | 2026-07-14 | +5.5 months |

Every category grew proportionally (~1% for unknowns, unchanged as a share),
which is the check that mattered — a column-mapping error would have shown up as
a spike in `unknown` donors or a collapse in one type. **Zero null dates** in the
final table, confirming the ISO parser caught every row.

Party coverage held at 71%. Total contributions in the database: $979,175,622.

Template render verified end-to-end against committee 5185 (Rob Sand for Iowa):
page figures ($32,628,827 raised / 223,225 transactions / 90,856 unique donors /
latest May 26, 2026) match `committee_summary` exactly. `donor_template.qmd`
also renders clean.

---

## Two blockers hit along the way

**dbplyr 2.6.0 vs dplyr 1.1.4.** Every campaign finance template failed at
`library(dbplyr)` with `object 'filter_out' is not exported by 'namespace:dplyr'`.
dbplyr 2.6.0 needs `dplyr::filter_out()`, added in dplyr 1.2.0; the project pins
dplyr 1.1.4. **Both versions were pinned in `renv.lock`**, so this was a baked-in
incompatibility, not local drift — it would have broken any CF render since
whenever dbplyr was bumped (the last successful render was 2026-05-10).

Resolved by downgrading dbplyr to 2.5.0 rather than upgrading dplyr: the
legislature pipeline runs daily in CI and depends on dplyr, but doesn't use
dbplyr at all, so the downgrade has a much smaller blast radius. `renv.lock`
snapshotted. Note the snapshot also tried to bump the recorded R version
4.5.1 → 4.5.3 (an artifact of the local R install); that line was reverted by
hand so the lockfile diff is dbplyr-only. CI pins R 4.4 regardless.

**Committee code types.** Rendering with `-P committee_code:5185` failed with
`Could not convert string 'CTY51640' to INT32`. Quarto YAML-parses a bare
numeric parameter as a number, so dbplyr emitted `WHERE committee_code = 5185`,
and DuckDB cast the entire varchar column to INT32 — failing on the alphanumeric
codes. Codes are genuinely mixed: 5,629 numeric and 1,412 alphanumeric
(`CTY51589`, `SWGA51409`), with **no leading zeros** anywhere (checked, because
YAML would eat them). This is not new to the 202607 export — the 202603 file had
alphanumeric codes too. The May render simply used the quoted default parameter
and never hit it.

Fixed in the template with a single `as.character()` coercion. This matters for
the future `render.R`, which will loop over codes programmatically.

---

---

## Follow-up same day: donor attribution

Scoped deliberately to the two unambiguous cases (unitemized and unidentified);
the legacy summary rows were left for a separate decision.

**The problem.** A largest-donors ranking built on `donor_summary` led with
`Contributions Total` at #3 ($25.4M), `(Unknown)` at #4 ($13.5M), and
`Unitemized Unitemized` at #5 ($12.3M). IECDB files report-level bookkeeping as
ordinary transaction rows, and nothing in the pipeline distinguished them from
gifts by a named donor.

**The change.** `classify_donor_attribution()` in `utils.R` adds a
`donor_attribution` column in `02`:

| Value | Rows | Amount |
|---|---|---|
| `itemized` | 3,154,190 | $939.2M |
| `unitemized` | 14,875 | $26.5M |
| `unidentified` | 31,722 | $13.5M |

`unidentified` needs no string matching — it's exactly `donor_type == "unknown"`,
which `02` already computed. `unitemized` matches the token `UNITEMIZED` against
`norm_org` / `norm_first` / `norm_last`.

**One subtlety worth remembering:** the match is a *substring*, not a word
boundary. The first version used `\bUNITEMIZED\b` and left 9 donor keys behind —
`Cash-Unitemized`, `Pass The Hat/Unitemized`, `Unitemized,Unitemized U`. The
normalizers strip punctuation *without* inserting a space, so those collapse to
`CASHUNITEMIZED` / `UNITEMIZEDUNITEMIZED U` with no boundary to anchor to. Only
$5,337 in total, but they'd still have appeared as named donors, which is the
entire point of the exercise.

**Where it's applied in `04`.** Donor identity is filtered; money is not.
`committee_donor`, `donor_summary`, `donor_committee` and `donor_year` are
itemized-only. `committee_summary` and `committee_year` keep every row in their
totals but count only itemized keys in `n_unique_donors`.

**Verified.** Total contributions unchanged at $979,175,623 (all-rows sum ==
`committee_summary` sum), zero bookkeeping rows left in any donor view, and
Rob Sand's page still shows $32,628,827 raised with unique donors falling by
exactly one (90,856 → 90,855). Both templates re-render clean. Classifier has
15 unit cases including two false-positive guards (a real org named
"Total Sports Inc", a person named "Item Ized").

**Deliberately left undone — the summary rows.** Investigated in detail after
the attribution work landed, then deferred by decision. Section below.

---

## Summary rows: investigated and scoped, not fixed

Follow-up to the above, same day. The question was "what exactly *are*
`Contributions Total` and `Total Summary`, and how big a problem is this?" The
answer is that they're well understood now, bounded, and safe to leave alone
until committee pages get mass-rendered.

### What they are

Rows with **no contributor at all**. A line label off a filed disclosure report
ended up in the contributor name field. The raw record:

```
contribution_received_date  2005-12-31
committee_nm                Iowans for Nussle
organization_nm             Contributions Total
address_line_1              N/A
city                        N/A
zip_code                    00000
amount                      2390585.72
check_number                (null)
contr_committee_cd          (null)
```

`Total Summary` is the same thing keyed into the personal-name fields instead —
`first_nm = "total"`, `last_nm = "Summary"`, with `00000` in address and city.
Placeholder address, no check number, no contributing committee: the signature
of a form line, not a gift.

### Scope

| | |
|---|---|
| Transactions | 5,807 (**0.18%** of all rows) |
| Committees | 743 — **650** clear $10k, **268** still active 2024+ |
| Dollars | $49.2M (**5.0%** of all money) |
| Era | 2003–2012; only 2 transactions after 2012 |

Three distinct labels — `Contributions Total` ($25.4M / 630 committees /
2003–2012), `Total Summary` ($15.5M / 196 / 2003–**2018**), `Inkind
Contributions Total` ($4.1M / 291 / 2003–2007) — plus ~22 spelling variants
(`Total_a`, `Total, Contributions`, `Total Schedule A`, `Totals Contribution`).

**These supersede the first-pass figures** (644 committees, 4,301 rows, ~$29.5M,
ending 2012), which counted `Contributions Total` alone and missed both the
sibling labels and the variants. The full family is 743 committees and $49.2M,
and `Total Summary` runs six years later than that first pass suggested.

### Why it can't be automated

**Real businesses are named "Total."** Scanning for labels starting with Total
pulls in `Total Maintenance Inc`, `Total Tax Service`, and `Total Detailing` —
genuine Iowa donors. Only ~$315 between them, so the dollar risk is nil, but it
kills the token approach: "Unitemized" is a term of art that never appears in a
real name, "Total" is an ordinary English word.

**The double-count question has no consistent answer.** Tested period-by-period
on Iowans for Nussle against the itemized rows in each filing window:

| Period end | Summary row | Itemized in window |
|---|---|---|
| 2006-05-14 | $1,181,239 | $1,195,094 |
| 2006-05-30 | $51,696 | $54,946 |
| 2006-07-14 | $370,224 | $456,368 |
| 2006-10-14 | $1,441,757 | $2,962,921 |
| 2006-10-31 | $488,987 | $1,165,366 |

May matches almost exactly (reads like a true period total); October is off by
2×. Across all affected committee-years: **603** have a summary row and no
itemized detail at all (the summary is the only surviving record of that money),
**465** have a larger summary, **429** have larger itemized. Deleting loses
history, keeping inflates totals, and no rule separates the cases.

### Why deferring is safe, and what ends that

Nothing is published, so nothing is currently wrong on any live page. Every
affected row sits in 2003–2012, so modern committees are unaffected in their
recent activity even when they're among the 268 still active.

**The trigger is the first mass render of committee pages, not the donor index.**
On an affected committee's own page the bookkeeping row ranks as its top donor:

| Iowans for Nussle — top donors today | |
|---|---|
| Contributions Total | $6,048,402 |
| Rga - Iowa Pac | $1,400,000 |
| Inkind Contributions Total | $394,680 |

650 committees would show this. The label list is short and finite and the real
businesses are obvious on sight, so manual classification would settle it
permanently — but it should happen before those pages exist, not after.

---

## Not done

- **`01_build_committee_lookup.R` was not re-run.** It scrapes the IECDB web API
  across ~7,900 committees; `committee_lookup.rds` is still from 2026-04-19, so
  committees registered since then have no API-sourced party. Party coverage is
  unchanged at 71%, and 02 degrades gracefully, but a re-run would improve
  attribution for 2026 committees. Deliberately left for a moment when hammering
  a state server for several thousand requests is intentional.
- **FEC data not refreshed** — still the 2026-05-10 download. The `FILTER_STATE`
  crash is now fixed, but note that every download step skips files that already
  exist, so refreshing the mid-stream 2026 cycle requires clearing
  `source/federal/2026/` first (keep `headers/`).
- **`03_link_donors.R`** still doesn't work. Confirmed nothing downstream
  references a crosswalk, so it stayed out of scope.
- **Summary rows still unflagged** — investigated and scoped above, deferred by
  decision. Deadline is the first mass render of committee pages.
- **Nothing published.** No `render.R`, no `index.qmd`, no `docs/campaign_finance/`,
  navbar entry still commented out.
