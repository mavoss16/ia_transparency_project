# Bills and their last action: https://www.legis.iowa.gov/legislation/billTracking/billDisposition
# Bills Introduced: https://www.legis.iowa.gov/legislation/billTracking/billpacket
# Bill Actions: https://www.legis.iowa.gov/legislation/billTracking/sessiondaily
# Similar and Companion: https://www.legis.iowa.gov/legislation/billTracking/similarCompanion



library(dplyr)
library(stringr)
library(janitor)
library(rvest)
library(RSelenium)
library(readr)



# Read Previous Data ------------------------------------------------------

# prev_actions <- data.frame("sponsor" = character(0), "action" = character(0), "date" = POSIXct(0), "sponsor_s" = character(0))
# write_rds(prev_actions, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_legislation_91st_ga.rds")

# prev_actions <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_legislation_90th_ga.rds")
prev_actions <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_legislation_91st_ga.rds")
# prev_lsa <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_lsa_90th_ga.rds")
action_documentation <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_documentation.rds")


# rsDriver Attempt --------------------------------------------------------

rd <- rsDriver(port = 4567L, browser = "firefox", chromever = NULL)
driver <- rd$client


actions_url <- "https://www.legis.iowa.gov/legislation/billTracking/sessiondaily"
driver$navigate(actions_url)

dropdown <- driver$findElement(using = "xpath", value = "//*[@id=\"publicationDate\"]")
dropdown$clickElement()
dropdown_elements <- dropdown$findChildElements(using = "tag name", value = "option")
# date <- driver$findElement(using = "xpath", value = "//*[@id=\"publicationDate\"]/option[16]")
# date$clickElement()

# page <- read_html(driver$getPageSource()[[1]])
# tables <- html_table(page)
actions <- data.frame()
for(i in 1:4){
  print(i)
  dropdown_elements[[i]]$clickElement()
  Sys.sleep(runif(1, 0.5, 1.5))
  page <- read_html(driver$getPageSource()[[1]])
  tables <- html_table(page)
  date <- dropdown_elements[[i]]$getElementText()[[1]]
  senate_passage <- tables[[1]] |>
    mutate(action = "Voted out of Senate")
  house_passage <- tables[[2]] |>
    mutate(action = "Voted out of House")
  senate_committee <- tables[[3]] |>
    mutate(action = "Voted out of Senate Committee")
  house_committee <- tables[[4]] |>
    mutate(action = "Voted out of House Committee")
  withdrawn <- tables[[5]] |>
    mutate(action = "Withdrawn")
  passed_on_file <- tables[[6]] |>
    mutate(action = "Passed on File")
  sent_to_gov <- tables[[7]] |>
    mutate(action = "Sent to Governor")
  veto <- tables[[8]] |>
    mutate(action = "Vetoed by Governor")
  signed <- tables[[9]] |>
    mutate(action = "Signed by Governor")
  
  daily_actions <- bind_rows(
    senate_passage, house_passage, senate_committee, house_committee,
    withdrawn, passed_on_file, sent_to_gov, veto, signed
  ) |>
    clean_names() |>
    mutate(date = date)
  
  actions <- bind_rows(actions, daily_actions)
}



documents_url <- "https://www.legis.iowa.gov/legislation/billTracking/billpacket"
driver$navigate(documents_url)


dropdown <- driver$findElement(using = "xpath", value = "//*[@id=\"publicationDate\"]")
dropdown$clickElement()
dropdown_elements <- dropdown$findChildElements(using = "tag name", value = "option")


filed <- data.frame()
lsa <- data.frame()
for(i in 1:4){
  print(i)
  dropdown_elements[[i]]$clickElement()
  Sys.sleep(runif(1, 1, 1.5))
  page <- read_html(driver$getPageSource()[[1]])
  tables <- html_table(page)
  j = 0
  while(length(tables) == 0){
    Sys.sleep(1)
    page <- read_html(driver$getPageSource()[[1]])
    tables <- html_table(page)
    j = j + 1
    print(j)
    if(j == 50) break
  }
  date <- dropdown_elements[[i]]$getElementText()[[1]]
  bills <- tables[[1]] |>
    mutate(action = "Bill Filed")
  study_bills <- tables[[2]] |>
    mutate(action = "Study Bill Filed")
  if(ncol(tables[[3]]) == 3){
    amendments <- tables[[3]] |>
      select(-3) |>
      mutate(action = "Amendment Filed")
  } else{
    amendments <- tables[[3]] |>
      mutate(action = "Amendment Filed")
  }
  fiscal_notes <- tables[[4]] |>
    mutate(action = "Fiscal Note Published")
  noba <- tables[[5]] |>
    mutate(action = "Notes on Bills and Amendments")
  
  daily_filed <- bind_rows(
    bills, study_bills, amendments
  ) |>
    clean_names() |>
    mutate(date = date)
  
  filed <- bind_rows(filed, daily_filed)
  
  # daily_lsa <- bind_rows(fiscal_notes, noba) |>
  #   clean_names()
  # lsa <- bind_rows(lsa, daily_lsa)
}


driver$close()
rd$server$stop()


full_actions <- actions |>
  filter(!str_detect(bill, "^\\*\\*\\*"))

full_filed <- filed |>
  mutate(
    bill = ifelse(is.na(bill), yes = amendment, no = bill),
    sponsor = ifelse(is.na(sponsor_s), yes = sponsor, no = sponsor_s)
  ) |>
  select(-amendment, -sponsor_s) |>
  filter(!str_detect(bill, "^\\*\\*\\*"))

all_actions <- bind_rows(full_filed, full_actions) |>
  mutate(date = lubridate::mdy(date)) |>
  arrange(date, bill) |>
  rename(file = bill, file_title = bill_title)

all_actions <- bind_rows(prev_actions, all_actions) |>
  distinct()

# all_lsa <- bind_rows(prev_lsa, lsa) |>
#   distinct()

action_documentation <- bind_rows(
  action_documentation,
  as.data.frame(
    list(
      date = Sys.Date(), 
      file_dates = paste(unique(filed$date), collapse = ", "), 
      action_dates = paste(unique(actions$date), collapse = ", "),
      num_leg_actions_added = nrow(all_actions) - nrow(prev_actions)
    )
  )
)


write_rds(all_actions, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_legislation_91st_ga.rds")
write_rds(action_documentation, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_documentation.rds")
# write_rds(all_lsa, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/actions_lsa_90th_ga.rds")
