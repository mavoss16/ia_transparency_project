# 05_salience_scores.R
#
# Describes how contested and how far-reaching each bill in a General Assembly was,
# as a set of separate, citable indicators rather than one blended score.
# Replaces the 2026-05-17 weighted composite (archived as
# archive/05_salience_scores_composite.R). Rationale and sources:
# notes/legislature/2026-10-24_salience-precedents.md
#
# Indicators (all computed at the bill-group level; group members share them):
#
#   Lobby heat   — UHERO "Heat Score" (Gordner & Moore 2025): the share of
#                  organizations on the minority side, 0 (agreement) to 0.5
#                  (even split). Iowa adaptation: computed on For + Against
#                  only. Undecided declarations are ~54% of all declarations
#                  and mostly signal monitoring, so they count toward
#                  attention, not toward either side. Band cutoffs follow
#                  UHERO (< 0.10, 0.10–0.30, >= 0.30) but are labelled
#                  One-sided / Leaning / Divided rather than UHERO's
#                  Cool / Warm / Hot: a low score means lobbyists didn't
#                  disagree with *each other*, not that the bill was
#                  uncontroversial — Medicaid work requirements (4 For,
#                  43 Against) scores 0.085. One-sided bills also record
#                  which way they lean. No band is assigned below
#                  MIN_POSITIONED organizations taking a side.
#   Vote heat    — the same minority-share formula applied to the most
#                  contested passage vote in the group, alongside the
#                  existing party-division label for that vote.
#   Stage        — furthest stage reached by any group member, on the site's
#                  status scale, incl. the end states (cf. SLES stage progression).
#   Bill class   — resolution / commemorative / substantive, following the
#                  SLES commemorative tier (Bucchianeri, Volden & Wiseman 2025).
#   Attention    — organizations declaring (any current position), hearings,
#                  amendments filed, fiscal note.
#
# Nothing here is blended into a single number. Use most_contested_bills()
# for the two-axis ordering (Divided bills, by organizations taking a side).
#
# Usage:
#   source("R/legislature/05_salience_scores.R")
#   salience <- compute_salience()
#   salience_summary(salience)
#   most_contested_bills(salience)

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

source(here("R/legislature/utils.R"))  # STATUS_LEVELS (and session.R)

# Paths for one session; compute_salience(ga = ...) for another
salience_paths <- function(ga = CURRENT_GA) {
  paths <- ga_paths(ga)
  list(
    json_dir    = paths$bill_json,
    csv_dir     = paths$derived,
    data_dir    = paths$data,
    lobby_path  = file.path(paths$lobbying, "lobbyist_declarations.rds"),
    output_path = file.path(paths$bills, "salience.rds")
  )
}
OUTPUT_PATH <- salience_paths()$output_path

# Minimum organizations taking a side (For + Against) before a heat band is
# assigned. One For and one Against would otherwise read as "Hot" on two
# data points. Provisional — revisit against the refreshed declarations.
MIN_POSITIONED <- 5

# Band lower bounds — UHERO's cutoffs, our labels (UHERO: Cool / Warm / Hot)
HEAT_BANDS <- c(`One-sided` = 0, Leaning = 0.10, Divided = 0.30)

LOBBY_BAND_LEVELS <- c("Divided", "Leaning", "One-sided",
                       "Too few positions", "No positions")

# Site status scale, by position in display order: the end states sit at the
# top, so a group's furthest stage is its highest position
STATUS_ORDER <- names(STATUS_LEVELS)

# Roll calls that decide a bill's fate, as opposed to amendments, deferrals,
# or procedural motions
PASSAGE_VOTE_PATTERN <- regex(
  "shall the bill pass|joint resolution be adopted|motion to concur",
  ignore_case = TRUE
)

# Commemorative bills: naming official symbols, designating observances,
# honoring people. Kept narrow on purpose — broad terms like "designating"
# or "recognizing" also match substantive bills ("designating kratom as a
# schedule I controlled substance"), so only add a pattern after checking it
# against every bill title.
COMMEMORATIVE_PATTERN <- regex(
  paste(
    "as the official state",
    "designat\\w* .+ as .+ (day|week|month)\\b",
    "\\bhonoring\\b",
    "commemorative coins",
    sep = "|"
  ),
  ignore_case = TRUE
)

