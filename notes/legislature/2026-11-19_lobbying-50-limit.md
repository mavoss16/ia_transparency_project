# Lobbyist declarations: the 50-row limit

Checked 2026-11-19 (evening CT). Read-only investigation; no code changed.

## Finding: the limit is real

- `data/legislature/ga91/lobbying/lobbyist_filings.rds` (92,958 rows, 4,027 bills with declarations): **501 bills have exactly 50 rows, and none has more than 50.** Bills with 40 to 49 rows run 30 to 54 each, so the pile-up at 50 is the cap, not chance.
- The declarations page (`https://www.legis.iowa.gov/lobbyist/reports/declarations?ga={ga}&ba={bill}`) renders only the **50 most recent** rows (newest first). An orange "Click to load all declarations" control above the table loads the rest in place, with no change to the page URL (so it's an XHR, not a link).
- **HF 639 (GA 91)**, checked in a browser: 50 rows before the click, **67 after**. The 17 missing rows are the oldest (Feb 28 to Mar 25, 2025). They include **7 clients missing entirely** from the saved data (Iowa Utilities Commission, Iowa Chapter of Sierra Club, Iowa State Association of Counties, Iowa State Association of County Supervisors, Urban County Coalition, Linn County Board of Supervisors, Cedar Rapids Metro Economic Alliance). Saved: 22 clients; true: 29.
- **HF 1008 (GA 91)**: still 50 after the click, so some of the 501 bills genuinely have 50. How many of the 501 are truncated, and by how much, is unknown until they're re-scraped with the fix.
- GA 90 pages (HF 2612, SF 496) show the same 50 rows plus the same control, so a GA 90 scrape with today's code would be capped too.
- `lobbyist_declarations.rds` (one row per client) is built from the filings, so everything downstream undercounts on busy bills: bill pages, 04a alignment, 04b clients, 04c organizations, 05 salience.

## Not yet known: the endpoint

I couldn't capture what the control calls. This environment's network proxy refuses legis.iowa.gov for curl, and the browser tools show the page but not its scripts or network requests. **This is the first step in Claude Code locally** (about two minutes):

1. Open `https://www.legis.iowa.gov/lobbyist/reports/declarations?ga=91&ba=HF639` in Chrome, DevTools > Network (Fetch/XHR), click "Click to load all declarations", and copy the request (method, URL, form data) and the response type. Or `curl` the page and grep its `<script>` tags and linked `.js` for "load all" / "action=".
2. A likely shape, **unverified**: the page already uses `POST declarations?action=getDeclarationComments&declarationID={decid}&col=7` for comments (ROADMAP line 48), so the load-all is probably another `declarations?action=...` call with `ga` and the bill. Expected count to check against: HF 639 = 67 rows.

## Fix plan

All in the scrape layer; downstream code needs no change.

1. **`R/legislature/utils.R`, `scrape_lobbyist_declarations()`**
   - Pull the row parsing (the `cell()` / `cell_text()` block and the `tibble(...)`) into a helper, e.g. `parse_declaration_rows(table_node)`, so the first page and the load-all response share it.
   - After the first fetch, if the page has the load-all control (or exactly 50 `tr.decRow` rows), make the load-all request with `httr2` (or whatever `fetch_html()` wraps) and parse that instead. If the response is HTML rows rather than a full table, read headers from the first page.
   - Guard: if the full result has fewer rows than the first page, `stop()` so `scrape_lobby_safe()` records a failure rather than silently saving a capped bill.
2. **Sanity check** in `update_lobbyist_declarations()` / `rescrape_lobbyist_declarations()` (`R/legislature/04_lobbyist_declarations.R`): after a run, message how many bills came back with exactly 50 rows. A large number means the load-all path broke.
3. **Test** on HF 639 (expect 67) and HF 1008 (expect 50), then a dry run on a handful of the 501.
4. **Refill GA 91.** No special run needed: the weekly Lobbying Update (`run_lobbying.R`) re-scrapes every bill, rebuilds 04a/04b/05/04c and re-renders pages whose declarations changed. For a faster check first: `rescrape_lobbyist_declarations(<the 501 bills>)` (list below), then `run_lobbying(scrape = FALSE)`.
5. **Then GA 90** with the fixed scraper (the lobbying-update.yml `ga` input is still a separate open item).

## The 501 GA 91 bills at exactly 50 rows

Regenerate in R:

```r
readRDS("data/legislature/ga91/lobbying/lobbyist_filings.rds") |>
  filter(!is.na(lobbyist)) |>
  count(bill) |>
  filter(n == 50) |>
  pull(bill)
```
