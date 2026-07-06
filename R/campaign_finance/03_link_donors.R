# R/campaign_finance/03_link_donors.R
#
# Fuzzy donor deduplication. Identifies donor_key values that refer to the
# same real-world donor (typos, address variants, middle-name variation) and
# produces a crosswalk table mapping every key to a single canonical key.
#
# Depends on: 02_clean_normalize.R (must run first)
# Input:  data/campaign_finance/processed/contributions.parquet
# Output: data/campaign_finance/processed/donor_crosswalk.parquet
#         data/campaign_finance/processed/donor_review.csv  (borderline pairs)
#
# Workflow:
#   1. Run this script — auto-merges high-confidence pairs; writes donor_review.csv
#      for borderline pairs that need a human decision.
#   2. Open donor_review.csv, fill in "merge" or "split" in the `decision` column.
#   3. Re-run — applies manual decisions and rebuilds the crosswalk.
#
# The crosswalk is consumed by 04_build_database.R to resolve donor_key →
# canonical_key in the summary views.

library(arrow)
library(dplyr)
library(tidyr)
library(stringr)
library(stringdist)
library(igraph)
library(readr)
library(scales)
library(here)

source(here("R/campaign_finance/utils.R"))

# ── Configuration ─────────────────────────────────────────────────────────────

# Jaro-Winkler composite score thresholds (0–1 scale).
AUTO_MERGE_THRESHOLD <- 0.95  # at or above: merge automatically
REVIEW_THRESHOLD     <- 0.88  # at or above but below auto: flag for manual review

# Blocking keys:
#   Individuals — 3-char last prefix + 1-char first initial + state.
#   Adding the first initial cuts typical block sizes by ~26x vs last+state alone,
#   which is necessary for common surnames ("SMITH", "JOHNSON", etc.).
#   Organizations — 5-char name prefix.
IND_BLOCK_CHARS <- 3L
ORG_BLOCK_CHARS <- 5L

# Hard cap on donors per block. Blocks larger than this are skipped entirely —
# a block of 200 "SMITH J IA" donors is almost certainly not the same person.
# Raise this if matching quality seems low; lower it if memory is still tight.
MAX_BLOCK_SIZE <- 150L

review_path    <- here("data/campaign_finance/processed/donor_review.csv")
crosswalk_path <- here("data/campaign_finance/processed/donor_crosswalk.parquet")

# ── Load donor profiles ───────────────────────────────────────────────────────

message("Reading contributions.parquet...")
contributions_cols <- read_parquet(
  here("data/campaign_finance/processed/contributions.parquet"),
  col_select = c("donor_key", "donor_type", "norm_last", "norm_first",
                 "norm_org", "norm_city", "norm_state")
)

# One row per unique donor_key; n_transactions used to pick canonical keys.
donor_profiles <- contributions_cols |>
  count(donor_key, donor_type, norm_last, norm_first, norm_org, norm_city, norm_state,
        name = "n_transactions") |>
  filter(!is.na(donor_key), donor_type != "committee")

message(sprintf(
  "  %s unique individual/org donor keys loaded.",
  comma(nrow(donor_profiles))
))

# Committee keys pass through untouched — exact code already deduplicates them.
committee_keys <- contributions_cols |>
  filter(donor_type == "committee") |>
  distinct(donor_key) |>
  pull(donor_key)

# ── Load existing manual decisions ───────────────────────────────────────────

if (file.exists(review_path)) {
  manual_decisions <- read_csv(
    review_path,
    col_types      = cols(.default = col_character()),
    show_col_types = FALSE
  ) |>
    filter(!is.na(decision) & nchar(decision) > 0)
  message(sprintf("  %s manual decisions loaded from donor_review.csv.", nrow(manual_decisions)))
} else {
  manual_decisions <- tibble(donor_key_1 = character(), donor_key_2 = character(),
                              decision = character())
}

# ── Fuzzy matching helpers ────────────────────────────────────────────────────

# Jaro-Winkler similarity (0 = no match, 1 = identical). NA inputs → 0.
jw_sim <- function(a, b) {
  s <- 1 - stringdist(a, b, method = "jw", p = 0.1)
  coalesce(s, 0)
}

# Generate candidate pairs within blocks using combn() — produces only the
# upper triangle (N*(N-1)/2 pairs per block) one block at a time, avoiding
# the N² cross-product that inner_join would create in memory.
block_pairs <- function(df, block_col, key_col, compare_cols) {
  df |>
    select(.key = {{ key_col }}, {{ block_col }}, all_of(compare_cols)) |>
    group_by({{ block_col }}) |>
    filter(n() >= 2L) |>
    nest() |>
    mutate(pairs = lapply(data, function(grp) {
      idx <- combn(nrow(grp), 2L)
      out <- list(
        donor_key_1 = grp$.key[idx[1L, ]],
        donor_key_2 = grp$.key[idx[2L, ]]
      )
      for (col in compare_cols) {
        out[[paste0(col, "_1")]] <- grp[[col]][idx[1L, ]]
        out[[paste0(col, "_2")]] <- grp[[col]][idx[2L, ]]
      }
      as.data.frame(out, stringsAsFactors = FALSE)
    })) |>
    select(-data) |>
    unnest(pairs) |>
    ungroup() |>
    select(-{{ block_col }})
}

