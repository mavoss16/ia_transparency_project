
library(dplyr)
library(janitor)
library(stringr)
library(lubridate)
library(purrr)

library(rvest)

fill_empty <- function(x, default = NA) {
  if (is.null(x) || length(x) == 0) default else x
}

#' Generate a URL-friendly filename for a legislator
#' @param people_id Numeric ID for the legislator
#' @param people_df Optional dataframe of people (to avoid re-reading CSV)
#' @return Character string like "rep-dave-jacoby-6970" or "sen-jason-schultz-6973"
get_legislator_filename <- function(people_id, people_df = NULL) {
  if (is.null(people_df)) {
    people_df <- readr::read_csv(here::here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)
  }

  person <- people_df |> filter(people_id == !!people_id)

  if (nrow(person) == 0) {
    return(as.character(people_id))
  }

  # Chamber prefix
  prefix <- if (person$role[1] == "Sen") "sen" else "rep"

  first_name <- tolower(person$first_name[1])
  last_name <- tolower(person$last_name[1])

  # Remove special characters and replace spaces with hyphens
  first_name <- str_replace_all(first_name, "[^a-z0-9]", "-")
  last_name <- str_replace_all(last_name, "[^a-z0-9]", "-")

  # Remove multiple consecutive hyphens and trim
  first_name <- str_replace_all(first_name, "-+", "-") |> str_trim()
  last_name <- str_replace_all(last_name, "-+", "-") |> str_trim()

  paste0(prefix, "-", first_name, "-", last_name, "-", people_id)
}

#' Generate a URL-friendly filename for a committee
#' @param people_id Numeric ID for the committee (from people.csv)
#' @param people_df Optional dataframe of people (to avoid re-reading CSV)
#' @return Character string like "house-commerce-7061" or "senate-judiciary-7121"
get_committee_filename <- function(people_id, people_df = NULL) {
  if (is.null(people_df)) {
    people_df <- readr::read_csv(here::here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)
  }

  person <- people_df |> filter(people_id == !!people_id)

  if (nrow(person) == 0) {
    return(as.character(people_id))
  }

  # Chamber prefix
  chamber <- if (person$role[1] == "Sen") "senate" else "house"

  # Committee name from the name field
  committee_name <- tolower(person$name[1])
  committee_name <- str_replace_all(committee_name, "[^a-z0-9]", "-")
  committee_name <- str_replace_all(committee_name, "-+", "-")
  committee_name <- str_replace(committee_name, "^-", "")
  committee_name <- str_replace(committee_name, "-$", "")

  paste0(chamber, "-", committee_name, "-", people_id)
}

items_to_df <- function(list){
  if(length(list) >= 1){
    map(list, function(item){
      item <- map(item, fill_empty)
      as.data.frame(item)
    }) |>
      bind_rows()
  } else{
    NULL
  }
}

scrape_lobbyist_declarations <- function(bill_number, ga = 91, max_retries = 3, retry_delay = 2) {

  # Construct URL dynamically
  url <- paste0("https://www.legis.iowa.gov/lobbyist/reports/declarations?ga=", ga, "&ba=", bill_number)

  # Retry loop for network requests
  page <- NULL
  for (attempt in seq_len(max_retries)) {
    page <- tryCatch(
      read_html(url),
      error = function(e) {
        if (attempt < max_retries) {
          message(paste0("Lobbyist scrape attempt ", attempt, "/", max_retries,
                         " failed for ", bill_number, ": ", e$message, ". Retrying..."))
          Sys.sleep(retry_delay)
        }
        NULL
      }
    )
    if (!is.null(page)) break
  }

  if (is.null(page)) {
    stop("Failed to fetch lobbyist declarations after ", max_retries, " attempts.")
  }

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
