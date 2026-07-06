# campaign_finance_explore.R
#
# Initial exploration of Iowa Campaign Contributions and Expenditures data.
# Filtered to 2022-2026 (two most recent election cycles) to keep size manageable.
# Full files: ~3M contributions, ~636k expenditures going back to 2003.
#
# Also joins registered committee files to assess party coverage:
#   - Registered_Political_Candidates,_Committees_and_Entities_in_Iowa_20260308.csv
#   - Other_State_Federal_Political_Action_Committees_Filing_in_Iowa_20260308.csv

library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)

# ── Load & filter ─────────────────────────────────────────────────────────────

contribs_raw <- read_csv(
  here::here("data/campaign_finance/source/Iowa_Campaign_Contributions_Received_20260307.csv"),
  col_types = cols(.default = "c")
)

expend_raw <- read_csv(
  here::here("data/campaign_finance/source/Iowa_Campaign_Expenditures_20260307.csv"),
  col_types = cols(.default = "c")
)

# Registered Iowa committees/candidates (has Party field)
registered_ia <- read_csv(
  here::here("data/campaign_finance/source/Registered_Political_Candidates,_Committees_and_Entities_in_Iowa_20260308.csv"),
  col_types = cols(.default = "c")
)

# Out-of-state/federal PACs filing in Iowa (Party mostly "Not Available")
registered_other <- read_csv(
  here::here("data/campaign_finance/source/Other_State_Federal_Political_Action_Committees_Filing_in_Iowa_20260308.csv"),
  col_types = cols(.default = "c")
)

# Build a unified committee lookup: Committee Number → Party
# Combine both registration files, keeping only what's needed for the join
committee_lookup <- bind_rows(
  registered_ia    |> select(`Committee Number`, Party),
  registered_other |> select(`Committee Number`, Party)
) |>
  # Normalize party labels
  mutate(party = case_when(
    Party == "Republican"     ~ "Republican",
    Party == "Democratic"     ~ "Democratic",
    Party == "Independent"    ~ "Independent",
    Party == "Libertarian"    ~ "Libertarian",
    Party == "Green"          ~ "Green",
    Party == "Other"          ~ "Other",
    TRUE                      ~ NA_character_   # "Not Available", blanks, junk values
  )) |>
  select(committee_code = `Committee Number`, party) |>
  distinct(committee_code, .keep_all = TRUE)  # drop any duplicate registrations

# Parse dates and filter to recent cycles
contribs <- contribs_raw |>
  mutate(
    date       = mdy(Date),
    year       = year(date),
    amount     = parse_number(`Contribution Amount`)
  ) |>
  filter(year >= 2022)

expend <- expend_raw |>
  mutate(
    date   = mdy(Date),
    year   = year(date),
    amount = parse_number(`Expenditure Amount`)
  ) |>
  filter(year >= 2022)

cat("Contributions (2022+):", nrow(contribs), "rows\n")
cat("Expenditures  (2022+):", nrow(expend),   "rows\n")


# ── Contributions overview ────────────────────────────────────────────────────

# Date range
range(contribs$date, na.rm = TRUE)

# Committee types represented
contribs |>
  count(`Committee Type`, sort = TRUE)

# Transaction types
contribs |>
  count(`Transaction Type`, sort = TRUE)

# Annual totals
contribs |>
  group_by(year) |>
  summarise(
    n          = n(),
    total      = sum(amount, na.rm = TRUE),
    median_amt = median(amount, na.rm = TRUE),
    mean_amt   = mean(amount, na.rm = TRUE)
  )

# Top receiving committees by total dollars
contribs |>
  group_by(`Committee Name`, `Committee Type`) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20)

# Top individual donors (non-org contributions — First Name present)
contribs |>
  filter(!is.na(`First Name`)) |>
  mutate(donor = str_trim(paste(`First Name`, `Last Name`))) |>
  group_by(donor, City, State) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20)

# Top contributing organizations
contribs |>
  filter(!is.na(`Contributing Organization`)) |>
  group_by(`Contributing Organization`, City, State) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20)

# Iowa vs. out-of-state contributions
contribs |>
  mutate(in_state = State == "IA") |>
  group_by(in_state) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n())

# Contribution size distribution
contribs |>
  mutate(size_bucket = cut(
    amount,
    breaks = c(0, 25, 100, 500, 1000, 5000, Inf),
    labels = c("$0-25", "$26-100", "$101-500", "$501-1k", "$1k-5k", "$5k+"),
    include.lowest = TRUE
  )) |>
  count(size_bucket)


# ── Expenditures overview ─────────────────────────────────────────────────────

# Committee types represented
expend |>
  count(`Committee Type`, sort = TRUE)

# Annual totals
expend |>
  group_by(year) |>
  summarise(
    n     = n(),
    total = sum(amount, na.rm = TRUE)
  )

# Top spending committees
expend |>
  group_by(`Committee Name`, `Committee Type`) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20)

# Top recipients of expenditures (organizations)
expend |>
  filter(!is.na(`Receiving Organization Name`)) |>
  group_by(`Receiving Organization Name`) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20)


# ── Cross-file: committees in both ───────────────────────────────────────────

