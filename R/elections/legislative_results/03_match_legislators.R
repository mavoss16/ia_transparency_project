# 03_match_legislators.R
# Link election candidates to LegiScan legislators (people_id), then add
# people_id, incumbent and open_seat to the race table.
#
# Input:  data/elections/processed/legislative_results.rds (02_build_race_table.R)
#         data/elections/processed/legislative_results_precinct.rds (counties per race)
#         legiscan/ga{N}/derived/people.csv (for each N in LEGISCAN_SESSIONS)
#         data/general/candidate_legislators_manual.csv (overrides; see below)
# Output: data/general/candidate_legislators.csv — one row per matched candidate row:
#           people_id, legislator, year, type, chamber, district, primary_party,
#           candidate, match ("seat", "name" or "manual")
#         data/general/candidate_legislators_review.csv — possible matches not
#           accepted, for a person to decide (copy a row into the manual file)
#         data/elections/processed/legislative_results.rds, with people_id,
#           incumbent and open_seat added
#
# Matching, per legislator:
#   name key — first name (or LegiScan nickname, or a common short form from
#     NICKNAMES) + last name, as name_key() builds it
#   home counties — the counties of their seat on the 2021 map, from the 2024
#     House general (a Senate seat n covers House districts 2n - 1 and 2n)
#   seat  — the matching winner of their seat in a general or special from 2022 on
#   name  — any other race (losses, primaries, the other chamber, older maps)
#     whose candidate has the same name key (first or nickname + last name) and
#     shares a county with the home counties
#   review — a name-key match outside the home counties, a key two legislators
#     share, or a same-surname candidate with another first name in the home
#     counties (nicknames LegiScan doesn't list)
#
# Manual overrides (data/general/candidate_legislators_manual.csv):
#   year, type, chamber, district, primary_party, candidate, people_id, note.
#   A row with a people_id adds or replaces that candidate's match; a row with
#   an empty people_id removes it.
#
# incumbent: the candidate won a general for the same chamber whose term covers
#   the election (House: two years earlier; Senate: two or four), matched by
#   people_id or, for non-legislators, by name key. NA when those generals
#   aren't in the data. A special's winner holds the seat in later elections
#   until the seat's next general. Specials before 2025 aren't in the data, so
#   members who won one earlier show as not incumbent.
# open_seat: per chamber × district × year, no incumbent ran in any of its
#   races (general or primaries). NA when incumbency is unknown.
#
# Usage:
#   source("R/elections/legislative_results/03_match_legislators.R")
#   matches <- match_legislators()
#   races   <- add_incumbency(matches)

library(here)
library(readr)
source(here("R/elections/legislative_results/02_build_race_table.R"))

LEGISCAN_SESSIONS <- 91
PRECINCT_INPUT <- here("data/elections/processed/legislative_results_precinct.rds")
CROSSWALK      <- here("data/general/candidate_legislators.csv")
REVIEW         <- here("data/general/candidate_legislators_review.csv")
MANUAL         <- here("data/general/candidate_legislators_manual.csv")

RACE_COLS <- c("year", "type", "chamber", "district", "primary_party")
TERM_YEARS <- c(house = 2, senate = 4)

# Common short forms LegiScan's nickname field often leaves out (both directions)
NICKNAMES <- tribble(
  ~formal,       ~short,
  "Andrew",      "Andy",
  "Anthony",     "Tony",
  "Charles",     "Chuck",
  "Christopher", "Chris",
  "Daniel",      "Dan",
  "David",       "Dave",
  "Donald",      "Don",
  "Gregory",     "Greg",
  "James",       "Jim",
  "Jeffrey",     "Jeff",
  "Jonathan",    "Jon",
  "Joseph",      "Joe",
  "Kenneth",     "Ken",
  "Matthew",     "Matt",
  "Michael",     "Mike",
  "Nicholas",    "Nick",
  "Patrick",     "Pat",
  "Richard",     "Rick",
  "Robert",      "Bob",
  "Robert",      "Rob",
  "Ronald",      "Ron",
  "Samuel",      "Sam",
  "Stephen",     "Steve",
  "Steven",      "Steve",
  "Thomas",      "Tom",
  "Timothy",     "Tim",
  "William",     "Bill",
  "William",     "Will"
)

first_name_forms <- function(x) {
  unique(c(x, NICKNAMES$short[NICKNAMES$formal %in% x], NICKNAMES$formal[NICKNAMES$short %in% x]))
}

