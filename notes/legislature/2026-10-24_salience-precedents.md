# Session Notes — 2026-10-24

## Salience score — published precedents

Follow-up to `2026-05-17_salience-score.md`, whose "Similar measures" section
concluded the approach was novel and lacked an external validity check. Goal of
this pass: find published measures the score can cite, so it reads as built on
established methods rather than entirely our own construction.

**Bottom line:** no one publishes a bill-level salience score for Iowa, but two
published measures are directly adoptable, and the federal literature supports
the composite structure itself.

---

## Directly adoptable

### 1. State Legislative Effectiveness Scores (SLES)

Bucchianeri, Volden & Wiseman, "Legislative Effectiveness in the American
States," *American Political Science Review* 119(1), 2025. Scores
*legislators*, but classifies every bill to do so, and **covers Iowa**.

- **Significance tiers:**
  - *Commemorative (C):* names or renames a site or building, or commemorates a person or date
  - *Substantive and Significant (SS):* mentioned in a prominent state newspaper
  - *Substantive (S):* everything else; also used when a bill qualifies as both C and SS
- **Weights:** C = 1, S = 5, SS = 10.
- **Stages:** introduced (BILL), action in committee (AIC), action beyond
  committee (ABC), passed home chamber (PASS), became law (LAW).
- **SS coding:** automated regex extraction of bill-number mentions from one
  newspaper per state (LexisNexis / Newsbank). Iowa's paper is the **Dubuque
  *Telegraph Herald*** (flagged as a smaller outlet, used because the larger
  papers lacked consistent archive coverage). Iowa got custom regex adjustments
  for its bill-numbering style.
- **Validation:** hand-coding in NC / VA / TX found the automated process and
  the RAs each caught ~70% of the other's significant bills.
- **Iowa-specific:** committee bills are attributed to the floor manager as sponsor.

**Use for us:** a citable significance classification and a stage-progression
scale, replacing the binary `floor_vote` component. Their significance signal is
**news coverage**, which our score lacks entirely.

### 2. UHERO "Heat Score"

Gordner & Moore, "Consensus and conflict: a data-driven look at the biggest
bills in Hawaii's 2025 legislature," UHERO (University of Hawaiʻi), 2025-08-28.
Labeled preliminary; a policy-center post, not peer-reviewed.

- **Data:** lobbyist testimony positions (support / oppose / comment), which
  are structurally like Iowa's lobbyist declarations.
- **"Biggest" bills:** ranked by total position volume; their chart shows bills with 10+ positions.
- **Heat Score:** the share of organizations taking the minority position, so 0
  is full agreement and 0.5 an even split. "Comment" counts as non-support.
  - Cool Consensus: HS < 0.10 (78% of bills)
  - Warm Mix: 0.10–0.30 (8%)
  - Hotly Contested: 0.30–0.50 (14%)
- Gaps: no exact formula published, and cutoffs and dedup of multi-position orgs aren't explained.

**Use for us:** a citable replacement for `comp_lobby_opposition`
(`against / (for + against)`). That component is directional: 1 against / 0 for
scores the full 20 points, while 10 for / 0 against scores 0. Heat Score is
symmetric and measures contestation, not opposition, which also fits the
PRODUCT.md neutrality principle. We still have to decide how Undecided
declarations count (UHERO treats comments as non-support).

---

## Supporting literature

- **Combining several imperfect indicators.** Clinton & Lapinski, "Measuring
  Legislative Accomplishment, 1877–1994," *AJPS* 50(1), 2006: an item-response
  model estimating the significance of every public statute from multiple
  indicators, with standard errors. Howell, Adler, Cameron & Riemann, "Divided
  Government and the Legislative Productivity of Congress, 1945–94," *LSQ*
  25(2), 2000: a four-tier significance measure across 17,663 public laws,
  extending Mayhew's landmark list. Both support the *structure* of a
  composite; both derive the weighting from data, whereas ours is hand-set.
- **News coverage as the standard salience test.** Epstein & Segal, "Measuring
  Issue Salience," *AJPS* 44, 2000: NYT front-page coverage as salience for
  Supreme Court cases, later critiqued as coarse (dichotomous; front-page space
  shrinking). With SLES this makes news mentions the obvious validation target.
- **Bill length = detail/complexity, not importance.** Huber & Shipan,
  *Deliberate Discretion* (2002): longer statutes carry more policy detail and
  constrain agencies. Bussing, Howard & Lerner (2024) criticize length as an
  overly simple complexity proxy. Count words, not pages (page counts overstate
  length because of whitespace). Defensible as a "scope" signal, not as importance by itself.
