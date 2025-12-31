

library(readxl)
library(readr)

library(dplyr)
library(janitor)
library(stringr)
library(lubridate)
library(purrr)

library(rvest)



files <- read_excel("data/legislation_list.xlsx")


get_bill_versions <- function(bill_number, ga = 91) {

  print(bill_number)

  # Construct the URL
  base_url <- "https://www.legis.iowa.gov/legislation/BillBook"
  url <- paste0(base_url, "?ba=", bill_number, "&ga=", ga)

  # Read the HTML content of the page
  # page <- read_html_live(url)

  for(attempt in 1:3){
    page <- tryCatch(
      {read_html_live(url)},
      error = function(e){
        last_err <<- e
        NULL
      }
    )
    if(!is.null(page)){break}
    else if(is.null(page) & attempt < 3){
      print(paste0("Page Reading Failed, trying Attempt #", attempt))
      Sys.sleep(2)
    } else{
      stop(last_err)
    }
  }
  Sys.sleep(1)

  related_info <- page |>
    html_elements("table") |>
    html_elements(xpath = "//*[contains(@class, 'billRelatedInfo')]")

  versions <- related_info |>
    html_elements("a")

  # Extract link text and href attributes
  version_df <- data.frame(
    text = versions %>% html_text(trim = TRUE),
    link = versions %>% html_attr("href"),
    stringsAsFactors = FALSE
  ) |>
    filter(
      str_detect(text, "^[A-Z]+[0-9]+$")
    ) |>
    mutate(
      orig_bill = bill_number
    )

  # Make links absolute
  version_df$link <- paste0("https://www.legis.iowa.gov", version_df$link)

  return(version_df)
}

# Example usage:
# bill_versions <- get_bill_versions("HF1038")

version_list <- map(
  files$file_num |> str_remove(" "),
  get_bill_versions
)

versions <- bind_rows(version_list)


scrape_lobbyist_declarations <- function(bill_number, ga = 91) {
  print(bill_number)

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

# Example usage:
# result <- scrape_lobbyist_declarations("HF1038")

lobby <- map(
  c(files$file_num |> str_remove(" ")),
  scrape_lobbyist_declarations
)

declarations <- bind_rows(lobby) |>
  mutate(bill = str_remove(bill, " ")) |>
  left_join(
    versions |> select(-link), by = c("bill" = "text")
  )

write_rds(declarations, "data/legislation_lobby_declarations.rds")