FISCAL_NOTE_TYPES <- c("Fiscal Note", "Fiscal Note/Analysis")

# =============================================================================
# Helpers
# =============================================================================

#' Minority share: the UHERO Heat Score formula
#'
#' @param a,b Counts on each side (For/Against, or Yea/Nay)
#' @return 0 (unanimous) to 0.5 (even split); NA when a + b == 0
minority_share <- function(a, b) {
  if_else(a + b > 0, pmin(a, b) / (a + b), NA_real_)
}

#' Map a lobby heat value to a band (UHERO cutoffs)
#'
#' @param heat Heat score (0-0.5)
#' @param n_positioned Organizations taking a side
heat_band <- function(heat, n_positioned) {
  case_when(
    n_positioned == 0                ~ "No positions",
    n_positioned < MIN_POSITIONED    ~ "Too few positions",
    heat >= HEAT_BANDS[["Divided"]]  ~ "Divided",
    heat >= HEAT_BANDS[["Leaning"]]  ~ "Leaning",
    TRUE                             ~ "One-sided"
  )
}

#' Which way a one-sided bill leans
#'
#' @param band Output of heat_band()
#' @param n_for,n_against Organizations on each side
#' @return "mostly for" / "mostly against" for One-sided bills, else NA
lobby_lean <- function(band, n_for, n_against) {
  case_when(
    band != "One-sided"  ~ NA_character_,
    n_for > n_against    ~ "mostly for",
    TRUE                 ~ "mostly against"
  )
}

#' Classify a bill as resolution, commemorative, or substantive
#'
#' Following SLES, simple and concurrent resolutions (HR, SR, HCR, SCR) are
#' separated out because they cannot carry the force of law. Joint
#' resolutions (constitutional amendments, state symbols) are kept as bills.
classify_bill <- function(bill_number, title) {
  prefix <- str_extract(bill_number, "^[A-Z]+")
  case_when(
    prefix %in% c("HR", "SR", "HCR", "SCR")       ~ "resolution",
    str_detect(title, COMMEMORATIVE_PATTERN)      ~ "commemorative",
    TRUE                                          ~ "substantive"
  )
}

