# 04c_lobbying_organizations.R
#
# Per-organization lobbying data for the organization pages, at the bill-group
# level (a renumbered bill's committee version and floor version are one
# group, so counting bills would make renumbered bills look like they died).
#
# Each organization counts once per group, at its most recent declaration on
# any bill in the group (the same rule 05's lobby heat uses). Organizations
# are keyed by client_slug from 04b, so a filed name excluded there drops out.
#
# Outcomes come from the group's stage (05's furthest stage on the site's
# status scale), bucketed:
#   Signed into law        Signed by Governor (incl. item vetoes)
#   Vetoed                 Vetoed
#   Passed a chamber       Passed one or both chambers, not enacted (joint
#                          resolutions stop here: they don't go to the Governor)
#   Didn't pass a chamber  Introduced through Passed committee
#   Adopted                Resolutions adopted
# Outcome rates use substantive bills only (05's bill_class), because
# resolutions and commemorative bills nearly always pass. Undecided bills
# became law more often than supported ones in the 91st, so every rate is
# shown next to the session baseline, never as a bare "win rate".
#
# Output, in data/legislature/ga{N}/lobbying/:
#   organization_bills.rds      one row per organization and bill group
#   organization_outcomes.rds   per organization, position and outcome
#                               (substantive groups only)
#   outcome_baseline.rds        the same counts over all organizations
#   organization_lobbyists.rds  per organization and lobbyist
#
# Run after 04b (clients.rds) and 05 (salience.rds).
#
# Usage:
#   source("R/legislature/04c_lobbying_organizations.R")
#   build_lobbying_organizations()

library(dplyr)
library(stringr)
library(here)

source(here("R/legislature/session.R"))

OUTCOME_LEVELS <- c("Signed into law", "Vetoed", "Passed a chamber",
                    "Didn't pass a chamber", "Adopted")
POSITION_LEVELS <- c("For", "Against", "Undecided", "Withdrawn")

#' Outcome bucket for a group's stage
#' @param stage Stage names from salience.rds
#' @return Factor with levels OUTCOME_LEVELS
stage_outcome <- function(stage) {
  out <- case_when(
    stage == "Signed by Governor" ~ "Signed into law",
    stage == "Vetoed"             ~ "Vetoed",
    stage == "Adopted"            ~ "Adopted",
    stage %in% c("Passed one chamber", "Passed both chambers") ~ "Passed a chamber",
    !is.na(stage)                 ~ "Didn't pass a chamber"
  )
  factor(out, levels = OUTCOME_LEVELS)
}

#' Count outcomes by position, with each outcome's share of the position
#' Every position appears with every outcome (zeros included), except
#' "Adopted", which substantive bills never reach.
#' @param org_bills Rows of organization_bills (substantive only)
#' @param ... Extra grouping columns (e.g. client_slug)
#' @return Tibble with ..., position, outcome, n, n_position, share
count_outcomes <- function(org_bills, ...) {
  org_bills |>
    filter(position %in% c("For", "Against", "Undecided")) |>
    mutate(
      position = droplevels(position),
      outcome  = factor(outcome, levels = setdiff(OUTCOME_LEVELS, "Adopted"))
    ) |>
    count(..., position, outcome, .drop = FALSE) |>
    group_by(..., position) |>
    mutate(n_position = sum(n)) |>
    ungroup() |>
    mutate(share = if_else(n_position > 0, n / n_position, NA_real_))
}

#' Build the per-organization lobbying tables
#'
#' @param ga General Assembly (default: CURRENT_GA); sets the paths below
#' @param lobbying_dir Folder with lobbying inputs and outputs
#' @param salience_path Path to salience.rds (from 05_salience_scores.R)
#' @return Invisible list of the four output tibbles
build_lobbying_organizations <- function(
    ga            = CURRENT_GA,
    lobbying_dir  = ga_paths(ga)$lobbying,
    salience_path = file.path(ga_paths(ga)$bills, "salience.rds")
) {
  clients <- readRDS(file.path(lobbying_dir, "clients.rds")) |>
    select(client, client_slug, client_name, client_type)
  declarations <- readRDS(file.path(lobbying_dir, "lobbyist_declarations.rds")) |>
    filter(!is.na(client))
  filings <- readRDS(file.path(lobbying_dir, "lobbyist_filings.rds")) |>
    filter(!is.na(client))

  groups <- readRDS(salience_path) |>
    select(bill = bill_number, bill_group_id, lead_bill, group_size, bill_class, stage)
  # A group's class is its lead bill's (members are companions of one bill)
  group_info <- groups |>
    filter(bill == lead_bill) |>
    distinct(bill_group_id, lead_bill, group_size, bill_class, stage) |>
    mutate(outcome = stage_outcome(stage))

  # ── Organization × bill group ───────────────────────────────────────────
  org_bills <- declarations |>
    inner_join(clients, by = "client") |>
    inner_join(select(groups, bill, bill_group_id), by = "bill") |>
    summarise(
      bills_declared = list(sort(unique(bill))),
      position = most_recent_declaration[which.max(date)],
      date     = max(date),
      .by = c(client_slug, client_name, client_type, bill_group_id)
    ) |>
    left_join(group_info, by = "bill_group_id") |>
    mutate(position = factor(position, levels = POSITION_LEVELS)) |>
    select(client_slug, client_name, client_type, bill_group_id, lead_bill,
           group_size, bills_declared, position, date, bill_class, stage, outcome) |>
    arrange(client_slug, desc(date))

  substantive <- filter(org_bills, bill_class == "substantive")

  org_outcomes <- count_outcomes(substantive, client_slug)
  baseline     <- count_outcomes(substantive)

  # ── Organization × lobbyist ─────────────────────────────────────────────
  org_lobbyists <- filings |>
    inner_join(clients, by = "client") |>
    summarise(
      lobbyist   = last(lobbyist, order_by = date),
      n_bills    = n_distinct(bill),
      first_date = min(date),
      last_date  = max(date),
      .by = c(client_slug, lobbyist_id)
    ) |>
    arrange(client_slug, desc(n_bills))

  outputs <- list(
    organization_bills      = org_bills,
    organization_outcomes   = org_outcomes,
    outcome_baseline        = baseline,
    organization_lobbyists  = org_lobbyists
  )
  for (name in names(outputs)) {
    saveRDS(outputs[[name]], file.path(lobbying_dir, paste0(name, ".rds")))
  }

  message(sprintf(
    "Saved %d organization–group rows (%d organizations, %d groups), %d lobbyist rows to %s",
    nrow(org_bills), n_distinct(org_bills$client_slug),
    n_distinct(org_bills$bill_group_id), nrow(org_lobbyists), lobbying_dir
  ))
  invisible(outputs)
}

# Run if executed directly
if (sys.nframe() == 0) {
  build_lobbying_organizations()
}
