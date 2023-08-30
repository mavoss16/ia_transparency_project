
library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(janitor)
library(lubridate)
library(data.table)
library(tigris)


orig_contributions <- read_csv("data/Iowa_Campaign_Contributions_Received.csv") |> clean_names()
candidate_committees <- read_csv("data/Registered_Political_Candidates__Committees_and_Entities_in_Iowa.csv") |> clean_names()

zip_sf <- tigris::zctas()
ia_zips <- tigris::zctas(state = "IA", year = 2010)

# dt_orig_contributions <- fread("data/Iowa_Campaign_Contributions_Received.csv")


candidate_committees <- candidate_committees |>
  mutate(
    committee_unique_name = ifelse(
      !is.na(candidate_name),
      yes = paste0(committee_name, " (", candidate_name, ")"),
      no = committee_name
    )
  ) |>
  select(
    committee_name, committee_number, committee_unique_name,
    district, party, election_year, candidate_name, 
  )


contributions <- orig_contributions |>
  mutate(
    date = mdy(date),
    year = year(date),
    month = month(date),
    .before = committee_code
  ) |>
  filter(
    date >= mdy("01/01/2016")
  ) |>
  mutate(
    zip5 = str_sub(zip_code, end = 5),
    .after = zip_code
  )

contributions <- left_join(
  contributions,
  candidate_committees,
  by = c(
    "committee_name",
    "committee_code" = "committee_number"
  )
) |>
  mutate(
    committee_type2 = case_when(
      committee_type %in% c("State Central Committee", "County Central Committee") ~ "Party",
      committee_type %in% c("Governor", "Treasurer of State", "Attorney General", "Secretary of Agriculture", "Secretary of State", "Auditor of State", "Lt Governor") ~ "State Candidate",
      committee_type %in% c("State House", "State Senate") ~ "Legislative Candidate",
      committee_type %in% c("Iowa PAC") ~ "PAC",
      str_detect(committee_type, "County|City|School Board|Local") ~ "Local",
      TRUE ~ "Unknown"
    ),
    .after = committee_type
  ) |>
  mutate(
    contribution_geo = ifelse(zip5 %in% ia_zips$ZCTA5CE10 | toupper(state) == "IA", yes = "Iowa", no = "Outside Iowa"),
    contribution_type = ifelse(!is.na(contributing_organization), "Organization", "Individual"),
    contribution_name = case_when(
      !is.na(contributing_organization) ~ contributing_organization,
      !is.na(first_name) & !is.na(last_name) ~ paste0(first_name, " ", last_name),
      is.na(first_name) & !is.na(last_name) ~ paste0(first_name, "(No last name provided)"),
      !is.na(first_name) & !is.na(last_name) ~ paste0(last_name, "(No first name provided)"),
      is.na(first_name) & is.na(last_name) ~ "No name or organization provided",
      TRUE ~ NA_character_
    )
  )


write_rds(contributions, "data/cleaned_contributions_post_2016.rds")
write_rds(candidate_committees, "data/candidate_committees.rds")
write_rds(zip_sf, "data/us_zctas.rds")
write_rds(ia_zips, "data/ia_zctas.rds")