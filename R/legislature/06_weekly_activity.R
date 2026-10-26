# 06_weekly_activity.R
#
# Builds the dated, classified action table behind the weekly activity
# summary (home page card + one page per week). Plan and counting rules:
# notes/legislature/2026-10-24_weekly-activity-summary.md
#
# Output: data/legislature/ga{N}/bills/bill_actions.rds — one row per history
# action, carrying its milestone (classify_action() in utils.R, the same
# rules as bill status), its week, its bill group, and whether the bill was
# born from a committee renumbering.
#
# Counting rules, enforced by the helpers below rather than left to callers:
#   - The unit is the bill GROUP (groups.rds), matching the week table's rows.
#     A period's count for a milestone is the number of distinct groups with
#     at least one action of that kind in the period, never a count of
#     actions: 650 bills have a committee report in each chamber and 389 have
#     more than one floor passage.
#   - A study bill that passes committee is renumbered ("Committee report
#     approving bill, renumbered as HF 123.") and the new bill is introduced
#     a day or so later. That introduction is the committee step seen twice,
#     so bills born this way are flagged committee_originated and their
#     introduction does not count as one (counts_as_introduction) — provided
#     the source bill is in the same group, whose introduction already
#     counted. 03 adds every renumbering as a grouping edge, so source and
#     target always share a group; the check is a safeguard so that a group
#     can never end up with no introduction at all.
#   - A week runs Monday–Sunday and is labelled by its Monday.
#   - A week's counts are not the sum of its days': one group can reach the
#     same milestone on two days.
#
# Usage:
#   source("R/legislature/06_weekly_activity.R")
#   bill_actions <- build_bill_actions()
#   weekly_activity_summary(bill_actions)
#   latest_active_week(bill_actions)
#   period_milestone_counts(bill_actions, as.Date("2026-02-16"))

library(dplyr)
library(stringr)
library(readr)
library(lubridate)
library(here)

source(here("R/legislature/utils.R"))

# =============================================================================
# Configuration
# =============================================================================

GA          <- CURRENT_GA
GROUPS_PATH <- file.path(ga_paths(GA)$bills, "groups.rds")
OUTPUT_PATH <- file.path(ga_paths(GA)$bills, "bill_actions.rds")

# Milestones in display order for the count cards (least to furthest).
# "vetoed" is shown only in periods where it occurs.
MILESTONE_LEVELS <- c("introduced", "subcommittee", "committee",
                      "floor", "signed", "vetoed")

MILESTONE_LABELS <- c(
  introduced   = "Introduced",
  subcommittee = "Passed subcommittee",
  committee    = "Passed committee",
  floor        = "Passed a chamber",
  signed       = "Signed by Governor",
  vetoed       = "Vetoed"
)

# =============================================================================
# Helpers
# =============================================================================

derived_csv_dir <- function(ga = GA) {
  ga_paths(ga)$derived
}

# =============================================================================
# Build
# =============================================================================

