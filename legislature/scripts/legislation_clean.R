

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(readr)
library(lubridate)

filter_count <- function(df, filter_var, filter_vals){df |> filter({{filter_var}} %in% filter_vals) |> nrow()}

file_actions <- read_rds("data/legislative_actions_2023.rds") |> rename(sponsor = sponsor_s)
floor_votes <- read_rds("data/floor_vote_records_2023.rds")
lobbyist_declarations <- read_rds("data/lobbyist_declarations_2023.rds")


file_actions <- file_actions |>
  filter(
    !str_detect(bill, " to ")
  )

remove_bill_title_text <- "Passed House.+$|Passed Senate.+$|Ayes.+$|Read first time.+$|Withdrawn.+$|Signed by Governor.+$|Passed on file.+$"
file_actions <- file_actions |>
  mutate(
    action_notes = str_extract(
      bill_title, remove_bill_title_text),
    bill_title = str_remove_all(bill_title, remove_bill_title_text) |> str_trim()
  )


sponsors <- file_actions |>
  distinct(bill, bill_title, sponsor) |>
  mutate(sponsor = ifelse(sponsor == "", yes = NA, no = sponsor)) |>
  filter(!is.na(sponsor))

file_actions <- left_join(
  file_actions |> select(-sponsor),
  sponsors
)


last_actions <- file_actions |>
  group_by(bill, bill_title) |>
  # mutate(sponsors = paste0(unique(sponsor, collapse = ", "))) |>
  mutate(action_list = paste0(unique(action), collapse = ", ")) |>
  slice_tail(n = 1) |>
  ungroup() |>
  transmute(
    bill = bill, bill_title = bill_title,
    last_action = action, action_list = action_list
  )

files <- file_actions |>
  nest(actions = c(action, date, action_notes), .by = c(bill, bill_title, sponsor)) |>
  left_join(last_actions)



# Add Lobbyist Declarations -----------------------------------------------

final_declaration <- lobbyist_declarations |>
  group_by(bill, lobbyist, client) |>
  # filter(date_time == max(date_time)) |>
  slice_max(order_by = date_time, n = 1) |>
  ungroup()

lobby_files <- final_declaration |>
  nest(lobbyist_declarations = c(lsb_number, lobbyist, declaration, client, date, date_time, comments), .by = c(bill)) |>
  ungroup() |>
  rowwise() |>
  mutate(
    num_dec = nrow(lobbyist_declarations),
    num_dec_for = filter_count(lobbyist_declarations, declaration, "For"),
    num_dec_against = filter_count(lobbyist_declarations, declaration, "Against"),
    num_dec_und = filter_count(lobbyist_declarations, declaration, "Undecided"),
    num_dec_withdrawn = filter_count(lobbyist_declarations, declaration, "Withdrawn")
  )

files <- left_join(files, lobby_files)


# Add Floor Votes ---------------------------------------------------------

senate <- floor_votes |> 
  filter(chamber == "Senate") |>
  mutate(date = mdy(date))
house <- floor_votes |> 
  filter(chamber == "House") |>
  mutate(date = mdy(date))

final_senate <- senate |>
  mutate(sequence_no = str_extract(sequence_no, "\\d+") |> as.numeric()) |>
  group_by(file_name) |>
  slice_max(order_by = sequence_no, n = 1) |>
  ungroup() |>
  select(
    date, time,
    file_name, file_sponsor, file_title,
    vote_yes_count, vote_no_count,
    gop_yes, gop_no, dem_yes, dem_no,
    vote_record
  ) |>
  mutate(
    vote_outcome = case_when(
      vote_no_count == 0 ~ "Unanimous",
      (gop_no == 0 & dem_yes == 0) | (gop_yes == 0 & dem_no == 0) ~ "Party Line",
      (gop_yes > 0 & dem_yes > 0) & (gop_no > 0 & dem_no > 0) ~ "Bipartisan Support and Opposition",
      (gop_yes > 0 & dem_yes > 0) ~ "Bipartisan Support",
      (gop_no > 0 & dem_no > 0) ~ "Bipartisan Opposition"
    ),
    .after = dem_no
  ) |>
  rename_with(
    # !tidyselect::contains("file_"),
    .fn = function(x){paste0("senate_vote_", x) |> str_replace_all("vote_vote_", "vote_")}
  )

final_house <- house |>
  mutate(sequence_num = str_extract(sequence_no, "\\d+") |> as.numeric()) |>
  group_by(file_name) |>
  slice_max(order_by = sequence_no, n = 1) |>
  ungroup() |>
  select(
    date, time,
    file_name, file_sponsor, file_title,
    vote_yes_count, vote_no_count,
    gop_yes, gop_no, dem_yes, dem_no,
    vote_record
  ) |>
  mutate(
    vote_outcome = case_when(
      vote_no_count == 0 ~ "Unanimous",
      (gop_no == 0 & dem_yes == 0) | (gop_yes == 0 & dem_no == 0) ~ "Party Line",
      (gop_yes > 0 & dem_yes > 0) & (gop_no > 0 & dem_no > 0) ~ "Bipartisan Support and Opposition",
      (gop_yes > 0 & dem_yes > 0) ~ "Bipartisan Support",
      (gop_no > 0 & dem_no > 0) ~ "Bipartisan Opposition"
    ),
    .after = dem_no
  ) |>
  rename_with(
    # !tidyselect::contains("file_"),
    .fn = function(x){paste0("house_vote_", x) |> str_replace_all("vote_vote_", "vote_")}
  )


files <- left_join(
  files,
  final_senate,
  by = c("bill" = "senate_vote_file_name")
)

files <- left_join(
  files,
  final_house,
  by = c("bill" = "house_vote_file_name")
)


# Create Categories and Arrange -------------------------------------------

get_file_date <- function(df){df |> filter(str_detect(action, "Filed")) |> slice(1) |> pull(date) |> unique() |> as.Date()}
files <- files |>
  rename(
    file = bill, file_title = bill_title
  ) |>
  mutate(
    categorization = case_when(
      str_detect(action_list, "Signed by Governor") ~ "Signed by Governor",
      str_detect(action_list, "Voted out of Senate,|Voted out of Senate$") & str_detect(action_list, "Voted out of House,|Voted out of House$") ~ "Passed Both Chambers",
      str_detect(action_list, "Voted out of Senate,|Voted out of Senate$|Voted out of House,|Voted out of House$") ~ "Passed One Chamber",
      str_detect(action_list, "Voted out of Senate Committee|Voted out of House Committee") ~ "Passed Committee",
      TRUE ~ "Introduced"
    )
  ) |>
  rowwise() |>
  mutate(
    file_introduced_date = list(get_file_date(actions)),
    .after = sponsor
  ) |>
  mutate(
    lobbyist_declarations = list(as.data.frame(lobbyist_declarations)),
    senate_vote_record = list(as.data.frame(senate_vote_record)),
    house_vote_record = list(as.data.frame(house_vote_record))
  ) |>
  ungroup()


# files_sorted <- files[mixedorder(files$file),] |> arrange(file_introduced_date)

files_sorted <- files |>
  mutate(
    sort_var = paste0(as.numeric(file_introduced_date), file)
  )
files_sorted <- files_sorted[mixedorder(files_sorted$sort_var), ] |>
  select(-sort_var)

write_rds(files_sorted, "data/legislation_2023_clean.rds")
