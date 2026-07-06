
library(readr)

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(lubridate)

library(pdftools)



votes <- read_rds("data/floor_vote_records_90th_ga.rds")


individual_votes <- votes$vote_record |>
  bind_rows()




# Prep Data Paths ---------------------------------------------------------

vote_files <- list.files("data/Floor Votes/2023")
votes_path <- "data/Floor Votes/2023"

legislators <- read_rds("data/legislators_90th_ga.rds") |>
  mutate(
    plain_name = str_remove_all(Name, "[A-Za-z]+\\.") |> str_squish() |> str_trim(),
    last_name = word(plain_name, start = -1)
  ) |>
  group_by(Chamber, last_name) |>
  add_count(name = "last_name_count") |>
  ungroup() |>
  mutate(
    initial_last = ifelse(last_name_count > 1, yes = paste0(last_name, ", ", str_sub(Name, start = 1, end = 1), "."), no = last_name),
    initial_first = ifelse(last_name_count > 1, yes = paste0(str_sub(Name, start = 1, end = 1), ". ", last_name), no = last_name),
    party_abbr = case_when(
      Party == "Republican" ~ "gop",
      Party == "Democrat" ~ "dem"
    )
  ) |>
  select(Chamber, Name, party_abbr, initial_last, initial_first)


# Read PDF Function -------------------------------------------------------

read_vote_pdf <- function(file_path){
  text <- pdf_text(file_path)
  
  text <- text |>
    str_replace_all("\\\n", "~") |>
    str_squish() |>
    str_trim()
  
  chamber <- str_extract(text, "[A-Z ]+")
  text <- str_remove(text, "[^~]+~") |> str_trim() |> str_remove("^~")
  session <- str_extract(text, ".+SEQUENCE") |> str_remove_all("SEQUENCE") |> str_trim()
  sequence_no <- str_extract(text, "SEQUENCE NO\\. \\d+")
  text <- str_remove(text, ".+SEQUENCE NO\\. \\d+") |> str_trim()
  date <- str_extract(text, "DATE:[^~]+") |> str_remove("DATE: ") |> str_trim()
  text <- str_remove(text, "DATE:[^~]+")
  file_name <- str_extract(text, "[^~]+") |> str_trim()
  text <- str_remove(text, "[^~]+~") |> str_trim() |> str_remove("^~")
  time <- str_extract(text, "TIME:[^~]+") |> str_remove("TIME: ") |> str_trim()
  text <- str_remove(text, "TIME:[^~]+")
  file_sponsor <- str_extract(text, "[^~]+") |> str_trim()
  text <- str_remove(text, "[^~]+~") |> str_trim() |> str_remove("^~")
  file_title <- str_extract(text, "[^~]+") |> str_trim()
  text <- str_remove(text, "[^~]+~") |> str_trim() |> str_remove("^~")
  
  if(str_detect(chamber, "HOUSE")){
    vote_yes_count <- str_extract(text, "AYES - \\d+") |> str_remove("AYES - ") |> as.numeric()
    vote_yes <- str_extract(text, "AYES.+NAYS") |> str_remove("NAYS")
    vote_no_count <- str_extract(text, "NAYS - \\d+") |> str_remove("NAYS - ") |> as.numeric()
    vote_no <- str_extract(text, "NAYS.+ABSENT") |> str_remove("ABSENT")
    
    house_absent <- str_extract(text, "ABSENT.+RULE") |> str_remove("RULE")
    house_rule_76 <- str_extract(text, "RULE.+PRESIDING") |> str_remove("PRESIDING")
    senate_present <- NA_character_
    senate_absent <- NA_character_
    senate_excused <- NA_character_
  } else{
    vote_yes_count <- str_extract(text, "YEAS - \\d+") |> str_remove("YEAS - ") |> as.numeric()
    vote_yes <- str_extract(text, "YEAS.+NAYS") |> str_remove("NAYS")
    vote_no_count <- str_extract(text, "NAYS - \\d+") |> str_remove("NAYS - ") |> as.numeric()
    vote_no <- str_extract(text, "NAYS.+PRESENT") |> str_remove("PRESENT")
    
    house_absent <- NA_character_
    house_rule_76 <- NA_character_
    senate_present <- str_extract(text, "PRESENT.+ABSENT") |> str_remove("ABSENT")
    senate_absent <- str_extract(text, "ABSENT.+EXCUSED") |> str_remove("EXCUSED")
    senate_excused <- str_extract(text, "EXCUSED.+")
  }
  
  file_info <- data.frame(
    file_path, chamber, session, sequence_no, date, time, file_name, file_sponsor, file_title, 
    vote_yes_count, vote_yes, vote_no_count, vote_no, 
    house_absent, house_rule_76, senate_present, senate_absent, senate_excused
  ) |>
    mutate(
      chamber = case_when(
        chamber == "IOWA SENATE" ~ "Senate",
        chamber == "IOWA HOUSE OF REPRESENTATIVES" ~ "House"
      )
    )
  
  return(file_info)
}



