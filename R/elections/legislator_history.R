# legislator_history.R
#
# A legislator's electoral history, read from the race table, for the
# Elections tab on legislator pages. Data only; the markup is in
# R/elections/ui_helpers.R.
#
# Input: data/elections/processed/legislative_results.rds (02_build_race_table.R,
#        with people_id, incumbent and open_seat from 03_match_legislators.R)
#
# Usage:
#   source(here::here("R/elections/legislator_history.R"))
#   results <- load_legislative_results()
#   races   <- legislator_races(21044, results, legiscan_party = "R")
#   tenure_text(races, "Ray Sorensen", "house")

library(dplyr)
library(purrr)
library(stringr)

LEGISLATIVE_RESULTS <- here::here("data/elections/processed/legislative_results.rds")

#' The race table, one row per candidate per race
load_legislative_results <- function(path = LEGISLATIVE_RESULTS) readRDS(path)

#' Regular elections from `from` (default: the first general loaded) on that
#' are not in the race table yet
#' @return list(general = years, primary = years)
missing_elections <- function(results, from = min(results$year[results$type == "general"])) {
  years <- seq(from, max(results$year[results$type == "general"]), by = 2L)
  loaded <- \(t) unique(results$year[results$type == t])
  list(general = setdiff(years, loaded("general")),
       primary = setdiff(years, loaded("primary")))
}

#' "2018", "2018 and 2020", "2018, 2020 and 2022"
join_and <- function(x) {
  x <- as.character(x)
  if (length(x) <= 1) return(paste(x, collapse = ""))
  paste(paste(x[-length(x)], collapse = ", "), "and", x[length(x)])
}

#' "Iowa House" / "Iowa Senate"
chamber_body <- function(chamber) if_else(chamber == "senate", "Iowa Senate", "Iowa House")

#' "House District 23"
seat_label <- function(chamber, district) {
  paste(if_else(chamber == "senate", "Senate", "House"), "District", district)
}

LEGISCAN_PARTY <- c(R = "Republican", D = "Democratic", I = "Independent", L = "Libertarian")

#' Every race a legislator ran in, with all of its candidates
#'
#' Races are grouped into blocks, one per year and seat (newest first). A block
#' holds the person's own races (general, special, their own primary) and,
#' marked `other_primary`, the other parties' primaries for the same seat that
#' year.
#' @param people_id LegiScan people_id
#' @param results The race table (load_legislative_results())
#' @param legiscan_party LegiScan party code ("R", "D", ...), used where the
#'   results file gives the legislator no party (most 2018–2020 generals)
#' @return Candidate rows plus block, race, is_self and other_primary; zero rows
#'   when no race is matched to the person
legislator_races <- function(people_id, results, legiscan_party = NA_character_) {
  id <- people_id
  race_cols <- c("year", "type", "chamber", "district", "primary_party")

  own <- results |>
    filter(people_id %in% id) |>
    distinct(across(all_of(race_cols)))
  if (nrow(own) == 0) return(results[0, ] |> mutate(block = character(), race = character(),
                                                     is_self = logical(), other_primary = logical()))

  seats <- own |> distinct(year, chamber, district)
  others <- results |>
    filter(type == "primary") |>
    semi_join(seats, by = c("year", "chamber", "district")) |>
    anti_join(own, by = race_cols) |>
    distinct(across(all_of(race_cols)))

  fill_party <- unname(LEGISCAN_PARTY[legiscan_party])

  results |>
    semi_join(bind_rows(own, others), by = race_cols) |>
    mutate(is_self = people_id %in% id) |>
    mutate(other_primary = type == "primary" & !any(is_self), .by = all_of(race_cols)) |>
    mutate(
      party_source = if_else(is_self & is.na(party) & !is.na(fill_party), "legiscan", party_source),
      party = if_else(is_self & is.na(party), fill_party, party),
      block = paste(year, chamber, district),
      race = paste(year, type, chamber, district, coalesce(primary_party, ""))
    ) |>
    mutate(.block_date = max(election_date), .by = block) |>
    # Newest block first; in a block the person's general or special, then their
    # primary, then the other primaries; write-ins last, else by votes (rank)
    arrange(desc(.block_date), block, other_primary, type == "primary",
            primary_party, candidate == "Write-in", rank) |>
    select(-.block_date)
}

#' The person's wins in generals and specials, oldest first
legislator_wins <- function(races) {
  races |>
    filter(is_self, winner, type %in% c("general", "special")) |>
    arrange(election_date)
}

