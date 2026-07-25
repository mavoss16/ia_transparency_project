# R/campaign_finance/02_clean_normalize.R
#
# Reads raw Iowa IECDB source CSVs, cleans and normalizes fields, and writes
# Parquet files for downstream use in 04_build_database.R.
#
# Source files are read from the newest export directory under
# data/campaign_finance/source/IECDB/ (one YYYYMM directory per download).
# Column names and date formats differ between export vintages; utils.R maps
# both onto the canonical names the DuckDB views and templates expect.
#
# Depends on: 01_build_committee_lookup.R should be run first so that
#   committee_lookup.rds is available for party enrichment in step 04.
#   This script does NOT require it — it only cleans the raw source files.
#
# Outputs (data/campaign_finance/processed/):
#   contributions.parquet  — cleaned contribution transactions
#   expenditures.parquet   — cleaned expenditure transactions
#   committees.parquet     — cleaned committee/candidate registry (registered CSV)

library(vroom)
library(readr)
library(dplyr)
library(stringr)
library(lubridate)
library(janitor)
library(tidyr)
library(arrow)
library(here)

source(here("R/campaign_finance/utils.R"))

# ── Contributions ─────────────────────────────────────────────────────────────

message("Reading contributions CSV...")
contribution_files <- find_source_files("contributions_received")
message(sprintf("  %d file(s):\n%s",
                length(contribution_files),
                paste0("    ", basename(contribution_files), collapse = "\n")))

raw_contributions <- vroom(
  contribution_files,
  col_types      = cols(.default = col_character()),
  na             = c("", "NA", "N/A"),
  show_col_types = FALSE
) |>
  clean_names() |>
  rename_if_present(IECDB_CONTRIBUTION_COLS)

message(sprintf("  %s rows read.", scales::comma(nrow(raw_contributions))))
message("Cleaning contributions...")

contributions <- raw_contributions |>
  mutate(
    # --- Parse typed fields ---
    date                = parse_iecdb_date(date),
    contribution_amount = parse_number(contribution_amount)
  ) |>
  # The 202607 export carries a handful of truncated/blank records at the head
  # of part 1 (oldest data). Rows with no date, committee, or amount carry no
  # information at all — drop them rather than let them become "unknown" donors.
  filter(!(is.na(date) & is.na(committee_code) & is.na(contribution_amount))) |>
  mutate(
    contribution_id     = row_number(),
    year                = year(date),
    zip_code            = normalize_zip(zip_code),

    # --- Donor classification (committee transfer takes priority) ---
    donor_type = case_when(
      !is.na(contributing_committee_code) ~ "committee",
      !is.na(contributing_organization)   ~ "organization",
      !is.na(first_name)                  ~ "individual",
      TRUE                                ~ "unknown"
    ),

    # --- Normalized fields (uppercase, stripped) for key generation / fuzzy step ---
    norm_last  = normalize_personal_name(last_name),
    norm_first = normalize_personal_name(first_name),
    norm_org   = normalize_org_name(contributing_organization),
    norm_city  = normalize_city(city),
    norm_state = normalize_state(state),

    # --- Is this row an actual donor, or report-level bookkeeping? ---
    donor_attribution = classify_donor_attribution(
      donor_type, norm_org, norm_first, norm_last
    ),

    # --- Display-ready fields (title case) ---
    clean_first = str_to_title(str_squish(replace_na(first_name, ""))),
    clean_last  = str_to_title(str_squish(replace_na(last_name, ""))),
    clean_org   = str_to_title(str_squish(replace_na(contributing_organization, ""))),
    clean_city  = str_to_title(str_squish(replace_na(city, ""))),

    # Human-readable label used in UI
    donor_display = case_when(
      donor_type %in% c("committee", "organization")
        ~ str_to_title(str_squish(replace_na(contributing_organization, ""))),
      donor_type == "individual"
        ~ str_trim(paste(
            str_to_title(str_squish(replace_na(first_name, ""))),
            str_to_title(str_squish(replace_na(last_name,  "")))
          )),
      TRUE ~ "(Unknown)"
    ),

    # Stable key for exact deduplication; fuzzy pass handled in step 03
    donor_key = make_donor_key(
      donor_type, contributing_committee_code,
      norm_last, norm_first, norm_org, norm_city, norm_state
    )
  )

message(sprintf(
  "  Donor type breakdown:\n%s",
  paste(
    capture.output(print(count(contributions, donor_type))),
    collapse = "\n"
  )
))

message(sprintf(
  "  Donor attribution (non-itemized rows stay in committee totals but are\n  excluded from donor views by 04_build_database.R):\n%s",
  paste(
    capture.output(print(
      contributions |>
        count(donor_attribution) |>
        left_join(
          summarize(group_by(contributions, donor_attribution),
                    amount = sum(contribution_amount, na.rm = TRUE)),
          by = "donor_attribution"
        )
    )),
    collapse = "\n"
  )
))

# ── Expenditures ──────────────────────────────────────────────────────────────

message("Reading expenditures CSV...")
raw_expenditures <- vroom(
  find_source_files("expenditures"),
  col_types      = cols(.default = col_character()),
  na             = c("", "NA", "N/A"),
  show_col_types = FALSE
) |>
  clean_names() |>
  rename_if_present(IECDB_EXPENDITURE_COLS)

message(sprintf("  %s rows read.", scales::comma(nrow(raw_expenditures))))
message("Cleaning expenditures...")

