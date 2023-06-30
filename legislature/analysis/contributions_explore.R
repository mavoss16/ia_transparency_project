

library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(janitor)
library(lubridate)


orig_contributions <- read_csv("../Iowa_Campaign_Contributions_Received.csv") |> clean_names()
candidate_committees <- read_csv("../Registered_Political_Candidates__Committees_and_Entities_in_Iowa.csv") |> clean_names()


contributions <- orig_contributions |>
  mutate(
    date = mdy(date),
    year = year(date),
    month = month(date),
    .before = committee_code
  )

groups <- contributions |>
  group_by(
    committee_type, committee_code, committee_name
  ) |>
  summarize(total = sum(contribution_amount, na.rm = T))

groups_ia_cont <- contributions |>
  filter(state == "IA") |>
  group_by(
    committee_type, committee_code, committee_name
  ) |>
  summarize(total = sum(contribution_amount, na.rm = T))


org_donors <- contributions |>
  filter(!is.na(contributing_organization)) |>
  group_by(
    contributing_committee_code, contributing_organization,
    first_name, last_name, 
    address_line_1, address_line_2, city, state, zip_code
  ) |>
  summarize(total = sum(contribution_amount, na.rm = T))


ind_donors <- contributions |>
  filter(!is.na(contributing_organization)) |>
  group_by(
    first_name, last_name, 
    address_line_1, address_line_2, city, state, zip_code
  ) |>
  summarize(total = sum(contribution_amount, na.rm = T))
