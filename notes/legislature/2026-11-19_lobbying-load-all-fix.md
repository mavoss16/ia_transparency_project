# Lobbyist declarations: fetching past the 50-row limit

Follows [`2026-11-19_lobbying-50-limit.md`](2026-11-19_lobbying-50-limit.md), which found the cap but not the request behind "Click to load all declarations".

## The endpoint

From `publicLobby.js` on legis.iowa.gov (`searchDeclarations(true)`):

```
POST https://www.legis.iowa.gov/lobbyist/reports/declarations?action=search
form: ga, date="", personID="", clientID="", ba={bill}, index=1, loadAll=true
```

The response is bare `<tr class="decRow">` rows in the page table's column order, with no header. `loadAll=false` with `index=2, 3, …` pages 50 at a time (the infinite scroll); not used.

## Change

- `R/legislature/utils.R`: `fetch_all_declaration_rows()` replays that POST with httr2 (wrapping the fragment in `<table>` so the parser keeps the rows). `scrape_lobbyist_declarations()` calls it when the page has `DECLARATIONS_PAGE_SIZE` (50) rows, parses the result with the page's headers, and stops if it returns fewer rows than the page, so `scrape_lobby_safe()` logs a failure instead of saving a capped bill. Bills under 50 cost no extra request.
- `R/legislature/04_lobbyist_declarations.R`: `update_lobbyist_declarations()` ends by reporting how many scraped bills have exactly 50 rows, as a tripwire if the POST breaks.

## Test (live, 2026-11-19)

| Bill | Saved | Scraped now |
|---|---|---|
| HF 639 | 50 | 67 (matches the browser) |
| HF 1008 | 50 | 50 (genuine) |
| HCR 6, HCR 7 | 39, 9 | 39, 9 (no extra request) |
| 8 random bills of the 501 at 50 | 50 each | SF 220 105, HF 583 95, SSB 1051 86, SSB 3008 73, HF 957 59, SSB 3026 54, SF 2442 50, SF 111 50 |

No NA lobbyists, IDs or dates; no duplicate rows. HF 639's dates now reach back to 2025-02-28. GA 90 HF 2612 returns 136 rows from the same POST.

Not yet done: the refill of the 91st's data (ROADMAP).
