
library(dplyr)
library(janitor)
library(stringr)
library(lubridate)
library(purrr)

library(rvest)

#' Simplify vote descriptions into short category labels
#' @param desc Character vector of vote descriptions
#' @return Character vector of simplified labels
simplify_vote_desc <- function(desc) {
  case_when(
    str_detect(desc, "bill pass") ~ "Floor Passage",
    str_detect(desc, "rules be suspended") ~ "Rule Suspension",
    str_detect(desc, "resolution be adopted|Resolution.*be adopted") ~ "Resolution",
    str_detect(desc, "motion") ~ "Motion",
    str_detect(desc, "amendment") ~ "Amendment",
    TRUE ~ desc
  )
}

fill_empty <- function(x, default = NA) {
  if (is.null(x) || length(x) == 0) default else x
}

#' Format a bill number as an HTML link with spaced display name
#' @param bill_number Bill number string (e.g., "HF1", "SF23")
#' @param path_prefix Relative path prefix to the legislation directory (e.g., "../legislation/")
#' @return HTML anchor tag string
format_bill_link <- function(bill_number, path_prefix = "") {
  display <- str_replace(bill_number, "^([A-Z]+)(\\d+)$", "\\1 \\2")
  str_glue("<a href='{path_prefix}{bill_number}.html'>{display}</a>")
}

#' Generate a URL-friendly filename for a legislator
#' @param people_id Numeric ID for the legislator
#' @param people_df Optional dataframe of people (to avoid re-reading CSV)
#' @return Character string like "rep-dave-jacoby-6970" or "sen-jason-schultz-6973"
get_legislator_filename <- function(people_id, people_df = NULL) {
  if (is.null(people_df)) {
    people_df <- readr::read_csv(here::here("legiscan/files_ga91_derived/people.csv"), show_col_types = FALSE)
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
    people_df <- readr::read_csv(here::here("legiscan/files_ga91_derived/people.csv"), show_col_types = FALSE)
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

parse_district_number <- function(district_str) {
  as.numeric(stringr::str_extract(district_str, "\\d+$"))
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

#' Generate an HTML progress bar showing a bill's position in the legislative process
#' @param status Character string matching one of the defined status levels, e.g. "Passed Committee"
#' @return Character string of raw HTML (include via cat() with output: asis)
render_bill_progress_bar <- function(status) {
  steps <- c(
    "Introduced",
    "Passed Subcommittee",
    "Passed Committee",
    "Passed One Chamber",
    "Passed Both Chambers",
    "Signed by Governor"
  )

  status_levels <- c(
    "Introduced"          = 1,
    "Passed Subcommittee" = 2,
    "Passed Committee"    = 3,
    "Passed One Chamber"  = 4,
    "Passed Both Chambers"= 5,
    "Signed by Governor"  = 6
  )

  current_level <- status_levels[status]
  if (is.na(current_level)) current_level <- 1L

  n <- length(steps)
  parts <- character(0)

  for (i in seq_along(steps)) {
    is_done <- i <= current_level
    step_class <- if (is_done) "bpb-step done" else "bpb-step"
    node_content <- if (is_done) "&#10003;" else as.character(i)

    parts <- c(parts, sprintf(
      '<div class="%s"><div class="bpb-node">%s</div><div class="bpb-label">%s</div></div>',
      step_class, node_content, steps[i]
    ))

    if (i < n) {
      conn_class <- if (i < current_level) "bpb-connector done" else "bpb-connector"
      parts <- c(parts, sprintf('<div class="%s"></div>', conn_class))
    }
  }

  css <- paste0(
    '<style>',
    '.bpb{display:flex;align-items:flex-start;margin:1rem 0 1.5rem;}',
    '.bpb-step{display:flex;flex-direction:column;align-items:center;flex:0 0 90px;}',
    '.bpb-node{width:28px;height:28px;border-radius:50%;display:flex;align-items:center;',
    'justify-content:center;font-size:12px;font-weight:700;background:#e2e8f0;color:#94a3b8;}',
    '.bpb-step.done .bpb-node{background:#1a56db;color:#fff;}',
    '.bpb-label{font-size:10px;text-align:center;margin-top:5px;color:#94a3b8;',
    'line-height:1.3;max-width:80px;}',
    '.bpb-step.done .bpb-label{color:#1a56db;font-weight:600;}',
    '.bpb-connector{flex:1;height:2px;background:#e2e8f0;margin-top:13px;align-self:flex-start;}',
    '.bpb-connector.done{background:#1a56db;}',
    '</style>'
  )

  paste0(css, '<div class="bpb">', paste(parts, collapse = ""), '</div>')
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
    # Filter out "no declarations" placeholder rows
    filter(!str_detect(bill, "(?i)no declarations")) |>
    mutate(
      date = mdy_hm(date)
    )

  if (nrow(df) == 0) return(df)

  # Deduplicate and select relevant columns
  clean_df <- df %>%
    distinct(bill, declaration, client, date) |>
    slice_max(date, by = c(client)) |>
    rename(most_recent_declaration = declaration)

  return(clean_df)
}
