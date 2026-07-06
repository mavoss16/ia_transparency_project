# 04a_legislator_lobbyist_alignment.R
#
# Computes alignment scores between each legislator and lobbyist clients.
#
# For each (legislator, client) pair:
#   alignment = (bill-votes aligned with client position) /
#               (bill-votes where both have a position)
#
# Aligned:  client "For"     + legislator Yea
#           client "Against" + legislator Nay
# Opposed:  client "For"     + legislator Nay
#           client "Against" + legislator Yea
#
# "Undecided" and "Withdrawn" declarations are excluded.
# Only floor passage votes (desc matching "bill pass") are used.
# Pairs with fewer than MIN_SHARED_BILLS bill-votes are excluded.
#
# Note: a single bill can contribute two bill-votes if it passed both chambers,
# so n_shared counts bill-votes, not unique bills.
#
# Output saved to data/lobbying/legislator_client_alignment.rds
#
# Usage:
#   source("R/data_pipeline/04a_legislator_lobbyist_alignment.R")
#   compute_legislator_lobbyist_alignment()

library(dplyr)
library(readr)
library(purrr)
library(stringr)
library(here)

MIN_SHARED_BILLS <- 5   # minimum bill-votes to report a score
TOP_N            <- 5   # most/least aligned clients to keep per legislator

#' Compute legislator-lobbyist client alignment scores
#'
#' @param records_path  Path to vote records RDS (from 02_process_votes.R)
#' @param lobby_path    Path to lobbyist declarations RDS (from 04_lobbyist_declarations.R)
#' @param people_path   Path to people.csv
#' @param output_path   Path to write output RDS
#' @param min_shared    Minimum shared bill-votes required for a valid score
#' @param top_n         Number of most/least aligned clients to keep per legislator
#' @param verbose       Print progress messages
#' @return Invisible tibble of top-N alignment rows
compute_legislator_lobbyist_alignment <- function(
    records_path = here("data/votes/records_91st_ga.rds"),
    lobby_path   = here("data/lobbying/lobbyist_declarations.rds"),
    people_path  = here("legiscan/files_ga91_derived/people.csv"),
    output_path  = here("data/lobbying/legislator_client_alignment.rds"),
    min_shared   = MIN_SHARED_BILLS,
    top_n        = TOP_N,
    verbose      = TRUE
) {
  # ---------------------------------------------------------------------------
  # 1. Load data
  # ---------------------------------------------------------------------------
  if (verbose) message("Loading data...")

  vote_records <- readRDS(records_path)

  lobby <- readRDS(lobby_path)

  people <- read_csv(people_path, show_col_types = FALSE) |>
    filter(party_id != 0) |>
    select(people_id, name, party, role, district)

  # ---------------------------------------------------------------------------
  # 2. Filter vote records to floor passage Yea/Nay votes
  #    "bill pass" matches "Shall the bill pass?" in vote_desc
  # ---------------------------------------------------------------------------
  if (verbose) message("Filtering to floor passage votes...")

  floor_votes <- vote_records |>
    filter(
      str_detect(vote_desc, "bill pass"),
      vote_text %in% c("Yea", "Nay")
    ) |>
    select(people_id, bill_number, vote_text)

  if (verbose) message(sprintf(
    "  %d floor Yea/Nay votes | %d legislators | %d bills",
    nrow(floor_votes),
    n_distinct(floor_votes$people_id),
    n_distinct(floor_votes$bill_number)
  ))

  # ---------------------------------------------------------------------------
  # 3. Filter lobbyist declarations to For/Against only
  # ---------------------------------------------------------------------------
  lobby_clean <- lobby |>
    filter(most_recent_declaration %in% c("For", "Against"), !is.na(client)) |>
    select(bill, client, declaration = most_recent_declaration)

  if (verbose) message(sprintf(
    "  %d For/Against declarations | %d clients | %d bills",
    nrow(lobby_clean),
    n_distinct(lobby_clean$client),
    n_distinct(lobby_clean$bill)
  ))

  # ---------------------------------------------------------------------------
  # 4. Join votes to declarations on bill number
  # ---------------------------------------------------------------------------
  if (verbose) message("Joining votes to lobbyist declarations...")

  joined <- floor_votes |>
    inner_join(lobby_clean, by = c("bill_number" = "bill"), relationship = "many-to-many") |>
    mutate(
      aligned = (declaration == "For"     & vote_text == "Yea") |
                (declaration == "Against" & vote_text == "Nay")
    )

  if (verbose) message(sprintf(
    "  %d (legislator, client, bill-vote) triples after join",
    nrow(joined)
  ))

  # ---------------------------------------------------------------------------
  # 5. Aggregate by (people_id, client)
  # ---------------------------------------------------------------------------
  if (verbose) message("Computing alignment scores...")

  alignment <- joined |>
    group_by(people_id, client) |>
    summarize(
      n_shared  = n(),
      n_aligned = sum(aligned),
      n_opposed = sum(!aligned),
      .groups = "drop"
    ) |>
    filter(n_shared >= min_shared) |>
    mutate(alignment = n_aligned / n_shared)

  if (verbose) message(sprintf(
    "  %d (legislator, client) pairs with >= %d shared bill-votes",
    nrow(alignment), min_shared
  ))

  # ---------------------------------------------------------------------------
  # 6. Build top-N per legislator (most aligned and most opposed)
  # ---------------------------------------------------------------------------
  if (verbose) message("Building top-N tables...")

  leg_ids <- unique(alignment$people_id)

  top_n_rows <- map_dfr(leg_ids, function(pid) {
    base <- alignment |> filter(people_id == pid)

    most_aligned <- base |>
      arrange(desc(alignment), desc(n_shared)) |>
      slice_head(n = top_n) |>
      mutate(rank_type = "most_aligned", rank = row_number())

    most_opposed <- base |>
      arrange(alignment, desc(n_shared)) |>
      slice_head(n = top_n) |>
      mutate(rank_type = "most_opposed", rank = row_number())

    bind_rows(most_aligned, most_opposed)
  })

  # Join legislator display info
  result <- top_n_rows |>
    left_join(
      people |> select(people_id, name, party, role, district),
      by = "people_id"
    )

  # ---------------------------------------------------------------------------
  # 7. Save
  # ---------------------------------------------------------------------------
  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(result, output_path)

  if (verbose) {
    message(sprintf("Saved %d rows to %s", nrow(result), output_path))
    message("Done!")
  }

  invisible(result)
}

# Run if executed directly
if (sys.nframe() == 0) {
  compute_legislator_lobbyist_alignment()
}
