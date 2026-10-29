# Phase B — change-detection ingest, built and first live run

2026-08-01. Continues [`2026-07-25_iecdb-api-data-sources.md`](2026-07-25_iecdb-api-data-sources.md),
which holds the endpoint reconnaissance and the A–D plan.

Two pieces of work: the transaction-class split (pulled forward out of Phase D),
then Phase B itself. Everything below is **uncommitted** as of this writing.

---

## 1. Transaction-class split — done and verified

The pipeline was summing cash contributions, in-kind, and loans received into
one `total_raised`. Fixed end to end:

- `classify_transaction_class()` in `utils.R` maps `CON`/`INK`/`LOANREC` →
  `contribution`/`in_kind`/`loan`, and **errors** on anything else including
  `NA` — an unclassed row would drop out of every per-class sum silently.
- `02_clean_normalize.R` emits `transaction_class` and reports the breakdown.
- The six state views in `04` now carry `total_contributions`, `total_in_kind`,
  `total_loans`, `total_donated`, and **no bare `total`**. The ambiguous name is
  what let loans read as donations, so callers must name the money they mean.
- Both static templates updated; `recipient_template_ojs.qmd` deliberately left
  stale (see CLAUDE.md).

Verified against the entities the fix was for: Lahn for Governor now reads cash
$1,197,133 / in-kind $21,569 / loans $2,500,000, with Zach Lahn at **$0 cash**
and no longer the committee's top donor. Lahn May 15–26 cash = $60,049.96,
matching the filed DR2 Schedule A to the cent. View sums reconcile exactly to
the base table. Full detail in CLAUDE.md → *Transaction class*.

---

## 2. Phase B — `R/campaign_finance/01b_iecdb_ingest.R`

Plan and execute are separate functions so the request cost is visible before
it is spent; writes are incremental with an `on.exit()` save, so the sweep is
resumable. Design detail in CLAUDE.md → *Phase B ingest*.

### Bug found on the first live call: HTTP 400 from `iecdb_filings()`

`list()` has no names, and jsonlite cannot tell an empty object from an empty
array, so the body serialized to `[]` where the endpoint wanted `{}`.
`iecdb_statements()` never hit this because its body is non-empty. Fixed in
`iecdb_perform()` by naming the empty list; **non-empty bodies are untouched**,
so the `NULL → {}` serialization that the transactions endpoint has always
accepted is left exactly as it was.

The canary missed it because `iecdb_health_check()` exercises committee search
and transactions only — the filings endpoint had never been called through the
client at all. Worth adding if the canary is meant to gate the ingest.

### Bug found on the first parse: `reported_through` was the period's START

Real `periodDescription` values use the word "through", not a dash. The parser
split on a dash that wasn't there, then took the first month/day in the string
— so "January 1 through May 14" returned **January 1**. Wrong on **14,948 of
17,876 filings**, and wrong in the worst way: a plausible-looking date rather
than a visible failure.

Rewritten to split on the *last* separator and read only the tail, which also
makes "Oct. 15 through Dec. 31 or Wed. Preceding General through Dec. 31" land
on Dec 31. Now **91.6% of filings parse, 99.5% of committees** get a date from
their latest filing. Sand, Lahn and Henderson all resolve to 2026-07-14 —
independently matching the currency established during reconnaissance.

The unparsed remainder is almost entirely "… through Tuesday Preceding
Primary/General" (1,437 filings) — periods ending at an **election, not a
date**. `NA` is correct without an election calendar; the start date would be
a lie.

### The filings feed is state-only — a structural gap, not an age effect

17,876 filings but only **1,403 committees**, against 8,531 in
`committee_summary`. Every local committee type is at **0%** coverage
*regardless of recency* — County Candidate (all offices), City Candidate,
School Board, County Central Committee ($33.4M), Local Ballot Issue — as are
the `CTY`/`LOCL`/`BALLOT` code prefixes. State types run 47–100%.

Age is a real but **secondary** effect operating only inside the state slice:
the index thins sharply before 2014 (395 filings in 2014 vs 1,734 in 2016), so
long-dissolved state committees are missing too.