- **Lobbying volume as salience.** Baumgartner et al., *Lobbying and Policy
  Change* (2009) and the Advocacy & Public Policy project treat advocate
  mobilization as an issue-salience signal. Exact measurement not verified from
  online sources.
- **Iowa's disclosure is unusual.** Reinvent Albany's 2026 survey of other
  states: Wisconsin and Nebraska also require bill positions, but Iowa's
  declarations database (client, position, date per bill) is the most usable for
  a conflict measure.

## Not precedent

- **Passage prediction:** FiscalNote/PolicyNote bill forecasts, Smith Moses
  passage likelihood, and the Atlanta Journal-Constitution's Georgia tool all
  predict *whether a bill passes*, a different question.
- **Advocacy scorecards** (ACLU CA, CJAC, Courage Score): score legislators on
  hand-picked bills.

---

## Implications for the design

Candidate attribution line:

> Bill significance tiers and stage progression follow the State Legislative
> Effectiveness Scores (Bucchianeri, Volden & Wiseman 2025); lobbying
> contestation follows UHERO's Heat Score (Gordner & Moore 2025).

That covers roughly 70% of the current weight with cited methods.

Open directions (nothing decided):

1. **Replace `lobby_opposition` with Heat Score** and decide how Undecided counts.
2. **Replace binary `floor_vote` with SLES stages** (BILL → AIC → ABC → PASS → LAW).
3. **Adopt the commemorative tier.** Detect naming/honorary bills and
   resolutions and down-weight them.
4. **News mentions.** Count bill-number mentions ("HF 948") in Iowa Capital
   Dispatch / Des Moines Register. This gives the SLES SS tier by their own
   method *and* the external validation the May note said was missing.
5. **Two scores, not one** (from the 2026-10-24 discussion): *contested*
   (Heat Score, party division, hearings, amendments) vs *consequential*
   (sections/length, fiscal dollars, stage reached). Used for ordering and
   "most contested" lists, not shown as a number.

Related findings from the same session:
- `05` checks `type == "Fiscal Note"` exactly and misses the 226
  `"Fiscal Note/Analysis"` supplements (622 fiscal supplements across 239 bills).
- `text_size` (bytes, includes HTML) is in the LegiScan JSON for every text
  version, so it's a free length proxy. Section counts need the `state_link` HTML.
- Fiscal note PDFs (`legis.iowa.gov/docs/publications/FN/…`) may yield dollar
  figures via `pdftools`. Format consistency not yet checked.
- Salience scores are **not displayed anywhere on the site**, and neither is
  the `04a` alignment output.

---

## Sources

- Bucchianeri, Volden & Wiseman, [working paper PDF](https://thelawmakers.org/wp-content/uploads/2024/01/BVW_SLES_Jan2024.pdf) · [APSR 2025 listing](https://ideas.repec.org/a/cup/apsrev/v119y2025i1p21-39_3.html) · [Center for Effective Lawmaking project page](https://thelawmakers.org/legislative-research/legislative-effectiveness-in-the-american-states)
- Gordner & Moore, [Consensus and conflict, UHERO 2025](https://uhero.hawaii.edu/consensus-and-conflict-a-data-driven-look-at-the-biggest-bills-in-hawaiis-2025-legislature/)
- Clinton & Lapinski 2006, [AJPS (PDF)](https://cdn.vanderbilt.edu/vu-my/wp-content/uploads/sites/349/2011/10/14093745/CL_AJPS2006.pdf)
- Howell, Adler, Cameron & Riemann 2000, [LSQ](https://collaborate.princeton.edu/en/publications/divided-government-and-the-legislative-productivity-of-congress-1/)
- Epstein & Segal, [Measuring Issue Salience](https://epstein.usc.edu/salience)
- Bussing, Howard & Lerner 2024, [PDF](https://priceschool.usc.edu/wp-content/uploads/2024/12/Bussing-Howard-and-Lerner.pdf) · [Huber & Shipan reading notes](https://adambrown.info/p/notes/huber_and_shipan_deliberate_discretion)
- Baumgartner et al., [Advocacy & Public Policy issue-level codebook](https://fbaum.unc.edu/lobby/_documentation/data/Issue_level_codebook_24_August_2010.pdf)
- Reinvent Albany, [Lobbying support/oppose disclosure in other states (2026)](https://reinventalbany.org/wp-content/uploads/2026/04/Lobbying-Support_Oppose-Other-States-Research-April-28-2026.pdf)
- [FiscalNote bill forecasts](https://fiscalnote.com/blog/bill-forecasts-policynote-feature) · [Smith Moses methodology](https://www.smithmoses.com/methodology)
