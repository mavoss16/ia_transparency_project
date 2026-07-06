# 02b_legislator_similarity.R
#
# Computes pairwise vote agreement rates between all legislators.
#
# For each pair (A, B):
#   similarity = (votes where both voted the same) / (votes where both participated)
#
# Only floor votes (Yea/Nay) count; Absent/NV are treated as non-participation.
# Pairs sharing fewer than MIN_SHARED_VOTES get NA rather than an unreliable score.
#
# Outputs saved to data/votes/:
#   similarity_top_n.rds    — per-legislator top-N most similar, overall and cross-party
#   similarity_matrix.rds   — full n_leg × n_leg named matrix (for future comparison tool)
#   pair_lookup.rds         — flat table of all valid pairs with agree/disagree counts (for compare page)
#
# Usage:
#   source("R/data_pipeline/02b_legislator_similarity.R")
#   compute_legislator_similarity()

library(dplyr)
library(tidyr)
library(readr)
library(purrr)
library(stringr)
library(here)

MIN_SHARED_VOTES  <- 20   # minimum shared votes to report a similarity score
TOP_N_OVERALL     <- 5    # most similar legislators to keep per person
TOP_N_CROSS_PARTY <- 5    # most similar from opposite party to keep per person
TOP_N_LEAST       <- 5    # least similar legislators to keep per person

