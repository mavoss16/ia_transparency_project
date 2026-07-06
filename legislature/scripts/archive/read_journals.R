

library(dplyr)
source("read_journal_functions.R")

senate_journals <- list.files("data/Journals/90th General Assembly/Senate")
house_journals <- list.files("data/Journals/90th General Assembly/House")


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


intro_files <- data.frame()
committee_files <- data.frame()
bill_votes <- data.frame()

for(file in senate_journals){
  print(file)
  action_list <- read_journal(
    paste0("data/Journals/90th General Assembly/Senate/", file),
    legislators,
    "Senate"
  )
  intro_files <- bind_rows(intro_files, action_list[[1]])
  committee_files <- bind_rows(committee_files, action_list[[2]])
  bill_votes <- bind_rows(bill_votes, action_list[[3]])
}

# house_intro_files <- data.frame()
# house_bill_votes <- data.frame()
# 
# # Stopped at 20230419_HJNL.pdf
# for(file in house_journals){
#   print(file)
#   action_list <- read_journal(
#     paste0("data/Journals/90th General Assembly/House/", file),
#     legislators,
#     "House"
#   )
#   house_intro_files <- bind_rows(house_intro_files, action_list[[1]])
#   house_bill_votes <- bind_rows(house_bill_votes, action_list[[3]])
# }

bill_votes_copy <- bill_votes

# Vote by Party -----------------------------------------------------------

count_votes_by_filter <- function(df, filter_var, filter_values, vote_var, vote_values){
  df |>
    as.data.frame() |>
    filter(
      {{filter_var}} %in% filter_values & {{vote_var}} %in% vote_values
    ) |>
    nrow()
}

bill_votes <- bill_votes_copy
bill_votes <- bill_votes |>
  rowwise() |>
  mutate(
    gop_yea = count_votes_by_filter(vote_record, Party, "Republican", vote, "Yea"),
    dem_yea = count_votes_by_filter(vote_record, Party, "Democrat", vote, "Yea"),
    gop_nay = count_votes_by_filter(vote_record, Party, "Republican", vote, "Nay"),
    dem_nay = count_votes_by_filter(vote_record, Party, "Democrat", vote, "Nay"),
  ) |>
  ungroup()


# Vote Combinations -------------------------------------------------------

# Get vote records
senate_vote_records <- bill_votes$vote_record

# Get data frame of combos
yea_combos <- lapply(senate_vote_records, function(x){x |> filter(vote == "Yea") |> pull(Name) |> combn(m = 2) |> t() |> as.data.frame()}) |> bind_rows()
nay_combos <- lapply(senate_vote_records, function(x){x |> filter(vote == "Nay") |> pull(Name)})
nay_combos <- nay_combos[-which(sapply(nay_combos, function(x){length(x) <= 1}), arr.ind = TRUE)] |>
  lapply(function(x){x |> combn(m = 2) |> t() |> as.data.frame()}) |> 
  bind_rows()

# Get frequency of combos
yea_combo_freq <- xtabs(~ V1 + V2, data = yea_combos) |> as.data.frame() |> filter(Freq > 0) |> rename(yea_freq = Freq)
nay_combo_freq <- xtabs(~V1 + V2, data = nay_combos) |> as.data.frame() |> filter(Freq > 0) |> rename(nay_freq = Freq)

# Join info
join <- full_join(yea_combo_freq, nay_combo_freq) |>
  mutate(combo_votes = yea_freq + nay_freq)


library(visNetwork)
library(tidygraph)
library(ggraph)
library(igraph)
# https://www.jessesadler.com/post/network-analysis-with-r/#creating-network-objects