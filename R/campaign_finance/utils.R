# R/campaign_finance/utils.R
#
# Shared helpers for the campaign finance pipeline. Source this file; do not
# run it directly. Caller must have loaded `here`.

library(stringr)
library(dplyr)

# ── Source-file discovery ─────────────────────────────────────────────────────

# Selects the most recently modified file under data/campaign_finance/source/
# matching `pattern`. Re-downloading a fresh IECDB export requires no code changes.
find_source_file <- function(pattern) {
  files <- list.files(
    here("data/campaign_finance/source"),
    pattern    = pattern,
    full.names = TRUE
  )
  if (length(files) == 0) stop("No source file matching: ", pattern)
  files[which.max(file.mtime(files))]
}

# ── Normalization helpers ─────────────────────────────────────────────────────

# Tokens stripped from personal names when building normalized keys.
# Not removed from display names.
NAME_SUFFIXES <- c(
  "JR", "SR", "II", "III", "IV", "V",
  "MD", "DO", "PHD", "DDS", "DVM", "RN", "NP", "PA",
  "ESQ", "CPA", "PE", "LCSW", "MBA"
)
NAME_PREFIXES <- c("MR", "MRS", "MS", "MISS", "DR", "REV", "HON", "JUDGE")

strip_tokens <- function(x, tokens) {
  pattern <- paste0("(?<![A-Z])(", paste(tokens, collapse = "|"), ")(?![A-Z])\\.?")
  str_remove_all(x, regex(pattern))
}

norm_key_string <- function(x) {
  x |>
    str_to_upper() |>
    str_remove_all("[^A-Z0-9\\s]") |>
    str_squish()
}

normalize_personal_name <- function(x) {
  x |>
    norm_key_string() |>
    strip_tokens(NAME_SUFFIXES) |>
    strip_tokens(NAME_PREFIXES) |>
    str_squish()
}

normalize_org_name <- function(x) {
  x |>
    str_to_upper() |>
    str_remove_all("[^A-Z0-9&\\s]") |>
    str_squish()
}

normalize_city <- function(x) {
  x |>
    str_to_upper() |>
    str_remove_all("[^A-Z\\s]") |>
    str_squish()
}

normalize_state <- function(x) {
  str_to_upper(str_squish(x))
}

normalize_zip <- function(x) {
  str_extract(x, "^\\d{5}")
}

# Build a pipe-delimited string key that uniquely identifies a donor for exact
# deduplication. 03_link_donors.R collapses fuzzy near-duplicates further.
make_donor_key <- function(donor_type, committee_code, norm_last, norm_first,
                           norm_org, norm_city, norm_state) {
  case_when(
    donor_type == "committee"    ~ paste0("CMT|", committee_code),
    donor_type == "organization" ~ paste("ORG", norm_org, norm_city, norm_state, sep = "|"),
    donor_type == "individual"   ~ paste("IND", norm_last, norm_first, norm_city, norm_state, sep = "|"),
    TRUE                         ~ NA_character_
  )
}