# ── Fuzzy matching: individuals ───────────────────────────────────────────────

message("Matching individuals...")

individuals <- donor_profiles |>
  filter(donor_type == "individual",
         !is.na(norm_last), nchar(norm_last) > 0) |>
  mutate(
    first_init = str_sub(coalesce(norm_first, ""), 1L, 1L),
    block_key  = paste(str_sub(norm_last, 1L, IND_BLOCK_CHARS), first_init, norm_state, sep = "_")
  )

ind_skipped <- individuals |> add_count(block_key) |> filter(n > MAX_BLOCK_SIZE)
if (nrow(ind_skipped) > 0) {
  message(sprintf("  Skipping %s donors in %s oversized block(s) (> %d donors each).",
                  comma(nrow(ind_skipped)),
                  comma(n_distinct(ind_skipped$block_key)),
                  MAX_BLOCK_SIZE))
  individuals <- individuals |>
    add_count(block_key) |>
    filter(n <= MAX_BLOCK_SIZE) |>
    select(-n)
}

ind_pairs <- if (nrow(individuals) >= 2) {
  block_pairs(individuals,
              block_col    = block_key,
              key_col      = donor_key,
              compare_cols = c("norm_last", "norm_first", "norm_city")) |>
    mutate(score = jw_sim(norm_last_1,  norm_last_2)  * 0.50 +
                   jw_sim(norm_first_1, norm_first_2) * 0.35 +
                   jw_sim(norm_city_1,  norm_city_2)  * 0.15) |>
    filter(score >= REVIEW_THRESHOLD) |>
    select(donor_key_1, donor_key_2, score)
} else tibble(donor_key_1 = character(), donor_key_2 = character(), score = numeric())

message(sprintf("  %s individual pairs at or above review threshold.", comma(nrow(ind_pairs))))

# ── Fuzzy matching: organizations ─────────────────────────────────────────────

message("Matching organizations...")

organizations <- donor_profiles |>
  filter(donor_type == "organization",
         !is.na(norm_org), nchar(norm_org) > 0) |>
  mutate(block_key = str_sub(norm_org, 1L, ORG_BLOCK_CHARS))

org_skipped <- organizations |> add_count(block_key) |> filter(n > MAX_BLOCK_SIZE)
if (nrow(org_skipped) > 0) {
  message(sprintf("  Skipping %s orgs in %s oversized block(s) (> %d each).",
                  comma(nrow(org_skipped)),
                  comma(n_distinct(org_skipped$block_key)),
                  MAX_BLOCK_SIZE))
  organizations <- organizations |>
    add_count(block_key) |>
    filter(n <= MAX_BLOCK_SIZE) |>
    select(-n)
}

org_pairs <- if (nrow(organizations) >= 2) {
  block_pairs(organizations,
              block_col    = block_key,
              key_col      = donor_key,
              compare_cols = c("norm_org", "norm_city", "norm_state")) |>
    mutate(score = jw_sim(norm_org_1,   norm_org_2)   * 0.70 +
                   jw_sim(norm_city_1,  norm_city_2)  * 0.20 +
                   jw_sim(norm_state_1, norm_state_2) * 0.10) |>
    filter(score >= REVIEW_THRESHOLD) |>
    select(donor_key_1, donor_key_2, score)
} else tibble(donor_key_1 = character(), donor_key_2 = character(), score = numeric())

message(sprintf("  %s organization pairs at or above review threshold.", comma(nrow(org_pairs))))

# ── Classify all candidate pairs ─────────────────────────────────────────────

# Both orderings of a pair may appear in manual_decisions; handle both.
all_pairs <- bind_rows(ind_pairs, org_pairs) |>
  left_join(
    manual_decisions |> select(donor_key_1, donor_key_2, decision),
    by = c("donor_key_1", "donor_key_2")
  ) |>
  left_join(
    manual_decisions |> select(donor_key_1 = donor_key_2, donor_key_2 = donor_key_1,
                                decision_rev = decision),
    by = c("donor_key_1", "donor_key_2")
  ) |>
  mutate(
    decision = coalesce(decision, decision_rev),
    decision = case_when(
      !is.na(decision)              ~ decision,
      score >= AUTO_MERGE_THRESHOLD ~ "merge",
      TRUE                          ~ "pending"
    )
  ) |>
  select(donor_key_1, donor_key_2, score, decision)

