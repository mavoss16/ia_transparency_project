

library(dplyr)
library(readr)
library(tidyr)
library(stringr)


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
    sponsor_signed_count = count_by_filter(sponsor, categorization, c("Signed by Governor"))
  ) |>
  ungroup()



# Add Counts for Votes ----------------------------------------------------

# Want:
  # Num votes with party majority
  # Num votes against party majority
  # Num yes/no votes
  # Num NA votes




write_rds(legislators_counts, "data/legislators_90th_ga_clean.rds")
