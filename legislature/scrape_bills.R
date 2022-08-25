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
    bill_lobby_link = paste0(
      "https://www.legis.iowa.gov/lobbyist/reports/declarations?ga=",
      ga_num,
      "&ba=",
      str_remove_all(name, " ")
    )
  ) %>%
  arrange(name)


closeAllConnections()


status_list = list()
floor_manager_ids_list = list()
related_bills_list = list()
companion_bills_list = list()
full_history_list = list()

for(i in 1:nrow(bill_df)){
  
  url = bill_df$bill_history_link[i]
  history = read_html(url)
  
  if(length(html_element(history, xpath = "//*[@id=\"content\"]/table[1]")) == 0){
    header = history %>% html_element(xpath = "//div[@class=\"divideVert\"]/div[1]")
  } else{
    header = history %>% html_element(xpath = "//div[@class=\"divideVert\"]")
  }

  status = html_children(header)[1] %>% 
    html_text() %>%
    str_extract("Status: .*") %>%
    str_remove("Status: ")
  status_list[[i]] = status
  
  header_children = html_children(header)[3] %>%
    html_children()
  floor_manager_ids = header_children[1] %>%
    html_children() %>%
    html_attr(name = "href") %>%
    str_extract("personID=\\d+") %>%
    str_remove("personID=")
  floor_manager_ids_list[[i]] = floor_manager_ids
  
  related_bills = header_children[4:(length(header_children) - 1)] %>% 
    html_children() %>%
    html_text()
  
  companion_bills = header_children[length(header_children)] %>% html_children()
  
  full_history = history %>%
    html_element(xpath = "//table[@class=\"billActionTable divideVert sortable\"]")
  
  full_history = full_history %>%
    html_table()


}
