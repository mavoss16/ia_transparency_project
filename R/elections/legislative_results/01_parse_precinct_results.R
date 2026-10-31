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
# generals have it only where the source prints it (2012, 2014), so it is NA
# for 2010 and 2016–2024 generals.
#
# Not parsed: PDFs (Scott 2020 general) and anything before 2010 (the 2006 and
# 2008 statewide files have party columns, not candidates).
#
# Usage:
#   source("R/elections/legislative_results/01_parse_precinct_results.R")
#   results <- parse_all_results()
#   results_summary(results)

library(here)
source(here("R/elections/legislative_results/parsers.R"))

RAW_DIR    <- here("data/elections/raw/precinct_results")
OUTPUT     <- here("data/elections/processed/legislative_results_precinct.rds")
FIRST_YEAR <- 2010

parse_all_results <- function() {
  files <- tibble(path = list.files(RAW_DIR, recursive = TRUE, full.names = TRUE)) |>
    mutate(
      source = str_remove(path, fixed(paste0(RAW_DIR, "/"))),
      year   = as.integer(str_sub(dirname(source), 1, 4)),
      type   = str_remove(dirname(source), "^\\d{4}_"),
      name   = tools::file_path_sans_ext(basename(path))
    )
  skipped <- filter(files, year < FIRST_YEAR | tools::file_ext(path) == "pdf")
  files   <- filter(files, !path %in% skipped$path)

  results <- pmap(files, \(path, source, year, type, name) {
    message("  ", source)
    # Statewide files carry the county on each row
    parse_results_file(path, type, county = if (name == "statewide") NULL else name) |>
      mutate(year = year, type = type, source = source)
  }) |>
    list_rbind() |>
    relocate(year, type)

  if (nrow(skipped)) message("Not parsed: ", paste(skipped$source, collapse = ", "))
  saveRDS(results, OUTPUT)
  message("Saved ", nrow(results), " rows to ", OUTPUT)
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
  print(results_summary(parse_all_results()), n = Inf, width = Inf)
}
