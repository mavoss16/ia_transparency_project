# Scrape general assembly and legislator information
# Author: Matthew Voss

library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(lubridate)
library(janitor)
library(rvest)
library(RSelenium)


# Senators: https://www.legis.iowa.gov/legislators/senate
# Representatives: https://www.legis.iowa.gov/legislators/house

senators_url = "https://www.legis.iowa.gov/legislators/senate"
reps_url = "https://www.legis.iowa.gov/legislators/house"


# Set up driver -----------------------------------------------------------

binman::rm_platform("phantomjs")
wdman::selenium(retcommand = TRUE)

rd <- rsDriver(port = 4111L, browser = "chrome", version = "latest", chromever = "112.0.5615.49")  

rd <- rsDriver(port = 4567L, browser = "firefox", chromever = NULL)

driver <- rd$client

driver$navigate(senators_url)



# General Assembly List ---------------------------------------------------

selection = driver$findElement(value = "//*[@id=\"legislatorContent\"]/div[2]/ul")

selection$clickElement()


ga_list = selection$findChildElements(using = "tag name", value = "li")

ga_list[[6]]$findElement(value = "//*[@id=\"legislatorContent\"]/div[2]/ul/li[6]/a")$clickElement()

ga_dates = list()

for(i in 2:length(ga_list)){
  ga_dates = append(ga_dates, ga_list[[i]]$getElementText()[[1]])
}


ga_df = data.frame(ga = unlist(ga_dates)) %>%
  mutate(
    ga_num = str_remove_all(ga, "General Assembly: |Legislative Assembly: ") %>% str_sub(start = 1, end = 2),
    ga_start_date = str_remove_all(ga, "General Assembly: \\d+ \\(|Legislative Assembly: \\d+ \\(") %>% str_sub(start = 1, end = 10) %>% mdy(),
    ga_end_date = str_sub(ga, start = -11, end = -2) %>% mdy()
  )

write_csv(ga_df, "data/general_assemblies.csv")


ga_df = data.frame(ga_num = c(90))

# Representative List -----------------------------------------------------

test_url = "https://www.legis.iowa.gov/legislators/house?v.template=legislators/legislatorsAjax&layout=false&ga=88&layout=false&chamberID=H&partyID=-1"
url_1 = "https://www.legis.iowa.gov/legislators/house?v.template=legislators/legislatorsAjax&layout=false&ga="
url_2 = "&layout=false&chamberID=H&partyID=-1"


all_legislators = data.frame()
all_leg_composition = data.frame()
for(i in 1){
  print(i)
  
  # Read HTML page
  page = read_html(paste0(url_1, ga_df$ga_num[i], url_2))
  
  # Get list of tables
  tables = html_table(page)
  
  # Get legislator table and extract links
  legislator_table = html_element(page, xpath = "//*[@id=\"sortableTable\"]/tbody")
  rows = html_elements(legislator_table, "a")
  links = html_attr(rows, "href")
  links = links[str_detect(links, "legislator")]
  
  # Clean legislator table
  legislators = tables[[1]] %>%
    mutate(
      ga_num = ga_df$ga_num[i],
      start_date = ga_df$ga_start_date[i],
      end_date = ga_df$ga_end_date[i]
    )
  
  # Add links and personID to legislator DF
  legislators$link = links
  legislators = legislators %>%
    rowwise() %>%
    mutate(
      person_id = str_sub(link, start = str_locate(link, "personID=")[[2]] + 1, end = -1)
    )
  
  # Extract legislature composition data
  leg_composition = tables[[2]] %>%
    mutate(
      ga_num = ga_df$ga_num[i]
    )
  all_leg_composition = bind_rows(all_leg_composition, leg_composition)
  
  # Extract former legislator table, if it exists
  if(length(tables) == 3){
    # Get table and links
    former_legislator_table = html_element(page, xpath = "/html/body/div/table[3]/tbody")
    rows = html_elements(former_legislator_table, "a")
    links = html_attr(rows, "href")
    links = links[str_detect(links, "legislator")]
    
    # Clean former legislator data
    former_legislators = tables[[3]] %>%
      rowwise() %>%
      mutate(
        ga_num = ga_df$ga_num[i],
        start_date = str_extract(Name, "\\(\\d+/\\d+/\\d+") %>% str_sub(start = 2) %>% mdy(),
        end_date = str_extract(Name, "\\d+/\\d+/\\d+\\)") %>% str_sub(end = -2) %>% mdy(),
        Name = str_sub(Name, start = 1, end = str_locate(Name, "\\(")[[1]] - 2)
      )
    
    # Add links and personID to former_legislators DF
    former_legislators$link = links
    former_legislators = former_legislators %>%
      rowwise() %>%
      mutate(
        person_id = str_sub(link, start = str_locate(link, "personID=")[[2]] + 1, end = -1)
      )
    
    # Fix dates for legislators with partial terms
    for(j in 1:nrow(former_legislators)){
      index = which(legislators$District == former_legislators$District[j])
      legislators$start_date[index] = (former_legislators$end_date[j] + 1) %>% as_date()
    }
    
    # Add former legislators data
    legislators = bind_rows(legislators, former_legislators) %>%
      clean_names() %>%
      arrange(district, start_date)
    
  } else{
    
    # Add data if no former legislators data exists
    legislators = legislators %>%
      clean_names() %>%
      arrange(district, start_date)
  }
  
  # Combine all legislator data
  all_legislators = bind_rows(all_legislators, legislators)
}


