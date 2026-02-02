#' Process LegiScan Vote Data
#'
#' This script processes raw LegiScan data to create vote summaries,
#' individual vote records with party alignment, and legislator statistics.
#'
#' Outputs:
#'   - data/vote_summaries_91st_ga.rds: Roll call level summaries with classification
#'   - data/vote_records_91st_ga.rds: Individual votes with party alignment
#'   - data/legislator_voting_stats_91st_ga.rds: Per-legislator voting statistics
#'
#' Usage:
#'   source("R/data_pipeline/02_process_votes.R")
#'   # Or call process_votes() directly

library(here)

# Source the vote analysis functions
source(here("R/data_pipeline/vote_analysis.R"))


# Configuration -----------------------------------------------------------

LEGISCAN_CSV_DIR <- here("legiscan/files_ga91")
LEGISCAN_JSON_DIR <- here("legiscan/files_ga91_json")
OUTPUT_DIR <- here("data")

# Ensure output directory exists
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}


# Main Processing Function ------------------------------------------------

#' Process all vote data and create output files
#'
#' @param csv_dir Directory containing LegiScan CSV files
#' @param json_dir Directory containing LegiScan JSON files
#' @param output_dir Directory for output RDS files
#' @param verbose Print progress messages
#' @return List of processed data frames (invisibly)
process_votes <- function(
    csv_dir = LEGISCAN_CSV_DIR,
    json_dir = LEGISCAN_JSON_DIR,
    output_dir = OUTPUT_DIR,
    verbose = TRUE, 
    only_floor_votes = TRUE
) {

  if (verbose) message("Loading data...")

  # Load raw data
  people <- load_people_data(file.path(csv_dir, "people.csv"))
  votes <- load_votes_data(file.path(csv_dir, "votes.csv"))
  bills <- load_bills_data(file.path(csv_dir, "bills.csv"))
  roll_calls <- load_roll_call_metadata(file.path(json_dir, "vote"))
  
  if(only_floor_votes == TRUE){
    roll_calls <- roll_calls |> filter(!str_detect(vote_desc, "Report$"))
    votes <- votes |> filter(roll_call_id %in% roll_calls$roll_call_id)
  }

  if (verbose) {
    message(sprintf("  - %d legislators loaded", nrow(people)))
    message(sprintf("  - %d individual votes loaded", nrow(votes)))
    message(sprintf("  - %d bills loaded", nrow(bills)))
    message(sprintf("  - %d roll calls loaded", nrow(roll_calls)))
  }


  # Process votes
  if (verbose) message("Processing vote data...")

  # Aggregate party votes
  party_votes <- aggregate_party_votes(votes, people)

  # Create roll call summaries
  vote_summaries <- summarize_roll_calls(votes, people, roll_calls, bills)

  # Create individual vote records with party alignment
  vote_records <- create_vote_records(votes, people, party_votes)

  # Create legislator statistics
  legislator_stats <- summarize_legislator_voting(vote_records)


  # Add roll call metadata to vote records
  vote_records <- vote_records |>
    left_join(
      roll_calls |> select(roll_call_id, bill_id, vote_date, vote_desc),
      by = "roll_call_id"
    ) |>
    left_join(
      bills |> select(bill_id, bill_number),
      by = "bill_id"
    )


  if (verbose) {
    message("Vote classification summary:")
    outcome_summary <- summarize_vote_outcomes(vote_summaries)
    for (i in seq_len(nrow(outcome_summary))) {
      message(sprintf(
        "  - %s: %d (%.1f%%)",
        outcome_summary$vote_outcome[i],
        outcome_summary$count[i],
        outcome_summary$pct[i]
      ))
    }
  }


  # Write output files
  if (verbose) message("Writing output files...")

  write_rds(vote_summaries, file.path(output_dir, "vote_summaries_91st_ga.rds"))
  write_rds(vote_records, file.path(output_dir, "vote_records_91st_ga.rds"))
  write_rds(legislator_stats, file.path(output_dir, "legislator_voting_stats_91st_ga.rds"))

  if (verbose) {
    message("Output files written to:")
    message(sprintf("  - %s", file.path(output_dir, "vote_summaries_91st_ga.rds")))
    message(sprintf("  - %s", file.path(output_dir, "vote_records_91st_ga.rds")))
    message(sprintf("  - %s", file.path(output_dir, "legislator_voting_stats_91st_ga.rds")))
    message("Done!")
  }

  invisible(list(
    vote_summaries = vote_summaries,
    vote_records = vote_records,
    legislator_stats = legislator_stats,
    people = people,
    bills = bills
  ))
}


