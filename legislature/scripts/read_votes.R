
library(dplyr)
library(stringr)
library(pdftools)
library(readr)
# source("read_journal_functions.R")


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
    initial_first = ifelse(last_name_count > 1, yes = paste0(str_sub(Name, start = 1, end = 1), ". ", last_name), no = last_name)
  ) |>
  select(-plain_name, -last_name, -last_name_count, -sponsor, -floor_manager)

# file_path <- file.path(votes_path, "floor_vote_1.pdf")


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
  )
  
  return(file_info)
}



# Read Vote PDFs ----------------------------------------------------------

votes <- data.frame()
for(file in vote_files){
  print(file)
  pdf_df <- read_vote_pdf(file.path(votes_path, file))
  votes <- bind_rows(pdf_df, votes)
}


# Create Legislator Vote Function -----------------------------------------

create_vote_df <- function(leg_df, leg_name_var, yes_votes, no_votes, chamber = c("House", "Senate")){
  return_df <- leg_df |>
    filter(Chamber %in% chamber) |>
    mutate(
      vote = case_when(
        str_detect(yes_votes, {{leg_name_var}}) ~ "Yes",
        str_detect(no_votes, {{leg_name_var}}) ~ "No",
        TRUE ~ NA_character_
      )
    )
  
  return(return_df)
}


# Create Legislator Vote Records ------------------------------------------

vote_records <- votes |>
  mutate(
    chamber = ifelse(chamber == "IOWA SENATE", yes = "Senate", no = "House")
  ) |>
  rowwise() |>
  mutate(
    vote_record = list(create_vote_df(
      legislators, initial_last,
      vote_yes, vote_no, chamber = chamber
    ))
  ) |>
  ungroup()




# Vote by Party -----------------------------------------------------------

count_votes_by_filter <- function(df, filter_var, filter_values, vote_var, vote_values){
  df |>
    as.data.frame() |>
    filter(
      {{filter_var}} %in% filter_values & {{vote_var}} %in% vote_values
    ) |>
    nrow()
}

vote_records <- vote_records |>
  rowwise() |>
  mutate(
    gop_yes = count_votes_by_filter(vote_record, Party, "Republican", vote, "Yes"),
    dem_yes = count_votes_by_filter(vote_record, Party, "Democrat", vote, "Yes"),
    gop_no = count_votes_by_filter(vote_record, Party, "Republican", vote, "No"),
    dem_no = count_votes_by_filter(vote_record, Party, "Democrat", vote, "No"),
  ) |>
  ungroup()


write_rds(vote_records, "data/floor_vote_records_2023.rds")

# Vote Combinations -------------------------------------------------------

# Get vote records
legislator_vote_records <- vote_records$vote_record

# Get data frame of combos
yes_combos <- lapply(legislator_vote_records, function(x){x |> filter(vote == "Yes") |> pull(Name) |> combn(m = 2) |> t() |> as.data.frame()}) |> bind_rows()
no_combos <- lapply(legislator_vote_records, function(x){x |> filter(vote == "No") |> pull(Name)})
no_combos <- no_combos[-which(sapply(no_combos, function(x){length(x) <= 1}), arr.ind = TRUE)] |>
  lapply(function(x){x |> combn(m = 2) |> t() |> as.data.frame()}) |> 
  bind_rows()

# Get frequency of combos
yes_combo_freq <- xtabs(~ V1 + V2, data = yes_combos) |> as.data.frame() |> filter(Freq > 0) |> rename(yea_freq = Freq)
no_combo_freq <- xtabs(~V1 + V2, data = no_combos) |> as.data.frame() |> filter(Freq > 0) |> rename(nay_freq = Freq)

# Join info
join <- full_join(yes_combo_freq, no_combo_freq) |>
  mutate(combo_votes = yea_freq + nay_freq)

write_rds(join, "analysis/legislator_floor_vote_combinations.rds")
