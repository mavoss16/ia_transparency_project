# Scrape legislation information
# Author: Matthew Voss

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(lubridate)
library(janitor)
library(rvest)
library(RSelenium)


house_file_index_url = "https://www.legis.iowa.gov/legislation/billTracking/directory/index?legType=HF&ga=89"
senate_file_index_url = "https://www.legis.iowa.gov/legislation/billTracking/directory/index?legType=SF&ga=89"


# Get links to bill groups ------------------------------------------------

house_file_page = read_html(house_file_index_url)
senate_file_page = read_html(senate_file_index_url)

house_links = house_file_page %>%
  html_element(xpath = "//*[@id=\"dolIndexContent\"]/div[2]/nav/ul") %>%
  html_children() %>%
  html_children() %>%
  html_attr(name = "href")

senate_links = senate_file_page %>%
  html_element(xpath = "//*[@id=\"dolIndexContent\"]/div[2]/nav/ul") %>%
  html_children() %>%
  html_children() %>%
  html_attr(name = "href")

bill_links = paste0("https://www.legis.iowa.gov", c(house_links, senate_links))



# Get lists of bill information -------------------------------------------

bill = list()
bill_summary = list()
for(i in seq_along(bill_links)){
  print(i)
  
  page = read_html(bill_links[i])
  
  text = page %>%
    html_element(xpath = "//*[@id=\"dolListingContent\"]/div[2]/ul") %>%
    html_children() %>%
    html_children() %>%
    html_text()
  
  names = text[c(TRUE, FALSE)]
  summaries = text[c(FALSE, TRUE)]
  
  bill = append(bill, names)
  bill_summary = append(bill_summary, summaries)
}



# Create bill data frame --------------------------------------------------

bill_df = data.frame(unlist(bill), unlist(bill_summary))
names(bill_df) = c("name", "summary")

bill_df = bill_df %>%
  mutate(
    ga_num = 89,
    bill_book_link = paste0(
      "https://www.legis.iowa.gov/legislation/BillBook?ba=",
      str_remove_all(name, " "),
      "&ga=",
      ga_num
    ),
    bill_history_link = paste0(
      "https://www.legis.iowa.gov/legislation/billTracking/billHistory?ga=",
      ga_num,
      "&billName=",
      str_remove_all(name, " ")
    ),
    bill_history_journal_actions_link = paste0(
      "https://www.legis.iowa.gov/legislation/billTracking/billHistory?enhanced=false&ga=",
      ga_num,
      "&billName=",
      str_remove_all(name, " ")
    ),
    bill_lobby_link = paste0(
      "https://www.legis.iowa.gov/lobbyist/reports/declarations?ga=",
      ga_num,
      "&ba=",
      str_remove_all(name, " ")
    )
  ) %>%
  arrange(name)


closeAllConnections()



# Get bill information from Bill History page -----------------------------

url_list = list()
# status_list = list()
# floor_manager_ids_list = list()
# related_bills_list = list()
# companion_bills_list = list()
# similar_bills_list = list()
author_list = list()
full_history_list = list()
introduction_date_list = list()
house_committee_passage_date_list = list()
house_committee_journal_list = list()
house_passage_date_list = list()
house_passage_journal_list = list()
house_yes_list = list()
house_no_list = list()
senate_committee_passage_date_list = list()
senate_committee_journal_list = list()
senate_passage_date_list = list()
senate_passage_journal_list = list()
senate_yes_list = list()
senate_no_list = list()
signature_date_list = list()

