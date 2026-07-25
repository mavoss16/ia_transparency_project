---
target: docs/index.html (home)
total_score: 31
p0_count: 0
p1_count: 2
timestamp: 2026-07-11T22-17-56Z
slug: docs-index-html
---
# Critique — docs/index.html (home)

Method: ⚠️ DEGRADED: single-context (harness policy — sub-agents not spawned unless explicitly requested; Assessment A locked before detector ran)
Register: product · Platform: web · Target: rendered home page (docs/index.html, fresh render verified)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | "Last updated" + active-nav shown; static site, little status surface |
| 2 | Match System / Real World | 3 | Legislative jargon + a non-monotonic "progress" chart tax the newcomer |
| 3 | User Control and Freedom | 3 | Search + browse paths; low-risk static surface |
| 4 | Consistency and Standards | 4 | Tight `.ia-*` system; uniform pills/cards/stat tiles |
| 5 | Error Prevention | 3 | n/a — no forms or destructive actions |
| 6 | Recognition Rather Than Recall | 3 | Everything browsable and labeled |
| 7 | Flexibility and Efficiency | 3 | Search + browse; no home-level filters/shortcuts (they live on sub-pages) |
| 8 | Aesthetic and Minimalist Design | 3 | Strong restraint; mild uppercase-label proliferation + card-heaviness |
| 9 | Error Recovery | 3 | n/a on a static index |
| 10 | Help and Documentation | 3 | Footnotes + About + cited sources give real context |
| **Total** | | **31/40** | **Good — solid foundation, address weak areas** |

## Anti-Patterns Verdict

**Does it look AI-generated? Mostly no — this passes the product slop test.** A category-fluent user would trust it. No gradient text, no glassmorphism, no side-stripe cards, no invented affordances. Party colors are used only to label data, never to decorate — exactly right for the neutrality constraint.

**Deterministic scan:** `detect.mjs` on docs/index.html → `[]` (clean, exit 0). No structural slop tells.

**The one mild tell** the detector can't see: uppercase-tracked micro-labels proliferate — the hero eyebrow ("2025–2026 SESSION"), every stat label ("TOTAL BILLS"), tally labels, split labels. Any one is fine; the aggregate is the single spot where "AI grammar" peeks through on an otherwise disciplined page.

## Overall Impression

A genuinely restrained, credible civic dashboard that already clears the bar most AI redesigns miss. It reads as neutral and authoritative. The biggest opportunities aren't aesthetic — they're **accessibility and mobile**, both of which currently contradict commitments in PRODUCT.md (WCAG AA; broad non-expert public who will arrive on phones).

## What's Working

1. **Fit to brief.** Warm-neutral + serif/sans + data-only party color = "neutral, authoritative, trustworthy" delivered, not just stated. Restraint is doing the impartiality work.
2. **Real hierarchy with a confident emphasis move.** Hero → 4 KPIs → two analytical cards → recent activity → browse CTAs. The single dark browse card ("Browse all legislation") prioritizes the primary path without shouting.
3. **Density without a dump.** Headline stats carry context subs ("5.2% of all bills introduced"), so the numbers inform rather than decorate.

## Priority Issues

- **[P1] Secondary text fails WCAG AA.** The `$faint` token (`#8a877e`) computes to **3.32–3.59:1** everywhere it carries text — `.ia-updated` (3.32), `.ia-stat-label`, `.ia-recent-meta`, `.ia-footnote`, `.ia-tally-label` (all 3.59). AA requires 4.5:1 for this size. You just committed to WCAG 2.1 AA, so this is a direct violation, and it's systemic (one token, ~6 uses). **Fix:** darken `$faint` to ≥4.5:1 on both white and `#f7f6f3` (≈ `#6c6960` or merge toward `$muted` `#6d6a62`, which already passes at 5.40). *Command: /impeccable colorize (or polish).*

- **[P1] Mobile layout breaks on the recent-activity list.** `.ia-recent-row` keeps its fixed 4-column grid (`84px / 1fr / auto / 104px`) at 375px, so ~498px of content sits in a ~343px column and the date column's right edge lands at **563px** — off-screen and clipped (no page scroll, so it's silently cut, not scrollable). `.ia-browse-grid` also stays 2-up at 154px/card (cramped). Only `.ia-stat-grid` reflows. **Fix:** collapse `.ia-recent-row` to a stacked layout under ~600px and drop `.ia-browse-grid` to one column. *Command: /impeccable adapt.*

- **[P2] "Where bills stand" reads as a broken funnel.** Under a progress framing, the bars are non-monotonic — Passed Committee (1,589) dwarfs Passed Subcommittee (439) and even Introduced (1,535). It only makes sense after reading the footnote ("furthest individual progress"). For a non-expert (the stated primary audience) this is a comprehension speed bump. **Fix:** reframe the heading/label as a distribution of "furthest stage reached," or visually separate terminal states (Signed/Awaiting) from in-progress. *Command: /impeccable clarify (copy) or layout (structure).*

- **[P2] Uppercase-tracked labels proliferate.** Eyebrow + stat labels + tally labels + split labels all use the same small-caps-tracked treatment. It's the one AI-grammar tell on the page. **Fix:** let one cadence carry; demote the others to sentence-case or weight-based emphasis. *Command: /impeccable typeset.*

- **[P3] Party tally conveys R/D by color alone.** "67 – 33" uses red/blue numerals; the legend maps color→party but the numbers themselves don't restate it. Minor AA "don't rely on color alone." *Command: /impeccable clarify / colorize.*

- **[P3] Hero sources are plain text; footer repeats them as links.** Minor redundancy/inconsistency in how LegiScan / Iowa Legislature are presented.

## Persona Red Flags

**Jordan (Confused First-Timer)** — the primary persona, per "broad non-expert public": Hits the "Where bills stand" chart and can't reconcile why "Passed Committee" is bigger than "Passed Subcommittee"; the explaining footnote is below the chart, in failing-contrast `$faint` text. Legislative shorthand ("HSB 780", "Message from House. S.J. 879.") is unglossed.

**Casey (Distracted Mobile User)** — implied by a broad public that arrives via phone: On a 375px screen the recent-activity dates/status are clipped off the right edge; the two browse cards are squeezed to 154px. The most-scannable content degrades exactly where a casual visitor meets it.

## Minor Observations

- `.ia-card-sub` / `.ia-stat-sub` (`$muted` 5.40) and `.ia-lead` (7.22) pass AA comfortably — the contrast problem is isolated to `$faint`, which makes the fix a one-token change.
- Card-density is high (4 stat + 2 content + recent + 2 browse). No *nested* cards (good), but worth watching that every box still earns its border.

## Questions to Consider

- Is the warm-cream `#f7f6f3` + serif the identity you want, or the safest expected one? (You said you're not locked to it — worth a deliberate decision rather than an inherited default.)
- Should the home page's job be "orient + route" (fewer, larger entry points) rather than "summarize everything"? What does a first-time Iowan actually need in the first screen?
- Could "where bills stand" tell a clearer story as a true funnel of *unique* bills rather than furthest-stage tallies?