# Senators List -----------------------------------------------------------

url_1 = "https://www.legis.iowa.gov/legislators/senate?v.template=legislators/legislatorsAjax&layout=false&ga="
url_2 = "&layout=false&chamberID=S&partyID=-1"


for(i in 1){
  print(i)
  
  # Read HTML page
  page = read_html(paste0(url_1, ga_df$ga_num[i], url_2))
  
  # Get list of tables
  tables = html_table(page)
  
  # Get legislator table and extract links
  legislator_table = html_element(page, xpath = "//*[@id=\"sortableTable\"]/tbody")
  rows = html_elements(legislator_table, "a")
  links = html_attr(rows, "href")
  links = links[str_detect(links, "legislator")]
  
  # Clean legislator table
  legislators = tables[[1]] %>%
    mutate(
      ga_num = ga_df$ga_num[i],
      start_date = ga_df$ga_start_date[i],
      end_date = ga_df$ga_end_date[i]
    )
  
  # Add links and personID to legislator DF
  legislators$link = links
  legislators = legislators %>%
    rowwise() %>%
    mutate(
      person_id = str_sub(link, start = str_locate(link, "personID=")[[2]] + 1, end = -1)
    )
  
  # Extract legislature composition data
  leg_composition = tables[[2]] %>%
    mutate(
      ga_num = ga_df$ga_num[i]
    )
  all_leg_composition = bind_rows(all_leg_composition, leg_composition)
  
  # Extract former legislator table, if it exists
  if(length(tables) == 3){
    # Get table and links
    former_legislator_table = html_element(page, xpath = "/html/body/div/table[3]/tbody")
    rows = html_elements(former_legislator_table, "a")
    links = html_attr(rows, "href")
    links = links[str_detect(links, "legislator")]
    
    # Clean former legislator data
    former_legislators = tables[[3]] %>%
      rowwise() %>%
      mutate(
        ga_num = ga_df$ga_num[i],
        start_date = str_extract(Name, "\\(\\d+/\\d+/\\d+") %>% str_sub(start = 2) %>% mdy(),
        end_date = str_extract(Name, "\\d+/\\d+/\\d+\\)") %>% str_sub(end = -2) %>% mdy(),
        Name = str_sub(Name, start = 1, end = str_locate(Name, "\\(")[[1]] - 2)
      )
    
    # Add links and personID to former_legislators DF
    former_legislators$link = links
    former_legislators = former_legislators %>%
      rowwise() %>%
      mutate(
        person_id = str_sub(link, start = str_locate(link, "personID=")[[2]] + 1, end = -1)
      )
    
    # Fix dates for legislators with partial terms
    for(j in 1:nrow(former_legislators)){
      index = which(legislators$District == former_legislators$District[j])
      legislators$start_date[index] = (former_legislators$end_date[j] + 1) %>% as_date()
    }
    
    # Add former legislators data
    legislators = bind_rows(legislators, former_legislators) %>%
      clean_names() %>%
      arrange(district, start_date)
    
  } else{
    
    # Add data if no former legislators data exists
    legislators = legislators %>%
      clean_names() %>%
      arrange(district, start_date)
  }
  
  # Combine all legislator data
  all_legislators = bind_rows(all_legislators, legislators)
}

write_csv(all_leg_composition, "data/general_assembly_composition.csv")
write_csv(all_legislators, "data/legislators_90th_ga.csv")


driver$close()
  

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

# 2023/04/15, 2:30 PM - need to run floor manager code still
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

write_rds(all_legislators, "data/legislators_90th_ga_sponsor_fm.rds")
