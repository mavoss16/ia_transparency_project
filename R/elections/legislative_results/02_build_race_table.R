# 02_build_race_table.R
# Sum the precinct results into one row per candidate per race: the table the
# legislator pages' electoral history reads.
#
# Input:  data/elections/processed/legislative_results_precinct.rds (01_parse_precinct_results.R)
#         data/elections/processed/legislative_results_special.csv (special
#           elections, county rows entered from SOS canvasses or ENR; type "special")
#         data/elections/processed/legislative_results_corrections.csv (hand
#           fixes per race and candidate: correct_name for a misspelling the
#           spelling merge can't catch, write_in = TRUE for a write-in the
#           results don't mark; with a note)
# Output: data/elections/processed/legislative_results.rds, one row per
#   year × type × chamber × district × party (primaries) × candidate
#   (a second special for the same seat in one year would need election_date
#   in that key):
#     year, type, election_date, district_map (the map the district number
#       refers to: "2001", "2011" or "2021"), chamber, district,
#     primary_party (the primary's party; NA for generals),
#     candidate ("Write-in" sums every write-in), party, party_source,
#     votes, race_votes (all candidates and write-ins), pct (of race_votes),
#     rank, winner, unopposed, no_candidate, convention, margin, margin_pct,
#     write_in, counties, race_counties, source_url
#
# write_in: a named candidate who was a write-in, not on the ballot. A ballot
# candidate is printed in every county of the district, so a name that
# appears in fewer of the race's counties than the race covers is a write-in
# some county reported by name ("Kayla Koether", 2024 HD 63, Winneshiek only).
# A primary name with more votes in another party's primary for the same seat
# is also a write-in (2018 files list write-ins by name: Skyler Wheeler,
# HD 4 Democratic). It keeps its name and votes but counts like "Write-in"
# below. A name some county marks "(W)" or "(write-in)" (2020 primary) is a
# write-in, with the mark removed, and so is a name in a one-county primary
# that the race's unnamed write-ins outpoll. Other names written in within a
# one-county race can't be told apart from ballot candidates (the 2018
# Libertarian one-vote "winners"); list those in the corrections file.
#
# "Named" below means on the ballot: neither "Write-in" nor write_in.
# pct and margin_pct are shares of race_votes, write-ins included. margin
# (per race, repeated on each row): top named candidate's votes minus the
# second's; NA when fewer than two named candidates ran. Incumbent, open seat
# and people_id are added by 03_match_legislators.R.
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
#   that year ("primary"); otherwise NA. The 2026 general prints a code for
#   every party's candidates, so a ballot name with none there is "No Party"
#   ("no_code"). Primaries: the primary's party.
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

INPUT    <- here("data/elections/processed/legislative_results_precinct.rds")
SPECIALS <- here("data/elections/processed/legislative_results_special.csv")
CORRECTIONS <- here("data/elections/processed/legislative_results_corrections.csv")
OUTPUT   <- here("data/elections/processed/legislative_results.rds")

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
    x %in% c("NP", "NOP") ~ "No Party",  # ENR's county codes, 2026 general
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

# Special elections, entered by hand from the SOS canvasses: one row per county
# and candidate, in the precinct table's columns plus the special's own date
# and source
read_specials <- function(path = SPECIALS) {
  readr::read_csv(path, col_types = readr::cols(election_date = "D", district = "i", votes = "i", .default = "c")) |>
    transmute(
      year = as.integer(year(election_date)), type = "special", county, precinct = NA_character_,
      chamber = str_to_lower(chamber), district, party, candidate, votes,
      special_date = election_date, special_url = source_url
    )
}

# Hand fixes, one row per race and candidate (primary_party empty for generals)
read_corrections <- function(path = CORRECTIONS) {
  readr::read_csv(path, col_types = readr::cols(year = "i", district = "i", write_in = "l", .default = "c"))
}

# Write-in tallies under the files' own labels: "Write-in" in any case, and in
# some 2018 and 2020 primaries "Scattering" (Story), "Blank" / "(Blank)" and
# "No Name"
WRITE_IN_LABEL <- regex("^\\(?(write[- ]?in|scattering|blank|no name)\\)?$", ignore_case = TRUE)
# A write-in some county lists by name and marks: "Dennis Bush (W)"
WRITE_IN_MARK <- regex("\\s*\\((w|write[- ]?in)\\)$", ignore_case = TRUE)

