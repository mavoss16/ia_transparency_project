# 2026-11-02 — safeconduct trial against sos.iowa.gov

Tried [safeconduct](https://mountainmath.github.io/safeconduct/) 0.1.0 (mountainMath, GitHub only) as a way past the SOS 403 that blocks `download_all_results()` for every SOS election. It drives a real Chrome through `chromote`, passes the host's browser check there, then downloads with curl using the browser's cookies, or inside the browser if the server still refuses curl. Installed into a scratch library outside renv; nothing in the repo uses it.

## Results

- **`probe()`** on `precinct-results-county-2018-primary`: 403, `challenged = TRUE`, `blocked = FALSE`. safeconduct's checks are written for Cloudflare, but it reads the Akamai 403 as a challenge.
- **Index pages work.** `browser_session("https://sos.iowa.gov/", headed = FALSE)` opened in 3–4 s, and `read_page()` on the 2018 primary index returned 200 with all 99 county `.xls` links. httr2 can't get this page.
- **Files don't.** `fetch()` on `2018primary/adair.xls`:
  - headless: SOS runs a second check at the file URL; not passed within 150 s (`safeconduct_not_passed`).
  - `headed = TRUE`: the first file was "cancelled by the browser"; the second hit the check again. The user clicked "Verify you are human" several times; each time it spun and came back. Not passed within 120 s.
- No file was downloaded.

## Reading

Akamai lets an automated Chrome read HTML pages but not files, and won't clear the file check even when a person clicks. It probably sees the browser is under DevTools control. Getting past that would mean hiding the automation, which is evasion, so this stops here. Downloading by hand in an ordinary browser still works.

## If revisited

- A middle path: use safeconduct only for the index pages, to list each election's file URLs, and download the files by hand. The URLs follow `elections/pdf/precinctresults/{year}{type}/{county}.xls`, so the listing alone saves little.
- Ask the SOS elections office for bulk files, or whether a non-browser client is allowed.
