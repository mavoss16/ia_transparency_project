# Clean 2024 General Election precinct results for all 99 Iowa counties.
#
# The files downloaded from electionresults.iowa.gov are SpreadsheetML XML
# (served as .xlsx but not a ZIP — readxl cannot open them), saved as .xml by
# download/election_results.R. Parsed with xml2.
#
# File layout per county (one XML file, multiple "sheets"):
#   Sheet 1: Table of Contents
#   Sheet 2: Registered Voters by precinct
#   Sheets 3+: One sheet per contest
#
# Each contest sheet:
#   Row 1: Contest name (merged across all columns)
#   Row 2: Candidate names (each merged across 3 columns: ED, AB, Total)
#   Row 3: Column headers — Precinct | Registered Voters |
#           [Election Day | Absentee | Total Votes] × N candidates | Total
#   Row 4..n-1: Precinct data rows
#   Row n: "Total:" county totals (excluded)
#
# Output: data/elections/processed/2024/precinct_elections_2024.csv
#   Columns: county, precinct, registered_voters, contest, district,
#            candidate, vote_type, votes

library(xml2)
library(dplyr)
library(purrr)
library(stringr)
library(readr)
library(here)

INPUT_DIR  <- here("data/elections/raw/precinct_results/2024_general")
OUTPUT_DIR <- here("data/elections/processed/2024")
OUTPUT_FILE <- file.path(OUTPUT_DIR, "precinct_elections_2024.csv")

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- XML helpers ----

# Read all cell values in a row, expanding MergeAcross and handling Index gaps.
expand_row <- function(row_xml) {
  cells <- xml_find_all(row_xml, ".//*[local-name()='Cell']")
  vals  <- character(0)
  for (cell in cells) {
    idx <- xml_attr(cell, "Index")
    if (!is.na(idx)) {
      needed <- as.integer(idx) - 1L - length(vals)
      if (needed > 0L) vals <- c(vals, rep(NA_character_, needed))
    }
    d   <- xml_find_first(cell, "*[local-name()='Data']")
    val <- if (inherits(d, "xml_missing")) NA_character_ else xml_text(d)
    n   <- {
      m <- xml_attr(cell, "MergeAcross")
      if (is.na(m)) 1L else as.integer(m) + 1L
    }
    vals <- c(vals, rep(val, n))
  }
  vals
}

# ---- Contest parser ----

parse_contest <- function(ws) {
  rows   <- xml_find_all(ws, ".//*[local-name()='Row']")
  n_rows <- length(rows)
  if (n_rows < 4) return(NULL)

  contest_raw <- expand_row(rows[[1]])[[1]]
  candidates  <- expand_row(rows[[2]])
  vote_types  <- expand_row(rows[[3]])
  n_cols      <- length(vote_types)

  # Data rows: row 4 through second-to-last (last row is county "Total:")
  data_rows <- rows[seq(4L, n_rows - 1L)]
  if (length(data_rows) == 0L) return(NULL)

  # Build matrix: one column per XML column, one row per precinct
  mat <- do.call(rbind, lapply(data_rows, function(r) {
    v <- expand_row(r)
    length(v) <- n_cols   # pad short rows
    v
  }))

  # Vote column indices: skip col 1 (precinct name), col 2 (registered voters),
  # and the last column (county-wide total across all candidates)
  vote_idx <- seq(3L, n_cols - 1L)

  # Build long-format tibble: one row per precinct × candidate × vote_type
  result <- map_dfr(vote_idx, \(i) tibble(
    precinct          = mat[, 1],
    registered_voters = suppressWarnings(as.integer(mat[, 2])),
    candidate         = candidates[[i]],
    vote_type         = vote_types[[i]],
    votes             = suppressWarnings(as.integer(mat[, i]))
  ))

  # Parse contest name and district number from the raw contest label
  # e.g. "State Senator District 38 ( 1)" → contest = "State Senator", district = "38"
  # e.g. "County Supervisor Dist. 2 ( 1)" → contest = "County Supervisor", district = "2"
  district <- str_match(contest_raw, "(?i)dist(?:rict)?\\.?\\s*(\\d+)\\s*\\(")[, 2]
  contest  <- str_trim(contest_raw) |>
    str_remove("\\s*\\([^)]+\\)$") |>
    str_remove("(?i)\\s+dist(?:rict)?\\.?\\s+\\d+$") |>
    str_trim()

  mutate(result, contest = contest, district = district)
}

# ---- County processor ----

process_county <- function(path) {
  county <- path |>
    basename() |>
    str_remove("\\.xml$") |>
    str_replace_all("_", " ") |>
    str_to_title()

  message("  ", county)

  doc    <- read_xml(path)
  sheets <- xml_find_all(doc, "//*[local-name()='Worksheet']")

  # Sheets 1 & 2 are Table of Contents and Registered Voters — skip
  contest_sheets <- sheets[seq(3L, length(sheets))]

  county_data <- map(contest_sheets, parse_contest) |>
    compact() |>
    bind_rows() |>
    mutate(county = county, .before = everything())

  county_data
}

# ---- Run ----

paths <- list.files(INPUT_DIR, pattern = "\\.xml$", full.names = TRUE)
message("Processing ", length(paths), " counties...")

results <- map(paths, process_county)

elections_2024 <- bind_rows(results) |>
  select(county, precinct, registered_voters, contest, district,
         candidate, vote_type, votes)

write_csv(elections_2024, OUTPUT_FILE)
message("\nDone. ", nrow(elections_2024), " rows written to ", OUTPUT_FILE)
