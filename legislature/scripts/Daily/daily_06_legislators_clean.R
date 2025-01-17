

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(purrr)


data <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/legislators_91st_ga_sponsor_fm.rds")
legislation <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/legislation_91st_ga_clean.rds")
vote_records <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_records_91st_ga.rds")

add_legislation_info <- function(file_name_list, legislation_df){
  
  files <- file_name_list |> unlist()
  if(length(files) == 0){
    return(NULL)
  }
  df <- data.frame(file = files)
  
  df <- left_join(
    df,
    legislation_df
  )
  if(nrow(df) > length(file_name_list)){print(file_name_list)}
  
  return(df)
}

count_by_filter <- function(df, filter_var, filter_values){
  if(is.null(df)){
    return(0)
  }
  df |>
    as.data.frame() |>
    filter(
      {{filter_var}} %in% filter_values
    ) |>
    nrow()
}

count_by_na <- function(df, filter_var){
  if(is.null(df)){
    return(0)
  }
  df |>
    as.data.frame() |>
    filter(
      is.na({{filter_var}})
    ) |>
    nrow()
}

legislators <- data |>
  rowwise() |>
  mutate(
    sponsor = list(add_legislation_info(sponsor, legislation)),
    floor_manager = list(add_legislation_info(floor_manager, legislation))
  ) |>
  ungroup()

# Add Counts for File Outcomes --------------------------------------------

legislators_counts <- legislators |>
  rowwise() |>
  mutate(
    sponsor_count = count_by_filter(sponsor, categorization, unique(legislation$categorization)),
    sponsor_sole_count = ifelse(
      is.null(sponsor), yes = 0,
      no = sponsor |> filter(!str_detect(sponsor, ", ") & !str_detect(sponsor |> tolower(), " and ")) |> nrow()
    ),
    floor_manager_count = count_by_filter(floor_manager, categorization, unique(legislation$categorization)),
    sponsor_advanced_count = count_by_filter(
      sponsor, 
      categorization, 
      c("Passed Committee", "Passed One Chamber", "Signed by Governor", "Passed Both Chambers")
    ),
    sponsor_signed_count = count_by_filter(sponsor, categorization, c("Signed by Governor")),
    floor_manager_signed_count = count_by_filter(floor_manager, categorization, c("Signed by Governor")),
    sponsor_group_advanced_count = count_by_filter(
      sponsor,
      group_categorization,
      c("Passed Committee", "Passed One Chamber", "Signed by Governor", "Passed Both Chambers")
    ),
    sponsor_group_signed_count = count_by_filter(sponsor, group_categorization, c("Signed by Governor")),
    floor_manager_group_signed_count = count_by_filter(floor_manager, group_categorization, c("Signed by Governor"))
  ) |>
  ungroup()


# Effectiveness Values ----------------------------------------------------

legislators_counts <- legislators_counts |>
  group_by(Chamber) |>
  mutate(
    
    sponsor_advanced_pct = sponsor_advanced_count / sponsor_count,
    sponsor_signed_pct = sponsor_signed_count / sponsor_count,
    sponsor_group_advanced_pct = sponsor_group_advanced_count / sponsor_count,
    sponsor_group_signed_pct = sponsor_group_signed_count / sponsor_count,
    floor_manager_signed_pct = floor_manager_signed_count / floor_manager_count,
    floor_manager_group_signed_pct = floor_manager_group_signed_count / floor_manager_count,
    
    across(
      c(contains("_count"), contains("_pct")),
      .fns = function(x){rank(-x, ties.method = "min")},
      .names = "{.col}_rank"
    )
  ) |>
  ungroup()


# Add Counts for Votes ----------------------------------------------------

count_votes <- vote_records |>
  group_by(Chamber, Name, Party, District, County) |>
  summarize(
    yes_count = sum(vote == "Yes", na.rm = T),
    no_count = sum(vote == "No", na.rm = T),
    na_count = sum(is.na(vote)),
    with_party = sum(vote_agree == TRUE, na.rm = T)
  ) |>
  mutate(
    with_party_pct = with_party / (yes_count + no_count)
  )


# Combine Data ------------------------------------------------------------

write_file <- left_join(legislators_counts, count_votes)

# Write Data --------------------------------------------------------------

write_rds(write_file, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/legislators_91st_ga_clean.rds")
