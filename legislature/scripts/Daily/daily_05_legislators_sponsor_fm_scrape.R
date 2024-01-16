# Scrape legislator sponsorship and floor managed-files
# Author: Matthew Voss

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(lubridate)
library(janitor)
library(rvest)
library(RSelenium)


all_legislators <- read_csv("data/legislators_90th_ga.csv")


# Legislator Sponsorship --------------------------------------------------

url = "https://www.legis.iowa.gov/legislation/findLegislation/findBillBySponsorOrManager?ga=87&pid=9397"

sponsor_column = list()
for(i in 1:nrow(all_legislators)){
  print(i)
  url = paste0(
    "https://www.legis.iowa.gov/legislation/findLegislation/findBillBySponsorOrManager?ga=",
    all_legislators$ga_num[i],
    "&pid=",
    all_legislators$person_id[i]
  )
  
  page = read_html(url)
  
  tables = html_table(page)
  
  bill_list = list()
  
  if(length(tables) > 0){
    for(j in 1:length(tables)){
      table = tables[[j]]
      if(any(str_detect(table$Bill, "HF")) || any(str_detect(table$Bill, "SF"))){
        bill_list = append(bill_list, table$Bill)
      } else{
        next
      }
    }
  }
  
  Sys.sleep(runif(1, 0.1, 0.6))
  sponsor_column[[i]] = bill_list
}

# Legislator Floor Manager ------------------------------------------------

fm_column = list()
for(i in 1:nrow(all_legislators)){
  print(i)
  url = paste0(
    "https://www.legis.iowa.gov/legislation/findLegislation/findBillBySponsorOrManager?ga=",
    all_legislators$ga_num[i],
    "&pid=",
    all_legislators$person_id[i],
    "&type=fm" 
  )
  
  page = read_html(url)
  
  tables = html_table(page)
  
  bill_list = list()
  
  if(length(tables) > 0){
    for(j in 1:length(tables)){
      table = tables[[j]]
      if(any(str_detect(table$Bill, "HF")) || any(str_detect(table$Bill, "SF"))){
        bill_list = append(bill_list, table$Bill)
      } else{
        next
      }
    }
  }
  
  Sys.sleep(runif(1, 0.1, 0.6))
  fm_column[[i]] = bill_list
}


all_legislators_copy = all_legislators
all_legislators$sponsor = sponsor_column
all_legislators$floor_manager = fm_column

write_rds(all_legislators, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/legislators_90th_ga_sponsor_fm.rds")