build_race_table <- function(precinct = readRDS(INPUT), specials = read_specials(),
                             corrections = read_corrections()) {
  race_cols <- c("year", "type", "chamber", "district", "primary_party")
  races <- bind_rows(precinct, specials) |>
    mutate(
      candidate     = if_else(str_detect(candidate, WRITE_IN_LABEL), "Write-in", fix_caps(candidate)),
      marked        = str_detect(candidate, WRITE_IN_MARK),
      candidate     = str_remove(candidate, WRITE_IN_MARK),
      primary_party = if_else(type == "primary", party, NA_character_),
      party         = standard_party(party)
    ) |>
    left_join(corrections |> filter(!is.na(correct_name)) |> select(all_of(race_cols), candidate, correct_name),
              by = c(race_cols, "candidate")) |>
    mutate(
      candidate = coalesce(correct_name, candidate),
      spelling  = str_squish(str_remove_all(str_to_lower(candidate), "[^a-z ]"))
    ) |>
    # County files can differ in case or punctuation ("TJ Widbin" / "Tj Widbin",
    # "Matt W. Windschitl" / "Matt. W. Windschitl"): use the spelling with the
    # most votes in the race
    mutate(
      candidate = candidate[which.max(votes)],
      .by = c(year, type, chamber, district, primary_party, spelling)
    ) |>
    # Counties the race covers, write-in rows included
    mutate(race_counties = n_distinct(county), .by = c(year, type, chamber, district, primary_party)) |>
    summarise(
      votes    = sum(votes),
      counties = n_distinct(county),
      race_counties = first(race_counties),
      # A county file may lack the label (Adair 2016) while others print it
      party    = first(party[!is.na(party)]),
      special_date = first(special_date),
      special_url  = first(special_url),
      marked   = any(marked),
      .by = c(year, type, chamber, district, primary_party, candidate)
    ) |>
    left_join(corrections |> filter(write_in %in% TRUE) |> select(all_of(race_cols), candidate, listed = write_in),
              by = c(race_cols, "candidate")) |>
    mutate(
      party_source = if_else(!is.na(party), "results", NA_character_),
      key          = name_key(candidate),
      write_in     = candidate != "Write-in" &
                     ((race_counties > 1 & counties < race_counties) | marked | listed %in% TRUE)
    ) |>
    select(-marked, -listed) |>
    # A name in a one-county primary that the unnamed write-ins outpoll was
    # written in too (2018 and 2020 list write-ins by name; no other year has one)
    mutate(
      write_in_votes = sum(votes[candidate == "Write-in"]),
      write_in = write_in | (type == "primary" & race_counties == 1 & candidate != "Write-in" &
                             votes < write_in_votes),
      .by = all_of(race_cols)
    ) |>
    select(-write_in_votes) |>
    # A primary name with more votes in another party's primary for the seat
    # is that party's candidate, written in here
    mutate(
      write_in = write_in | (type == "primary" & candidate != "Write-in" &
                             n_distinct(primary_party) > 1 & votes < max(votes)),
      .by = c(year, type, chamber, district, key)
    )

  # Generals without a printed party: the primary the candidate won that year
  nominees <- races |>
    filter(type == "primary", candidate != "Write-in") |>
    mutate(race_votes = sum(votes), .by = c(year, chamber, district, primary_party)) |>
    filter(!write_in) |>
    filter(votes == max(votes), votes >= PRIMARY_THRESHOLD * race_votes,
           .by = c(year, chamber, district, primary_party)) |>
    transmute(year, chamber, district, key, nominee_party = primary_party) |>
    distinct()

  races <- races |>
    left_join(nominees, by = c("year", "chamber", "district", "key"), relationship = "many-to-one") |>
    mutate(
      fill         = type == "general" & is.na(party) & candidate != "Write-in" & !is.na(nominee_party),
      party_source = if_else(fill, "primary", party_source),
      party        = if_else(fill, nominee_party, party),
      no_party     = type == "general" & year == 2026 & is.na(party) & candidate != "Write-in" & !write_in,
      party_source = if_else(no_party, "no_code", party_source),
      party        = if_else(no_party, "No Party", party)
    ) |>
    select(-key, -nominee_party, -fill, -no_party)

  races <- races |>
    mutate(
      on_ballot  = candidate != "Write-in" & !write_in,
      race_votes = sum(votes),
      pct        = if_else(race_votes > 0, votes / race_votes, NA_real_),
      rank       = min_rank(desc(votes)),
      named      = sum(on_ballot),
      unopposed  = named == 1,
      no_candidate = named == 0,
      top_pct    = max(pct[on_ballot], 0, na.rm = TRUE),
      convention = type == "primary" & !no_candidate & top_pct < PRIMARY_THRESHOLD,
      # A primary write-in "win" is usually no nominee; who (if anyone) was
      # nominated by write-in is in the canvass, not these results
      winner     = rank == 1 & votes > 0 & !convention &
                   !(type == "primary" & !on_ballot),
      # First minus second named candidate; NA with fewer than two
      margin     = if (first(named) >= 2) diff(sort(votes[on_ballot], decreasing = TRUE)[2:1]) else NA_integer_,
      margin_pct = margin / race_votes,
      .by = c(year, type, chamber, district, primary_party)
    ) |>
    left_join(source_url_table(), by = c("year", "type")) |>
    mutate(
      election_date = coalesce(special_date, election_date(year, type)),
      source_url    = coalesce(special_url, source_url),
      district_map  = district_map(year)
    ) |>
    select(year, type, election_date, district_map, chamber, district, primary_party,
           candidate, party, party_source, votes, race_votes, pct, rank,
           winner, unopposed, no_candidate, convention, margin, margin_pct,
           write_in, counties, race_counties, source_url) |>
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
      candidates    = sum(candidate != "Write-in" & !write_in),
      named_write_ins = sum(write_in),
      party_missing = sum(is.na(party) & candidate != "Write-in" & !write_in),
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
    write_in_won = races |> filter(winner, candidate == "Write-in" | write_in),
    # Two names in one race sharing a surname: likely one person spelled two ways
    name_variants = races |>
      filter(candidate != "Write-in") |>
      mutate(last = word(str_remove(candidate, ",? (Jr|Sr|II|III|IV)\\.?$"), -1)) |>
      filter(n() > 1, .by = c(all_of(race_cols), last)),
    # Names flagged as write-ins. A ballot candidate here means a county file
    # that wasn't parsed for them: check the source before trusting the flag
    named_write_ins = races |>
      filter(write_in) |>
      select(all_of(race_cols), candidate, votes, counties, race_counties)
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
