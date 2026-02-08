#' Vote Analysis Functions for LegiScan Data
#'
#' Modular functions for analyzing legislative voting patterns,
#' party alignment, and vote classification.

library(dplyr)
library(tidyr)
library(readr)
library(purrr)
library(jsonlite)
library(stringr)


# Core Classification Functions -------------------------------------------

#' Classify a vote outcome based on party vote counts
#'
#' @param dem_yes Number of Democrats voting yes
#' @param dem_no Number of Democrats voting no
#' @param gop_yes Number of Republicans voting yes
#' @param gop_no Number of Republicans voting no
#' @return Character string classification
classify_vote_outcome <- function(dem_yes, dem_no, gop_yes, gop_no) {
  # Handle NA values

  dem_yes <- replace_na(dem_yes, 0)
  dem_no <- replace_na(dem_no, 0)
  gop_yes <- replace_na(gop_yes, 0)
  gop_no <- replace_na(gop_no, 0)

  total_no <- dem_no + gop_no

  case_when(
    # No opposition at all
    total_no == 0 ~ "Unanimous",
    # Party line: one party all yes, other all no (or vice versa)
    (gop_no == 0 & dem_yes == 0) | (gop_yes == 0 & dem_no == 0) ~ "Party Line",
    # Both parties have members voting yes AND both have members voting no
    (gop_yes > 0 & dem_yes > 0) & (gop_no > 0 & dem_no > 0) ~ "Bipartisan Support and Opposition",
    # Both parties have members voting yes (but not both opposing)
    (gop_yes > 0 & dem_yes > 0) ~ "Bipartisan Support",
    # Both parties have members voting no (but not both supporting)
    (gop_no > 0 & dem_no > 0) ~ "Bipartisan Opposition",
    TRUE ~ "Other"
  )
}


#' Determine party position based on majority vote direction
#'
#' @param yes_count Number of party members voting yes
#' @param no_count Number of party members voting no
#' @return Character: "Yes", "No", or "Evenly Split"
determine_party_position <- function(yes_count, no_count) {
  yes_count <- replace_na(yes_count, 0)
  no_count <- replace_na(no_count, 0)


  case_when(
    yes_count > no_count ~ "Yes",
    no_count > yes_count ~ "No",
    yes_count == no_count & (yes_count + no_count) > 0 ~ "Evenly Split",
    TRUE ~ NA_character_
  )
}


#' Check if a legislator's vote agrees with their party position
#'
#' @param vote Individual vote ("Yea" or "Nay")
#' @param party_position Party's majority position ("Yes" or "No")
#' @return Logical or NA
calculate_party_agreement <- function(vote, party_position) {
  case_when(
    is.na(vote) | is.na(party_position) ~ NA,
    !vote %in% c("Yea", "Nay") ~ NA,
    party_position == "Evenly Split" ~ NA,
    vote == "Yea" & party_position == "Yes" ~ TRUE,
    vote == "Nay" & party_position == "No" ~ TRUE,
    TRUE ~ FALSE
  )
}


# Data Loading Functions --------------------------------------------------

#' Load and prepare people data from LegiScan CSV
#'
#' @param people_path Path to people.csv
#' @return Tibble of legislators (excluding committees)
load_people_data <- function(people_path) {
  read_csv(people_path, show_col_types = FALSE) |>
    # Filter out committees (party_id == 0)
    filter(party_id != 0) |>
    select(
      people_id, name, first_name, last_name,
      party_id, party, role_id, role, district
    ) |>
    mutate(
      party_abbr = case_when(
        party == "D" ~ "dem",
        party == "R" ~ "gop",
        TRUE ~ "other"
      ),
      chamber = case_when(
        role == "Rep" ~ "House",
        role == "Sen" ~ "Senate",
        TRUE ~ NA_character_
      )
    )
}