#' Build and save the classified action table
#'
#' @param ga          General Assembly number (selects the LegiScan directory)
#' @param groups_path Path to groups.rds (03_bill_relationships.R)
#' @param output_path Where to save bill_actions.rds
#' @return Tibble, one row per action, invisibly
build_bill_actions <- function(
    ga          = GA,
    groups_path = file.path(ga_paths(ga)$bills, "groups.rds"),
    output_path = file.path(ga_paths(ga)$bills, "bill_actions.rds")
) {
  csv_dir <- derived_csv_dir(ga)

  bills <- read_csv(file.path(csv_dir, "bills.csv"),
                    col_select = c(bill_id, bill_number),
                    show_col_types = FALSE)
  history <- read_csv(file.path(csv_dir, "history.csv"), show_col_types = FALSE)
  groups <- readRDS(groups_path) |>
    select(bill, bill_group_id)

  actions <- history |>
    inner_join(bills, by = "bill_id") |>
    rename(bill = bill_number) |>
    left_join(groups, by = "bill")

  # A bill missing from groups.rds would silently drop out of every group
  # count, so refuse to build rather than undercount.
  ungrouped <- actions |> filter(is.na(bill_group_id)) |> distinct(bill) |> pull(bill)
  if (length(ungrouped) > 0) {
    stop(length(ungrouped), " bill(s) have history but no group in groups.rds (",
         paste(head(ungrouped, 5), collapse = ", "),
         "). Re-run 03_bill_relationships.R first.")
  }

  # Committee renumberings: source bill -> the new bill it became. A bill
  # renumbered more than once keeps its earliest source.
  renumbered <- actions |>
    mutate(target = parse_renumbered_target(action)) |>
    filter(!is.na(target), target %in% bills$bill_number) |>
    arrange(date, sequence) |>
    distinct(target, .keep_all = TRUE) |>
    select(bill = target, renumbered_from = bill) |>
    left_join(groups |> rename(renumbered_from = bill, source_group_id = bill_group_id),
              by = "renumbered_from")

  actions <- actions |>
    left_join(renumbered, by = "bill") |>
    mutate(
      milestone             = factor(classify_action(action), levels = MILESTONE_LEVELS),
      floor_chamber         = floor_chamber(action, chamber),
      week_start            = floor_date(date, "week", week_start = 1),
      committee_originated  = !is.na(renumbered_from),
      counts_as_introduction = milestone %in% "introduced" &
        !(committee_originated & coalesce(source_group_id == bill_group_id, FALSE))
    ) |>
    select(bill, bill_group_id, date, week_start, chamber, sequence, action,
           milestone, floor_chamber, committee_originated, renumbered_from,
           counts_as_introduction) |>
    arrange(date, bill, sequence)

  saveRDS(actions, output_path)
  message(sprintf(
    "Saved %s actions (%s bills, %s groups, %d weeks with activity) to %s",
    format(nrow(actions), big.mark = ","),
    format(n_distinct(actions$bill), big.mark = ","),
    format(n_distinct(actions$bill_group_id), big.mark = ","),
    n_distinct(actions$week_start[!is.na(actions$milestone)]),
    output_path
  ))

  invisible(actions)
}

# =============================================================================
# Period summaries
# =============================================================================

#' Load bill_actions.rds
load_bill_actions <- function(path = OUTPUT_PATH) {
  readRDS(path)
}

#' Milestone actions that count toward a period's numbers
#'
#' Drops procedural actions and committee-originated introductions.
counted_milestones <- function(bill_actions) {
  bill_actions |>
    filter(!is.na(milestone),
           milestone != "introduced" | counts_as_introduction)
}

#' Distinct bill groups reaching each milestone in a period
#'
#' @param bill_actions Output of build_bill_actions()
#' @param from         First day of the period (a week's Monday, or a day)
#' @param to           Last day of the period; defaults to the Sunday of the
#'   week starting at `from`
#' @return Tibble: milestone, label, n_groups — one row per milestone level,
#'   zeros included, so callers can lay out cards without checking
period_milestone_counts <- function(bill_actions, from, to = from + 6) {
  counted_milestones(bill_actions) |>
    filter(date >= from, date <= to) |>
    distinct(milestone, bill_group_id) |>
    count(milestone, name = "n_groups", .drop = FALSE) |>
    mutate(label = unname(MILESTONE_LABELS[as.character(milestone)])) |>
    select(milestone, label, n_groups)
}

#' One row per week that has any action, with its milestone counts
#'
#' active = at least one counted milestone. Weeks with only procedural
#' actions (a fiscal note in October) get a row with active = FALSE: they
#' have a page, but never become the default week.
weekly_activity_summary <- function(bill_actions) {
  totals <- bill_actions |>
    group_by(week_start) |>
    summarise(
      n_actions       = n(),
      n_groups_active = n_distinct(bill_group_id),
      .groups = "drop"
    )

  milestones <- counted_milestones(bill_actions) |>
    distinct(week_start, milestone, bill_group_id) |>
    count(week_start, milestone) |>
    tidyr::pivot_wider(names_from = milestone, values_from = n, values_fill = 0)

  # Every milestone column present even if it never occurs
  for (m in setdiff(MILESTONE_LEVELS, names(milestones))) milestones[[m]] <- 0L

  totals |>
    left_join(milestones, by = "week_start") |>
    mutate(across(all_of(MILESTONE_LEVELS), \(x) coalesce(as.integer(x), 0L)),
           active = rowSums(across(all_of(MILESTONE_LEVELS))) > 0) |>
    select(week_start, active, all_of(MILESTONE_LEVELS), n_groups_active, n_actions) |>
    arrange(desc(week_start))
}

