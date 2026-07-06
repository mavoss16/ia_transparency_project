# 01c_generate_csvs.R
#
# Derives all LegiScan bulk CSV files from local JSON files.
# Run after 01_incremental_update.R to keep CSVs in sync with the JSON data.
#
# Produces the same schema as the getDatasetRaw CSV bulk download, written to
# a parallel directory to distinguish from the original bulk download:
#   legiscan/files_ga91_derived/bills.csv
#   legiscan/files_ga91_derived/people.csv
#   legiscan/files_ga91_derived/sponsors.csv
#   legiscan/files_ga91_derived/votes.csv
#   legiscan/files_ga91_derived/history.csv
#   legiscan/files_ga91_derived/rollcalls.csv
#   legiscan/files_ga91_derived/documents.csv
#
# Usage:
#   source("R/data_pipeline/01c_generate_csvs.R")
#   generate_csvs()

library(dplyr)
library(purrr)
library(readr)
library(jsonlite)
library(here)

CSV_DIR  <- here("legiscan/files_ga91_derived")
JSON_DIR <- here("legiscan/files_ga91_json")

# LegiScan status code -> description mapping
STATUS_DESC <- c(
  "1" = "Introduced",
  "2" = "Engrossed",
  "3" = "Enrolled",
  "4" = "Passed",
  "5" = "Vetoed",
  "6" = "Failed"
)

expand_chamber <- function(x) {
  case_when(x == "H" ~ "House", x == "S" ~ "Senate", .default = x)
}

# =============================================================================
# Per-JSON extraction helpers
# =============================================================================

# Each function takes a parsed bill/vote/person list and returns a tibble
# (or NULL if there is nothing to extract). Using simplifyVector = TRUE when
# reading means arrays of objects come back as data frames automatically.

extract_bill_row <- function(b) {
  last_action_date <- NA_character_
  last_action      <- NA_character_
  if (is.data.frame(b$history) && nrow(b$history) > 0) {
    last_action_date <- b$history$date[nrow(b$history)]
    last_action      <- b$history$action[nrow(b$history)]
  }

  committee_name <- ""
  if (is.data.frame(b$committee) && nrow(b$committee) > 0) {
    committee_name <- b$committee$name[1]
  }

  tibble(
    bill_id          = b$bill_id,
    session_id       = b$session_id,
    bill_number      = b$bill_number,
    status           = b$status,
    status_desc      = unname(STATUS_DESC[as.character(b$status)]),
    status_date      = b$status_date %||% NA_character_,
    title            = b$title       %||% NA_character_,
    description      = b$description %||% NA_character_,
    committee_id     = b$pending_committee_id %||% 0L,
    committee        = committee_name,
    last_action_date = last_action_date,
    last_action      = last_action,
    url              = b$url        %||% NA_character_,
    state_link       = b$state_link %||% NA_character_
  )
}

extract_sponsors <- function(b) {
  if (!is.data.frame(b$sponsors) || nrow(b$sponsors) == 0) return(NULL)
  tibble(
    bill_id   = b$bill_id,
    people_id = b$sponsors$people_id,
    position  = b$sponsors$sponsor_order
  )
}

extract_history <- function(b) {
  if (!is.data.frame(b$history) || nrow(b$history) == 0) return(NULL)
  tibble(
    bill_id  = b$bill_id,
    date     = b$history$date,
    chamber  = expand_chamber(b$history$chamber),
    sequence = seq_len(nrow(b$history)),
    action   = b$history$action
  )
}

extract_documents <- function(b) {
  rows <- list()

  if (is.data.frame(b$texts) && nrow(b$texts) > 0) {
    rows$texts <- tibble(
      bill_id       = b$bill_id,
      document_id   = b$texts$doc_id,
      document_type = "text",
      document_size = b$texts$text_size,
      document_mime = b$texts$mime,
      document_desc = b$texts$type,
      url           = b$texts$url,
      state_link    = b$texts$state_link
    )
  }

  if (is.data.frame(b$supplements) && nrow(b$supplements) > 0) {
    rows$supplements <- tibble(
      bill_id       = b$bill_id,
      document_id   = b$supplements$supplement_id,
      document_type = "supplement",
      document_size = b$supplements$supplement_size,
      document_mime = b$supplements$mime,
      document_desc = b$supplements$type,
      url           = b$supplements$url,
      state_link    = b$supplements$state_link
    )
  }

  if (length(rows) == 0) return(NULL)
  bind_rows(rows)
}

extract_rollcall_row <- function(rc) {
  tibble(
    bill_id      = rc$bill_id,
    roll_call_id = rc$roll_call_id,
    date         = rc$date,
    chamber      = expand_chamber(rc$chamber),
    description  = rc$desc,
    yea          = rc$yea,
    nay          = rc$nay,
    nv           = rc$nv,
    absent       = rc$absent,
    total        = rc$total
  )
}

extract_votes <- function(rc) {
  if (!is.data.frame(rc$votes) || nrow(rc$votes) == 0) return(NULL)
  tibble(
    roll_call_id = rc$roll_call_id,
    people_id    = rc$votes$people_id,
    vote         = rc$votes$vote_id,
    vote_desc    = rc$votes$vote_text
  )
}

