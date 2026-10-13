# R/campaign_finance/utils.R
#
# Shared helpers for the campaign finance pipeline. Source this file; do not
# run it directly. Caller must have loaded `here`.

library(stringr)
library(dplyr)
library(lubridate)

# ── Source-file discovery ─────────────────────────────────────────────────────

# IECDB exports are stored one directory per download, named YYYYMM:
#   data/campaign_finance/source/IECDB/202607/
# The newest export is used by default; pass `export_dir` to pin an older one.
iecdb_root <- function() here("data/campaign_finance/source/IECDB")

latest_iecdb_export <- function() {
  dirs <- list.dirs(iecdb_root(), recursive = FALSE, full.names = TRUE)
  dirs <- dirs[str_detect(basename(dirs), "^\\d{6}$")]
  if (length(dirs) == 0)
    stop("No IECDB export directories (YYYYMM) found under ", iecdb_root())
  dirs[which.max(basename(dirs))]
}

# All files in an export matching `pattern`, sorted by name. One logical table
# may arrive split across numbered part files (the 202607 contributions export
# came in four); sorting by name keeps them in order so they stack correctly.
find_source_files <- function(pattern, export_dir = latest_iecdb_export()) {
  files <- list.files(export_dir, pattern = pattern, ignore.case = TRUE,
                      full.names = TRUE)
  if (length(files) == 0)
    stop("No source file matching '", pattern, "' in ", export_dir)
  sort(files)
}

find_source_file <- function(pattern, export_dir = latest_iecdb_export()) {
  files <- find_source_files(pattern, export_dir)
  if (length(files) > 1)
    stop("Expected one file matching '", pattern, "' in ", export_dir,
         " but found ", length(files), " — use find_source_files().")
  files
}

# ── Column harmonization ──────────────────────────────────────────────────────

# The 202607 export renamed every column (human-readable "Contribution Amount"
# → machine "amount"). Downstream code and the DuckDB views are written against
# the older names, so incoming files are mapped back onto them. Mappings whose
# source column is absent are skipped, so either export vintage reads cleanly.
# Applied after janitor::clean_names().
IECDB_CONTRIBUTION_COLS <- c(
  date                        = "contribution_received_date",
  committee_code              = "committee_cd",
  committee_name              = "committee_nm",
  contributing_committee_code = "contr_committee_cd",
  contributing_organization   = "organization_nm",
  first_name                  = "first_nm",
  last_name                   = "last_nm",
  contribution_amount         = "amount"
)

IECDB_EXPENDITURE_COLS <- c(
  date                        = "calendar_date",
  committee_code              = "committee_cd",
  committee_name              = "committee_nm",
  receiving_committee_code    = "rec_committee_cd",
  receiving_organization_name = "organization_nm",
  first_name                  = "first_nm",
  last_name                   = "last_nm",
  expenditure_amount          = "amount",
  state                       = "state_cd",
  zip                         = "zip_code"
)

IECDB_REGISTERED_COLS <- c(committee_code = "committee_number")

rename_if_present <- function(df, mapping) {
  present <- mapping[mapping %in% names(df)]
  if (length(present) > 0) df <- rename(df, all_of(present))
  df
}

# ── Date parsing ──────────────────────────────────────────────────────────────

# IECDB has shipped two date formats: "MM/DD/YYYY" in exports through 202603,
# and ISO "YYYY-MM-DD[ HH:MM:SS]" from 202607 on. Accept either, per element.
parse_iecdb_date <- function(x) {
  x   <- str_trim(as.character(x))
  out <- as.Date(NA_character_)[rep(1L, length(x))]

  iso      <- !is.na(x) & str_detect(x, "^\\d{4}-\\d{2}-\\d{2}")
  out[iso] <- as.Date(str_sub(x[iso], 1L, 10L))

  legacy <- !is.na(x) & !iso
  if (any(legacy)) out[legacy] <- suppressWarnings(mdy(x[legacy]))
  out
}

