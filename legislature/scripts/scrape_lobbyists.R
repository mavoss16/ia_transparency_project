
# Author: Matthew Voss

library(dplyr)
library(stringr)
library(janitor)
library(rvest)
library(RSelenium)



# Base Lobbyist Table -----------------------------------------------------


url <- "https://www.legis.iowa.gov/lobbyist/reports/searchLobby?type=lobbyist"

page <- read_html(url)

lobbyists <- html_table(page)[[1]] |>
  clean_names()

table_html <- html_element(page, "tbody")



# Lobbyist IDs ------------------------------------------------------------

table_links <- html_elements(table_html, "a") |>
  html_attr("href")

table_links <- table_links[!is.na(table_links)]
  
lobbyists$url <- table_links

lobbyists <- lobbyists |>
  mutate(
    id = str_extract(url, "personID=\\d+") |> str_remove("personID="),
    .after = name
  )




# Lobbyist Declarations ---------------------------------------------------


declaration_url <- "https://www.legis.iowa.gov/lobbyist/reports/declarations?personID=28792&ga=90"


# Docker Attempt ----------------------------------------------------------

# page <- session(declaration_url)
# table <- html_table(page)[[1]]
# 
# html_form(page)

# docker run -d -p 4445:4444 selenium/standalone-chrome
# docker ps

# system("docker run --name chrome_scrape -d -p 4445:4444 selenium/standalone-chrome")
# system("docker run -d -p 4445:4444 selenium/standalone-chrome")
# system("docker run -d -p 4445:4444 -p 5901:5900 selenium/standalone-firefox-debug")

# rd <- rsDriver(port = 4445L, browser = "chrome", version = "latest", chromever = "113.0.5672.24")  
# 
# remDr <- RSelenium::remoteDriver(remoteServerAddr = "172.17.0.2", #localhost or 172.17.0.2
#                                  port = 4445L)



# remDr$setTimeout(type = "page load", milliseconds = 60000)
# remDr$open()

# remDr <- remoteDriver$new()


# rsDriver Attempt --------------------------------------------------------

rd <- rsDriver(port = 4111L, browser = "firefox", chromever = NULL)
driver <- rd$client

# driver$navigate(declaration_url)
# 
# element <- driver$findElement(using = "xpath", "//*[@id=\"loadAllDeclarations\"]")
# driver$mouseMoveToLocation(webElement = element)
# 
# driver$click()
# 
# table <- driver$findElement(using = "xpath", "//*[@id=\"declarationsTable\"]")
# 
# table_html <- table$getElementAttribute("outerHTML")[[1]]
# 
# page_source <- driver$getPageSource()
# 
# page <- read_html(page_source[[1]])
# 
# test <- html_table(page)[[1]]

# lobbyists$declarations <- NA

declaration_list <- list()

for(i in 1:nrow(lobbyists)){
  print(
    paste0(i, "/677: ", lobbyists$name[i])
  )
  declaration_url <- paste0(
    "https://www.legis.iowa.gov/lobbyist/reports/declarations?personID=",
    lobbyists$id[i],
    "&ga=90"
  )
  
  # Navigate to page
  driver$navigate(declaration_url)
  Sys.sleep(0.7)
  
  # Click to expand table
  element <- driver$findElement(using = "xpath", "//*[@id=\"loadAllDeclarations\"]")
  driver$mouseMoveToLocation(webElement = element)
  driver$click()
  Sys.sleep(0.2)
  # Get page and declaration table
  page <- read_html(driver$getPageSource()[[1]])
  declaration_table <- html_table(page)[[1]]
  
  declaration_list[[i]] <- declaration_table
  Sys.sleep(0.1)
}

# Close driver
driver$close()

# system("docker stop chrome_scrape")
lobbyists_copy <- lobbyists
lobbyists$declarations <- declaration_list


readr::write_rds(lobbyists, "lobbying/lobbyists_2023.rds")
