# Past-session index pages (2026-11-11)

Phase 1 work from the [multi-session plan](2026-10-24_multi-session-plan.md), done before the 92nd GA switch. The problem: every index page listed `CURRENT_GA` only. Once `CURRENT_GA = 92`, the 91st's bill list, lobbying organizations, week pages and members who left would have had nothing linking to them.

## What was built

- **Archived section indexes.** `site/{legislation,legislators,lobbying}/index.qmd` take a `ga` param (null = current). `render_session_archives()` (`render.R`) renders each one for every session before `CURRENT_GA` to `docs/{section}/ga91.html`. `render_site()` calls it before the project render, and `render_backlog("everything")` calls it too.
- **When they re-render.** Manifest type `session_index`, key `ga91/legislation`. The hash covers the section's `.qmd`, its session list (`section_gas()`) and `CURRENT_GA`. The pages' data is frozen, so they re-render only after a template edit or when a session is added, which the switcher needs.
- **Session switcher.** `session_nav()` (`R/legislature/ui_helpers.R`) shows a line under each index's lead, such as "General Assembly: 92nd · 2027–2028 (current) · 91st · 2025–2026". It's NULL while a section has one session, so the live site is unchanged until the switch. `section_gas()` (`session.R`) lists only the sessions that have the data the section reads, so a backfilled session without lobbying data gets no Lobbying link.
- **Weekly archive.** `site/activity/index.qmd` reads every session's `bill_actions.rds` and shows one card per session and year. It has no per-session pages, because week pages are keyed by date and don't collide. `render_session_archives()` also runs `render_all_weeks(ga = g)` for earlier sessions. That renders nothing for the 91st, whose weeks were rendered while it was current, but it covers a backfilled 90th.
- **Legislator links.** On an earlier session's Legislators page, members who served again link to their `legislators/ga91/` archive page. Members who left link to their career page, which still shows that session.
- Search: `site_page_kind()` treats `{section}/gaNN.html` as a `session_index` (a general entry).

## Choices

- **Sibling file, not a subdirectory.** `legislation/ga91.html` sits at the same depth as `index.html`, so the existing `.qmd` renders as-is with a param. `legislation/ga91/index.html` would have needed each index split into partials plus a deeper template, as the legislator pages do. It would also share a folder with the bill pages.
- No committee index exists for any session; committee pages stay reachable from bill and legislator pages.

## Testing

Tested with a faked 92nd: copies of `legiscan/ga91/derived` and `data/legislature/ga91` as `ga92`, with `CURRENT_GA = 92`. All three archived pages rendered at the right paths, and a second run rendered nothing. Editing a template triggered a re-render. Links checked: 91st bills go to `../legislation/ga91/`, returning members to `ga91/{name}.html`, and the switchers between `index.html` and `ga91.html`. The fake data was then removed. With the real single session, the four current pages render with no switcher, and the weekly archive's text is identical to the committed page.

Not tested against real two-session data: the ROADMAP item for the first two-session render covers that.
