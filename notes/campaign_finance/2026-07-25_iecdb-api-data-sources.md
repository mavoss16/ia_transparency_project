# IECDB as a Data Source — API Reconnaissance

**Date:** 2026-07-25

Triggered by an [Iowa Capital Dispatch article](https://iowacapitaldispatch.com/briefs/sand-breaks-iowa-fundraising-record-lahn-receives-large-party-pac-donations/)
(July 20, 2026) reporting figures our rendered pages couldn't reproduce. Root
cause turned out to be source freshness, not a pipeline bug — which raised the
question of whether IECDB should replace data.iowa.gov as the primary source.

**Conclusion: yes.** IECDB's portal is backed by a JSON API that is current,
returns full result sets in one call, and exposes fields the bulk export drops.

---

## The freshness gap, measured

Our data comes from [data.iowa.gov dataset 917](https://data.iowa.gov/catalog/dataset/917),
exported 2026-07-25. IECDB queried live the same day:

| | data.iowa.gov (our export) | IECDB API |
|---|---|---|
| Sand contributions | 223,225 | **256,786** |
| Sand latest transaction | 2026-05-26 | **2026-07-14** |
| Lahn contributions | 733 | **1,175** |
| Lahn latest transaction | 2026-05-26 | **2026-07-14** |

Sand's DR2 for the May 15–July 14 period was filed **2026-07-20 17:06** — five
days before our export was pulled — and still wasn't in it. Note 306 other
committees *did* have post-May-26 data in our export, so the bulk feed is not
uniformly cut off; freshness varies by committee. Treat data.iowa.gov as
"eventually consistent," never as an as-of date.

### The IECDB numbers reproduce the article exactly

| Article | IECDB API |
|---|---|
| Sand "more than $9.38 million", "more than 33,500 donations" | $9,394,697 across 33,561 transactions |
| Sand "$2.5 million from the Democratic Governor's Association" | Democratic Governors Association, $2,500,000, 2026-07-13 |
| Lahn "more than $6.3 million" | $6,392,942 across 444 transactions |
| Lahn "six large donations from RGA Right Direction PAC… $5 million" | RGA Right Direction PAC, $1,000,000 each on 6/12, 6/26, 7/10, … |

---

## API contracts

Undocumented internal API behind the React portal at `webapp.iecdb.iowa.gov`.
All discovered by hooking `fetch`/`XMLHttpRequest` and reading the JS bundle.

### Committee lookup

```
POST /api/search/committee
{"criteria": "Rob Sand for Iowa", "filerTypeIds": []}
→ [{ id: "<guid>", name, type, committeeTypeCd, politicalParty, county, filerTypeName }]
```

The field is `criteria` — any other key is silently ignored and returns an
unfiltered list of 20, which looks like a working query but isn't. `id` is a
GUID, **not** the `committee_code` we key on — but the crosswalk already exists,
see "Is the GUID vs committee_code split a problem?" below.

### Transactions

```
POST /api/search/table
{"primaryCommitteeId": "<guid>", "secondaryCommitteeId": null,
 "transactionType": "CON", "primaryCommittee": null,
 "dateFrom": null, "dateTo": null,
 "transactionOption": 1, "secondaryCommittee": null}
→ { results: [ … ] }
```

Returns the **entire** result set in one response — 256,786 rows for Sand, no
paging needed. Row fields:

`transactionId, date, primaryCommitteeCode, primaryName, primaryAddress1,
primaryCity, primaryState, primaryZip, secondaryCommitteeCode, secondaryName,
secondaryAddress1, secondaryAddress2, secondaryCity, secondaryState,
secondaryZip, transactionType, amount, checkNumber, referenceId, referenceType,
referenceDR2Id`

Two fields matter that the bulk export doesn't give us:

- **`transactionType`** — the bulk CSV has this too, but here it's first-class;
  it's what separates `CON` from `INK` (in-kind) and `LOANREC` (loans). Our
  current pipeline sums all three into "total raised", which is why Lahn's page
  showed a $2.5M candidate loan as his largest *donation*.
- ~~**`referenceDR2Id`** — links each transaction to the DR2 filing that
  reported it, giving reporting-period attribution.~~ **Wrong — corrected while
  building the client.** The field is the all-zeros GUID
  `00000000-0000-0000-0000-000000000000` on every one of Lahn's 1,175 rows,
  with `referenceType` empty alongside it. It appears reserved for
  earmarked/referred transactions and is unpopulated for ordinary ones. Period
  attribution still has to be **inferred** from `date` against the period
  boundaries in the filings index. The client normalizes the placeholder GUID
  to `NA` so it can't be mistaken for a usable key.

`transactionOption: 1` appears to mean "to a committee" (the UI's Transaction
Option selector); other values not yet explored. `transactionType: "EXP"` and
the `secondary*` fields cover expenditures.

### Filings index (this is where cash on hand lives)

```
POST /api/publicreports/state {}
→ { totalCount: 17873, results: [ … ] }
```

Every state DR2 filing, **1999–2026**, in one response. 9,921 Candidate,
7,853 PAC, 93 Party. Row fields: `id, periodDescription, periodYear, reportType,
organizationType, committeeCode, committeeName, candidateName, filedOn,
fileName, fileUrl`.

`fileUrl` is a direct, unauthenticated PDF link, e.g.
`https://iecdbblobstorage.blob.core.windows.net/reports-prod/5185_DR2_Summary_07-20-2026T18.01.46.916.pdf`.
The timestamp in the filename is not derivable — the index is the only way to
resolve it.

Latest `filedOn` in the index was 2026-07-24, i.e. current.

**Cash on hand is not in any transaction feed.** It's a report-level figure on
the DR2 summary (beginning balance + receipts − disbursements = ending balance)
and reaching it means parsing these PDFs. It cannot be derived from our data:
no beginning balance before our window opens, in-kind never touches cash, loans
add cash but are repayable, and there are other receipts/disbursements we don't
capture. Sand's contributions minus expenditures in our data is $18,137,142,
temptingly near the reported $17.95M — pure coincidence, since ours stops May 26
and the reported figure is as of July 14 after another $9.39M raised.

### Other endpoints seen in the bundle

`countyReports`, `statements` (organization/dissolution), `vsr` (verified
statements of registration — out-of-state committee contributions), `otc`
(one-time contributions), `ie` (independent expenditures), `escheat`,
`buildingFund`, `gb` (gifts/bequests), `pfd` (personal financial disclosures),
`filteredLateReports`, plus `filingPeriods?year=&startYear=&isState=`.

`api/search/export-contributions` and `export-expenditures` exist but returned
405 to a POST; the Export button's exact contract wasn't pinned down. Not
important — `/api/search/table` already returns everything as JSON.

---

## Recommendation

Move to IECDB as the primary source for the legislature-adjacent campaign
finance work, keeping data.iowa.gov as a fallback/cross-check.

What it buys us, in priority order:

1. **Current data.** The gap that started this investigation disappears.
2. **A real "reported through" date per committee**, from the filings index —
   so pages can state their own currency instead of implying completeness.
3. **Clean separation of contributions, in-kind, and loans** via
   `transactionType`, fixing the loan-as-donation misrepresentation.
4. **Reporting-period attribution** via `referenceDR2Id`, which is the unit
   journalists and campaigns actually talk in.
5. **A path to cash on hand**, via the DR2 PDFs.

---

## Follow-up answers (same day)

### Is there a terms of service?

- `webapp.iecdb.iowa.gov/robots.txt` is **fully permissive**: `User-agent: *` / `Disallow:` with no path — nothing is disallowed.
- The Iowa.gov policies page has **no clause** on automated access, scraping, bulk download, or rate limits. It notes information under **Iowa Code Chapter 22** (open records) may be posted for electronic access.
- So: no prohibition found, but no affirmative permission either. Absence of a rule is not a licence to be rude — throttle anyway, identify the client in a `User-Agent`, and cache hard.
- **We are already a consumer of this API.** `01_build_committee_lookup.R` has been calling `POST /api/publicreports/statements` and `POST /api/search/committee` since April. Moving transaction ingest here extends an existing dependency rather than creating a new one.

### Does an unfiltered query dump the whole database?

**No.** Tested and settled:

| Query | Result |
|---|---|
| All filters null | **204 No Content** |
| Date window only, no committee | **204 No Content** |
| Committee + date window | 200, 213 rows |
| Committee + ISO datetimes | 200, 213 rows (same) |

`primaryCommitteeId` is mandatory; the endpoint returns nothing without it. Date
filtering works but only alongside a committee. So there is no single bulk pull —
ingest must iterate committees.

**This makes the filings index the important endpoint.** `POST /api/publicreports/state`
*is* one unfiltered call (all 17,873 filings, with `filedOn` per filing), so it
works as a **change feed**: diff it against a manifest and re-pull transactions
only for committees whose latest `filedOn` moved. That collapses a ~7,900-call
sweep into a handful of calls on a normal day — the same pattern as
`render_manifest.csv` on the legislature side.

### Is the GUID vs committee_code split a problem?

**No — the crosswalk already exists.** Two independent reasons:

1. `POST /api/search/committee` returns **both** `id` (GUID) and `committeeCode`
   on the same object, along with party, office sought, election year, district
   and county.
2. `committee_lookup.rds` (from `01_build_committee_lookup.R`) already stores
   `committee_uuid` for **7,935 of 7,936** committees. Verified: Rob Sand's
   stored uuid `6a0d5912-88d5-431d-a00f-33e87237a523` matches the live API `id`
   exactly.

The GUID is only ever needed as *input* to a query; transaction rows come back
carrying `primaryCommitteeCode`, so everything joins to our existing
`committee_code` key with no schema change.

---

## Plan: migrating to IECDB

Agreed direction, not yet started. Four phases, each gating the next.

### Phase A — built 2026-07-25: `R/campaign_finance/iecdb_api.R`

One module, `R/campaign_finance/iecdb_api.R`, that every later phase goes
through. Nothing calls the API directly.

- **Throttle.** Configurable delay between calls, default conservative (~1–2s).
- **Backoff.** Exponential retry on 5xx/timeout; give up rather than hammer.
- **Hard per-run request cap.** A runaway loop should stop itself, not the
  agency's server.
- **Identify the client.** `User-Agent` naming the project and a contact.
- **Schema contract per endpoint.** Assert the expected field set on every
  response; **fail loudly** on drift rather than silently ingesting partial data.
- Wrap the two calls `01_build_committee_lookup.R` already makes, so there is
  one client rather than two conventions.

**Two bugs the build surfaced, both worth remembering:**

1. **Silent zero rows.** `/api/search/table` returns a **bare JSON array**;
   the publicreports endpoints return a `{totalCount, results}` envelope.
   Reaching for `parsed$results` on the array yielded `NULL` → zero rows → no
   error. Exactly the silent-partial-ingest failure this phase exists to
   prevent. `iecdb_rows()` now accepts both shapes and **errors** on anything
   else rather than returning empty.

2. **Row-wise parsing is unusable at scale.** `map(rows, \(r) tibble(...)) |>
   list_rbind()` took >10 minutes on Sand's 256,786 rows and dominated the
   request entirely. Switched the transaction path to
   `jsonlite::fromJSON(simplifyDataFrame = TRUE)` plus a `col_or_na()` helper
   for columns the API omits: **53 seconds** for the same pull. The small
   endpoints keep the list parser.

`iecdb_health_check()` is a 2-request canary asserting eight properties against
known values (committee resolves, UUID and name stable, transactions return,
codes join, dates respect the window, amounts numeric, types are `CON`/`INK`).
An earlier version asserted `reference_dr2_id` was populated, which passed
trivially against the all-zeros placeholder — a check that can only pass is
worse than no check, and it has been replaced.

### Phase B — change-detection ingest — **built 2026-08-01**, not yet run live

`R/campaign_finance/01b_iecdb_ingest.R`. All of the below is implemented:

- One call to `POST /api/publicreports/state` → all 17,873 filings with `filedOn`.
- Diff against a manifest (same pattern as `render_manifest.csv`); re-pull
  transactions only for committees whose latest `filedOn` moved.
- Turns a ~7,900-call sweep into a handful of calls on a normal day.
- Store **`reported_through`** per committee as a first-class column — the date
  its most recent filing covers. Pages display it instead of implying currency.

Plan and execute are separate functions, so the request cost is printed before
anything is spent. Writes are incremental with an `on.exit()` save, so the first
full sweep is resumable. Offline logic is tested against a synthetic filings
index under `options(warn = 2)`; the live path is untested.

### First live call, 2026-08-01: one bug, one surprise

**Bug: `iecdb_filings()` was posting `[]` and getting HTTP 400.** An empty R
list has no names, and jsonlite cannot distinguish an empty object from an
empty array, so `list()` serialized to `[]` where the endpoint wanted `{}`.
`iecdb_statements()` had never hit this only because its body is non-empty.
Fixed in `iecdb_perform()` by naming the empty list; non-empty bodies are
untouched, so the `NULL → {}` serialization the transactions endpoint has been
happily accepting is left exactly as it was. The canary missed it because it
exercises committee search and transactions only — the filings endpoint had
never actually been called through the client.

**Surprise: the feed is 1,403 committees, not ~7,900.** `/api/publicreports/state`
is state filings only, and the split is structural rather than an artifact of
age. Every local committee type sits at 0% coverage regardless of recency
(County Candidate, City Candidate, School Board, County Central Committee,
Local Ballot Issue; `CTY`/`LOCL`/`BALLOT` prefixes), while state types run
47–100%. It still reaches **80.7% of all money** ($778.8M of $964.5M), because
the uncovered committees are numerous but individually small — though County
Central Committees run $1–3M each and 1,147 uncovered committees were active in
2024 or later, holding $50.6M.

Age is a real but *secondary* effect, operating only within the state slice:
the index thins sharply before 2014, so long-dissolved state committees have no
filings in it either.

**Consequence:** `countyReports` (seen in the JS bundle, never probed) is
needed before the API can replace data.iowa.gov rather than supplement it. It
should drop into the same manifest and loop — one more client wrapper. Phase C
reconciliation should be scoped to the state slice until then.

**Also fixed: the period parser was returning the period's START date.** The
real vocabulary uses "through", not a dash — "January 1 through May 14" — and
the original implementation split on a dash that wasn't there, then took the
first month/day it found. It was wrong on **14,948 of 17,876 filings**, and
wrong in the worst way: a plausible-looking date. Rewritten to split on the
last separator and read only the tail, which is also what makes
"Oct. 15 through Dec. 31 or Wed. Preceding General through Dec. 31" land on
Dec 31. Now 91.6% of filings parse and 99.5% of committees get a date from
their latest filing; Sand, Lahn and Henderson all resolve to 2026-07-14,
independently matching the currency established during reconnaissance.

The unparsed remainder is almost all "… through Tuesday Preceding
Primary/General" (1,437 filings) — periods that end at an **election, not a
date**. `NA` is correct there without an election calendar.

**Still to check on the first transaction pull:** whether one
`iecdb_transactions()` call per committee really returns everything.
Reconnaissance saw no paging on a 257k-row committee, but that was one
committee.

### Phase C — reconcile, then cut over

Run both sources side by side before switching:

- Compare per-committee totals on the overlapping period; investigate every
  disagreement before trusting either.
- Cut over only when they agree.
- Afterwards keep data.iowa.gov as a **periodic audit**, not the source — it
  becomes the independent check rather than the input.

### Phase D — the payoffs

- ~~Split `transaction_type` so loans and in-kind stop counting as donations.~~
  **Done 2026-07-27, pulled forward out of Phase D.** It needs no API access —
  the bulk feed already carries `transaction_type` — and it was the one item on
  the list that made the *current* data wrong rather than merely stale, so it
  was not worth gating behind the migration. `transaction_class` is emitted in
  `02`, the six state views split money four ways, and both static templates
  were re-verified against Lahn for Governor. See the Transaction class section
  in CLAUDE.md.
- Reporting-period attribution — **by inferring from `date`**, not by joining
  `referenceDR2Id` (see the correction above).
- Surface `reported_through` on committee pages.
- Later: parse DR2 PDFs for **cash on hand**.

### Open blocker for cutover: loans are missing from the API

Found while smoke-testing the client. Requesting `transactionType = "CON"`
returns a **category**, not a row type — Lahn's pull came back as 1,125 `CON`
plus 50 `INK` rows, totalling 1,175. Useful (in-kind arrives pre-labelled), but:

**No `LOANREC` rows come back at all.** Confirmed across five committees of
three different types, deliberately chosen because they *do* have loans in the
bulk export, dated inside the window the API returned:

| Committee | Type | Bulk export | IECDB API | Loans returned |
|---|---|---|---|---|
| CTY51589 Reimer For Supervisor | County Supervisor | `LOANREC`=2 | *(nothing)* | 0 of 2 |
| CTY51583 Gregory T Guy | County Treasurer | `LOANREC`=4 `CON`=6 | `CON`=6 | 0 of 4 |
| 2570 Henderson for House | **State House** | `CON`=310 `INK`=25 `LOANREC`=116 | `CON`=310 `INK`=25 | 0 of 116 |
| CTY50056 DVogel for Supervisor | County Supervisor | `CON`=20 `INK`=3 `LOANREC`=9 | `CON`=20 | 0 of 9 |
| 5185 Rob Sand for Iowa | Governor | `CON` `INK` only | `CON` `INK` | n/a — no loans |

131 loan transactions across four committees, none returned.

**The decisive test — a same-date pair.** Counting by type isn't quite enough,
because the API's returned date "span" is just the range of the `CON`/`INK`
rows it chose to return; a committee whose loans fall outside its contribution
dates will always *look* like a date-coverage problem. So: Henderson for House
has two transactions on **2026-07-06** in the bulk export —

| Source | Date | Type | Amount | Party |
|---|---|---|---|---|
| bulk | 2026-07-06 | `CON` | $20 | Bruce Helvig |
| bulk | 2026-07-06 | `LOANREC` | $180 | Robert Henderson |

Querying the API for exactly that single date returns **only the $20
contribution**. Same committee, same date, same request. No date-range
explanation survives when both rows share a date.

Querying the exact date of a loan on the other three returns nothing at all,
because those dates contain only loans. And Reimer *is* in the API — committee
search returns it as a Candidate filer — so its empty transaction result is not
a missing committee, it is a committee whose only transactions are loans.

This also disposes of the reasonable objection that Lahn simply had no loans in
that period.

**Second, smaller discrepancy:** DVogel's 3 `INK` rows are in the bulk export
but did not come back from the API, while Henderson's 25 `INK` rows did. So the
contributions category is not reliably a superset of `CON` + `INK` either. Cause
unknown.

Cutting over without resolving this would **silently drop loan data** — for
Lahn that is 67% of what the current pipeline reports as "total raised".

### RESOLVED (same day): loans are definitively not in the public API — but the DR2 PDFs carry full loan detail

The follow-up investigation exhausted the API angles:

**1. The app's own enum has hidden values — none of them work.** The JS bundle
defines six transaction types where the UI dropdown exposes two:

```
Vo.CONTRIBUTION = "CON"          Vo.LOANRECEIVED = "LOANREC"
Vo.EXPENDITURE  = "EXP"          Vo.LOANREPAID   = "LOANREP"
Vo.INKINDCONTRIBUTION = "INK"    Vo.VSR = "VSR"
```

Sent `LOANREC`, `LOANREP`, `VSR`, `INK` against Henderson (116 known loans):
**0 rows each**. The server returns empty for any type outside CON/EXP.

**2. All `transactionOption` values recovered and tested.** The enum runs 1–8
(`TO_A_COMMITTEE=1` … `FROM_A_COMMITTEE_TYPE=8`). `LOANREC` × options 1–4:
**0 rows each**. (Options do work as counterparty filters for real types —
`CON` with `FROM_AN_INDIVIDUAL=3` returns Henderson's 276 individual rows.)

**3. Schedule endpoints exist but are filer-side.** The bundle wires
`POST /api/schF1LoansReceived/table?dr2Id=<id>` (Schedule F1 = Loans Received)
plus siblings for every schedule. Tested against Lahn's May filing (dr2Id
204280): **401 Unauthorized**. The `id` in the public filings index is the
dr2Id — right key, closed door.

**4. The DR2 "Summary" PDFs are actually the complete filed reports.**
Downloaded Lahn's May 15–26 filing PDF (189 KB, 16 pages, digitally generated —
`pdftools::pdf_text()` extracts cleanly, no OCR):

- **Page 1 — Statement of Cash On Hand**: beginning balance $709,448.88,
  Schedule A total $60,049.96, **Schedule F1 Loans Received Total $500,000.00**,
  ending balance. (Cash on hand, previously thought to need dedicated work,
  falls out of the same parse.)
- **Schedule F1 detail page**: lender name/address (Lahn, Zach — PO Box 129,
  Belle Plaine), relationship to candidate ("Self"), date incurred 5/22/2026,
  amount $500,000 — plus running totals: unpaid from last period $2,000,000,
  outstanding at end $2,500,000.
- Schedule F2 (Loans Paid or Forgiven), Schedule D (debts), Schedule G
  (consultants) are all present too.

**Cross-validation**: the PDF's Schedule A total ($60,049.96) matches the
bulk-derived May 15–26 `CON` sum ($60,050) to the cent, confirming both the
period boundaries and the transaction feed against the filed report.

### Storage decision for the PDFs (2026-07-25)

Downloaded DR2 PDFs go to `data/campaign_finance/source/dr2_filings/`, which is
**already git-ignored** (the whole of `data/campaign_finance/source/` is). No
`.gitignore` change needed. Sizing: ~200 KB each × 17,900 filings ≈ 3–4 GB for
a full mirror — never commit that, and never pull it either; the gap-fill only
needs the few hundred filings newer than their committee's bulk data.

Candidate pages link to the filed report via the `file_url` from the filings
index — the state's own public blob URL, so zero hosting cost on our side.
**Render links fresh from the latest filings pull**: amended filings get a new
filename (the generation timestamp is embedded), so a baked-in URL can go
stale even though old blobs appear to stay up.

### Resulting source strategy for loans

Exactly the hybrid proposed when this gap was found: **bulk data.iowa.gov for
loan history** (it has `LOANREC` back to at least 2020, and its lag is small —
Henderson's 2026-07-06 loan was already in the 202607 export) **plus DR2 PDF
Schedule F1 parsing to close the recency gap** for committees whose bulk data
trails their filings. The filings index supplies `filed_on` for change
detection and the PDF URL; `iecdb_download_filing()` in the client fetches
politely (same throttle/budget as API calls). Parsing effort also yields cash
on hand for free, collapsing what were two separate work items into one.

### Consistency checks (the gate, not an afterthought)

| Check | Behavior on failure |
|---|---|
| Expected field set present on every response | **Fail** the run |
| Per-committee all-time total changed since last pull | **Flag**, don't fail — amended filings legitimately rewrite history |
| Canary committees match known values | **Fail** |
| Transaction sums vs DR2 filed totals (once PDFs parse) | **Flag** — genuine cross-source check, not self-consistency |
| Row count drops for any committee | **Fail** — should never happen absent an amendment |

Self-consistency is not enough; the checks that matter compare against an
independent source (data.iowa.gov during Phase C, DR2 totals after Phase D).

### Sequencing against the design work

**Phases A–C go before `render.R`, the index pages, and the donor pages** —
despite delaying visible progress.

Phase D changes the data model those pages are built on: splitting contributions
from loans changes what "total raised" means on every page, period attribution
changes how time series are drawn, and `reported_through` is a field the page
has to display. Building index and donor pages first means rebuilding them
after — the same trap the legislature domain is currently in, where a full
`render_site(force = TRUE)` is pending because design changes landed after
pages were rendered.

The one exception: **finish the donor template restyle first.** It's the last
sibling of the redesign pass, and leaving it half-done makes the styling work
more expensive to resume.

### Cautions

Still live:

- **Undocumented internal API.** No stability guarantee; it can change without
  notice. Any ingest must fail loudly on schema drift rather than silently
  producing partial data. This is the single biggest risk in the migration and
  the reason Phase A exists.
- **Be a good citizen.** Responses are large — 7.8 MB for the filings index,
  256,786 rows for one committee. Cache aggressively and throttle even though
  nothing forbids us from not doing so.
- **Committee enumeration still needs a sweep.** Since there's no bulk dump,
  a first full load means one call per committee (~7,900). Do it once, slowly,
  then let the filings change feed keep it current. Don't re-sweep casually.
- **PDF parsing is real work.** Cash on hand is worth it, but it's a project,
  not an afternoon.

Resolved during this session (kept so they aren't re-investigated):

- ~~Check terms of use~~ — done: permissive `robots.txt`, no automated-access
  or rate-limit clause in Iowa.gov policies, Chapter 22 open-record data.
- ~~`id` is a GUID, a crosswalk is needed~~ — the crosswalk already exists in
  `committee_lookup.rds` (`committee_uuid`, 7,935/7,936, verified live).
- ~~Never issue an unbounded query, it would probably dump everything~~ — tested:
  it returns `204 No Content`. There is no unbounded query to worry about.
