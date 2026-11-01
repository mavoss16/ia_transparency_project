# 04b_lobbying_clients.R
#
# Builds the lobbying client table: one row per client name as filed, with the
# name and page slug the site uses. Organization pages key on client_slug.
#
# Client names on legis.iowa.gov come from a registry, not free text, so in the
# 91st GA no organization appears under two spellings (checked 2026-11-01 with
# case/punctuation folding, Jaro-Winkler < 0.06 and whole-word containment).
# The table therefore mostly passes names through. What it does:
#
#   - "Personal Interest-Name" clients (individuals lobbying for themselves,
#     spelled several ways, one "Intereset") become client_type "personal"
#     with client_name "Name (personal interest)".
#   - A trailing "c/o MultiState Associates LLC" (the lobbying firm or a
#     contact, on 6 names) is dropped from client_name.
#   - Hand fixes from data/legislature/lobbying_client_overrides.csv, shared
#     across sessions: action "rename" maps a filed name to client_name (for an
#     organization renamed between sessions, or a misspelling); "exclude"
#     drops a name that isn't a usable client (e.g. "res" on SSB1071).
#
# Output saved to data/legislature/ga{N}/lobbying/clients.rds
#
# Usage:
#   source("R/legislature/04b_lobbying_clients.R")
#   build_lobbying_clients()

library(dplyr)
library(readr)
library(stringr)
library(here)

source(here("R/legislature/session.R"))

PERSONAL_PATTERN <- regex("personal\\s+intere\\w*", ignore_case = TRUE)

#' Read the hand-maintained client overrides
#' @param path Path to the overrides CSV
#' @return Tibble with client, action, client_name, note
read_client_overrides <- function(path = here("data/legislature/lobbying_client_overrides.csv")) {
  read_csv(path, col_types = cols(.default = col_character()))
}

#' Name of the person behind a "Personal Interest" client
#' Handles "Personal Interest-Name", "Personal Interest- Name" and
#' "Name - Personal Interest".
#' @param client Client names as filed
#' @return The person's name
personal_name <- function(client) {
  client |>
    str_remove(PERSONAL_PATTERN) |>
    str_remove_all("^[\\s-]+|[\\s-]+$")
}

#' URL slug for a client name
#' @param name Display names
#' @return Lowercase, hyphen-separated slugs
client_slug <- function(name) {
  name |>
    str_to_lower() |>
    str_replace_all("&", " and ") |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_remove_all("^-|-$")
}

#' Build the lobbying client table
#'
#' @param ga             General Assembly (default: CURRENT_GA); sets the paths below
#' @param filings_path   Path to lobbyist_filings.rds (from 04_lobbyist_declarations.R)
#' @param overrides_path Path to the overrides CSV
#' @param output_path    Path to write output RDS
#' @return Tibble with client (as filed), client_name, client_slug,
#'   client_type ("organization" / "personal"), n_bills and n_lobbyists
build_lobbying_clients <- function(
    ga             = CURRENT_GA,
    filings_path   = file.path(ga_paths(ga)$lobbying, "lobbyist_filings.rds"),
    overrides_path = here("data/legislature/lobbying_client_overrides.csv"),
    output_path    = file.path(ga_paths(ga)$lobbying, "clients.rds")
) {
  filings   <- readRDS(filings_path) |> filter(!is.na(client))
  overrides <- read_client_overrides(overrides_path)

  unknown <- setdiff(overrides$client, filings$client)
  if (length(unknown) > 0) {
    message("Overrides for clients not in this session (ignored): ",
            paste(unknown, collapse = ", "))
  }

  clients <- filings |>
    summarise(
      n_bills     = n_distinct(bill),
      n_lobbyists = n_distinct(lobbyist_id),
      .by = client
    ) |>
    mutate(
      client_type = if_else(str_detect(client, PERSONAL_PATTERN), "personal", "organization"),
      client_name = if_else(
        client_type == "personal",
        paste0(personal_name(client), " (personal interest)"),
        str_squish(str_remove(client, regex("\\s+c/o\\s.*$", ignore_case = TRUE)))
      )
    ) |>
    left_join(
      overrides |> select(client, action, override_name = client_name),
      by = "client"
    ) |>
    filter(is.na(action) | action != "exclude") |>
    mutate(client_name = coalesce(if_else(action == "rename", override_name, NA), client_name)) |>
    mutate(client_slug = client_slug(client_name)) |>
    select(client, client_name, client_slug, client_type, n_bills, n_lobbyists) |>
    arrange(client_name)

  # Two filed names may share a slug only when they share a client_name (a
  # rename override merging them); otherwise their pages would collide.
  collisions <- clients |>
    distinct(client_slug, client_name) |>
    filter(n() > 1, .by = client_slug)
  if (nrow(collisions) > 0) {
    stop("Client slugs collide: ", paste(unique(collisions$client_slug), collapse = ", "))
  }

  saveRDS(clients, output_path)
  message(sprintf(
    "Saved %d client names (%d pages: %d organizations, %d personal) to %s",
    nrow(clients), n_distinct(clients$client_slug),
    n_distinct(clients$client_slug[clients$client_type == "organization"]),
    n_distinct(clients$client_slug[clients$client_type == "personal"]),
    output_path
  ))
  invisible(clients)
}