# Election dates in the registered-committees export use their own two formats:
# "2022 Nov 08 12:00:00 AM" through 202603, ISO from 202607 on.
parse_iecdb_election_date <- function(x) {
  x   <- str_trim(as.character(x))
  out <- as.Date(NA_character_)[rep(1L, length(x))]

  iso      <- !is.na(x) & str_detect(x, "^\\d{4}-\\d{2}-\\d{2}")
  out[iso] <- as.Date(str_sub(x[iso], 1L, 10L))

  legacy <- !is.na(x) & !iso
  if (any(legacy)) {
    out[legacy] <- as.Date(suppressWarnings(parse_date_time(
      str_extract(x[legacy], "^\\S+\\s+\\S+\\s+\\d+"),
      orders = "Ybd",
      quiet  = TRUE
    )))
  }
  out
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

# ── Donor attribution ─────────────────────────────────────────────────────────

# Not every contribution row describes a gift from an identifiable donor. Two
# kinds of report-level bookkeeping are filed as ordinary rows:
#
#   unitemized   — a lump sum covering everyone who gave below the itemization
#                  threshold, filed under a placeholder name ("Unitemized",
#                  "Unitemized Contributions", "Contributions Unitemized", …)
#   unidentified — filed with no donor name, organization, or committee at all
#
# Both are real money and belong in committee totals. Neither is a donor, so
# both must be kept out of donor rankings, donor pages, and unique-donor counts.
#
# Matching runs against the norm_* fields, which are already uppercased and
# stripped of punctuation, so one token catches the many spelling and comma
# variants without a per-variant list.
#
# The match is deliberately a substring, not a word boundary: normalization
# deletes punctuation without inserting a space, so "Cash-Unitemized" and
# "Unitemized,Unitemized" collapse to CASHUNITEMIZED / UNITEMIZEDUNITEMIZED
# with no boundary to anchor to. "UNITEMIZED" is not a fragment of any real
# name, so a substring match is safe — add tokens here only with the same
# confidence, since a common substring would silently hide real donors.
UNITEMIZED_TOKENS <- c("UNITEMIZED")

classify_donor_attribution <- function(donor_type, norm_org, norm_first, norm_last) {
  pattern   <- paste(UNITEMIZED_TOKENS, collapse = "|")
  has_token <- function(x) str_detect(coalesce(x, ""), pattern)

  case_when(
    donor_type == "unknown" ~ "unidentified",
    has_token(norm_org) | has_token(norm_first) | has_token(norm_last) ~ "unitemized",
    TRUE ~ "itemized"
  )
}

# ── Transaction class ─────────────────────────────────────────────────────────

# The "contributions received" export mixes three kinds of money under one
# transaction_type code, and only one of them is a cash donation:
#
#   CON      cash contribution      — a gift, and it touches the bank account
#   INK      in-kind contribution   — a gift of goods or services; real value,
#                                     but no cash ever moves
#   LOANREC  loan received          — borrowed money, repayable; not income and
#                                     not a gift, however it is filed
#
# Summing all three into one "total raised" overstates receipts by ~16%
# statewide and turns lenders into donors: Lahn for Governor's largest apparent
# donor was the candidate, on the strength of a $2.5M loan to his own committee
# against $0 in cash contributions. Downstream views therefore keep the three
# apart, and no view exposes an unqualified "total" — the caller has to say
# which money it means.
IECDB_TRANSACTION_CLASSES <- c(
  CON     = "contribution",
  INK     = "in_kind",
  LOANREC = "loan"
)

# Errors rather than bucketing surprises into "other". A new code would be a
# new kind of money, and the whole point of this column is that nothing gets
# silently added to a donation total — same contract-fails-loudly stance as
# iecdb_api.R.
classify_transaction_class <- function(transaction_type) {
  code <- str_to_upper(str_squish(as.character(transaction_type)))
  # NA counts as unrecognized: an unclassed row would be excluded from every
  # per-class sum, i.e. money that disappears from the page without a trace.
  code[is.na(code)] <- "(missing)"
  unknown <- setdiff(unique(code), names(IECDB_TRANSACTION_CLASSES))
  if (length(unknown) > 0) {
    stop("Unrecognized transaction_type in contributions: ",
         paste(sprintf("'%s'", unknown), collapse = ", "),
         ". Classify it in IECDB_TRANSACTION_CLASSES (utils.R) before ingesting — ",
         "an unclassified code would otherwise land in a donation total.",
         call. = FALSE)
  }
  unname(IECDB_TRANSACTION_CLASSES[code])
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
