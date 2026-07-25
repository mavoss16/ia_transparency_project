# Product

## Register

product

## Platform

web

## Users

The audience is the broad Iowa public, with no single primary persona to optimize for. A casual visitor who wants to look up their own representative and a journalist tracing sponsor relationships should both be served well without the design bending toward either extreme. Most arrive as non-experts: they know the legislature affects them but not how to read a bill number, a roll call, or a committee referral. Their context is incidental and low-commitment — a few minutes prompted by a news story, an election, or a bill they heard about — so the site cannot assume prior knowledge, a return visit, or patience for a learning curve.

This is an umbrella project spanning three domains — the Iowa Legislature (Phase 1, live), Iowa Elections, and Campaign Finance. The same broad-public framing carries across all three as they come online.

## Product Purpose

The project promotes political transparency in Iowa by taking public data that is technically available but practically unusable — scattered across government portals, buried in raw exports, disconnected from related records — and making it genuinely accessible and legible. The current live domain tracks the 91st General Assembly: bills, legislator profiles, voting records, and lobbyist declarations, aggregated from LegiScan and the official legislature site.

Success is broad civic education. Someone should leave understanding something about how their legislature works or what it is doing this session that they could not easily have learned before — whether that is a single fact looked up in seconds or a pattern noticed across datasets. The measure is comprehension gained, not a conversion or a task funnel completed.

## Positioning

Public Iowa political data, made genuinely accessible — and showing how bills, votes, legislators, and money connect. Raw government portals hand you records; this project hands you the relationships between them. Every page should reinforce that the data is both reachable and connected.

## Brand Personality

Neutral, authoritative, and trustworthy. The voice is that of a credible nonpartisan reference: plain, precise, and unhurried, explaining without editorializing. Restraint is doing real work here — impartiality is signaled by what the design refuses to do as much as by what it says. It should read as a civic institution a reasonable person of any political leaning would trust, not as an advocate, a campaign, or a hot take.

## Anti-references

- **Partisan or campaign styling.** No patriotic red-white-blue, flags, star-spangled motifs, or any visual language that reads as taking a side. The party colors exist to label data, never to decorate.
- **Generic SaaS / AI-slop dashboard.** No gradient-accented hero-metric cards, glassmorphism, endless identical icon-heading-text card grids, or the default "an AI made this" aesthetic.
- **Dated government-site drab.** No cluttered official-portal look: cramped gray tables, dead-weight density, absent hierarchy, the feel of a 2008 `.gov` page.
- **Overwhelming data dump.** No wall-of-spreadsheet presentation where every element carries equal weight and a visitor drowns before finding anything.

## Design Principles

Neutrality is a design constraint, not just an editorial one. Color, emphasis, ordering, and copy all have to be defensible as impartial; if a choice could be read as favoring a party or position, it is the wrong choice.

Legible to the newcomer. The default reader does not know the vocabulary, so the interface teaches as it presents — plain language over jargon, context where a term first appears, and complexity revealed progressively rather than dumped up front.

Connections over collections. The reason to exist is showing relationships raw portals never surface — bill groups, voting alignment, lobbyist positions, salience. Favor presentations that reveal how records relate over ones that merely list them.

Trust through restraint. Authority here comes from calm, not from decoration or persuasion. The tool should disappear into the task; a quieter page reads as more credible than a busier one.

Hierarchy over volume. There is a lot of data, and that is never an excuse to show all of it at once. Every screen guides attention to what matters first and lets the rest recede.

## Accessibility & Inclusion

Target WCAG 2.1 AA. As public-interest civic infrastructure for a broad, non-expert audience, the site should meet AA across the board: body text at ≥4.5:1 contrast (and no meaning carried by color alone — party is always labeled, not just tinted), full keyboard navigation, semantic structure and heading order, and a reduced-motion alternative for any animation. The R-generated tables, charts, and maps (`gt`, `reactable`, `ggparliament`, `leaflet`) are the areas most likely to fall short and warrant specific attention.
