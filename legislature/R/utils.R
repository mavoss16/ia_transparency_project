
library(dplyr)
library(janitor)
library(stringr)
library(lubridate)
library(purrr)

library(rvest)

items_to_df <- function(list){
  map(list, as.data.frame) |>
    bind_rows()
}

scrape_lobbyist_declarations <- function(bill_number, ga = 91) {

  # Construct URL dynamically
  url <- paste0("https://www.legis.iowa.gov/lobbyist/reports/declarations?ga=", ga, "&ba=", bill_number)
  
  # Read the webpage
  page <- read_html(url)
  
  # Extract all tables
  tables <- page %>% html_elements("table")
  if (length(tables) == 0) stop("No tables found on the page.")
  
  # Identify the correct table by checking headers
  target_table <- NULL
  for (tbl in tables) {
    headers <- tbl %>% html_elements("th") %>% html_text(trim = TRUE)
    if ("Client" %in% headers && "Declaration" %in% headers) {
      target_table <- tbl
      break
    }
  }
  
  if (is.null(target_table)) stop("Could not find the declarations table.")
  
  # Convert to data frame
  df <- target_table %>%
    html_table(fill = TRUE) |>
    clean_names() |>
    mutate(
      date = mdy_hm(date)
    )
  
  # Deduplicate and select relevant columns
  clean_df <- df %>%
    distinct(bill, declaration, client, date) |>
    slice_max(date, by = c(client)) |>
    rename(most_recent_declaration = declaration)# |>
  #select(-date)
  
  return(clean_df)
}