#' Tenure in one chamber, as the profile header line or the tab's opening sentence
#'
#' Says "first elected" only when that is known: the first win in the data was
#' a special (which fills a vacancy) or a general the person didn't enter as
#' incumbent. Otherwise earlier results are missing (no 2010 or 2014 general
#' yet), and the text says so rather than dating a career from the data's start.
#' @param races legislator_races() output
#' @param name Display name, used by the sentence form
#' @param chamber The chamber the person sits in now ("house" or "senate")
#' @param form "line" (profile header) or "sentence" (Elections tab)
#' @return A string, or NULL when the person has no win in the data
tenure_text <- function(races, name, chamber, form = c("line", "sentence")) {
  form <- match.arg(form)
  wins <- legislator_wins(races)
  here_wins <- wins |> filter(chamber == !!chamber)
  if (nrow(here_wins) == 0) return(NULL)

  body <- chamber_body(chamber)
  first <- here_wins[1, ]
  known_start <- first$type == "special" || isFALSE(first$incumbent)
  later <- here_wins$year[-1]

  text <- if (known_start) {
    how <- if (first$type == "special") paste("in a", first$year, "special election") else paste("in", first$year)
    if (form == "line") {
      paste0("First elected to the ", body, " ", how,
             if (length(later) > 0) paste0(" · re-elected ", join_and(later)))
    } else {
      paste0(name, " was first elected to the ", body, " ", how,
             if (length(later) > 0) paste0(" and re-elected in ", join_and(later)), ".")
    }
  } else {
    if (form == "line") {
      paste0("Elected to the ", body, " in ", join_and(here_wins$year),
             " · earlier results not yet included")
    } else {
      paste0(name, " won ", body, " elections in ", join_and(here_wins$year),
             ". Earlier results are not yet included.")
    }
  }

  other <- wins |> filter(chamber != !!chamber)
  if (nrow(other) > 0) {
    span_years <- range(other$year)
    years_text <- if (span_years[1] == span_years[2]) span_years[1] else paste0(span_years[1], "–", span_years[2])
    text <- if (form == "line") {
      paste0(text, " · previously elected to the ", chamber_body(other$chamber[1]), " (", years_text, ")")
    } else {
      paste0(text, " Before that, ", word(name, -1), " was elected to the ",
             chamber_body(other$chamber[1]), " (", years_text, ").")
    }
  }
  text
}

#' The district the person represented under each map, for the tab's summary:
#' "Since the 2021 redistricting, Sorensen has represented District 23; before
#' that, District 20." NULL when the district didn't change.
redistricting_text <- function(races, name, chamber) {
  wins <- legislator_wins(races) |> filter(chamber == !!chamber)
  by_map <- wins |> summarise(district = last(district), .by = district_map)
  if (nrow(by_map) < 2 || n_distinct(by_map$district) < 2) return(NULL)
  now <- by_map[nrow(by_map), ]
  before <- by_map[nrow(by_map) - 1, ]
  sprintf("Since the %s redistricting, %s has represented District %d; before that, District %d.",
          now$district_map, word(name, -1), now$district, before$district)
}

#' The person's most recent general or special result, for the district card
#' @return One row of legislator_races(), or NULL
latest_result <- function(races) {
  latest <- races |>
    filter(is_self, type %in% c("general", "special")) |>
    slice_max(election_date, n = 1, with_ties = FALSE)
  if (nrow(latest) == 0) NULL else latest
}

#' Context notes for one block: a new district map, an open seat, Iowa's 35%
#' convention rule. Notes are plain facts; link targets come from `page_href`.
#' @param block_races The block's rows of legislator_races()
#' @param races All of the person's races (for their earlier wins)
#' @param results The race table (for the seat's previous holder)
#' @param page_href function(people_id) -> href or NULL, to link legislators
#' @return A list of notes, each list(text, link_text, href) where link_text
#'   and href may be NULL; the link is placed where "{link}" appears in text
block_notes <- function(block_races, races, results, page_href = \(id) NULL) {
  notes <- list()
  main <- block_races |> filter(!other_primary)
  first_row <- main[1, ]
  when <- min(main$election_date)

  # First race under a new map, after an earlier win
  prior <- legislator_wins(races) |> filter(election_date < when)
  if (nrow(prior) > 0) {
    last_prior <- prior[nrow(prior), ]
    if (last_prior$district_map != first_row$district_map) {
      notes <- c(notes, list(list(text = sprintf(
        "First election under the %s district map. Previously represented %s.",
        first_row$district_map, seat_label(last_prior$chamber, last_prior$district)))))
    }
  }

  # Open seat: name the previous holder when the same map's last winner is known
  seat_open <- main |> filter(type %in% c("general", "special")) |> pull(open_seat)
  if (length(seat_open) > 0 && isTRUE(seat_open[1])) {
    holder <- results |>
      filter(chamber == first_row$chamber, district == first_row$district,
             district_map == first_row$district_map, type %in% c("general", "special"),
             winner, candidate != "Write-in", election_date < when) |>
      slice_max(election_date, n = 1, with_ties = FALSE)
    note <- if (nrow(holder) == 1) {
      href <- if (!is.na(holder$people_id)) page_href(holder$people_id) else NULL
      list(text = "Open seat: the incumbent, {link}, did not run.",
           link_text = holder$candidate, href = href)
    } else {
      list(text = "Open seat: no incumbent ran.")
    }
    notes <- c(notes, list(note))
  }

  # Iowa Code 43.66: a primary winner needs 35%; otherwise a convention picks
  convention <- main |> filter(type == "primary", convention) |> distinct(primary_party)
  for (party in convention$primary_party) {
    notes <- c(notes, list(list(text = sprintf(
      "No candidate in the %s primary won 35%% of the vote, so a party convention chose the nominee.",
      party))))
  }
  notes
}

#' Plain-text fingerprint of a person's races, for the render manifest
election_digest <- function(people_id, results) {
  races <- legislator_races(people_id, results)
  if (nrow(races) == 0) return("none")
  rows <- races |>
    transmute(row = paste(race, candidate, party, votes, winner, incumbent, open_seat,
                          people_id, source_url, sep = "\t")) |>
    pull(row)
  rlang::hash(sort(rows))
}