# Legislators (not committees) in the sessions listed, with every name key
# their names allow
load_legislators <- function(sessions = LEGISCAN_SESSIONS) {
  map(sessions, \(ga) {
    read_csv(here("legiscan", paste0("ga", ga), "derived/people.csv"),
             col_types = cols(.default = "c")) |>
      mutate(ga = ga)
  }) |>
    list_rbind() |>
    filter(!is.na(district)) |>
    transmute(
      people_id = as.integer(people_id), legislator = name, ga,
      first_name, nickname, last_name,
      chamber  = if_else(role == "Sen", "senate", "house"),
      district = as.integer(str_extract(district, "[0-9]+"))
    ) |>
    distinct()
}

legislator_keys <- function(legislators) {
  legislators |>
    distinct(people_id, first_name, nickname, legislator, last_name) |>
    mutate(firsts = pmap(list(first_name, nickname, word(legislator, 1)),
                         \(...) first_name_forms(unique(na.omit(c(...)))))) |>
    tidyr::unnest(firsts) |>
    transmute(people_id, key = name_key(paste(firsts, last_name))) |>
    distinct()
}

race_counties <- function(precinct = readRDS(PRECINCT_INPUT)) {
  bind_rows(precinct, read_specials()) |>
    mutate(primary_party = if_else(type == "primary", party, NA_character_)) |>
    distinct(across(all_of(RACE_COLS)), county) |>
    summarise(counties = list(county), .by = all_of(RACE_COLS))
}

# Candidate rows (one per candidate per race) with name key and counties
candidate_rows <- function(races, counties) {
  races |>
    filter(candidate != "Write-in") |>
    distinct(across(all_of(RACE_COLS)), candidate, winner) |>
    left_join(counties, by = RACE_COLS) |>
    mutate(key = name_key(candidate), last = word(key, -1))
}

match_legislators <- function(races = readRDS(OUTPUT)) {
  legislators <- load_legislators()
  keys        <- legislator_keys(legislators)
  cands       <- candidate_rows(races, race_counties())

  # Home counties: the seat's House districts in the 2024 general (2021 map;
  # Senate district n is House districts 2n - 1 and 2n)
  house_counties <- cands |>
    filter(type == "general", year == 2024, chamber == "house") |>
    summarise(home = list(unique(unlist(counties))), .by = district)
  home <- legislators |>
    distinct(people_id, legislator, chamber, district) |>
    mutate(house_district = map2(chamber, district, \(ch, d) if (ch == "senate") c(2 * d - 1, 2 * d) else d)) |>
    tidyr::unnest(house_district) |>
    left_join(house_counties, by = c(house_district = "district")) |>
    summarise(home = list(unique(unlist(home))), legislator = first(legislator), .by = people_id)

  # Every candidate row whose key is one of a legislator's keys
  by_key <- cands |>
    inner_join(keys, by = "key", relationship = "many-to-many") |>
    left_join(home, by = "people_id") |>
    mutate(
      in_home  = map2_lgl(counties, home, \(c, h) length(intersect(c, h)) > 0),
      shared   = n_distinct(people_id) > 1, .by = c(all_of(RACE_COLS), candidate)
    )

  seats <- legislators |>
    distinct(people_id, chamber, district) |>
    inner_join(by_key |> filter(type %in% c("general", "special"), winner, year >= 2022),
               by = c("people_id", "chamber", "district")) |>
    distinct(across(all_of(RACE_COLS)), candidate, people_id) |>
    mutate(match = "seat")

  named <- by_key |>
    filter(in_home, !shared) |>
    distinct(across(all_of(RACE_COLS)), candidate, people_id) |>
    anti_join(seats, by = c(RACE_COLS, "candidate")) |>
    mutate(match = "name")

  matches <- bind_rows(seats, named)

  # Same surname, other first name, in the home counties; or key matches set aside
  surname <- cands |>
    inner_join(keys |> mutate(last = word(key, -1)) |> distinct(people_id, last),
               by = "last", relationship = "many-to-many") |>
    left_join(home, by = "people_id") |>
    filter(map2_lgl(counties, home, \(c, h) length(intersect(c, h)) > 0)) |>
    mutate(reason = "same surname in home counties")
  set_aside <- by_key |>
    filter(!in_home | shared) |>
    mutate(reason = if_else(shared, "name shared by two legislators", "name match outside home counties"))
  review <- bind_rows(set_aside, surname) |>
    select(all_of(RACE_COLS), candidate, people_id, legislator, reason) |>
    distinct(across(all_of(RACE_COLS)), candidate, people_id, .keep_all = TRUE)

  # Manual overrides last: they replace whatever the rules found
  manual <- if (file.exists(MANUAL)) {
    read_csv(MANUAL, col_types = cols(year = "i", district = "i", people_id = "i", .default = "c"))
  } else {
    tibble(year = integer(), type = character(), chamber = character(), district = integer(),
           primary_party = character(), candidate = character(), people_id = integer(), note = character())
  }
  matches <- matches |>
    anti_join(manual, by = c(RACE_COLS, "candidate")) |>
    bind_rows(manual |> filter(!is.na(people_id)) |> select(-note) |> mutate(match = "manual"))

  # A candidate row may belong to one legislator only
  dupes <- matches |> filter(n() > 1, .by = c(all_of(RACE_COLS), candidate))
  if (nrow(dupes)) stop("Candidate rows matched to two legislators; fix in ", MANUAL, ":\n",
                        paste(capture.output(print(dupes)), collapse = "\n"))

  review <- review |>
    anti_join(matches, by = c(RACE_COLS, "candidate", "people_id")) |>
    anti_join(manual, by = c(RACE_COLS, "candidate")) |>
    arrange(legislator, year, type)

  legislator_names <- distinct(home, people_id, legislator)
  matches <- matches |>
    left_join(legislator_names, by = "people_id") |>
    select(people_id, legislator, all_of(RACE_COLS), candidate, match) |>
    arrange(legislator, year, type)

  dir.create(dirname(CROSSWALK), showWarnings = FALSE)
  write_csv(matches, CROSSWALK, na = "")
  write_csv(review, REVIEW, na = "")
  message("Saved ", nrow(matches), " matches to ", CROSSWALK, " and ", nrow(review), " to review")
  invisible(matches)
}