# Committees that appear as both receivers of contributions and spenders
contrib_committees <- contribs |>
  distinct(`Committee Code`, `Committee Name`, `Committee Type`)

expend_committees <- expend |>
  distinct(`Committee Code`, `Committee Name`, `Committee Type`)

inner_join(contrib_committees, expend_committees, by = "Committee Code") |>
  select(
    `Committee Code`,
    committee_name_contrib = `Committee Name.x`,
    committee_type         = `Committee Type.x`
  )

# For a given committee: money raised vs. money spent
committee_summary <- inner_join(
  contribs |>
    group_by(`Committee Code`, `Committee Name`) |>
    summarise(raised = sum(amount, na.rm = TRUE), .groups = "drop"),
  expend |>
    group_by(`Committee Code`, `Committee Name`) |>
    summarise(spent = sum(amount, na.rm = TRUE), .groups = "drop"),
  by = "Committee Code"
) |>
  mutate(balance = raised - spent) |>
  arrange(desc(raised))

print(committee_summary, n = 20)


# ── Party coverage ────────────────────────────────────────────────────────────

# How many distinct committee codes appear in the registration files?
cat("Committees in registration lookup:", nrow(committee_lookup), "\n")
cat("  with a known party:            ", sum(!is.na(committee_lookup$party)), "\n")
cat("  party = NA (Not Available):    ", sum( is.na(committee_lookup$party)), "\n")

# Join party onto contributions
contribs_party <- contribs |>
  left_join(committee_lookup, by = c("Committee Code" = "committee_code"))

# Join party onto expenditures
expend_party <- expend |>
  left_join(committee_lookup, by = c("Committee Code" = "committee_code"))

# --- Row-level coverage ---
coverage_summary <- function(df, label) {
  total_rows    <- nrow(df)
  matched_rows  <- sum(!is.na(df$party))
  known_party   <- sum(!is.na(df$party) & df$party != "Other")
  total_amt     <- sum(df$amount, na.rm = TRUE)
  matched_amt   <- sum(df$amount[!is.na(df$party)], na.rm = TRUE)

  cat("\n──", label, "──\n")
  cat("Total rows:         ", total_rows, "\n")
  cat("Matched to registry:", matched_rows,
      sprintf("(%.1f%%)\n", 100 * matched_rows / total_rows))
  cat("  of which unmatched (no registry entry):", total_rows - matched_rows,
      sprintf("(%.1f%%)\n", 100 * (total_rows - matched_rows) / total_rows))
  cat("Total dollars:      $", scales::comma(total_amt), "\n")
  cat("Matched dollars:    $", scales::comma(matched_amt),
      sprintf("(%.1f%%)\n", 100 * matched_amt / total_amt))
}

coverage_summary(contribs_party, "Contributions")
coverage_summary(expend_party,   "Expenditures")

# --- Party breakdown for matched contributions ---
cat("\nContributions by party (matched rows only):\n")
contribs_party |>
  filter(!is.na(party)) |>
  group_by(party) |>
  summarise(
    n          = n(),
    total      = sum(amount, na.rm = TRUE),
    pct_rows   = n / nrow(filter(contribs_party, !is.na(party))),
    pct_dollars = total / sum(filter(contribs_party, !is.na(party))$amount, na.rm = TRUE)
  ) |>
  arrange(desc(total)) |>
  mutate(
    pct_rows    = scales::percent(pct_rows,    accuracy = 0.1),
    pct_dollars = scales::percent(pct_dollars, accuracy = 0.1),
    total       = scales::dollar(total)
  ) |>
  print()

cat("\nExpenditures by party (matched rows only):\n")
expend_party |>
  filter(!is.na(party)) |>
  group_by(party) |>
  summarise(
    n           = n(),
    total       = sum(amount, na.rm = TRUE),
    pct_rows    = n / nrow(filter(expend_party, !is.na(party))),
    pct_dollars = total / sum(filter(expend_party, !is.na(party))$amount, na.rm = TRUE)
  ) |>
  arrange(desc(total)) |>
  mutate(
    pct_rows    = scales::percent(pct_rows,    accuracy = 0.1),
    pct_dollars = scales::percent(pct_dollars, accuracy = 0.1),
    total       = scales::dollar(total)
  ) |>
  print()

# --- Unmatched committees: what are we missing? ---
# Committee codes in the transaction data that have no registry entry at all
cat("\nTop unmatched committees by contribution volume:\n")
contribs_party |>
  filter(is.na(party)) |>
  group_by(`Committee Code`, `Committee Name`, `Committee Type`) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20) |>
  print()

cat("\nTop unmatched committees by expenditure volume:\n")
expend_party |>
  filter(is.na(party)) |>
  group_by(`Committee Code`, `Committee Name`, `Committee Type`) |>
  summarise(total = sum(amount, na.rm = TRUE), n = n(), .groups = "drop") |>
  slice_max(total, n = 20) |>
  print()

# --- Annual party breakdown: does coverage change by year? ---
cat("\nContributions matched-to-registry rate by year:\n")
contribs_party |>
  group_by(year) |>
  summarise(
    n         = n(),
    matched   = sum(!is.na(party)),
    pct_match = scales::percent(matched / n, accuracy = 0.1)
  ) |>
  print()
