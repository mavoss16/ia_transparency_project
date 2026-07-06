# Session Notes — 2026-05-17

## Salience score — initial implementation

Built an exploratory bill salience index (`R/data_pipeline/05_salience_scores.R`) that
produces a 0–100 score for every bill in the 91st GA. Output saved to
`data/bills/salience_scores.rds`.

### Architecture

Scores are computed at the **bill group level**, not the individual bill level.
All signals (hearings, lobbyists, amendments, floor votes) are pooled across
companion bills in the same group before scoring, so a hearing on HF948 and a
hearing on SF615 count as two hearings for the Medicaid work requirements fight
rather than one each. Each bill in a group receives the same score.

Individual-bill hearing and amendment counts are preserved as
`n_hearings_this_bill` / `n_amendments_this_bill` for display purposes.

### Components and weights

| Component          | Weight | Source                                      |
|--------------------|--------|---------------------------------------------|
| Lobby volume       | 0.20   | Unique clients per group (log-scaled, cap 15) |
| Lobby opposition   | 0.20   | Against / (For + Against) among declared    |
| Floor vote         | 0.15   | Any group member received a floor vote      |
| Party division     | 0.15   | Most contested vote: Party Line=1.0 → Unanimous=0.0 |
| Hearings           | 0.12   | Sum across group, normalized at 3           |
| Amendments         | 0.08   | Filed amendments from history text (JSON amendments[] is empty for GA91) |
| Fiscal note        | 0.05   | Any group member has a fiscal note supplement |
| Co-sponsors        | 0.03   | Sum of position>1 sponsors across group     |
| Companions         | 0.02   | Group size − 1, normalized at 4             |

### Lobbyist deduplication

Lobbyists are deduplicated by client across all bills in the group: a client
who filed declarations on both HF948 and SF615 is counted once, with their
most recent declaration taken as the position. This is handled by
`group_by(bill_group_id, client) |> slice_max(order_by = date, n = 1)`.

### Top 10 groups (as of 2026-05-17)

| Rank | Lead bill | Score | Group size | Lobbyists | Hearings | Subject |
|------|-----------|-------|------------|-----------|----------|---------|
| 1  | SF2201  | 95.5 | 2 | 15 (0 for, 10 against) | 5 | School funding FY2026 |
| 2  | HF948   | 95.3 | 5 | 63 (4 for, 43 against) | 8 | Medicaid work requirements |
| 3  | HF2327  | 91.5 | 4 | 18 (2 for, 6 against)  | 6 | Workforce development |
| 4  | SF512   | 90.0 | 2 | 14 (0 for, 3 against)  | 6 | Civil statutes of limitations |
| 5  | HF319   | 89.8 | 4 | 16 (3 for, 6 against)  | 4 | School funding FY2025 |
| 6  | HF852   | 87.6 | 4 | 58 (21 for, 26 against) | 5 | Pharmacy benefit managers |
| 7  | HF2711  | 87.3 | 2 | 22 (3 for, 16 against) | 5 | Race/gender requirements in state programs |
| 8  | SF579   | 87.3 | 2 | 12 (1 for, 2 against)  | 7 | Iowa Civil Rights Act / local commissions |
| 9  | SF378   | 87.1 | 2 | 10 (0 for, 1 against)  | 7 | Default speed limit increase |
| 10 | HF722   | 87.0 | 5 | 57 (8 for, 8 against)  | 9 | Workforce / unemployment insurance |

Notable: school funding appears twice (FY2025 and FY2026), reflecting its
annual recurrence. The Medicaid group is the clear outlier in raw lobbying
volume. HF852 (pharmacy benefit managers) is the most genuinely contested by
lobbyist position: 21 for vs. 26 against out of 58 total.

---

## Open questions and future work

### 1. Lobbyist counting in groups

Current approach (deduplicate by client, take most recent declaration) is
correct for counting unique organized interests. One unresolved nuance: a
client who declared "For" on an early study bill and "Against" on the final
version — taking the most recent declaration handles position drift, but
doesn't capture that they engaged across the full arc of the bill. Low
priority for now.

### 2. Weighting

Current weights are judgment calls, not empirically derived. Things worth
revisiting:

- **Lobby volume (0.20)** may overweight sheer number of registrants relative
  to how contested the bill actually is. HF722 (workforce/UI) has 57 lobbyists
  but 41 are undecided — that looks more like monitoring than opposition.
  Consider separating "contested" lobbyist signal (For + Against) from "watched"
  signal (Undecided), and weighting them differently.

- **Floor vote (0.15)** is binary — being passed by one chamber gets the same
  credit as being signed by the Governor. Could replace with a progression
  score (introduced → committee → floor → passed one chamber → signed).

- **Party division (0.15)** is only populated for the ~15% of bills that reach
  a floor vote. Its effective contribution is small. Could boost weight if
  floor vote occurred, or fold it into the floor vote component as a modifier.

- **Companions (0.02)** may be too low to matter — consider dropping or
  absorbing into group_size normalization elsewhere.

### 3. Similar measures for state legislation

Existing approaches in the literature and practice:

- **Legislative Effectiveness Score (LES)** — Volden & Wiseman (2014, and
  extended to states). Measures *legislator* effectiveness by tracking how many
  of their introduced bills advance through stages (committee, floor, passage).
  Not a bill-level salience measure, but the most widely cited quantitative
  framework for state legislative activity. Available for several state
  legislatures. Not directly comparable — it's about sponsor productivity, not
  bill importance.

- **MapLight** — tracks money and lobbying positions on bills, primarily
  federal and California. Closest in spirit to our lobbyist opposition signal.
  Not available for Iowa.

- **FiscalNote / Quorum** — commercial platforms that score bill "momentum"
  using progression speed, co-sponsor count, and committee referrals. Proprietary.

- **OpenStates** — aggregates state legislative data but provides no salience
  or importance scores.

- **Policy agendas / issue salience** — comparative politics tradition uses
  survey-based or media-coverage-based salience measures (e.g., percentage of
  public naming an issue as "most important"). Not operationalizable from
  legislative data alone.

- **News coverage proxies** — Grimmer & Stewart (2013) and others use text
  analysis of congressional records and media mentions as salience proxies.
  Would require scraping Iowa news sources, which is out of scope for now.

- **Iowa-specific**: no public scoring system found for Iowa state legislation.
  The Iowa Legislature's own website shows lobbyist declarations and bill
  history but no composite importance metric.

**Takeaway**: our approach is novel at the state level. The closest precedent
is MapLight's lobbyist-position framework combined with LES-style progression
tracking, but neither exists for Iowa. The main thing missing relative to the
academic literature is an external validity check — ideally you'd validate
against expert ratings or news coverage intensity for a sample of bills.