#' Compute pairwise legislator similarity from vote records
#'
#' @param records_path Path to vote_records RDS (from 02_process_votes.R)
#' @param people_path  Path to people.csv
#' @param output_dir   Directory to write output RDS files
#' @param min_shared   Minimum shared votes required for a valid score
#' @param top_n        Number of most-similar to keep (overall)
#' @param top_n_cross  Number of most-similar to keep (cross-party)
#' @param verbose      Print progress messages
#' @return Invisible list with similarity_matrix and top_n tibble
compute_legislator_similarity <- function(
    records_path = here("data/votes/records_91st_ga.rds"),
    people_path  = here("legiscan/files_ga91_derived/people.csv"),
    output_dir   = here("data/votes"),
    min_shared   = MIN_SHARED_VOTES,
    top_n        = TOP_N_OVERALL,
    top_n_cross  = TOP_N_CROSS_PARTY,
    top_n_least  = TOP_N_LEAST,
    verbose      = TRUE
) {
  # ---------------------------------------------------------------------------
  # 1. Load data
  # ---------------------------------------------------------------------------
  if (verbose) message("Loading vote records and people data...")

  vote_records <- readRDS(records_path)

  people <- read_csv(people_path, show_col_types = FALSE) |>
    filter(party_id != 0) |>
    select(people_id, name, party, role, district)

  # Floor votes only, Yea/Nay only
  votes_binary <- vote_records |>
    filter(vote_text %in% c("Yea", "Nay")) |>
    select(people_id, roll_call_id, vote_text) |>
    mutate(vote_num = if_else(vote_text == "Yea", 1L, 0L))

  if (verbose) {
    message(sprintf(
      "  %d Yea/Nay votes | %d legislators | %d roll calls",
      nrow(votes_binary),
      n_distinct(votes_binary$people_id),
      n_distinct(votes_binary$roll_call_id)
    ))
  }

  # ---------------------------------------------------------------------------
  # 2. Build wide vote matrix (legislators × roll calls)
  #    Values: 1 = Yea, 0 = Nay, NA = absent/NV
  # ---------------------------------------------------------------------------
  if (verbose) message("Building vote matrix...")

  vote_wide <- votes_binary |>
    select(people_id, roll_call_id, vote_num) |>
    pivot_wider(names_from = roll_call_id, values_from = vote_num)

  leg_ids <- vote_wide$people_id
  M <- as.matrix(vote_wide[, -1])
  rownames(M) <- as.character(leg_ids)

  # ---------------------------------------------------------------------------
  # 3. Compute pairwise agreement via matrix multiplication
  #    agree[i,j]  = # roll calls where both voted the same (both Yea or both Nay)
  #    shared[i,j] = # roll calls where both cast a Yea or Nay vote
  #    similarity  = agree / shared
  # ---------------------------------------------------------------------------
  if (verbose) message("Computing pairwise agreement matrix...")

  M_yea   <- (!is.na(M) & M == 1L) * 1L
  M_nay   <- (!is.na(M) & M == 0L) * 1L
  M_voted <- (!is.na(M)) * 1L

  agree_mat  <- M_yea %*% t(M_yea) + M_nay %*% t(M_nay)
  shared_mat <- M_voted %*% t(M_voted)

  sim_mat <- agree_mat / shared_mat

  # Mask unreliable pairs and self-comparisons
  sim_mat[shared_mat < min_shared] <- NA_real_
  diag(sim_mat) <- NA_real_

  valid_pairs <- sum(!is.na(sim_mat)) / 2L
  if (verbose) message(sprintf("  %d valid legislator pairs (min %d shared votes)",
                               valid_pairs, min_shared))

  # ---------------------------------------------------------------------------
  # 4. Save full similarity matrix
  # ---------------------------------------------------------------------------
  sim_matrix_path <- file.path(output_dir, "similarity_matrix.rds")
  saveRDS(sim_mat, sim_matrix_path)
  if (verbose) message(sprintf("  Saved %dx%d similarity matrix to %s",
                               nrow(sim_mat), ncol(sim_mat), sim_matrix_path))

  # ---------------------------------------------------------------------------
  # 4b. Save flat pair lookup for the legislator compare page
  #     One row per valid pair (upper triangle only to avoid duplicates)
  # ---------------------------------------------------------------------------
  valid_upper <- !is.na(sim_mat) & upper.tri(sim_mat)
  idx <- which(valid_upper, arr.ind = TRUE)

  pair_lookup <- tibble(
    people_id_a = as.integer(rownames(sim_mat)[idx[, 1]]),
    people_id_b = as.integer(rownames(sim_mat)[idx[, 2]]),
    similarity  = sim_mat[idx],
    n_shared    = as.integer(shared_mat[idx]),
    n_agree     = as.integer(agree_mat[idx]),
    n_disagree  = as.integer(shared_mat[idx] - agree_mat[idx])
  )

  pair_lookup_path <- file.path(output_dir, "pair_lookup.rds")
  saveRDS(pair_lookup, pair_lookup_path)
  if (verbose) message(sprintf("  Saved %d valid pairs to %s",
                               nrow(pair_lookup), pair_lookup_path))

  # ---------------------------------------------------------------------------
  # 5. Build per-legislator top-N tibble
  # ---------------------------------------------------------------------------
  if (verbose) message("Building per-legislator top-N tables...")

  party_lookup <- people |>
    filter(people_id %in% leg_ids) |>
    select(people_id, party)

  # Helper: generate URL-safe legislator filename for linking
  make_filename <- function(pid, ppl) {
    person <- ppl[ppl$people_id == pid, ]
    if (nrow(person) == 0) return(as.character(pid))
    prefix <- if (person$role[1] == "Sen") "sen" else "rep"
    first  <- str_replace_all(tolower(person$name[1]), "[^a-z0-9]+", "-")
    # Split on last hyphen segment for last name
    parts  <- str_split(first, "-")[[1]]
    paste0(prefix, "-", first, "-", pid)
  }

  top_n_rows <- map_dfr(leg_ids, function(pid) {
    pid_chr <- as.character(pid)
    scores  <- sim_mat[pid_chr, ]
    shared  <- shared_mat[pid_chr, ]
    other_ids <- as.integer(names(scores))

    base <- tibble(
      people_id_a = pid,
      people_id_b = other_ids,
      similarity  = as.numeric(scores),
      n_shared    = as.integer(shared)
    ) |>
      filter(!is.na(similarity))

    # Overall top-N
    overall <- base |>
      arrange(desc(similarity)) |>
      slice_head(n = top_n) |>
      mutate(rank_type = "overall", rank = row_number())

    my_party <- party_lookup$party[party_lookup$people_id == pid]

    # Cross-party top-N (most similar from opposite party)
    cross <- if (length(my_party) > 0) {
      opp_ids <- party_lookup$people_id[party_lookup$party != my_party]
      base |>
        filter(people_id_b %in% opp_ids) |>
        arrange(desc(similarity)) |>
        slice_head(n = top_n_cross) |>
        mutate(rank_type = "cross_party", rank = row_number())
    } else {
      tibble()
    }

    # Least similar overall
    least_overall <- base |>
      arrange(similarity) |>
      slice_head(n = top_n_least) |>
      mutate(rank_type = "least_overall", rank = row_number())

    # Least similar within own party
    least_own <- if (length(my_party) > 0) {
      own_ids <- party_lookup$people_id[party_lookup$party == my_party]
      base |>
        filter(people_id_b %in% own_ids) |>
        arrange(similarity) |>
        slice_head(n = top_n_least) |>
        mutate(rank_type = "least_own_party", rank = row_number())
    } else {
      tibble()
    }

    bind_rows(overall, cross, least_overall, least_own)
  })

  # Join display info for both legislators in each pair
  leg_info <- people |>
    filter(people_id %in% leg_ids) |>
    mutate(filename = map_chr(people_id, make_filename, ppl = pick(everything())))

  top_n_final <- top_n_rows |>
    left_join(
      leg_info |> rename_with(~paste0(.x, "_a"), -people_id) |>
        rename(people_id_a = people_id),
      by = "people_id_a"
    ) |>
    left_join(
      leg_info |> rename_with(~paste0(.x, "_b"), -people_id) |>
        rename(people_id_b = people_id),
      by = "people_id_b"
    )

  top_n_path <- file.path(output_dir, "similarity_top_n.rds")
  saveRDS(top_n_final, top_n_path)

  if (verbose) {
    message(sprintf("  Saved top-N to %s (%d rows)", top_n_path, nrow(top_n_final)))
    message("Done!")
  }

  invisible(list(
    similarity_matrix = sim_mat,
    top_n = top_n_final,
    pair_lookup = pair_lookup
  ))
}

# Run if executed directly
if (sys.nframe() == 0) {
  compute_legislator_similarity()
}