#' Load votes data from LegiScan CSV
#'
#' @param votes_path Path to votes.csv
#' @return Tibble of individual votes
load_votes_data <- function(votes_path) {
  read_csv(votes_path, show_col_types = FALSE) |>
    mutate(
      vote_text = case_when(
        vote == 1 ~ "Yea",
        vote == 2 ~ "Nay",
        vote == 3 ~ "NV",
        vote == 4 ~ "Absent",
        TRUE ~ NA_character_
      )
    )
}


#' Load roll call metadata from JSON files
#'
#' @param json_dir Directory containing vote JSON files
#' @return Tibble of roll call metadata
load_roll_call_metadata <- function(json_dir) {
  json_files <- list.files(json_dir, pattern = "\\.json$", full.names = TRUE)

  map_dfr(json_files, function(file) {
    json_data <- read_json(file)
    rc <- json_data$roll_call

    tibble(
      roll_call_id = rc$roll_call_id,
      bill_id = rc$bill_id,
      vote_date = as.Date(rc$date),
      vote_desc = rc$desc,
      yea_count = rc$yea,
      nay_count = rc$nay,
      nv_count = rc$nv,
      absent_count = rc$absent,
      total_count = rc$total,
      passed = rc$passed == 1,
      chamber = case_when(
        rc$chamber == "H" ~ "House",
        rc$chamber == "S" ~ "Senate",
        TRUE ~ rc$chamber
      )
    )
  })
}


#' Load bills data from LegiScan CSV
#'
#' @param bills_path Path to bills.csv
#' @return Tibble of bill information
load_bills_data <- function(bills_path) {

  read_csv(bills_path, show_col_types = FALSE) |>
    select(
      bill_id, bill_number, status, status_desc, status_date,
      title, description, committee, last_action_date, last_action
    )
}


# Aggregation Functions ---------------------------------------------------
#' Aggregate votes by party for each roll call
#'
#' @param votes_df Votes data frame
#' @param people_df People data frame
#' @return Tibble with party vote counts per roll call
aggregate_party_votes <- function(votes_df, people_df) {
  # Join votes with people to get party
  votes_with_party <- votes_df |>
    inner_join(
      people_df |> select(people_id, party_abbr, chamber),
      by = "people_id"
    )

  # Aggregate by roll call and party
  party_counts <- votes_with_party |>
    filter(vote_text %in% c("Yea", "Nay")) |>
    group_by(roll_call_id, party_abbr, vote_text) |>
    summarize(count = n(), .groups = "drop") |>
    pivot_wider(
      names_from = c(party_abbr, vote_text),
      values_from = count,
      names_glue = "vote_{party_abbr}_{vote_text}",
      values_fill = 0
    )

  # Ensure all columns exist
  expected_cols <- c("vote_dem_Yea", "vote_dem_Nay", "vote_gop_Yea", "vote_gop_Nay")
  for (col in expected_cols) {
    if (!col %in% names(party_counts)) {
      party_counts[[col]] <- 0L
    }
  }

  # Calculate party positions and vote classification
  party_counts |>
    mutate(
      vote_dem_yes = vote_dem_Yea,
      vote_dem_no = vote_dem_Nay,
      vote_gop_yes = vote_gop_Yea,
      vote_gop_no = vote_gop_Nay,
      party_position_dem = determine_party_position(vote_dem_yes, vote_dem_no),
      party_position_gop = determine_party_position(vote_gop_yes, vote_gop_no),
      vote_outcome = classify_vote_outcome(vote_dem_yes, vote_dem_no, vote_gop_yes, vote_gop_no)
    ) |>
    select(
      roll_call_id,
      vote_dem_yes, vote_dem_no, vote_gop_yes, vote_gop_no,
      party_position_dem, party_position_gop, vote_outcome
    )
}


# Summary Functions -------------------------------------------------------