extract_person_row <- function(p) {
  tibble(
    people_id          = p$people_id,
    name               = p$name               %||% NA_character_,
    first_name         = p$first_name         %||% NA_character_,
    middle_name        = p$middle_name        %||% NA_character_,
    last_name          = p$last_name          %||% NA_character_,
    suffix             = p$suffix             %||% NA_character_,
    nickname           = p$nickname           %||% NA_character_,
    party_id           = p$party_id           %||% NA_integer_,
    party              = p$party              %||% NA_character_,
    role_id            = p$role_id            %||% NA_integer_,
    role               = p$role               %||% NA_character_,
    district           = p$district           %||% NA_character_,
    followthemoney_eid = p$ftm_eid            %||% NA_integer_,
    votesmart_id       = p$votesmart_id       %||% NA_integer_,
    opensecrets_id     = p$opensecrets_id     %||% NA_character_,
    ballotpedia        = p$ballotpedia        %||% NA_character_,
    knowwho_pid        = p$knowwho_pid        %||% NA_integer_,
    committee_id       = p$committee_id       %||% 0L
  )
}

# =============================================================================
# Main
# =============================================================================

#' Generate all bulk CSV files from local JSON files
#'
#' @param json_dir Directory containing bill/, vote/, and people/ JSON folders
#' @param csv_dir  Output directory for CSV files (legiscan/files_ga91_derived/)
#' @return Invisible named list of row counts per file
generate_csvs <- function(
    json_dir = JSON_DIR,
    csv_dir  = CSV_DIR
) {
  dir.create(csv_dir, recursive = TRUE, showWarnings = FALSE)

  bill_dir   <- file.path(json_dir, "bill")
  vote_dir   <- file.path(json_dir, "vote")
  people_dir <- file.path(json_dir, "people")

  # --------------------------------------------------------------------------
  # 1. Bill JSONs -> bills.csv, sponsors.csv, history.csv, documents.csv
  # --------------------------------------------------------------------------
  bill_files <- list.files(bill_dir, pattern = "\\.json$", full.names = TRUE)
  message(sprintf("Reading %d bill JSON files...", length(bill_files)))

  bills_raw <- map(bill_files, function(f) {
    tryCatch(
      read_json(f, simplifyVector = TRUE)$bill,
      error = function(e) {
        message(sprintf("  [WARN] Skipping %s: %s", basename(f), conditionMessage(e)))
        NULL
      }
    )
  }) |> compact()

  message(sprintf("  %d bills parsed.", length(bills_raw)))

  bills_df     <- map(bills_raw, extract_bill_row)     |> list_rbind()
  sponsors_df  <- map(bills_raw, extract_sponsors)     |> list_rbind()
  history_df   <- map(bills_raw, extract_history)      |> list_rbind()
  documents_df <- map(bills_raw, extract_documents)    |> list_rbind()

  write_csv(bills_df,     file.path(csv_dir, "bills.csv"))
  write_csv(sponsors_df,  file.path(csv_dir, "sponsors.csv"))
  write_csv(history_df,   file.path(csv_dir, "history.csv"))
  write_csv(documents_df, file.path(csv_dir, "documents.csv"))

  message(sprintf("  bills.csv:     %d rows", nrow(bills_df)))
  message(sprintf("  sponsors.csv:  %d rows", nrow(sponsors_df)))
  message(sprintf("  history.csv:   %d rows", nrow(history_df)))
  message(sprintf("  documents.csv: %d rows", nrow(documents_df)))

  # --------------------------------------------------------------------------
  # 2. Vote JSONs -> rollcalls.csv, votes.csv
  # --------------------------------------------------------------------------
  vote_files <- list.files(vote_dir, pattern = "\\.json$", full.names = TRUE)
  message(sprintf("Reading %d vote JSON files...", length(vote_files)))

  votes_raw <- map(vote_files, function(f) {
    tryCatch(
      read_json(f, simplifyVector = TRUE)$roll_call,
      error = function(e) {
        message(sprintf("  [WARN] Skipping %s: %s", basename(f), conditionMessage(e)))
        NULL
      }
    )
  }) |> compact()

  message(sprintf("  %d roll calls parsed.", length(votes_raw)))

  rollcalls_df <- map(votes_raw, extract_rollcall_row) |> list_rbind()
  votes_df     <- map(votes_raw, extract_votes)        |> list_rbind()

  write_csv(rollcalls_df, file.path(csv_dir, "rollcalls.csv"))
  write_csv(votes_df,     file.path(csv_dir, "votes.csv"))

  message(sprintf("  rollcalls.csv: %d rows", nrow(rollcalls_df)))
  message(sprintf("  votes.csv:     %d rows", nrow(votes_df)))

  # --------------------------------------------------------------------------
  # 3. People JSONs -> people.csv
  # --------------------------------------------------------------------------
  people_files <- list.files(people_dir, pattern = "\\.json$", full.names = TRUE)
  message(sprintf("Reading %d people JSON files...", length(people_files)))

  people_raw <- map(people_files, function(f) {
    tryCatch(
      read_json(f, simplifyVector = FALSE)$person,
      error = function(e) {
        message(sprintf("  [WARN] Skipping %s: %s", basename(f), conditionMessage(e)))
        NULL
      }
    )
  }) |> compact()

  message(sprintf("  %d people parsed.", length(people_raw)))

  people_df <- map(people_raw, extract_person_row) |> list_rbind()

  write_csv(people_df, file.path(csv_dir, "people.csv"))
  message(sprintf("  people.csv:    %d rows", nrow(people_df)))

  message("\nCSV generation complete.")

  invisible(list(
    bills     = nrow(bills_df),
    sponsors  = nrow(sponsors_df),
    history   = nrow(history_df),
    documents = nrow(documents_df),
    rollcalls = nrow(rollcalls_df),
    votes     = nrow(votes_df),
    people    = nrow(people_df)
  ))
}
