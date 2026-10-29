# R/campaign_finance/02a_clean_normalize_federal.R
#
# Reads the FEC bulk files written by download/fec_contributions.R, cleans and
# normalizes fields, and writes Parquet files for downstream use in
# 04_build_database.R.
#
# Inputs (data/campaign_finance/source/federal/{cycle}/):
#   indiv_iowa_cands.txt  — contributions to Iowa H/S candidates (pipe-delimited, has header)
#   cm.txt        — FEC committee master
#   cn.txt        — FEC candidate master
#   ccl.txt       — FEC candidate-committee linkage
#
# Outputs (data/campaign_finance/processed/):
#   fec_contributions.parquet  — cleaned contribution transactions (all cycles)
#   fec_committees.parquet     — committee metadata joined with candidate info
#
# Run download/fec_contributions.R first to populate the source files.
# Run: source("R/campaign_finance/02a_clean_normalize_federal.R")

library(vroom)
library(dplyr)
library(stringr)
library(lubridate)
library(tidyr)
library(arrow)
library(purrr)
library(here)

source(here("R/campaign_finance/utils.R"))

# ── Locate source files ───────────────────────────────────────────────────────

federal_dir <- here("data/campaign_finance/source/federal")

cycle_dirs <- list.dirs(federal_dir, full.names = TRUE, recursive = FALSE) |>
  keep(\(d) str_detect(basename(d), "^\\d{4}$")) |>
  sort()

if (length(cycle_dirs) == 0) {
  stop("No cycle directories found under ", federal_dir,
       "\nRun R/campaign_finance/download/fec_contributions.R first.")
}

cycles <- as.integer(basename(cycle_dirs))
message(sprintf("Found %d cycle(s): %s", length(cycles), paste(cycles, collapse = ", ")))

find_cycle_file <- function(cycle_dir, filename) {
  path <- file.path(cycle_dir, filename)
  if (!file.exists(path)) {
    stop(sprintf("Expected file not found: %s\nRun fec_contributions.R for cycle %s.",
                 path, basename(cycle_dir)))
  }
  path
}

read_pipe <- function(path) {
  vroom(path,
        delim          = "|",
        col_types      = cols(.default = col_character()),
        na             = c("", "NA"),
        show_col_types = FALSE)
}

# ── FEC party code decoder ────────────────────────────────────────────────────

# FEC uses 3-letter party codes in CMTE_PTY_AFFILIATION and CAND_PTY_AFFILIATION.
# Full list: https://www.fec.gov/campaign-finance-data/party-code-descriptions/
decode_fec_party <- function(x) {
  case_when(
    x == "DEM" ~ "Democratic",
    x == "REP" ~ "Republican",
    x == "LIB" ~ "Libertarian",
    x == "GRE" ~ "Green",
    x %in% c("IND", "NNE", "NON", "NPA", "UNK") ~ NA_character_,
    is.na(x)   ~ NA_character_,
    TRUE        ~ str_to_title(x)   # preserve uncommon parties as-is
  )
}

# ── FEC entity type → donor_type ─────────────────────────────────────────────

# ENTITY_TP codes in the individual contributions file:
#   IND = individual, ORG = organization,
#   CCM/COM/PAC/PTY = committee or party (treated as "committee" here)
fec_entity_to_donor_type <- function(entity_tp) {
  case_when(
    entity_tp == "IND"                         ~ "individual",
    entity_tp == "ORG"                         ~ "organization",
    entity_tp %in% c("CCM", "COM", "PAC", "PTY") ~ "committee",
    TRUE                                        ~ "unknown"
  )
}

# ── NAME field parsing ────────────────────────────────────────────────────────

