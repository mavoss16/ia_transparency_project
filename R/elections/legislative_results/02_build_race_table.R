# 02_build_race_table.R
# Sum the precinct results into one row per candidate per race: the table the
# legislator pages' electoral history reads.
#
# Input:  data/elections/processed/legislative_results_precinct.rds (01_parse_precinct_results.R)
# Output: data/elections/processed/legislative_results.rds, one row per
#   year × type × chamber × district × party (primaries) × candidate:
#     year, type, election_date, district_map (the map the district number
#       refers to: "2001", "2011" or "2021"), chamber, district,
#     primary_party (the primary's party; NA for generals),
#     candidate ("Write-in" sums every write-in), party, party_source,
#     votes, race_votes (all candidates and write-ins), pct (of race_votes),
#     rank, winner, unopposed, no_candidate, convention, margin, margin_pct,
#     counties, source_url
#
# pct and margin_pct are shares of race_votes, write-ins included. margin
# (per race, repeated on each row): top named candidate's votes minus the
# second's; NA when fewer than two named candidates ran. Incumbent, open seat
# and people_id come from the candidate crosswalk (plan step 4), not here.
#
# winner: the top vote-getter. In a primary the nominee needs at least 35% of
#   the vote; below that the nomination goes to a party convention
#   (convention = TRUE, nobody marked winner). Write-ins never win a primary
#   here: a party with no filer usually has no nominee or a convention one,
#   and a write-in nomination is only in the canvass. A general write-in
#   "winner" is a write-in candidate whose name the results don't give.
# unopposed: one named candidate on the ballot (write-ins aside);
#   no_candidate: none (a primary nobody filed for).
# party (generals): the results file's party label where it prints one
#   (party_source "results"), else the party of the primary the candidate won
#   that year ("primary"); otherwise NA. Primaries: the primary's party.
#
# Usage:
#   source("R/elections/legislative_results/02_build_race_table.R")
#   races <- build_race_table()
#   race_summary(races)
#   check_race_table(races)

library(here)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(lubridate)

INPUT  <- here("data/elections/processed/legislative_results_precinct.rds")
OUTPUT <- here("data/elections/processed/legislative_results.rds")

PRIMARY_THRESHOLD <- 0.35  # Iowa Code 43.65: below this, a convention nominates

# RESULT_SOURCES (which page or file each election came from), without running
# anything else in the downloader
source_url_table <- function() {
  env <- new.env()
  sys.source(here("R/elections/download/election_results.R"), envir = env)
  env$RESULT_SOURCES |>
    mutate(
      year = as.integer(year),
      source_url = case_when(
        source == "sos_county"    ~ paste0("https://sos.iowa.gov/", location),
        source == "sos_statewide" ~ location,
        source == "enr"           ~ paste0("https://electionresults.iowa.gov/IA/", location, "/")
      )
    ) |>
    select(year, type, source_url)
}

# Iowa: primary on the first Tuesday in June, general on the Tuesday after the
# first Monday in November
election_date <- function(year, type) {
  first_tuesday <- \(y, m) {
    d <- make_date(y, m, 1)
    d + (2 - wday(d, week_start = 1)) %% 7
  }
  general <- first_tuesday(year, 11)
  general <- if_else(day(general) == 1, general + 7, general)
  if_else(type == "primary", first_tuesday(year, 6), general)
}

district_map <- function(year) {
  case_when(year < 2012 ~ "2001", year < 2022 ~ "2011", .default = "2021")
}

# Party labels as the results print them → one spelling
standard_party <- function(x) {
  case_when(
    str_detect(x, regex("^dem", ignore_case = TRUE)) ~ "Democratic",
    str_detect(x, regex("^rep", ignore_case = TRUE)) ~ "Republican",
    str_detect(x, regex("^lib", ignore_case = TRUE)) ~ "Libertarian",
    .default = x
  )
}

# 2010 prints names in capitals: "CLEL BAUDLER" → "Clel Baudler"
fix_caps <- function(x) {
  caps <- !is.na(x) & x == str_to_upper(x) & str_detect(x, "[A-Z]{2}")
  titled <- str_to_title(x) |>
    str_replace_all("\\b(Ii|Iii|Iv)\\b", str_to_upper) |>
    str_replace_all("\\bMc([a-z])", \(m) paste0("Mc", str_to_upper(str_sub(m, 3))))
  if_else(caps, titled, x)
}

# Matching key across files: first and last name, lower case, no punctuation
name_key <- function(x) {
  words <- str_split(str_to_lower(str_remove_all(x, "[^A-Za-z ]")), "\\s+")
  map_chr(words, \(w) {
    w <- w[w != "" & !w %in% c("jr", "sr", "ii", "iii", "iv")]
    if (!length(w)) NA_character_ else paste(w[1], w[length(w)])
  })
}