#' Create roll call summaries with classification
#'
#' @param votes_df Votes data frame
#' @param people_df People data frame
#' @param roll_call_df Roll call metadata (optional)
#' @param bills_df Bills data (optional)
#' @return Tibble of roll call summaries
summarize_roll_calls <- function(votes_df, people_df, roll_call_df = NULL, bills_df = NULL) {
  # Get party vote aggregations
  party_votes <- aggregate_party_votes(votes_df, people_df)

  # If we have roll call metadata, join it

if (!is.null(roll_call_df)) {
    result <- roll_call_df |>
      left_join(party_votes, by = "roll_call_id")

    # If we have bills data, add bill info
    if (!is.null(bills_df)) {
      result <- result |>
        left_join(
          bills_df |> select(bill_id, bill_number, title),
          by = "bill_id"
        )
    }
  } else {
    result <- party_votes
  }

  result
}


#' Create individual vote records with party alignment
#'
#' @param votes_df Votes data frame
#' @param people_df People data frame
#' @param party_votes_df Party vote aggregations (from aggregate_party_votes)
#' @return Tibble of individual votes with party alignment
create_vote_records <- function(votes_df, people_df, party_votes_df) {
  # Join votes with people
  votes_with_party <- votes_df |>
    inner_join(
      people_df |> select(people_id, name, party_abbr, party, chamber, district),
      by = "people_id"
    )

  # Join with party positions
  votes_with_party |>
    left_join(
      party_votes_df |> select(roll_call_id, party_position_dem, party_position_gop, vote_outcome),
      by = "roll_call_id"
    ) |>
    mutate(
      party_position = case_when(
        party_abbr == "dem" ~ party_position_dem,
        party_abbr == "gop" ~ party_position_gop,
        TRUE ~ NA_character_
      ),
      vote_with_party = calculate_party_agreement(vote_text, party_position)
    ) |>
    select(
      roll_call_id, people_id, name, party, party_abbr, chamber, district,
      vote, vote_text, party_position, vote_with_party, vote_outcome
    )
}


#' Summarize voting patterns per legislator
#'
#' @param vote_records_df Vote records with party alignment
#' @return Tibble of legislator voting statistics
summarize_legislator_voting <- function(vote_records_df) {
  vote_records_df |>
    group_by(people_id, name, party, party_abbr, chamber, district) |>
    summarize(
      total_votes = sum(vote_text %in% c("Yea", "Nay")),
      yes_votes = sum(vote_text == "Yea", na.rm = TRUE),
      no_votes = sum(vote_text == "Nay", na.rm = TRUE),
      nv_count = sum(vote_text == "NV", na.rm = TRUE),
      absent_count = sum(vote_text == "Absent", na.rm = TRUE),
      votes_with_party = sum(vote_with_party == TRUE, na.rm = TRUE),
      votes_against_party = sum(vote_with_party == FALSE, na.rm = TRUE),
      party_line_votes = sum(vote_outcome == "Party Line" & vote_text %in% c("Yea", "Nay"), na.rm = TRUE),
      bipartisan_votes = sum(
        vote_outcome %in% c("Bipartisan Support", "Bipartisan Opposition", "Bipartisan Support and Opposition") &
          vote_text %in% c("Yea", "Nay"),
        na.rm = TRUE
      ),
      unanimous_votes = sum(vote_outcome == "Unanimous" & vote_text %in% c("Yea", "Nay"), na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      with_party_pct = ifelse(
        votes_with_party + votes_against_party > 0,
        votes_with_party / (votes_with_party + votes_against_party),
        NA_real_
      ),
      participation_rate = ifelse(
        total_votes + nv_count + absent_count > 0,
        total_votes / (total_votes + nv_count + absent_count),
        NA_real_
      )
    )
}


#' Summarize vote outcomes by classification
#'
#' @param roll_call_summaries_df Roll call summaries
#' @return Tibble of vote outcome counts
summarize_vote_outcomes <- function(roll_call_summaries_df) {
  roll_call_summaries_df |>
    group_by(vote_outcome) |>
    summarize(
      count = n(),
      passed = sum(passed, na.rm = TRUE),
      failed = sum(!passed, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      pct = count / sum(count) * 100
    ) |>
    arrange(desc(count))
}
