# 01_parse_precinct_results.R
# Parse every downloaded precinct results file into one table of Iowa House
# and Senate results by precinct.
#
# Input:  data/elections/raw/precinct_results/{year}_{type}/ (download/election_results.R)
# Output: data/elections/processed/legislative_results_precinct.rds
#   year, type, county, precinct, chamber ("house"/"senate"), district, party,
#   candidate, votes, contest (the source's label), source (file under precinct_results/)
#
# party: primaries take it from the contest ("State Rep. Dist. 20 - Rep");
# generals have it only where the source prints it (2012, 2014, 2016 except
# Adair, and Scott 2020), so it is NA for most 2010 and 2018–2024 rows.
# 02_build_race_table.R fills it.
#
# Not parsed: anything before 2010 (the 2006 and 2008 statewide files have
# party columns, not candidates).
#
# Gaps: a county with no precinct file for an election (ENR 404s Black Hawk's
# 2024 primary) is filled from that election's statewide "results by county"
# file in data/elections/raw/county_results/{year}_{type}.{ext}, as county-level
# rows (precinct NA, source "county_results/..."), like the specials in 02.
#
# Incremental: the output carries a fingerprint per election (its raw files,
# its county_results file, and this script and parsers.R) in
# attr(, "digests"). A run re-parses only elections whose fingerprint changed
# and keeps the other elections' rows from the existing output, so editing the
# parser re-parses everything. force = TRUE (or --force) re-parses everything.
#
# Usage:
#   source("R/elections/legislative_results/01_parse_precinct_results.R")
#   results <- parse_all_results()          # or parse_all_results(force = TRUE)
#   results_summary(results)
#   Rscript R/elections/legislative_results/01_parse_precinct_results.R [--force]

library(here)
library(tidyr)
source(here("R/elections/legislative_results/parsers.R"))

RAW_DIR    <- here("data/elections/raw/precinct_results")
COUNTY_DIR <- here("data/elections/raw/county_results")
OUTPUT     <- here("data/elections/processed/legislative_results_precinct.rds")
FIRST_YEAR <- 2010

# County-level rows from an election's county_results file (if any) for the
# counties its precinct rows lack
fill_missing_counties <- function(rows, year, type, county_file) {
  if (is.na(county_file)) return(NULL)
  fill <- parse_results_file(county_file, type, county_rows = TRUE) |>
    filter(!county %in% rows$county)
  if (!nrow(fill)) return(NULL)
  message("  ", basename(county_file), ": filled ", paste(unique(fill$county), collapse = ", "))
  mutate(fill, year = year, type = type, source = file.path("county_results", basename(county_file)))
}

# One election's rows: its precinct files, then the counties they lack
parse_election <- function(files, year, type, county_file) {
  rows <- pmap(files, \(path, source, name, ...) {
    message("  ", source)
    # Statewide files carry the county on each row
    parse_results_file(path, type, county = if (name == "statewide") NULL else name) |>
      mutate(year = year, type = type, source = source)
  }) |>
    list_rbind()
  bind_rows(rows, fill_missing_counties(rows, year, type, county_file)) |>
    relocate(year, type)
}

# Hash of everything an election's rows depend on: file names and contents,
# plus the parsing code
election_digest <- function(paths) {
  code <- c(here("R/elections/legislative_results/01_parse_precinct_results.R"),
            here("R/elections/legislative_results/parsers.R"))
  paths <- c(sort(paths), code)
  rlang::hash(paste(basename(paths), unname(tools::md5sum(paths))))
}

parse_all_results <- function(force = FALSE) {
  files <- tibble(path = list.files(RAW_DIR, recursive = TRUE, full.names = TRUE)) |>
    mutate(
      source = str_remove(path, fixed(paste0(RAW_DIR, "/"))),
      year   = as.integer(str_sub(dirname(source), 1, 4)),
      type   = str_remove(dirname(source), "^\\d{4}_"),
      name   = tools::file_path_sans_ext(basename(path))
    )
  skipped <- filter(files, year < FIRST_YEAR)
  files   <- filter(files, !path %in% skipped$path)

  county_files <- tibble(county_file = list.files(COUNTY_DIR, full.names = TRUE)) |>
    mutate(election = tools::file_path_sans_ext(basename(county_file)))
  elections <- files |>
    nest(files = -c(year, type)) |>
    mutate(election = paste0(year, "_", type)) |>
    left_join(county_files, by = "election") |>
    arrange(year, type) |>
    mutate(digest = map2_chr(files, county_file, \(f, c) election_digest(c(f$path, na.omit(c)))))

  previous <- if (!force && file.exists(OUTPUT)) readRDS(OUTPUT)
  old_digests <- attr(previous, "digests") %||% character()
  elections <- mutate(elections, reuse = unname(old_digests[election] %in% digest))
  if (any(elections$reuse)) message("Unchanged, kept: ", paste(elections$election[elections$reuse], collapse = ", "))

  results <- pmap(elections, \(year, type, files, county_file, reuse, ...) {
    if (reuse) return(filter(previous, .data$year == .env$year, .data$type == .env$type))
    parse_election(files, year, type, county_file)
  }) |>
    list_rbind()
  attr(results, "digests") <- set_names(elections$digest, elections$election)

  if (nrow(skipped)) message("Not parsed: ", paste(skipped$source, collapse = ", "))
  saveRDS(results, OUTPUT)
  message("Saved ", nrow(results), " rows to ", OUTPUT, " (re-parsed ", sum(!elections$reuse),
          " of ", nrow(elections), " elections)")
  invisible(results)
}

# Per election: counties, districts and candidates found
results_summary <- function(results) {
  results |>
    summarise(
      counties         = n_distinct(county),
      house_districts  = n_distinct(district[chamber == "house"]),
      senate_districts = n_distinct(district[chamber == "senate"]),
      candidates       = n_distinct(paste(chamber, district, party, candidate)),
      party_missing    = mean(is.na(party) & candidate != "Write-in"),
      rows             = n(),
      .by = c(year, type)
    ) |>
    arrange(year, type)
}

if (sys.nframe() == 0) {
  force <- "--force" %in% commandArgs(trailingOnly = TRUE)
  print(results_summary(parse_all_results(force = force)), n = Inf, width = Inf)
}
