# 05_salience_scores.R
#
# Computes a salience index (0-100) for each bill in the 91st GA.
#
# The score is a weighted sum of normalized signals across two dimensions:
#   - Attention signals: lobbyist volume, hearings, co-sponsors, companion bills
#   - Controversy signals: lobbyist opposition, floor vote, party division, amendments
#
# Weights (sum to 1.0):
#   lobby_volume     0.20  — how many organized interests showed up
#   lobby_opposition 0.20  — fraction of lobbyists opposing the bill
#   floor_vote       0.15  — did it ever get a floor vote?
#   party_division   0.15  — how contested was the floor vote? (0=unanimous, 1=party-line)
#   hearings         0.12  — number of committee/subcommittee hearings
#   amendments       0.08  — amendments filed in history text
#   fiscal_note      0.05  — fiscal impact noted (proxy for spending/tax involvement)
#   cosponsors       0.03  — number of individual co-sponsors
#   companions       0.02  — companion bills in the same group
#
# Bills with no data for a component receive 0 for that component.
# All raw inputs are preserved in the output for display/debugging.
#
# Usage:
#   source("R/legislature/05_salience_scores.R")
#   scores <- compute_salience_scores()
#   salience_summary(scores)

library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(readr)
library(jsonlite)
library(here)

# =============================================================================
# Configuration
# =============================================================================

JSON_DIR    <- here("legiscan/files_ga91_json/bill")
CSV_DIR     <- here("legiscan/files_ga91_derived")
DATA_DIR    <- here("data/legislature")
OUTPUT_PATH <- here("data/legislature/bills/salience_scores.rds")

WEIGHTS <- c(
  lobby_volume     = 0.20,
  lobby_opposition = 0.20,
  floor_vote       = 0.15,
  party_division   = 0.15,
  hearings         = 0.12,
  amendments       = 0.08,
  fiscal_note      = 0.05,
  cosponsors       = 0.03,
  companions       = 0.02
)

# =============================================================================
# Component: JSON signals
# =============================================================================

#' Extract salience signals from a single bill JSON file
#'
#' @param bill_number Bill number string (e.g., "HF117")
#' @param json_dir Directory containing bill JSON files
#' @return Single-row tibble, or NULL if file missing
extract_json_signals <- function(bill_number, json_dir = JSON_DIR) {
  path <- file.path(json_dir, paste0(bill_number, ".json"))
  if (!file.exists(path)) return(NULL)

  b <- tryCatch(
    read_json(path)[["bill"]],
    error = function(e) NULL
  )
  if (is.null(b)) return(NULL)

  # Hearings: calendar entries of type "Hearing"
  n_hearings <- if (length(b[["calendar"]]) > 0) {
    sum(map_chr(b[["calendar"]], "type") == "Hearing")
  } else {
    0L
  }

  # Fiscal note: any supplement of type "Fiscal Note"
  has_fiscal_note <- if (length(b[["supplements"]]) > 0) {
    any(map_chr(b[["supplements"]], "type") == "Fiscal Note")
  } else {
    FALSE
  }

  # Amendments: history entries matching "Amendment <ID> filed"
  # (the amendments[] array is empty for GA91 — LegiScan doesn't populate it,
  # but the action text in history does record filed amendments)
  n_amendments <- if (length(b[["history"]]) > 0) {
    actions <- map_chr(b[["history"]], "action")
    sum(str_detect(actions, regex("amendment.+filed", ignore_case = TRUE)))
  } else {
    0L
  }

  tibble(
    bill_number     = bill_number,
    n_hearings      = as.integer(n_hearings),
    has_fiscal_note = has_fiscal_note,
    n_amendments    = as.integer(n_amendments)
  )
}

# =============================================================================
# Component helpers
# =============================================================================