# FEC NAME format: "LAST, FIRST MIDDLE" for individuals; no comma for orgs.
# Returns a two-column tibble (parsed_last, parsed_first).
parse_fec_name <- function(name) {
  has_comma <- str_detect(name, ",")
  last  <- if_else(has_comma,
                   str_trim(str_extract(name, "^[^,]+")),
                   NA_character_)
  first <- if_else(has_comma,
                   str_trim(str_remove(name, "^[^,]+,")),
                   NA_character_)
  tibble(parsed_last = last, parsed_first = first)
}

# ── Individual contributions ──────────────────────────────────────────────────

message("Reading individual contributions across all cycles...")

raw_contributions <- map(cycle_dirs, function(d) {
  path  <- find_cycle_file(d, "indiv_iowa_cands.txt")
  cycle <- as.integer(basename(d))
  message(sprintf("  Cycle %d: %s", cycle, path))
  read_pipe(path) |> mutate(cycle = cycle)
}) |>
  list_rbind()

message(sprintf("  %s total rows across %d cycle(s).",
                scales::comma(nrow(raw_contributions)), length(cycles)))

# ── Clean contributions ───────────────────────────────────────────────────────

message("Cleaning contributions...")

# Parse NAME into last/first before the main mutate to keep it tidy
parsed_names <- parse_fec_name(raw_contributions$NAME)

contributions <- raw_contributions |>
  bind_cols(parsed_names) |>
  mutate(
    fec_contribution_id = row_number(),

    # ── Typed fields ──
    # TRANSACTION_DT is MMDDYYYY; TRANSACTION_AMT is the dollar amount.
    date                = mdy(TRANSACTION_DT),
    year                = year(date),
    contribution_amount = parse_number(TRANSACTION_AMT),
    zip_code            = normalize_zip(ZIP_CODE),

    # ── Donor classification ──
    donor_type = fec_entity_to_donor_type(ENTITY_TP),

    # ── Normalized fields for key generation and fuzzy matching ──
    # For individuals: parse NAME into last/first.
    # For orgs: use NAME directly as the org name field.
    norm_last  = if_else(donor_type == "individual",
                         normalize_personal_name(parsed_last),
                         NA_character_),
    norm_first = if_else(donor_type == "individual",
                         normalize_personal_name(parsed_first),
                         NA_character_),
    norm_org   = if_else(donor_type != "individual",
                         normalize_org_name(NAME),
                         NA_character_),
    norm_city  = normalize_city(CITY),
    norm_state = normalize_state(STATE),

    # ── Display fields ──
    contributor_last  = str_to_title(replace_na(parsed_last, "")),
    contributor_first = str_to_title(str_squish(replace_na(parsed_first, ""))),

    donor_display = case_when(
      donor_type == "individual"
        ~ str_trim(paste(contributor_first, contributor_last)),
      donor_type %in% c("organization", "committee")
        ~ str_to_title(str_squish(replace_na(NAME, ""))),
      TRUE ~ "(Unknown)"
    ),

    # ── Stable exact-match key (mirrors state donor_key format) ──
    # For committee donors, OTHER_ID holds the contributing committee's FEC ID.
    fec_donor_key = make_donor_key(
      donor_type,
      committee_code = OTHER_ID,
      norm_last,
      norm_first,
      norm_org,
      norm_city,
      norm_state
    )
  ) |>
  select(
    fec_contribution_id, cycle, CMTE_ID,
    TRAN_ID, contribution_amount, date, year,
    donor_type, ENTITY_TP,
    NAME, contributor_last, contributor_first,
    CITY, STATE, zip_code,
    EMPLOYER, OCCUPATION,
    TRANSACTION_TP, OTHER_ID,
    norm_last, norm_first, norm_org, norm_city, norm_state,
    donor_display, fec_donor_key
  )

message(sprintf(
  "  Donor type breakdown:\n%s",
  paste(capture.output(print(count(contributions, donor_type))), collapse = "\n")
))

# ── Committee, candidate, and linkage tables ───────────────────────────────────

message("Reading committee, candidate, and linkage files...")