# Utility Functions -------------------------------------------------------

#' Get voting statistics for a specific legislator
#'
#' @param people_id LegiScan people_id
#' @param vote_records Vote records data frame
#' @param legislator_stats Legislator stats data frame
#' @return List with summary and detailed vote records
get_legislator_votes <- function(people_id, vote_records, legislator_stats) {
  summary <- legislator_stats |>
    filter(people_id == !!people_id)

  records <- vote_records |>
    filter(people_id == !!people_id) |>
    arrange(desc(vote_date))

  # Votes against party
  against_party <- records |>
    filter(vote_with_party == FALSE)

  list(
    summary = summary,
    records = records,
    against_party = against_party
  )
}


#' Get vote breakdown for a specific roll call
#'
#' @param roll_call_id LegiScan roll_call_id
#' @param vote_records Vote records data frame
#' @param vote_summaries Vote summaries data frame
#' @return List with summary and individual votes
get_roll_call_detail <- function(roll_call_id, vote_records, vote_summaries) {
  summary <- vote_summaries |>
    filter(roll_call_id == !!roll_call_id)

  individual_votes <- vote_records |>
    filter(roll_call_id == !!roll_call_id) |>
    arrange(party, name)

  # Who voted against their party?
  rebels <- individual_votes |>
    filter(vote_with_party == FALSE)

  list(
    summary = summary,
    individual_votes = individual_votes,
    rebels = rebels
  )
}


#' Find legislators who most frequently vote against their party
#'
#' @param legislator_stats Legislator stats data frame
#' @param min_votes Minimum votes to be included
#' @param top_n Number of legislators to return
#' @return Tibble of most independent legislators
find_independent_voters <- function(legislator_stats, min_votes = 10, top_n = 20) {
  legislator_stats |>
    filter(total_votes >= min_votes) |>
    mutate(
      against_party_pct = 1 - with_party_pct
    ) |>
    arrange(desc(against_party_pct)) |>
    head(top_n) |>
    select(
      name, party, chamber, district,
      total_votes, votes_against_party, against_party_pct, with_party_pct
    )
}


#' Find the most contentious votes (most "rebels")
#'
#' @param vote_records Vote records data frame
#' @param vote_summaries Vote summaries data frame
#' @param top_n Number of votes to return
#' @return Tibble of most contentious votes
find_contentious_votes <- function(vote_records, vote_summaries, top_n = 20) {
  # Count rebels per roll call
  rebel_counts <- vote_records |>
    filter(vote_with_party == FALSE) |>
    group_by(roll_call_id) |>
    summarize(
      rebel_count = n(),
      dem_rebels = sum(party_abbr == "dem"),
      gop_rebels = sum(party_abbr == "gop"),
      .groups = "drop"
    )

  vote_summaries |>
    left_join(rebel_counts, by = "roll_call_id") |>
    filter(!is.na(rebel_count)) |>
    arrange(desc(rebel_count)) |>
    head(top_n) |>
    select(
      roll_call_id, bill_number, title, vote_date, vote_desc,
      vote_outcome, passed, rebel_count, dem_rebels, gop_rebels
    )
}


#' Summarize voting patterns by chamber
#'
#' @param vote_summaries Vote summaries data frame
#' @return Tibble of vote outcome counts by chamber
summarize_by_chamber <- function(vote_summaries) {
  vote_summaries |>
    group_by(chamber, vote_outcome) |>
    summarize(
      count = n(),
      passed = sum(passed, na.rm = TRUE),
      .groups = "drop"
    ) |>
    group_by(chamber) |>
    mutate(
      pct = count / sum(count) * 100
    ) |>
    ungroup() |>
    arrange(chamber, desc(count))
}


# Run if executed directly ------------------------------------------------

if (sys.nframe() == 0) {
  # Script is being run directly (not sourced)
  result <- process_votes()
}