# Read Vote PDFs ----------------------------------------------------------


votes <- map(vote_files, function(file_path){
  print(file_path)
  pdf_df <- read_vote_pdf(file.path(votes_path, file_path))
}) |>
  bind_rows()

# votes <- data.frame()
# for(file in vote_files){
#   #print(file)
#   pdf_df <- read_vote_pdf(file.path(votes_path, file))
#   votes <- bind_rows(pdf_df, votes)
# }



# Get Legislator Votes ----------------------------------------------------

# Function to create a data frame of legislators with yes/no votes
create_vote_df <- function(legislator_df, leg_name_var, yes_votes, no_votes, file_name = "", sequence_no = "", chamber = c("House", "Senate")){
  return_df <- legislator_df |>
    filter(Chamber %in% chamber) |>
    mutate(
      vote = case_when(
        str_detect(yes_votes, {{leg_name_var}}) ~ "Yes",
        str_detect(no_votes, {{leg_name_var}}) ~ "No",
        TRUE ~ NA_character_
      ),
      file_name = file_name, sequence_no = sequence_no
    )
  
  return(return_df)
}

# Create long data frame with all file vote-legislator combos
ind_votes <- map(votes$file_name, function(file){
  info <- votes |>
    filter(file_name == file)
  create_vote_df(
    legislators, initial_last, info |> pull(vote_yes), info |> pull(vote_no), 
    file = file, chamber = info |> pull(chamber), sequence_no = info |> pull(sequence_no)
  )
}) |>
  bind_rows()

# Count by party and vote type for summary df
party_votes <- ind_votes |>
  mutate(vote = tolower(replace_na(vote, "NA"))) |>
  group_by(file_name, sequence_no, party_abbr, vote) |>
  count(name = "vote_num") |>
  pivot_wider(
    values_from = vote_num, names_from = c(party_abbr, vote), names_glue = "{party_abbr}_{vote}"
  ) |>
  bind_rows(data.frame(dem_yes = integer(), dem_no = integer(), dem_na = integer(), gop_yes = integer(), gop_no = integer(), gop_na = integer())) |>
  mutate(
    across(where(is.numeric), function(x){replace_na(x, 0)}),
    dem_vote = case_when(
      dem_yes > dem_no ~ "Yes",
      dem_no > dem_yes ~ "No",
      dem_yes == dem_no ~ "Evenly Split",
      TRUE ~ NA_character_
    ),
    gop_vote = case_when(
      gop_yes > gop_no ~ "Yes",
      gop_no > gop_yes ~ "No",
      gop_yes == gop_no ~ "Evenly Split",
      TRUE ~ NA_character_
    )
  ) |>
  select(
    file_name, sequence_no,
    dem_yes, dem_no, dem_na,
    gop_yes, gop_no, gop_na,
    dem_vote, gop_vote
  )


# Combine 
vote_summary <- left_join(votes, party_votes) |>
  select(
    file_path, chamber, sequence_no, date, time, 
    file_name, file_sponsor, file_title,
    vote_yes_count, vote_no_count,
    dem_yes, dem_no, dem_na,
    gop_yes, gop_no, gop_na,
    dem_vote, gop_vote
  )
