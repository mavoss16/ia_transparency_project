

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(purrr)


data <- read_rds("data/legislators_90th_ga.rds")
legislation <- read_rds("data/legislation_2023_clean.rds")

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

# Get data frame of legislator votes from legislation dataframe
get_legislator_votes <- function(legislation_df, df_list_column, column_name, filter_value, chamber, party){
  print(filter_value)
  
  # Filter each df in column by filter_value for {{column_name}}
  # If filtering to a legislator, should be one row df for each df (If there was not a vote, return df with 1 blank row)
  df_list <- map(
    df_list_column,
    function(x){
      if(nrow(x) == 0){return(data.frame(Name = "blank_name"))}
      x |>
        filter(
          {{column_name}} == filter_value
        )
    }
  )
  
  # Bind together all dfs, then add file names (order should be the same)
  votes <- bind_rows(df_list)
  votes$file <- legislation_df$file
  
  # Filter to votes that happened, select columns, then add other legislation vote info
  votes |>
    filter(!is.na(vote)) |>
    select(
      {{column_name}}, file, vote
    ) |>
    left_join(
      legislation_df |> 
        select(
          file, 
          house_vote_gop, house_vote_dem, house_vote_outcome, 
          senate_vote_gop, senate_vote_dem, senate_vote_outcome
        )
    ) |>
    mutate(
      vote_agree = case_when(
        chamber == "House" & party == "Republican" ~ vote == house_vote_gop,
        chamber == "House" & party == "Democrat" ~ vote == house_vote_dem,
        chamber == "Senate" & party == "Republican" ~ vote == senate_vote_gop,
        chamber == "Senate" & party == "Democrat" ~ vote == senate_vote_dem
        
      )
    )
  
}

# Add legislator votes for senators
senate_counts <- legislators_counts |>
  filter(Chamber == "Senate") |>
  rowwise() |>
  mutate(
    floor_vote_record = list(get_legislator_votes(legislation, legislation$senate_vote_record, Name, Name, Chamber, Party))
  ) |>
  ungroup()

# Add legislator votes for democrats
house_counts <- legislators_counts |>
  filter(Chamber == "House") |>
  rowwise() |>
  mutate(
    floor_vote_record = list(get_legislator_votes(legislation, legislation$house_vote_record, Name, Name, Chamber, Party))
  ) |>
  ungroup()


# Count yes and no votes
senate_counts2 <- senate_counts |>
  rowwise() |>
  mutate(
    yes_count = count_by_filter(floor_vote_record, vote, filter_values = "Yes"),
    no_count = count_by_filter(floor_vote_record, vote, filter_values = "No"),
    # NA_count = count_by_na(floor_vote_record, vote),
    with_party = count_by_filter(floor_vote_record, vote_agree, filter_values = TRUE),
    with_party_pct = with_party / (yes_count + no_count)
  ) |>
  ungroup()

house_counts2 <- house_counts |>
  rowwise() |>
  mutate(
    yes_count = count_by_filter(floor_vote_record, vote, filter_values = "Yes"),
    no_count = count_by_filter(floor_vote_record, vote, filter_values = "No"),
    # NA_count = count_by_na(floor_vote_record, vote),
    with_party = count_by_filter(floor_vote_record, vote_agree, filter_values = TRUE),
    with_party_pct = with_party / (yes_count + no_count)
  ) |>
  ungroup()



write_file <- bind_rows(senate_counts2, house_counts2)

# Write Data --------------------------------------------------------------

write_rds(write_file, "data/legislators_90th_ga_clean.rds")
write_rds(write_file, "shiny_data/legislators_90th_ga_clean.rds")