time = Sys.time()
for(i in 1:nrow(bill_df)){
  
  # print(i)
  if(i %% 50 == 0){
    print(i)
  }
  
  url = bill_df$bill_history_journal_actions_link[i]
  url_list[[i]] = url
  history = read_html(url)
  
  # Get committee/author
  author = history %>%
    html_element(xpath = "//*[@id=\"content\"]/div[2]/div[3]/div[1]") %>%
    html_text() %>%
    str_remove("By ") %>%
    str_trim()
  author_list[[i]] = author
  
  
  # Get bill history
  full_history = history %>%
    html_element(xpath = "//table[@class=\"billActionTable divideVert sortable\"]")
  
  full_history = full_history %>%
    html_table()
  names(full_history) = c("date", "summary")
  full_history = full_history %>%
    mutate(date = mdy(date))

  full_history_list[[i]] = full_history

  # Introduction
  introduction_date = full_history$date[which(str_detect(full_history$summary, "Introduced"))]
  introduction_date_list[[i]] = introduction_date
  
  # House Committee info
  house_committee_passage_date = full_history$date[
    which(
      (str_detect(full_history$summary, "recommending") & str_detect(full_history$summary, "passage") & str_detect(full_history$summary, "H.J.")) |
        (str_detect(full_history$summary, "approving bill") & str_detect(full_history$summary, "H.J."))
    )
  ] %>%
    max()
  house_committee_journal = full_history$summary[
    which(
      (str_detect(full_history$summary, "recommending") & str_detect(full_history$summary, "passage") & str_detect(full_history$summary, "H.J.") & full_history$date == house_committee_passage_date) |
        (str_detect(full_history$summary, "approving bill") & str_detect(full_history$summary, "H.J.") & full_history$date == house_committee_passage_date)
    )
  ] %>%
    str_extract("H.J. \\d*")
  house_committee_passage_date_list[[i]] = ifelse(house_committee_passage_date == -Inf, NA, house_committee_passage_date)
  house_committee_journal_list[[i]] = ifelse(length(house_committee_journal) == 0, NA, house_committee_journal)
  
  # House passage
  house_passage_date = full_history$date[
    which(str_detect(full_history$summary, "Passed House"))
  ] %>%
    max()
  house_passage_journal = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed House") & full_history$date == house_passage_date
    )
  ] %>%
    str_extract("H.J. \\d*")
  house_yes = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed House") & full_history$date == house_passage_date
    )
  ] %>%
    str_extract("yeas \\d*") %>%
    str_extract("\\d*$") %>%
    as.numeric()
  house_no = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed House") & full_history$date == house_passage_date
    )
  ] %>%
    str_extract("nays \\d*") %>%
    str_extract("\\d*$") %>%
    as.numeric()
  house_passage_date_list[[i]] = ifelse(house_passage_date == -Inf, NA, house_passage_date)
  house_passage_journal_list[[i]] = ifelse(length(house_passage_journal) == 0, NA, house_passage_journal)
  house_yes_list[[i]] = ifelse(length(house_yes) == 0, NA, house_yes)
  house_no_list[[i]] = ifelse(length(house_no) == 0, NA, house_no)
  
  # Senate Committee info
  senate_committee_passage_date = full_history$date[
    which(
      (str_detect(full_history$summary, "recommending") & str_detect(full_history$summary, "passage") & str_detect(full_history$summary, "S.J.")) |
        (str_detect(full_history$summary, "approving bill") & str_detect(full_history$summary, "S.J."))
    )
  ] %>%
    max()
  senate_committee_journal = full_history$summary[
    which(
      (str_detect(full_history$summary, "recommending") & str_detect(full_history$summary, "passage") & str_detect(full_history$summary, "S.J.") & full_history$date == senate_committee_passage_date) |
        (str_detect(full_history$summary, "approving bill") & str_detect(full_history$summary, "S.J.") & full_history$date == senate_committee_passage_date)
    )
  ] %>%
    str_extract("S.J. \\d*")
  senate_committee_passage_date_list[[i]] = ifelse(senate_committee_passage_date == -Inf, NA_Date_, senate_committee_passage_date)
  senate_committee_journal_list[[i]] = ifelse(length(senate_committee_journal) == 0, NA, senate_committee_journal)
  
  # Senate passage
  senate_passage_date = full_history$date[
    which(str_detect(full_history$summary, "Passed Senate"))
  ] %>%
    max()
  senate_passage_journal = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed Senate") & full_history$date == senate_passage_date
    )
  ] %>%
    str_extract("S.J. \\d*")
  senate_yes = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed Senate") & full_history$date == senate_passage_date
    )
  ] %>%
    str_extract("yeas \\d*") %>%
    str_extract("\\d*$") %>%
    as.numeric()
  senate_no = full_history$summary[
    which(
      str_detect(full_history$summary, "Passed Senate") & full_history$date == senate_passage_date
    )
  ] %>%
    str_extract("nays \\d*") %>%
    str_extract("\\d*$") %>%
    as.numeric()
  senate_passage_date_list[[i]] = ifelse(senate_passage_date == -Inf, NA, senate_passage_date)
  senate_passage_journal_list[[i]] = ifelse(length(senate_passage_journal) == 0, NA, senate_passage_journal)
  senate_yes_list[[i]] = ifelse(length(senate_yes) == 0, NA, senate_yes)
  senate_no_list[[i]] = ifelse(length(senate_no) == 0, NA, senate_no)
  
  # Signature
  signature_date = full_history$date[
    which(str_detect(full_history$summary, "Signed by Governor"))
  ] %>%
    max()
  signature_date_list[[i]] = ifelse(signature_date == -Inf, NA, signature_date)
  
  
}

