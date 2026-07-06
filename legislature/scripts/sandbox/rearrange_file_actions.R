# Bills and their last action: https://www.legis.iowa.gov/legislation/billTracking/billDisposition
# Bills Introduced: https://www.legis.iowa.gov/legislation/billTracking/billpacket
# Bill Actions: https://www.legis.iowa.gov/legislation/billTracking/sessiondaily
# Similar and Companion: https://www.legis.iowa.gov/legislation/billTracking/similarCompanion



library(dplyr)
library(stringr)
library(janitor)
library(rvest)
library(readr)



# Read Previous Data ------------------------------------------------------

file_actions <- read_rds("data/legislative_actions_2023.rds")
lsa_actions <- read_rds("data/lsa_actions_2023.rds")

amendment_actions <- file_actions |>
  filter(
    str_detect(bill, " to ")
  )


file_actions <- file_actions |>
  filter(
    !str_detect(bill, " to ")
  ) |>
  mutate(
    full_title = bill_title,
    bill_title = str_extract(bill_title, "[^.]+\\."),
    other_info = str_extract(full_title, "\\..+") |> str_remove("^\\."),
    related_info = str_extract(other_info, "\\([^()]+\\)") |> str_remove_all("\\(|\\)") |> str_trim(),
    action_notes = str_remove(other_info, "\\([^()]+\\)") |> str_trim()
  ) |>
  mutate(
    action_notes = str_trim(action_notes),
    action_notes = replace(action_notes, action_notes == "", NA_character_)
  ) |>
  select(-other_info, -full_title) |>
  rename(sponsor = sponsor_s)


file_info <- file_actions |>
  distinct(bill, bill_title, sponsor) |>
  mutate(sponsor = ifelse(sponsor == "", yes = NA, no = sponsor)) |>
  filter(!is.na(sponsor))


last_actions <- file_actions |>
  group_by(bill, bill_title) |>
  # mutate(sponsors = paste0(unique(sponsor, collapse = ", "))) |>
  mutate(
    action_list = paste0(unique(action), collapse = ", "),
    related_info = paste0(unique(related_info), collapse = ", ")
  ) |>
  slice_tail(n = 1) |>
  ungroup() |>
  transmute(
    bill = bill, bill_title = bill_title, related_info = related_info,
    last_action = action, action_list = action_list
  )

file_info <- left_join(file_info, last_actions)



# Create Categories and Arrange -------------------------------------------

get_file_date <- function(actions_df, file_name){actions_df |> filter(bill == file_name) |> filter(str_detect(action, "Filed")) |> slice(1) |> pull(date) |> unique() |> as.Date()}
files <- file_info |>
  rename(
    file = bill, file_title = bill_title
  ) |>
  mutate(
    sponsor_count = 1 + str_count(sponsor, ", ") + str_count(sponsor |> tolower(), " and "),
    sponsor_count = ifelse(str_detect(sponsor, "\\(PROPOSED"), yes = NA_integer_, no = sponsor_count),
    sponsor_count = ifelse(str_detect(tolower(sponsor), "committee"), yes = NA_integer_, no = sponsor_count),
    .after = sponsor
  ) |>
  mutate(
    categorization = case_when(
      str_detect(action_list, "Signed by Governor") ~ "Signed by Governor",
      str_detect(action_list, "Voted out of Senate,|Voted out of Senate$") & str_detect(action_list, "Voted out of House,|Voted out of House$") ~ "Passed Both Chambers",
      str_detect(action_list, "Voted out of Senate,|Voted out of Senate$|Voted out of House,|Voted out of House$") ~ "Passed One Chamber",
      str_detect(action_list, "Voted out of Senate Committee|Voted out of House Committee") ~ "Passed Committee",
      TRUE ~ "Introduced"
    ),
    .after = file_title
  ) |>
  rowwise() |>
  mutate(
    file_introduced_date = get_file_date(file_actions, file),
    .after = sponsor_count
  ) |>
  ungroup()


# files_sorted <- files[mixedorder(files$file),] |> arrange(file_introduced_date)

files_sorted <- files |>
  mutate(
    sort_var = paste0(as.numeric(file_introduced_date), file)
  )

library(gtools)
files_sorted <- files_sorted[mixedorder(files_sorted$sort_var), ] |>
  select(-sort_var)

# write_rds(files_sorted, "data/legislation_2023_clean.rds")


# Connect Related Files ---------------------------------------------------

linked_files <- files_sorted |>
  mutate(
    preceding_file = str_extract(related_info, "Formerly [a-zA-Z0-9 ,]+") |> str_remove("Formerly "),
    succeding_file = str_extract(related_info, "See [a-zA-Z0-9 ,]+") |> str_remove("See "),
    related_file_list = paste0(
      ifelse(!is.na(preceding_file), yes = paste0(preceding_file, ", "), no = ""),
      file, ", ",
      ifelse(!is.na(succeding_file), yes = succeding_file, no = "")
    ) |>
      str_remove_all(", $"),
    .after = categorization
  ) |>
  relocate(related_info, .before = preceding_file) |>
  rowwise() |>
  mutate(
    related_file_list_sorted = related_file_list |>
      str_split_1(", ") |>
      sort() |>
      paste0(collapse = ", "),
    .after = related_file_list
  ) |>
  ungroup() |>
  mutate(
    file_group_id = cur_group_id(), .by = related_file_list_sorted,
    .after = related_file_list_sorted
  ) |>
  mutate(
    categorization_fct = factor(categorization, c("Introduced", "Passed Committee", "Passed One Chamber", "Passed Both Chambers", "Signed by Governor"), ordered = TRUE),
    .after = categorization
  ) |>
  group_by(file_group_id) |>
  mutate(
    group_categorization = max(categorization_fct),
    group_final_file = file[which.max(categorization_fct)],
    .after = file_group_id
  ) |>
  ungroup()


