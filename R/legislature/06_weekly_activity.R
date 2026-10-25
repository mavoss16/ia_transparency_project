# 06_weekly_activity.R
#
# Builds the dated, classified action table behind the weekly activity
# summary (home page card + one page per week). Plan and counting rules:
# notes/legislature/2026-10-24_weekly-activity-summary.md
#
# Output: data/legislature/bills/bill_actions.rds — one row per history
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

GA          <- 91
GROUPS_PATH <- here("data/legislature/bills/groups.rds")
OUTPUT_PATH <- here("data/legislature/bills/bill_actions.rds")

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
  here(sprintf("legiscan/files_ga%d_derived", ga))
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
    groups_path = GROUPS_PATH,
    output_path = OUTPUT_PATH
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