Sys.time() - time

new_df = bill_df
new_df$author = author_list
new_df$full_history = full_history_list
new_df$introduction_date = introduction_date_list
new_df$house_committee_passage_date = house_committee_passage_date_list
new_df$house_committee_journal = house_committee_journal_list
new_df$house_passage_date = house_passage_date_list
new_df$house_passage_journal = house_passage_journal_list
new_df$house_yes = house_yes_list
new_df$house_no = house_no_list
new_df$senate_committee_passage_date = senate_committee_passage_date_list
new_df$senate_committee_journal = senate_committee_journal_list
new_df$senate_passage_date = senate_passage_date_list
new_df$senate_passage_journal = senate_passage_journal_list
new_df$senate_yes = senate_yes_list
new_df$senate_no = senate_no_list
new_df$signature_date = signature_date_list


df = new_df %>%
  mutate(
    status = case_when(
      !is.na(signature_date) ~ "Signed by Governor",
      !is.na(house_passage_date) & !is.na(senate_passage_date) ~ "Passed House & Senate",
      !is.na(house_passage_date) & is.na(senate_passage_date) ~ "Passed House",
      is.na(house_passage_date) & !is.na(senate_passage_date) ~ "Passed Senate",
      !is.na(house_committee_passage_date) ~ "Passed House Committee",
      !is.na(senate_committee_passage_date) ~ "Passed Senate Committee",
      TRUE ~ NA_character_
    )
  ) %>%
  relocate(
    ends_with("_link"),
    .after = status
  )


write_rds(df, "data/ga89_legislation.rds")


# Hold Code ---------------------------------------------------------------


# # Check if Bill History page is one of two versions
# if(length(html_element(history, xpath = "//*[@id=\"content\"]/table[1]")) == 0){
#   header = history %>% html_element(xpath = "//div[@class=\"divideVert\"]/div[1]")
# } else{
#   header = history %>% html_element(xpath = "//div[@class=\"divideVert\"]")
# }
# 
# 
# # Get bill status (if exists)
# status = html_children(header)[1] %>% 
#   html_text() %>%
#   str_extract("Status: .*") %>%
#   str_remove("Status: ")
# status_list[[i]] = status
# 
# 
# # Process header children
# header_children = html_children(header)[3] %>%
#   html_children()
# if(length(header_children) >= 4){
#   
#   # Get floor manager information
#   floor_manager_ids = header_children[1] %>%
#     html_children() %>%
#     html_attr(name = "href") %>%
#     str_extract("personID=\\d+") %>%
#     str_remove("personID=")
#   floor_manager_ids_list[[i]] = floor_manager_ids
#   
#   
#   # Get related bills
#   related_bills = header_children[4:(length(header_children) - 1)] %>% 
#     html_children() %>%
#     html_text()
#   related_bills_list[[i]] = related_bills
#   
#   
#   # Get companion and similar bills
#   related_bills_text = header_children[length(header_children)] %>% 
#     html_children() %>%
#     html_text()
#   
#   if(("(C)" %in% related_bills_text) & ("(S)" %in% related_bills_text)){
#     companion_bills = related_bills_text[(which(related_bills_text == "(C)") + 1):(which(related_bills_text == "(S)") - 1)]
#     similar_bills = related_bills_text[(which(related_bills_text == "(S)") + 1):length(related_bills_text)]
#     
#   } else if(("(C)" %in% related_bills_text) & !("(S)" %in% related_bills_text)){
#     companion_bills = related_bills_text[(which(related_bills_text == "(C)") + 1):length(related_bills_text)]
#     similar_bills = NULL
#     
#   } else if(!("(C)" %in% related_bills_text) & ("(S)" %in% related_bills_text)){
#     companion_bills = NULL
#     similar_bills = related_bills_text[(which(related_bills_text == "(S)") + 1):length(related_bills_text)]
#     
#   } else{
#     companion_bills = NULL
#     similar_bills = NULL
#     
#   }
#   
#   companion_bills_list[[i]] = companion_bills
#   similar_bills_list[[i]] = similar_bills
#   
#   
#   # Get committee
#   committee = html_children(header)[4]
#   committee = html_children(committee)[1] %>% 
#     html_text() %>%
#     str_trim() %>%
#     str_remove("By ")
#   
#   committee_list[[i]] = committee
# }