#' Map vote_outcome strings to a 0-1 contentiousness scale
#'
#' Party Line = maximum partisan split; Unanimous = no opposition.
map_party_division <- function(vote_outcome) {
  case_when(
    vote_outcome == "Party Line"                        ~ 1.0,
    vote_outcome == "Bipartisan Support and Opposition" ~ 0.8,
    vote_outcome == "Bipartisan Opposition"             ~ 0.6,
    vote_outcome == "Other"                             ~ 0.3,
    vote_outcome == "Bipartisan Support"                ~ 0.1,
    vote_outcome == "Unanimous"                         ~ 0.0,
    TRUE                                                ~ 0.0
  )
}

# =============================================================================
# Main scoring function
# =============================================================================

#' Compute salience scores for all bills
#'
#' @param json_dir    Directory containing bill JSON files
#' @param csv_dir     Directory containing derived LegiScan CSVs
#' @param data_dir    Directory containing processed RDS files
#' @param weights     Named numeric vector of component weights (must sum to 1)
#' @param output_path Path to write the output RDS
#' @param verbose     Print progress messages
#' @return Tibble of scores and components, invisibly
compute_salience_scores <- function(
    json_dir    = JSON_DIR,
    csv_dir     = CSV_DIR,
    data_dir    = DATA_DIR,
    weights     = WEIGHTS,
    output_path = OUTPUT_PATH,
    verbose     = TRUE
) {
  msg <- function(...) if (verbose) message(...)

  # ── Load inputs ──────────────────────────────────────────────────────────

  msg("Loading base data...")
  bills <- read_csv(
    file.path(csv_dir, "bills.csv"),
    col_select = c(bill_id, bill_number),
    show_col_types = FALSE
  )

  sponsors <- read_csv(
    file.path(csv_dir, "sponsors.csv"),
    show_col_types = FALSE
  )

  vote_summaries <- readRDS(file.path(data_dir, "votes/summaries_91st_ga.rds"))

  bill_groups <- readRDS(file.path(data_dir, "bills/groups.rds")) |>
    select(bill_number = bill, bill_group_id, group_size) |>
    mutate(bill_group_id = as.character(bill_group_id))

  lobbyists <- readRDS(file.path(data_dir, "lobbying/lobbyist_declarations.rds")) |>
    filter(!is.na(client))

  # ── Individual bill signals ───────────────────────────────────────────────

  # JSON signals: hearings, fiscal notes, amendments per bill
  bill_files <- str_remove(list.files(json_dir, pattern = "\\.json$"), "\\.json$")
  msg("Extracting JSON signals from ", length(bill_files), " bill files...")
  json_signals <- map(bill_files, extract_json_signals, json_dir = json_dir) |>
    bind_rows()

  # Vote signals: floor vote occurred, party division per bill
  msg("Computing vote signals...")
  vote_signals <- vote_summaries |>
    group_by(bill_number) |>
    summarise(
      had_floor_vote      = TRUE,
      comp_party_division = max(map_party_division(vote_outcome), na.rm = TRUE),
      .groups = "drop"
    )

  # Co-sponsors per bill (position > 1; may include committee entries)
  msg("Computing sponsor signals...")
  cosponsor_stats <- sponsors |>
    left_join(bills, by = "bill_id") |>
    filter(!is.na(bill_number)) |>
    group_by(bill_number) |>
    summarise(n_cosponsors = sum(position > 1, na.rm = TRUE), .groups = "drop")

  # ── Attach group IDs to per-bill signals ─────────────────────────────────

  # Bills not in groups.rds (shouldn't happen, but guard with coalesce)
  bill_base <- bills |>
    left_join(bill_groups,     by = "bill_number") |>
    left_join(json_signals,    by = "bill_number") |>
    left_join(vote_signals,    by = "bill_number") |>
    left_join(cosponsor_stats, by = "bill_number") |>
    mutate(
      bill_group_id = coalesce(bill_group_id, bill_number),
      group_size    = coalesce(group_size, 1L)
    )

  # ── Group-level aggregation ───────────────────────────────────────────────
  #
  # All signals are pooled across companion bills in the same group so that,
  # e.g., a hearing on HF948 and a hearing on companion SF615 count as two
  # hearings for the group rather than one each.

  msg("Aggregating signals to bill group level...")

  # JSON + vote + sponsor signals: sum/any across group members
  group_signals <- bill_base |>
    group_by(bill_group_id) |>
    summarise(
      n_hearings_grp      = sum(coalesce(n_hearings, 0L)),
      has_fiscal_note_grp = any(coalesce(has_fiscal_note, FALSE)),
      n_amendments_grp    = sum(coalesce(n_amendments, 0L)),
      had_floor_vote_grp  = any(coalesce(had_floor_vote, FALSE)),
      party_div_grp       = max(coalesce(comp_party_division, 0), na.rm = TRUE),
      n_cosponsors_grp    = sum(coalesce(n_cosponsors, 0L)),
      group_size_grp      = as.integer(max(coalesce(group_size, 1L))),
      .groups = "drop"
    )

  # Lobbyist signals: deduplicate by client across all bills in the group,
  # then recount. If the same client declared on both HF948 and SF615, that
  # counts as one client, taking their most recent declaration.
  group_lobby <- lobbyists |>
    left_join(bill_groups |> select(bill_number, bill_group_id),
              by = c("bill" = "bill_number")) |>
    mutate(bill_group_id = coalesce(bill_group_id, bill)) |>
    group_by(bill_group_id, client) |>
    slice_max(order_by = date, n = 1, with_ties = FALSE) |>
    ungroup() |>
    group_by(bill_group_id) |>
    summarise(
      n_lobbyists_grp  = n(),
      n_for_grp        = sum(most_recent_declaration == "For",      na.rm = TRUE),
      n_against_grp    = sum(most_recent_declaration == "Against",  na.rm = TRUE),
      n_undecided_grp  = sum(most_recent_declaration == "Undecided", na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      comp_lobby_volume_grp     = pmin(log1p(n_lobbyists_grp) / log1p(15), 1),
      comp_lobby_opposition_grp = if_else(
        n_for_grp + n_against_grp > 0,
        n_against_grp / (n_for_grp + n_against_grp),
        0
      )
    )

  # ── Score each bill using group-level signals ─────────────────────────────

  msg("Joining group signals and computing scores...")

  scores <- bill_base |>
    left_join(group_signals, by = "bill_group_id") |>
    left_join(group_lobby,   by = "bill_group_id") |>
    mutate(
      # Fill NAs for bills with no group/lobby data
      n_lobbyists_grp           = coalesce(n_lobbyists_grp, 0L),
      n_for_grp                 = coalesce(n_for_grp, 0L),
      n_against_grp             = coalesce(n_against_grp, 0L),
      n_undecided_grp           = coalesce(n_undecided_grp, 0L),
      comp_lobby_volume_grp     = coalesce(comp_lobby_volume_grp, 0),
      comp_lobby_opposition_grp = coalesce(comp_lobby_opposition_grp, 0),

      # Normalized components — all group-level
      comp_lobby_volume     = comp_lobby_volume_grp,
      comp_lobby_opposition = comp_lobby_opposition_grp,
      comp_floor_vote       = as.numeric(had_floor_vote_grp),
      comp_party_division   = party_div_grp,
      comp_hearings         = pmin(n_hearings_grp / 3, 1),      # 3+ hearings = max
      comp_amendments       = pmin(n_amendments_grp / 3, 1),    # 3+ amendments = max
      comp_fiscal_note      = as.numeric(has_fiscal_note_grp),
      comp_cosponsors       = pmin(n_cosponsors_grp / 8, 1),    # 8+ co-sponsors = max
      comp_companions       = pmin((group_size_grp - 1L) / 4, 1), # 4+ companions = max

      salience_score = round(100 * (
        weights["lobby_volume"]     * comp_lobby_volume     +
        weights["lobby_opposition"] * comp_lobby_opposition +
        weights["floor_vote"]       * comp_floor_vote       +
        weights["party_division"]   * comp_party_division   +
        weights["hearings"]         * comp_hearings         +
        weights["amendments"]       * comp_amendments       +
        weights["fiscal_note"]      * comp_fiscal_note      +
        weights["cosponsors"]       * comp_cosponsors       +
        weights["companions"]       * comp_companions
      ), 1)
    )

  # ── Select output columns ─────────────────────────────────────────────────

  output <- scores |>
    select(
      bill_number,
      bill_group_id,
      salience_score,
      # Group-level raw counts (what the score is based on)
      n_lobbyists = n_lobbyists_grp,
      n_for       = n_for_grp,
      n_against   = n_against_grp,
      n_undecided = n_undecided_grp,
      n_hearings  = n_hearings_grp,
      had_floor_vote = had_floor_vote_grp,
      n_cosponsors   = n_cosponsors_grp,
      group_size     = group_size_grp,
      n_amendments   = n_amendments_grp,
      has_fiscal_note = has_fiscal_note_grp,
      # Per-bill raw counts (for reference / display on individual pages)
      n_hearings_this_bill  = n_hearings,
      n_amendments_this_bill = n_amendments,
      # Normalized components
      comp_lobby_volume, comp_lobby_opposition,
      comp_floor_vote, comp_party_division,
      comp_hearings, comp_amendments,
      comp_fiscal_note, comp_cosponsors, comp_companions
    ) |>
    arrange(desc(salience_score))

  # ── Save ─────────────────────────────────────────────────────────────────

  if (!dir.exists(dirname(output_path))) {
    dir.create(dirname(output_path), recursive = TRUE)
  }

  saveRDS(output, output_path)
  msg("Saved salience scores for ", nrow(output), " bills → ", output_path)

  invisible(output)
}

# =============================================================================
# Diagnostic summary
# =============================================================================

#' Print a summary of computed salience scores
#'
#' @param scores Tibble from compute_salience_scores(), or NULL to load from disk
#' @param output_path Path to salience scores RDS (used if scores is NULL)
#' @param top_n Number of top-scoring bills to display
salience_summary <- function(
    scores      = NULL,
    output_path = OUTPUT_PATH,
    top_n       = 20
) {
  if (is.null(scores)) {
    if (!file.exists(output_path)) {
      message("No scores found. Run compute_salience_scores() first.")
      return(invisible(NULL))
    }
    scores <- readRDS(output_path)
  }

  cat("=== Salience Score Summary ===\n\n")
  cat(sprintf("Bills scored: %d\n", nrow(scores)))
  cat(sprintf("Score range:  %.1f – %.1f\n", min(scores$salience_score), max(scores$salience_score)))
  cat(sprintf("Median score: %.1f\n\n", median(scores$salience_score)))

  cat("Distribution:\n")
  breaks <- c(0, 10, 25, 50, 75, 100)
  labels <- paste0(breaks[-length(breaks)], "–", breaks[-1])
  tbl <- table(cut(scores$salience_score, breaks, labels = labels, include.lowest = TRUE))
  print(tbl)

  cat(sprintf("\nTop %d bills by salience:\n", top_n))
  scores |>
    head(top_n) |>
    select(bill_number, salience_score, n_lobbyists, n_for, n_against,
           n_hearings, had_floor_vote, n_amendments) |>
    print(n = top_n)

  cat("\nComponent means (across all bills):\n")
  scores |>
    summarise(across(starts_with("comp_"), mean)) |>
    tidyr::pivot_longer(everything(), names_to = "component", values_to = "mean") |>
    mutate(
      component = str_remove(component, "^comp_"),
      mean      = round(mean, 3)
    ) |>
    arrange(desc(mean)) |>
    print(n = Inf)

  invisible(scores)
}
