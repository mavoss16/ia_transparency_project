
library(dplyr)
library(stringr)
library(pdftools)
library(readr)
library(purrr)
library(lubridate)
# source("read_journal_functions.R")



# Previous Data -----------------------------------------------------------

prev_vote_records <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_records_90th_ga.rds")
prev_vote_summaries <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_summaries_90th_ga.rds")

# Prep Data Paths ---------------------------------------------------------

vote_files <- list.files("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/Floor Votes/2024", pattern = ".pdf$", full.names = TRUE)
votes_path <- "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/Floor Votes/2024"
# read_vote_files <- vote_files
read_vote_files <- vote_files[which(!(vote_files %in% unique(prev_vote_records$file_path)))]

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
  select(Chamber, Name, Party, District, County, party_abbr, initial_last, initial_first)



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

votes <- data.frame()
for(file in read_vote_files){
  print(file)
  pdf_df <- read_vote_pdf(file.path(file))
  votes <- bind_rows(pdf_df, votes)
}


# Create Legislator Vote Function -----------------------------------------

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

# return_df <- legislator_df |>
#   filter(Chamber %in% chamber) |>
#   mutate(
#     vote = case_when(
#       str_detect(yes_votes, initial_last) ~ "Yes",
#       str_detect(no_votes, initial_last) ~ "No",
#       TRUE ~ NA_character_
#     ),
#     file_name = file_name, sequence_no = sequence_no
#   )


# Create Legislator Vote Records ------------------------------------------

# vote_records <- votes |>
#   mutate(
#     chamber = ifelse(chamber == "IOWA SENATE", yes = "Senate", no = "House")
#   ) |>
#   rowwise() |>
#   mutate(
#     vote_record = list(create_vote_df(
#       legislators, initial_last,
#       vote_yes, vote_no, chamber = chamber
#     ))
#   ) |>
#   ungroup()

vote_records <- map(votes$file_path, function(input_file_path){
  info <- votes |>
    filter(file_path == input_file_path)
  create_vote_df(
    legislators, initial_last, yes_votes = info |> pull(vote_yes), no_votes = info |> pull(vote_no), 
    file = info |> pull(file_name), chamber = info |> pull(chamber), sequence_no = info |> pull(sequence_no)
  )
}) |>
  bind_rows()




# Vote by Party -----------------------------------------------------------
if(nrow(vote_records) > 0){
  party_votes <- vote_records |>
    mutate(vote = tolower(replace_na(vote, "NA"))) |>
    group_by(file_name, sequence_no, Chamber, party_abbr, vote) |>
    count(name = "vote_num") |>
    pivot_wider(
      values_from = vote_num, names_from = c(party_abbr, vote), names_glue = "vote_{party_abbr}_{vote}"
    ) |>
    bind_rows(data.frame(vote_dem_yes = integer(), vote_dem_no = integer(), vote_dem_na = integer(), vote_gop_yes = integer(), vote_gop_no = integer(), vote_gop_na = integer())) |>
    mutate(
      across(where(is.numeric), function(x){replace_na(x, 0)}),
      vote_dem = case_when(
        vote_dem_yes > vote_dem_no ~ "Yes",
        vote_dem_no > vote_dem_yes ~ "No",
        vote_dem_yes == vote_dem_no ~ "Evenly Split",
        TRUE ~ NA_character_
      ),
      vote_gop = case_when(
        vote_gop_yes > vote_gop_no ~ "Yes",
        vote_gop_no > vote_gop_yes ~ "No",
        vote_gop_yes == vote_gop_no ~ "Evenly Split",
        TRUE ~ NA_character_
      )
    )
  
  
  party_vote_long <- party_votes |>
    pivot_longer(
      cols = c(vote_dem, vote_gop), names_to = "party_abbr", values_to = "vote"
    ) |>
    mutate(
      party_abbr = str_remove(party_abbr, "vote_")
    ) |>
    select(file_name, sequence_no, Chamber, party_abbr, vote) |>
    rename(party_vote = vote)
  
  
  # Final Summary DF and Legislator Vote DF ---------------------------------
  
  vote_summaries <- left_join(votes, party_votes, by = c("file_name" = "file_name", "sequence_no" = "sequence_no", "chamber" = "Chamber")) |>
    select(
      file_path, chamber, sequence_no, date, time,
      file_name, file_sponsor, file_title,
      vote_yes_count, vote_no_count,
      vote_dem_yes, vote_dem_no, vote_dem_na,
      vote_gop_yes, vote_gop_no, vote_gop_na,
      vote_dem, vote_gop
    ) |>
    mutate(
      vote_outcome = case_when(
        vote_no_count == 0 ~ "Unanimous",
        (vote_gop_no == 0 & vote_dem_yes == 0) | (vote_gop_yes == 0 & vote_dem_no == 0) ~ "Party Line",
        (vote_gop_yes > 0 & vote_dem_yes > 0) & (vote_gop_no > 0 & vote_dem_no > 0) ~ "Bipartisan Support and Opposition",
        (vote_gop_yes > 0 & vote_dem_yes > 0) ~ "Bipartisan Support",
        (vote_gop_no > 0 & vote_dem_no > 0) ~ "Bipartisan Opposition"
      )
    ) |>
    mutate(
      date = mdy(date),
      datetime = paste(date, time) |> ymd_hm(),
      .after = time
    )
  
  vote_records_party <- left_join(vote_records, party_vote_long) |>
    mutate(
      vote_agree = vote == party_vote
    )
  
} else{
  vote_records_party <- data.frame()
  vote_summaries <- data.frame()
}


# Write Data --------------------------------------------------------------
# prev_vote_records <- data.frame()
# prev_vote_summaries <- data.frame()
write_vote_records <- bind_rows(prev_vote_records, vote_records_party)
write_vote_summaries <- bind_rows(prev_vote_summaries, vote_summaries)

write_rds(write_vote_records, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_records_90th_ga.rds")
write_rds(write_vote_summaries, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_summaries_90th_ga.rds")