#' Extract per-bill attention signals from a bill JSON file
#'
#' @param bill_number Bill number string (e.g., "HF117")
#' @param json_dir Directory containing bill JSON files
#' @return Single-row tibble, or NULL if file missing
extract_json_signals <- function(bill_number, json_dir = ga_paths()$bill_json) {
  path <- file.path(json_dir, paste0(bill_number, ".json"))
  if (!file.exists(path)) return(NULL)

  b <- tryCatch(
    read_json(path)[["bill"]],
    error = function(e) NULL
  )
  if (is.null(b)) return(NULL)

  n_hearings <- if (length(b[["calendar"]]) > 0) {
    sum(map_chr(b[["calendar"]], "type") == "Hearing")
  } else {
    0L
  }

  has_fiscal_note <- if (length(b[["supplements"]]) > 0) {
    any(map_chr(b[["supplements"]], "type") %in% FISCAL_NOTE_TYPES)
  } else {
    FALSE
  }

  # LegiScan's amendments[] is empty for GA91; history text records filings
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
# Main
# =============================================================================

#' Compute salience indicators for all bills
#'
#' @param ga          General Assembly (default: CURRENT_GA); sets the paths below
#' @param json_dir    Directory containing bill JSON files
#' @param csv_dir     Directory containing derived LegiScan CSVs
#' @param data_dir    Directory containing processed RDS files
#' @param lobby_path  Lobbyist declarations RDS (override to test on a copy)
#' @param output_path Path to write the output RDS (NULL = don't save)
#' @param verbose     Print progress messages
#' @return Tibble with one row per bill, invisibly
compute_salience <- function(
    ga          = CURRENT_GA,
    json_dir    = salience_paths(ga)$json_dir,
    csv_dir     = salience_paths(ga)$csv_dir,
    data_dir    = salience_paths(ga)$data_dir,
    lobby_path  = salience_paths(ga)$lobby_path,
    output_path = salience_paths(ga)$output_path,
    verbose     = TRUE
) {
  msg <- function(...) if (verbose) message(...)

  # ── Load inputs ──────────────────────────────────────────────────────────

  msg("Loading base data...")
  bills <- read_csv(
    file.path(csv_dir, "bills.csv"),
    col_select = c(bill_number, title),
    show_col_types = FALSE
  )

  bill_groups <- readRDS(file.path(data_dir, "bills/groups.rds")) |>
    select(bill_number = bill, bill_group_id, group_size, lead_bill, status) |>
    mutate(bill_group_id = as.character(bill_group_id))

  vote_summaries <- readRDS(file.path(data_dir, "votes/summaries.rds"))

  lobbyists <- readRDS(lobby_path) |>
    filter(!is.na(client))

  # ── Per-bill signals ─────────────────────────────────────────────────────

  bill_files <- str_remove(list.files(json_dir, pattern = "\\.json$"), "\\.json$")
  msg("Extracting JSON signals from ", length(bill_files), " bill files...")
  json_signals <- map(bill_files, extract_json_signals, json_dir = json_dir) |>
    bind_rows()

  bill_base <- bills |>
    left_join(bill_groups,  by = "bill_number") |>
    left_join(json_signals, by = "bill_number") |>
    mutate(
      bill_group_id = coalesce(bill_group_id, bill_number),
      group_size    = coalesce(group_size, 1L),
      lead_bill     = coalesce(lead_bill, bill_number),
      bill_class    = classify_bill(bill_number, title),
      stage_level   = match(status, STATUS_ORDER)
    )

  group_of <- bill_base |> select(bill_number, bill_group_id)

  # ── Group-level attention + stage ────────────────────────────────────────

  msg("Aggregating attention and stage to bill groups...")
  group_signals <- bill_base |>
    group_by(bill_group_id) |>
    summarise(
      n_hearings_grp      = sum(coalesce(n_hearings, 0L)),
      n_amendments_grp    = sum(coalesce(n_amendments, 0L)),
      has_fiscal_note_grp = any(coalesce(has_fiscal_note, FALSE)),
      stage_level_grp     = max(coalesce(stage_level, 1L)),
      .groups = "drop"
    ) |>
    mutate(stage_grp = STATUS_ORDER[stage_level_grp])

  # ── Lobby heat ───────────────────────────────────────────────────────────
  #
  # Each client counts once per group, at their most recent declaration, so a
  # client who declared on both companions isn't double-counted and one who
  # moved from Undecided to Against counts as Against.

  msg("Computing lobby heat...")
  group_lobby <- lobbyists |>
    inner_join(group_of, by = c("bill" = "bill_number")) |>
    group_by(bill_group_id, client) |>
    slice_max(order_by = date, n = 1, with_ties = FALSE) |>
    ungroup() |>
    group_by(bill_group_id) |>
    summarise(
      n_for       = sum(most_recent_declaration == "For",       na.rm = TRUE),
      n_against   = sum(most_recent_declaration == "Against",   na.rm = TRUE),
      n_undecided = sum(most_recent_declaration == "Undecided", na.rm = TRUE),
      n_withdrawn = sum(most_recent_declaration == "Withdrawn", na.rm = TRUE),
      .groups = "drop"
    )

  # ── Vote heat ────────────────────────────────────────────────────────────
  #
  # The most contested passage vote anywhere in the group.

  msg("Computing vote heat...")
  group_votes <- vote_summaries |>
    filter(str_detect(vote_desc, PASSAGE_VOTE_PATTERN)) |>
    inner_join(group_of, by = "bill_number") |>
    mutate(vote_heat = minority_share(yea_count, nay_count)) |>
    group_by(bill_group_id) |>
    mutate(n_passage_votes = n()) |>
    slice_max(order_by = vote_heat, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(
      bill_group_id, n_passage_votes, vote_heat,
      vote_outcome, vote_chamber = chamber, vote_date,
      vote_bill = bill_number, vote_yea = yea_count, vote_nay = nay_count
    )

  # ── Assemble ─────────────────────────────────────────────────────────────

  msg("Assembling output...")
  output <- bill_base |>
    left_join(group_signals, by = "bill_group_id") |>
    left_join(group_lobby,   by = "bill_group_id") |>
    left_join(group_votes,   by = "bill_group_id") |>
    mutate(
      across(c(n_for, n_against, n_undecided, n_withdrawn, n_passage_votes),
             \(x) coalesce(x, 0L)),
      n_positioned = n_for + n_against,
      n_orgs       = n_positioned + n_undecided,
      lobby_heat   = minority_share(n_for, n_against),
      lobby_band   = heat_band(lobby_heat, n_positioned),
      lobby_lean   = lobby_lean(lobby_band, n_for, n_against)
    ) |>
    select(
      bill_number, bill_group_id, lead_bill, group_size, bill_class,
      # Stage
      stage = stage_grp, stage_level = stage_level_grp,
      # Lobby heat
      lobby_band, lobby_lean, lobby_heat, n_orgs, n_positioned,
      n_for, n_against, n_undecided, n_withdrawn,
      # Vote heat
      vote_heat, vote_outcome, n_passage_votes,
      vote_bill, vote_chamber, vote_date, vote_yea, vote_nay,
      # Attention
      n_hearings = n_hearings_grp, n_amendments = n_amendments_grp,
      has_fiscal_note = has_fiscal_note_grp,
      # Per-bill counts, for display on the bill's own page
      n_hearings_this_bill = n_hearings, n_amendments_this_bill = n_amendments
    ) |>
    mutate(lobby_band = factor(lobby_band, levels = LOBBY_BAND_LEVELS)) |>
    arrange(lobby_band, desc(n_orgs))

  if (!is.null(output_path)) {
    if (!dir.exists(dirname(output_path))) {
      dir.create(dirname(output_path), recursive = TRUE)
    }
    saveRDS(output, output_path)
    msg("Saved salience indicators for ", nrow(output), " bills → ", output_path)
  }

  invisible(output)
}

# =============================================================================
# Views
# =============================================================================

#' Most contested bill groups: Divided lobby heat, ordered by organizations
#' taking a side
#'
#' The two-axis ordering (heat x volume) from UHERO's chart — no weights.
#' Volume here is For + Against, not all declarations: ordering by n_orgs
#' put bills with 60 Undecided and 5 positioned at the top.
#' One row per group, represented by its lead bill.
#'
#' @param salience Tibble from compute_salience(), or NULL to load from disk
#' @param n Number of groups to return
most_contested_bills <- function(salience = NULL, n = 20, output_path = OUTPUT_PATH) {
  if (is.null(salience)) salience <- readRDS(output_path)

  salience |>
    filter(bill_class == "substantive", lobby_band == "Divided") |>
    distinct(bill_group_id, .keep_all = TRUE) |>
    arrange(desc(n_positioned), desc(lobby_heat)) |>
    head(n) |>
    select(lead_bill, group_size, stage, n_positioned, n_for, n_against,
           n_undecided, lobby_heat, vote_heat, vote_outcome, n_hearings)
}

#' Print a summary of the salience indicators
#'
#' @param salience Tibble from compute_salience(), or NULL to load from disk
salience_summary <- function(salience = NULL, output_path = OUTPUT_PATH) {
  if (is.null(salience)) {
    if (!file.exists(output_path)) {
      message("No salience data found. Run compute_salience() first.")
      return(invisible(NULL))
    }
    salience <- readRDS(output_path)
  }

  groups <- salience |> distinct(bill_group_id, .keep_all = TRUE)

  cat("=== Salience Indicators ===\n\n")
  cat(sprintf("Bills: %d   Groups: %d\n\n", nrow(salience), nrow(groups)))

  cat("Bill class (bills):\n")
  print(count(salience, bill_class))

  cat("\nLobby heat band (groups, substantive only):\n")
  groups |>
    filter(bill_class == "substantive") |>
    count(lobby_band) |>
    mutate(share = round(n / sum(n), 3)) |>
    print()

  cat("\nAmong groups with a band (UHERO's Hawaii 2025 split was",
      "14% Divided / 8% Leaning / 78% One-sided):\n")
  groups |>
    filter(bill_class == "substantive",
           lobby_band %in% c("Divided", "Leaning", "One-sided")) |>
    count(lobby_band, lobby_lean) |>
    mutate(share = round(n / sum(n), 3)) |>
    print()

  cat("\nStage reached (groups):\n")
  print(count(groups, stage_level, stage))

  cat("\nMost contested (Divided, by organizations taking a side):\n")
  print(most_contested_bills(salience), n = 20)

  invisible(salience)
}