#' Monday of the most recent week with at least one counted milestone
latest_active_week <- function(bill_actions) {
  max(counted_milestones(bill_actions)$week_start)
}

# =============================================================================
# Period table rows (week page / home card)
# =============================================================================

# Sort weight of a milestone within a period: furthest first in the table
MILESTONE_RANK <- c(introduced = 1, subcommittee = 2, committee = 3,
                    floor = 4, vetoed = 5, signed = 6)

#' Pill label for a counted milestone action
#'
#' Floor passage names its chamber, and a resolution's is "Adopted" rather
#' than "Passed", so the pill reads the way the action did.
milestone_pill_label <- function(milestone, action, floor_chamber) {
  milestone <- as.character(milestone)
  case_when(
    milestone == "floor" & str_detect(action, "^Resolution adopted") ~
      paste("Adopted in", floor_chamber),
    milestone == "floor" ~ paste("Passed", floor_chamber),
    .default = unname(MILESTONE_LABELS[milestone])
  )
}

#' One row per bill group with any action in a period
#'
#' @param bill_actions Output of build_bill_actions()
#' @param from,to      Period bounds (inclusive)
#' @param groups       groups.rds (for lead bill and current group status)
#' @param bills        bills.csv (bill_number, title)
#' @return Tibble, furthest milestone first: bill_group_id, lead_bill, title
#'   (raw LegiScan title of the lead bill), bills (chr: group members with an
#'   action in the period, lead first), milestones (chr: pill labels,
#'   furthest first; empty for procedural-only groups), rank (0 = procedural
#'   only), n_actions, group_status, actions (tibble of the period's actions)
period_group_rows <- function(bill_actions, from, to = from + 6, groups, bills) {
  period <- bill_actions |>
    filter(date >= from, date <= to) |>
    mutate(counted = !is.na(milestone) &
             (milestone != "introduced" | counts_as_introduction))

  if (nrow(period) == 0) {
    return(tibble(bill_group_id = integer(), lead_bill = character(),
                  title = character(), bills = list(), milestones = list(),
                  rank = numeric(), n_actions = integer(),
                  group_status = character(), actions = list()))
  }

  group_info <- groups |>
    distinct(bill_group_id, lead_bill, group_status) |>
    left_join(bills |> select(lead_bill = bill_number, title), by = "lead_bill")

  pills <- period |>
    filter(counted) |>
    mutate(label = milestone_pill_label(milestone, action, floor_chamber),
           rank  = MILESTONE_RANK[as.character(milestone)]) |>
    distinct(bill_group_id, label, rank) |>
    arrange(bill_group_id, desc(rank), label) |>
    group_by(bill_group_id) |>
    summarise(milestones = list(label), rank = max(rank), .groups = "drop")

  period |>
    arrange(date, bill, sequence) |>
    group_by(bill_group_id) |>
    summarise(
      bills     = list(unique(bill)),
      n_actions = n(),
      actions   = list(tibble(date, bill, chamber, action, counted)),
      .groups   = "drop"
    ) |>
    left_join(group_info, by = "bill_group_id") |>
    left_join(pills, by = "bill_group_id") |>
    mutate(
      # Lead bill first among the active members
      bills      = purrr::map2(bills, lead_bill, \(b, l) c(intersect(l, b), setdiff(sort(b), l))),
      milestones = purrr::map(milestones, \(m) if (is.null(m)) character(0) else m),
      rank       = coalesce(rank, 0)
    ) |>
    arrange(desc(rank), desc(n_actions), lead_bill) |>
    select(bill_group_id, lead_bill, title, bills, milestones, rank,
           n_actions, group_status, actions)
}