| | Committees | Money |
|---|---|---|
| In the feed | 1,583 | $778.8M (**80.7%**) |
| Not in the feed | 6,948 | $185.7M (19.3%) |

Uncovered committees are numerous but individually small — though 1,147 were
active in 2024+ holding $50.6M, and county central committees run $1–3M each.

### First transaction pull: 5 committees, clean

5/5 ok, 5,247 rows, `CON` 4,982 + `INK` 265 and **no `LOANREC`** — the known API
gap, reconfirmed. One new field, `primaryAddress2`, surfaced by the drift notice
working as designed (an *extra* field, not a missing one); added to
`IECDB_KNOWN_FIELDS`.

Note the sample is not representative: `limit = 5` takes plan order, which
happened to be five old, inactive committees (median `reported_through`
2018-12-31).

---

## 3. Reconciliation against bulk — started, NOT finished

Both sources now exist locally for those five committees, so this is free to
run. Findings so far:

**No duplication.** 5,247 rows, 5,247 distinct `transaction_id`, 5,247 distinct
full rows. (An apparent "multiples of 11" pattern in per-year counts was
coincidence from small samples — checked and dismissed.)

**The API has deeper history than the bulk export.** API rows go back to
**1996**; bulk starts **2003-01-01**. Committee `109` is absent from bulk
entirely — all of its activity predates 2002. That is ~7 extra years the bulk
feed never had, and it is the opposite of the problem we expected.

**Open, and the reason this stopped: committee `1046` returns FEWER API rows
than bulk for 2007 (19 vs 81) and 2008 (23 vs 138)** — roughly 177 transactions
the API did not return. Every other year for that committee, and every other
committee, has API ≥ bulk. This is unexplained and is a **cutover blocker**:
until it is understood, the API cannot be assumed complete for historical data.

Candidate explanations, none tested:
- an amended filing that superseded the originals, with the API serving only
  the current version while bulk retains both
- transactions the API excludes by type or attribution
- a genuine gap in the API's historical backfill

The investigation script was written but not run:
`gap1046.R` compares the two sources on `(date, amount)` for that window, checks
whether the bulk-only rows cluster on particular dates, and breaks the
difference down by `transaction_type` and `donor_attribution`. Re-create or
re-run it as the next step.

**Also unverified:** whether one `iecdb_transactions()` call per committee
really returns everything. Reconnaissance saw no paging on a 257k-row committee,
but that was one committee, and the 1046 shortfall is exactly what truncation
would look like.

---

## 4. `countyReports` — endpoint exists, shape unconfirmed

`iecdb_post("/api/publicreports/countyReports", list())` returned a **4-element
list**. The probe snippet asked for `names(r[[1]])`, which came back `NULL` —
the snippet was wrong, not the response: it assumed a bare array, but 4 elements
matches the documented envelope `{totalCount, filteredCount, echo, results}`
used by the other publicreports endpoints.

Re-probe with:

```r
r <- iecdb_post("/api/publicreports/countyReports", list())
names(r)
r$totalCount
length(r$results)
names(r$results[[1]])
```

If it mirrors the state feed, county coverage is one client wrapper away and
drops into the same manifest and loop.

---

## Next steps, in order

1. **Commit.** The transaction-class split and Phase B are both uncommitted.
2. **Resolve the `1046` shortfall** — cutover blocker. Start with the
   `(date, amount)` diff described above.
3. **Confirm the `countyReports` shape**; if it matches, add the wrapper and a
   second change feed.
4. **Widen the sweep** (`iecdb_run_refresh(plan)`, ~1,429 requests, ~24 min)
   once 2 is understood — and re-reconcile on a *representative* sample,
   including a large active committee, not just old ones.
5. Phase C proper: side-by-side on the overlapping period, scoped to the state
   slice until the county feed exists.
6. Still open from before: DR2 Schedule F1 parsing (loans + cash on hand), the
   summary-rows classification, and `R/campaign_finance/render.R`.