n_auto   <- sum(all_pairs$decision == "merge"   & all_pairs$score >= AUTO_MERGE_THRESHOLD)
n_manual <- sum(all_pairs$decision %in% c("merge", "split") &
                  (all_pairs$score < AUTO_MERGE_THRESHOLD | is.na(all_pairs$score)))
n_pending <- sum(all_pairs$decision == "pending")

message(sprintf(
  "  Pairs: %s auto-merge, %s manual decision applied, %s pending review.",
  comma(n_auto), comma(n_manual), comma(n_pending)
))

# ── Write / update review file ────────────────────────────────────────────────

pending_pairs <- all_pairs |>
  filter(decision == "pending") |>
  left_join(
    donor_profiles |> select(donor_key, norm_last, norm_first, norm_org, norm_city, norm_state),
    by = c("donor_key_1" = "donor_key")
  ) |>
  rename(norm_last_1 = norm_last, norm_first_1 = norm_first,
         norm_org_1  = norm_org,  norm_city_1  = norm_city, norm_state_1 = norm_state) |>
  left_join(
    donor_profiles |> select(donor_key, norm_last, norm_first, norm_org, norm_city, norm_state),
    by = c("donor_key_2" = "donor_key")
  ) |>
  rename(norm_last_2 = norm_last, norm_first_2 = norm_first,
         norm_org_2  = norm_org,  norm_city_2  = norm_city, norm_state_2 = norm_state) |>
  mutate(decision = "") |>
  arrange(desc(score)) |>
  select(donor_key_1, donor_key_2, score,
         norm_last_1, norm_first_1, norm_org_1, norm_city_1, norm_state_1,
         norm_last_2, norm_first_2, norm_org_2, norm_city_2, norm_state_2,
         decision)

if (nrow(pending_pairs) > 0) {
  write_csv(pending_pairs, review_path)
  message(sprintf(
    "\n  %s pairs need manual review.\n  Open and fill in 'merge' or 'split' in the decision column:\n  %s\n  Then re-run this script.",
    comma(nrow(pending_pairs)), review_path
  ))
} else {
  if (file.exists(review_path)) file.remove(review_path)
  message("\n  No pairs pending review.")
}

# ── Build crosswalk via connected components ──────────────────────────────────

message("Building donor crosswalk...")

merges <- all_pairs |> filter(decision == "merge")

all_keys <- donor_profiles |> pull(donor_key)

if (nrow(merges) > 0) {
  g <- graph_from_data_frame(
    merges |> select(from = donor_key_1, to = donor_key_2),
    directed = FALSE,
    vertices = data.frame(name = all_keys)
  )
  comp_membership <- components(g)$membership

  manual_merged_keys <- c(
    filter(manual_decisions, decision == "merge")$donor_key_1,
    filter(manual_decisions, decision == "merge")$donor_key_2
  )

  crosswalk <- tibble(
    donor_key = names(comp_membership),
    component = comp_membership
  ) |>
    left_join(
      donor_profiles |> select(donor_key, n_transactions),
      by = "donor_key"
    ) |>
    mutate(n_transactions = coalesce(n_transactions, 0L)) |>
    # Within each component, sort to put the most-used key first; that becomes canonical.
    arrange(component, desc(n_transactions), donor_key) |>
    group_by(component) |>
    mutate(canonical_key = first(donor_key),
           component_size = n()) |>
    ungroup() |>
    mutate(match_type = case_when(
      component_size == 1                    ~ "unique",
      donor_key %in% manual_merged_keys      ~ "manual_merged",
      TRUE                                   ~ "auto_merged"
    )) |>
    select(donor_key, canonical_key, match_type)
} else {
  # No merges: every key is its own canonical key
  crosswalk <- tibble(
    donor_key     = all_keys,
    canonical_key = all_keys,
    match_type    = "unique"
  )
}

# Add committee pass-throughs
crosswalk <- bind_rows(
  crosswalk,
  tibble(donor_key = committee_keys, canonical_key = committee_keys, match_type = "unique")
)

n_merged_auto   <- sum(crosswalk$match_type == "auto_merged")
n_merged_manual <- sum(crosswalk$match_type == "manual_merged")
n_canonical     <- n_distinct(crosswalk$canonical_key)

message(sprintf("  Total donor keys:       %s", comma(nrow(crosswalk))))
message(sprintf("  Canonical donors:       %s", comma(n_canonical)))
message(sprintf("  Keys merged (auto):     %s", comma(n_merged_auto)))
message(sprintf("  Keys merged (manual):   %s", comma(n_merged_manual)))

# ── Write crosswalk ───────────────────────────────────────────────────────────

write_parquet(crosswalk, crosswalk_path)

message(sprintf("\nDone. Crosswalk written to:\n  %s", crosswalk_path))
if (n_pending > 0)
  message("Re-run after completing donor_review.csv to incorporate manual decisions.")
message("Re-run 04_build_database.R to apply the crosswalk to summary views.")