build_race_table <- function(precinct = readRDS(INPUT)) {
  races <- precinct |>
    mutate(
      candidate     = fix_caps(candidate),
      primary_party = if_else(type == "primary", party, NA_character_),
      party         = standard_party(party)
    ) |>
    summarise(
      votes    = sum(votes),
      counties = n_distinct(county),
      # A county file may lack the label (Adair 2016) while others print it
      party    = first(party[!is.na(party)]),
      .by = c(year, type, chamber, district, primary_party, candidate)
    ) |>
    mutate(party_source = if_else(!is.na(party), "results", NA_character_))

  # Generals without a printed party: the primary the candidate won that year
  nominees <- races |>
    filter(type == "primary", candidate != "Write-in") |>
    mutate(race_votes = sum(votes), .by = c(year, chamber, district, primary_party)) |>
    filter(votes == max(votes), votes >= PRIMARY_THRESHOLD * race_votes,
           .by = c(year, chamber, district, primary_party)) |>
    transmute(year, chamber, district, key = name_key(candidate), nominee_party = primary_party) |>
    distinct()

  races <- races |>
    mutate(key = name_key(candidate)) |>
    left_join(nominees, by = c("year", "chamber", "district", "key"), relationship = "many-to-one") |>
    mutate(
      fill         = type == "general" & is.na(party) & candidate != "Write-in" & !is.na(nominee_party),
      party_source = if_else(fill, "primary", party_source),
      party        = if_else(fill, nominee_party, party)
    ) |>
    select(-key, -nominee_party, -fill)

  races <- races |>
    mutate(
      race_votes = sum(votes),
      pct        = if_else(race_votes > 0, votes / race_votes, NA_real_),
      rank       = min_rank(desc(votes)),
      named      = sum(candidate != "Write-in"),
      unopposed  = named == 1,
      no_candidate = named == 0,
      top_pct    = max(pct[candidate != "Write-in"], 0, na.rm = TRUE),
      convention = type == "primary" & !no_candidate & top_pct < PRIMARY_THRESHOLD,
      # A primary write-in "win" is usually no nominee; who (if anyone) was
      # nominated by write-in is in the canvass, not these results
      winner     = rank == 1 & votes > 0 & !convention &
                   !(type == "primary" & candidate == "Write-in"),
      # First minus second named candidate; NA with fewer than two
      margin     = if (first(named) >= 2) diff(sort(votes[candidate != "Write-in"], decreasing = TRUE)[2:1]) else NA_integer_,
      margin_pct = margin / race_votes,
      .by = c(year, type, chamber, district, primary_party)
    ) |>
    left_join(source_url_table(), by = c("year", "type")) |>
    mutate(
      election_date = election_date(year, type),
      district_map  = district_map(year)
    ) |>
    select(year, type, election_date, district_map, chamber, district, primary_party,
           candidate, party, party_source, votes, race_votes, pct, rank,
           winner, unopposed, no_candidate, convention, margin, margin_pct,
           counties, source_url) |>
    arrange(year, type, chamber, district, primary_party, rank)

  saveRDS(races, OUTPUT)
  message("Saved ", nrow(races), " rows to ", OUTPUT)
  invisible(races)
}

# Per election: races, unopposed races, and how much party is still missing
race_summary <- function(races) {
  races |>
    summarise(
      house_races   = n_distinct(paste(district, primary_party)[chamber == "house"]),
      senate_races  = n_distinct(paste(district, primary_party)[chamber == "senate"]),
      unopposed     = n_distinct(paste(chamber, district, primary_party)[unopposed]),
      no_candidate  = n_distinct(paste(chamber, district, primary_party)[no_candidate]),
      conventions   = n_distinct(paste(chamber, district, primary_party)[convention]),
      candidates    = sum(candidate != "Write-in"),
      party_missing = sum(is.na(party) & candidate != "Write-in"),
      party_from_primary = sum(party_source %in% "primary"),
      .by = c(year, type)
    ) |>
    arrange(year, type)
}

# Problems worth a look before the table feeds pages; each element is a tibble
check_race_table <- function(races) {
  race_cols <- c("year", "type", "chamber", "district", "primary_party")
  list(
    # Not exactly one winner, other than conventions and primaries nobody filed for
    winners = races |>
      summarise(winners = sum(winner), skip = any(convention | no_candidate), .by = all_of(race_cols)) |>
      filter(winners != 1, !skip),
    # Write-ins ahead of every named candidate
    write_in_won = races |> filter(winner, candidate == "Write-in"),
    # Two names in one race sharing a surname: likely one person spelled two ways
    name_variants = races |>
      filter(candidate != "Write-in") |>
      mutate(last = word(str_remove(candidate, ",? (Jr|Sr|II|III|IV)\\.?$"), -1)) |>
      filter(n() > 1, .by = c(all_of(race_cols), last)),
    # A named candidate missing from some of the race's counties (a county file
    # not downloaded or not parsed)
    missing_counties = races |>
      filter(candidate != "Write-in") |>
      mutate(race_counties = max(counties), .by = all_of(race_cols)) |>
      filter(counties < race_counties) |>
      select(all_of(race_cols), candidate, counties, race_counties)
  )
}

if (sys.nframe() == 0) {
  races <- build_race_table()
  print(race_summary(races), n = Inf, width = Inf)
  iwalk(check_race_table(races), \(x, name) {
    message("\n", name)
    print(x, n = Inf, width = Inf)
  })
}