# people_id, incumbent and open_seat onto the race table
add_incumbency <- function(matches = read_csv(CROSSWALK, show_col_types = FALSE),
                           races = readRDS(OUTPUT)) {
  races <- races |>
    select(-any_of(c("people_id", "incumbent", "open_seat"))) |>
    left_join(matches |> select(all_of(RACE_COLS), candidate, people_id),
              by = c(RACE_COLS, "candidate"), relationship = "many-to-one") |>
    mutate(person = if_else(!is.na(people_id), paste0("id:", people_id), paste0("key:", name_key(candidate))))

  general_years <- unique(races$year[races$type == "general"])
  won <- races |>
    filter(type %in% c("general", "special"), winner, candidate != "Write-in") |>
    distinct(chamber, district, won_year = year, won_type = type, person)
  general_seats <- races |> filter(type == "general") |> distinct(chamber, district, year)

  # A special fills the rest of a term: it holds until the seat's next general
  later_general <- \(ch, d, from, to) {
    any(general_seats$chamber == ch & general_seats$district == d &
        general_seats$year > from & general_seats$year < to)
  }

  # For an election in `year`, the generals whose winners still hold the seat
  incumbency_known <- \(chamber, year) {
    map2_lgl(chamber, year, \(ch, y) all((y - seq(2, TERM_YEARS[[ch]], by = 2)) %in% general_years))
  }

  holders <- races |>
    distinct(year, chamber, person) |>
    inner_join(won, by = c("chamber", "person"), relationship = "many-to-many") |>
    filter(
      if_else(won_type == "special", year > won_year, year - won_year >= 2),
      year - won_year <= TERM_YEARS[chamber],
      won_type == "general" | !pmap_lgl(list(chamber, district, won_year, year), later_general)
    ) |>
    distinct(year, chamber, person) |>
    mutate(holds = TRUE)

  races |>
    left_join(holders, by = c("year", "chamber", "person")) |>
    mutate(
      holds     = coalesce(holds, FALSE),
      known     = incumbency_known(chamber, year),
      incumbent = if_else(known, holds & candidate != "Write-in", NA)
    ) |>
    mutate(
      open_seat = if_else(known, !any(incumbent), NA),
      .by = c(year, chamber, district)
    ) |>
    select(-person, -holds, -known) |>
    arrange(year, type, chamber, district, primary_party, rank) |>
    (\(out) { saveRDS(out, OUTPUT); message("Added people_id, incumbent and open_seat to ", OUTPUT); invisible(out) })()
}

if (sys.nframe() == 0) {
  matches <- match_legislators()
  print(count(matches, match))
  races <- add_incumbency(matches)
  print(races |>
          filter(type == "general") |>
          summarise(seats = n_distinct(paste(chamber, district)),
                    incumbents = sum(incumbent, na.rm = TRUE),
                    open_seats = n_distinct(paste(chamber, district)[open_seat %in% TRUE]),
                    .by = year),
        n = Inf)
}
