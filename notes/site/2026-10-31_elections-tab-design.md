# Elections on legislator pages — design direction (2026-10-31)

Decision doc for Phase 1 step 5 of the [electoral history plan](../elections/2026-10-30_legislator-electoral-history-plan.md); update in place as choices land. Grounded in [`PRODUCT.md`](../../PRODUCT.md). Run `/impeccable shape` on the tab before building it and `/impeccable critique` after.

**Mock:** [`mocks/2026-10-31_elections-tab-mock.html`](mocks/2026-10-31_elections-tab-mock.html), Ray Sorensen (HD 23) with his real 2018–2024 general results and the 2022 Republican primary from the canvass. Other primaries are dashed placeholders; general-election party labels are as step 3 will fill them (Karen Varley's is assumed). Open the file in a browser from the repo: it loads the compiled site CSS from `docs/site_libs/bootstrap/bootstrap-c738a8298c0df97af83792233af52165.min.css`, so if a render changes that hash, update the `<link>`.

## Three levels on the page

Progressive disclosure: one fact everywhere, detail in the tab.

1. **Profile header, tenure line** under the meta line: "In the Iowa House since 2019 · re-elected 2020, 2022 and 2024." Facts only, no margins. LegiScan can't give a start date; the elections can.
2. **District card, latest result** under the map: "Won the 2024 general with 72.1% of the vote. Electoral history →" (links to the tab). Competitiveness is a fact about the seat, so it sits with the district. The four stat cards stay as they are: they describe the session's work, and a fifth breaks the 2×2.
3. **An "Elections" tab** with the full history.

## The tab

- **Summary sentence first**, generated from the data: "Ray Sorensen was first elected to the Iowa House in 2018 and re-elected in 2020, 2022 and 2024. Since the 2021 redistricting he has represented District 23; before that, District 20." No count cards ("6 races · 5 wins"): that is the dashboard look PRODUCT.md rules out.
- **One block per election year, newest first.** Heading: year (serif) and "House District 23". Specials show their date in the race label.
- **Contested race:** label with date ("General election · November 5, 2024"), a thin share bar (`ui_share_bar()` look, 14px) of the named candidates only, then a small table: candidate, party, votes, share. Winner gets a green ✓ (with `aria-label`), "incumbent" in small muted text. Write-ins are one muted row, left out of the bar. Then a flat margin line: "Won by 7,898 votes (44.3 points)."
- **Unopposed race:** one line, no bar: "Ray Bubba Sorensen (Republican) incumbent ran unopposed: 11,399 votes; 249 write-ins." A 100% bar would show a contest that didn't happen.
- **Primaries:** the member's own primary right under the general (one line if unopposed, a table if contested; no party column, since it's one party). Other parties' primaries for the seat go in a collapsed `<details>` "Other primaries for this seat".
- **Context notes** in a quiet gray box, only where they apply: a changed district map ("First election under the 2021 district map. Sorensen previously represented District 20." with a link to an explainer), an open seat ("Open seat: the incumbent, Clel Baudler, did not run."), a special election, and Iowa's 35% convention rule in the rare race where it applied.
- **Source line per block:** "Iowa Secretary of State, precinct results by county (2024 general)", linked to the file.
- **Connections:** link an opponent's name when they are or were a legislator (needs the crosswalk). Leave room in the table for a campaign finance column once that domain publishes.
- **No maps** in v1: precinct shapefile coverage is patchy and maps are what made bill pages heavy.

## Rules

- **Neutrality:** no characterizing words ("landslide", "close race"); not even a defined-threshold "close race" badge in v1. Order candidates by votes.
- **Party is never color alone.** At ≤600px the Party column is hidden, so each name gets a short "(R)"/"(D)" label in the party color (found while building the mock).
- **Percentages are of all votes in the race, write-ins included** (Ballotpedia's convention). State it once in a footnote.
- Party colors label data only: R `#A8433A`, D `#3F5B93`; minor parties neutral gray.

## Data the race table (step 3) must carry

Election date and type (general/primary/special); the district map in force; per candidate: votes, share, winner, incumbent (through the crosswalk, because after redistricting the incumbent can run under a new number), party, and `people_id` for every candidate who matches a legislator, not only winners; margin; source URL. Also per seat-year: whether it was an open seat.

## Open

- **Where the tab sits** depends on the career-page decision in `ROADMAP.md`: if a page gets a tab per session, Elections sits outside the session tabs, since it spans the career.
- **Tab bar at phone width** already wraps to three rows; a fifth tab makes it worse. Fix with the tab, or with the career-page layout.
- **Latest margin in the district card** is the most prominent number this work adds. Recommended (it's the most useful single fact for a newcomer); confirm.
- **Component split:** the share-bar and result table could be shared (`R/ui_helpers.R`) if campaign finance or an elections section will show races too; the incumbent/party/redistricting wording is domain vocabulary and belongs in a domain helper.
