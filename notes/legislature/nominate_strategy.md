# NOMINATE Ideological Scoring — Strategy Note

## What It Is

NOMINATE (Nominal Three-Step Estimation) is the standard political science method
for placing legislators in ideological space from roll call votes. The R package
`wnominate` implements it. Produces a coordinate per legislator on 1–2 dimensions;
the first dimension captures the liberal-conservative axis in most legislatures.

## R Implementation Sketch

```r
library(wnominate)
library(pscl)

# Build legislators × votes matrix using pscl vote codes:
#   1 = Yea, 6 = Nay, 9 = Absent/NV
rc_matrix <- ...   # rows = legislators, cols = roll calls

rc <- rollcall(
  rc_matrix,
  yea = 1, nay = 6, missing = 9,
  notInLegis = NA,
  legis.names = legislator_ids
)

result <- wnominate(rc, dims = 2, polarity = c(1, 1))

scores <- tibble(
  people_id = ...,
  coord1 = result$legislators$coord1D,   # -1 (liberal) to +1 (conservative)
  coord2 = result$legislators$coord2D
)

# Save to data/votes/nominate_scores.rds
```

## Key Decisions Before Implementing

- **Polarity legislator**: Must designate one legislator per dimension to fix axis
  orientation so coord1 = -1 is consistently liberal and +1 is conservative.
  A strong-R legislator is a reliable choice for dim1.
- **Minimum votes threshold**: Legislators with very few votes get unreliable
  estimates — filter or flag them.
- **1D vs 2D**: 1D is likely sufficient for Iowa given strong party-line voting.
  2D can surface cross-cutting dimensions (e.g., rural/urban, fiscal/social).

## Output Location

`data/votes/nominate_scores.rds` — tibble with people_id, coord1, coord2,
plus fit statistics (correct classification %, APRE).

## Display Ideas

- **Legislator page**: coord1 on a -1 to +1 bar labeled "More Liberal ←→ More Conservative"
- **Legislators index**: 2D scatter of all legislators colored by party
- **Complement to pairwise similarity**: ideological distance = |coord1_A − coord1_B|

## Relationship to Option 1 (Pairwise Agreement)

- NOMINATE is better for placing a legislator in the full ideological landscape
  and spotting outliers (e.g., moderate Republicans).
- Option 1 pairwise similarity is better for "who does this legislator vote with
  most often" and is more concrete for a general audience.
- The two are complementary — NOMINATE gives ideology, Option 1 gives voting
  coalition membership.

## References

- Poole & Rosenthal (1985) original NOMINATE paper
- `wnominate` R package: https://cran.r-project.org/package/wnominate
- `pscl` R package (rollcall object): https://cran.r-project.org/package=pscl