expenditures <- raw_expenditures |>
  mutate(
    expenditure_id     = row_number(),
    date               = parse_iecdb_date(date),
    expenditure_amount = parse_number(expenditure_amount),
    year               = year(date),
    zip                = normalize_zip(zip),

    recipient_type = case_when(
      !is.na(receiving_committee_code)    ~ "committee",
      !is.na(receiving_organization_name) ~ "organization",
      !is.na(first_name)                  ~ "individual",
      TRUE                                ~ "unknown"
    ),

    norm_recipient_org  = normalize_org_name(receiving_organization_name),
    norm_recipient_last = normalize_personal_name(last_name),
    norm_city           = normalize_city(city),
    norm_state          = normalize_state(state),

    recipient_display = case_when(
      recipient_type %in% c("committee", "organization")
        ~ str_to_title(str_squish(replace_na(receiving_organization_name, ""))),
      recipient_type == "individual"
        ~ str_trim(paste(
            str_to_title(str_squish(replace_na(first_name, ""))),
            str_to_title(str_squish(replace_na(last_name,  "")))
          )),
      TRUE ~ "(Unknown)"
    )
  )

# ── Committees (registered CSV + API lookup merged) ───────────────────────────

# --- Registered CSV ---
message("Reading registered committees CSV...")
reg_committees <- vroom(
  find_source_file("registered_political"),
  col_types      = cols(.default = col_character()),
  # "NA" appears literally in some fields (e.g. county) — treat as missing
  na             = c("", "NA", "N/A", "#N/A"),
  show_col_types = FALSE
) |>
  clean_names() |>
  rename_if_present(IECDB_REGISTERED_COLS) |>
  mutate(
    election_year = suppressWarnings(as.integer(election_year)),
    election_date = parse_iecdb_election_date(election_date),
    # Normalize party labels to match API lookup vocabulary
    party = case_when(
      str_to_upper(party) %in% c("REPUBLICAN", "REP", "R")           ~ "Republican",
      str_to_upper(party) %in% c("DEMOCRAT", "DEMOCRATIC", "DEM", "D") ~ "Democratic",
      str_to_upper(party) %in% c("LIBERTARIAN", "LIB", "L")          ~ "Libertarian",
      str_to_upper(party) %in% c("GREEN", "G")                        ~ "Green",
      str_to_upper(party) %in% c("INDEPENDENT", "IND", "I")           ~ "Independent",
      str_to_upper(party) %in% c("NOT AVAILABLE", "NONPARTISAN", "NP") ~ NA_character_,
      is.na(party)                                                      ~ NA_character_,
      TRUE ~ str_to_title(party)
    )
  )

message(sprintf("  %s rows from registered CSV.", scales::comma(nrow(reg_committees))))

# --- API lookup (step 01 output) ---
lookup_path <- here("data/campaign_finance/processed/committee_lookup.rds")

if (file.exists(lookup_path)) {
  message("Loading committee_lookup.rds...")
  api_committees <- readRDS(lookup_path) |>
    mutate(
      # Convert integer district to character so it joins cleanly with CSV district
      district = as.character(district_number)
    ) |>
    select(-district_number)
  message(sprintf("  %s rows from API lookup.", scales::comma(nrow(api_committees))))
} else {
  message("WARNING: committee_lookup.rds not found — run 01_build_committee_lookup.R for full party coverage.")
  api_committees <- tibble(committee_code = character())
}

# --- Full join: keep every committee from either source ---
# Columns present in both get _reg / _api suffixes; COALESCE resolves them below.
# Unique columns from each source pass through untouched:
#   reg-only:  committee_type, county, candidate_*, chair_*, treasurer_*, parent_*, contact_*
#   api-only:  political_party, filer_type, committee_type_cd, description,
#              county_cd, committee_email, committee_uuid
committees <- full_join(
  reg_committees,
  api_committees,
  by     = "committee_code",
  suffix = c("_reg", "_api")
) |>
  mutate(
    # Party: API first (pre-decoded, broader coverage), registered CSV as fallback
    party         = coalesce(party_api, party_reg),
    committee_name = coalesce(committee_name_api, committee_name_reg),
    office_sought  = coalesce(office_sought_api,  office_sought_reg),
    election_year  = coalesce(election_year_api,  election_year_reg),
    election_date  = coalesce(election_date_api,  election_date_reg),
    district       = coalesce(district_api,       district_reg)
  ) |>
  select(
    -party_reg, -party_api,
    -committee_name_reg, -committee_name_api,
    -office_sought_reg,  -office_sought_api,
    -election_year_reg,  -election_year_api,
    -election_date_reg,  -election_date_api,
    -district_reg,       -district_api
  )

message(sprintf("  %s total committees after merge.", scales::comma(nrow(committees))))
message(sprintf(
  "  Party coverage: %s/%s (%.0f%%)",
  scales::comma(sum(!is.na(committees$party))),
  scales::comma(nrow(committees)),
  100 * mean(!is.na(committees$party))
))

# ── Write Parquet ─────────────────────────────────────────────────────────────

processed_dir <- here("data/campaign_finance/processed")
dir.create(processed_dir, showWarnings = FALSE, recursive = TRUE)

message("Writing contributions.parquet...")
write_parquet(contributions, file.path(processed_dir, "contributions.parquet"))

message("Writing expenditures.parquet...")
write_parquet(expenditures, file.path(processed_dir, "expenditures.parquet"))

message("Writing committees.parquet...")
write_parquet(committees, file.path(processed_dir, "committees.parquet"))

message(sprintf(
  "\nDone. Processed files written to: %s",
  processed_dir
))
message("Run 04_build_database.R next.")