# Read all cycles and deduplicate — keep the latest cycle's record for each ID
# so we have the most up-to-date committee and candidate metadata.
read_latest <- function(filename, id_col) {
  map(cycle_dirs, function(d) {
    path  <- find_cycle_file(d, filename)
    cycle <- as.integer(basename(d))
    read_pipe(path) |> mutate(cycle = cycle)
  }) |>
    list_rbind() |>
    group_by(.data[[id_col]]) |>
    slice_max(cycle, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(-cycle)
}

committees_raw <- read_latest("cm.txt",  "CMTE_ID")
candidates_raw <- read_latest("cn.txt",  "CAND_ID")
linkage_raw    <- read_latest("ccl.txt", "LINKAGE_ID")

message(sprintf(
  "  %s committees, %s candidates, %s linkage rows.",
  scales::comma(nrow(committees_raw)),
  scales::comma(nrow(candidates_raw)),
  scales::comma(nrow(linkage_raw))
))

# ── Build fec_committees ──────────────────────────────────────────────────────

# ccl links each committee to its principal candidate (CMTE_DSGN = "P").
# Where multiple linkage rows exist per committee, keep the principal designation.
principal_links <- linkage_raw |>
  filter(CMTE_DSGN == "P") |>
  select(CMTE_ID, CAND_ID) |>
  distinct(CMTE_ID, .keep_all = TRUE)

fec_committees <- committees_raw |>
  select(-CAND_ID) |>
  left_join(principal_links, by = "CMTE_ID") |>
  left_join(
    candidates_raw |>
      select(CAND_ID, CAND_NAME, CAND_PTY_AFFILIATION,
             CAND_OFFICE, CAND_OFFICE_ST, CAND_OFFICE_DISTRICT,
             CAND_ELECTION_YR),
    by = "CAND_ID"
  ) |>
  mutate(
    # Decode party: committee affiliation first, fall back to candidate's party
    party = coalesce(
      decode_fec_party(CMTE_PTY_AFFILIATION),
      decode_fec_party(CAND_PTY_AFFILIATION)
    ),

    # Human-readable office label
    office = case_when(
      CAND_OFFICE == "H" ~ "U.S. House",
      CAND_OFFICE == "S" ~ "U.S. Senate",
      CAND_OFFICE == "P" ~ "U.S. President",
      TRUE               ~ NA_character_
    )
  ) |>
  select(
    CMTE_ID,
    committee_name  = CMTE_NM,
    party,
    CMTE_PTY_AFFILIATION,
    CMTE_TP,
    CMTE_DSGN,
    ORG_TP,
    CONNECTED_ORG_NM,
    CAND_ID,
    candidate_name  = CAND_NAME,
    office,
    CAND_OFFICE,
    CAND_OFFICE_ST,
    CAND_OFFICE_DISTRICT,
    CAND_ELECTION_YR
  )

message(sprintf(
  "  %s committees; %s (%.0f%%) linked to a candidate.",
  scales::comma(nrow(fec_committees)),
  scales::comma(sum(!is.na(fec_committees$CAND_ID))),
  100 * mean(!is.na(fec_committees$CAND_ID))
))

message(sprintf(
  "  Party coverage: %s/%s (%.0f%%)",
  scales::comma(sum(!is.na(fec_committees$party))),
  scales::comma(nrow(fec_committees)),
  100 * mean(!is.na(fec_committees$party))
))

# ── Write Parquet ─────────────────────────────────────────────────────────────

processed_dir <- here("data/campaign_finance/processed")
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)

message("Writing fec_contributions.parquet...")
write_parquet(contributions, file.path(processed_dir, "fec_contributions.parquet"))

message("Writing fec_committees.parquet...")
write_parquet(fec_committees, file.path(processed_dir, "fec_committees.parquet"))

message(sprintf(
  "\nDone. Processed files written to: %s",
  processed_dir
))
message("Run 04_build_database.R next to ingest into DuckDB.")
