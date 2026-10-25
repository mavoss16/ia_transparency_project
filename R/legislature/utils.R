
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

#' Identify mid-session replacements among legislators sharing a district.
#'
#' When a legislator resigns or dies, LegiScan adds their replacement to the
#' same role + district, creating a duplicate. The one who stopped voting first
#' is the "former" member. Used by the index pages (to drop former members from
#' active counts) and the legislator template (to show a succession notice).
#'
#' @param people    data frame with people_id, role, district
#' @param votes     data frame with people_id, roll_call_id
#' @param rollcalls data frame with roll_call_id, date
#' @return tibble with one row per person in a duplicated role+district:
#'   people_id, role, district, is_former (logical), counterpart_id
#'   (the other member of the pair, or NA for groups other than 2).
classify_district_turnover <- function(people, votes, rollcalls) {
  last_vote_dates <- votes |>
    left_join(rollcalls |> select(roll_call_id, date), by = "roll_call_id") |>
    group_by(people_id) |>
    summarize(last_vote_date = max(date, na.rm = TRUE), .groups = "drop")

  dup_districts <- people |>
    count(role, district) |>
    filter(n > 1)

  people |>
    semi_join(dup_districts, by = c("role", "district")) |>
    left_join(last_vote_dates, by = "people_id") |>
    group_by(role, district) |>
    mutate(
      is_former = case_when(
        # Both have votes: the one who voted earlier is former
        all(!is.na(last_vote_date)) ~ last_vote_date == min(last_vote_date),
        # One has votes, one doesn't: the voter left and was replaced
        !is.na(last_vote_date) ~ TRUE,
        # No votes yet: this is the new replacement
        is.na(last_vote_date) ~ FALSE
      ),
      counterpart_id = if (dplyr::n() == 2) rev(people_id) else NA_integer_
    ) |>
    ungroup() |>
    select(people_id, role, district, is_former, counterpart_id)
}

# Bill stages in order of progression (higher = further along). This is the
# status scale used by the funnel, the status pills, and bill groups.
STATUS_LEVELS <- c(
  "Introduced" = 1,
  "Passed Subcommittee" = 2,
  "Passed Committee" = 3,
  "Passed One Chamber" = 4,
  "Passed Both Chambers" = 5,
  "Signed by Governor" = 6
)

#' Classify individual history actions into milestones.
#'
#' The single source of the action-text rules: bill status (furthest stage
#' reached) and the weekly activity summary both build on it.
#'
#' Notes on the vocabulary:
#' - Resolutions don't "pass"; they are adopted ("Resolution adopted."), which
#'   counts as floor passage in the chamber that adopted it.
#' - An item veto ("Item vetoed, signed by Governor.") counts as signed: the
#'   bill became law. Item-vetoed bills carry no separate "Signed by
#'   Governor." row, so without this they would stop at "Passed Both
#'   Chambers". The action text itself still says item-vetoed wherever the
#'   raw history is shown.
#' - Full vetoes get their own milestone but are not a stage on STATUS_LEVELS:
#'   a vetoed bill's status stays "Passed Both Chambers".
#' - A committee that amends a bill reports "Committee report, recommending
#'   amendment and passage." — that is committee passage too (390 actions in
#'   the 91st GA, uncounted before 2026-10-24).
#' - House simple and concurrent resolutions are introduced with "Resolution
#'   filed, laid over under Rule 25." rather than "Introduced"; both count as
#'   introduction. (Introduction is the floor of the status scale, so this
#'   affects only per-action counts, never a bill's status.)
#'
#' @param action Character vector of action text
#' @return Character vector: "signed", "vetoed", "floor", "committee",
#'   "subcommittee", "introduced", or NA for procedural actions
classify_action <- function(action) {
  case_when(
    str_detect(action, "Signed by Governor|^Item vetoed, signed by Governor") ~ "signed",
    str_detect(action, "^Vetoed by Governor")                               ~ "vetoed",
    str_detect(action, "^Passed (House|Senate)|^Resolution adopted")        ~ "floor",
    str_detect(action, "Committee report.*(recommending (amendment and )?passage|approving bill)") ~ "committee",
    str_detect(action, "Subcommittee recommends.*(passage|amendment and passage)") ~ "subcommittee",
    str_detect(action, "^Introduced|^Resolution filed")                     ~ "introduced",
    .default = NA_character_
  )
}

#' Chamber in which a floor action happened.
#'
#' "Passed House" / "Passed Senate" name the chamber in the text; for
#' "Resolution adopted" the chamber comes from the history row itself.
#'
#' @param action  Character vector of action text
#' @param chamber Character vector of the history row's chamber, in either
#'   LegiScan JSON form ("H" / "S") or derived CSV form ("House" / "Senate")
#' @return "House", "Senate", or NA (also NA for non-floor actions)
floor_chamber <- function(action, chamber) {
  row_chamber <- case_when(
    chamber %in% c("H", "House")  ~ "House",
    chamber %in% c("S", "Senate") ~ "Senate",
    .default = NA_character_
  )
  case_when(
    str_detect(action, "^Passed House")       ~ "House",
    str_detect(action, "^Passed Senate")      ~ "Senate",
    str_detect(action, "^Resolution adopted") ~ row_chamber,
    .default = NA_character_
  )
}

#' Bill a committee renumbering created.
#'
#' "Committee report approving bill, renumbered as HF 123." — a study bill
#' (or a member bill replaced by a committee bill) continues under a new
#' number. Used as a grouping edge in 03 and to flag committee-originated
#' bills in 06.
#'
#' @param action Character vector of action text
#' @return Bill number ("HF123") or NA. A handful of 91st GA actions read
#'   "renumbered as ." with the number missing; those return NA.
parse_renumbered_target <- function(action) {
  str_extract(action, "renumbered as ([A-Z]+ ?[0-9]+)", group = 1) |>
    str_remove_all(" ")
}

#' Determine bill status (furthest stage reached) from its history.
#'
#' @param history_df Data frame with 'action' and 'chamber' columns
#' @return Character string, one of names(STATUS_LEVELS)
get_bill_status_from_history <- function(history_df) {
  if (is.null(history_df) || nrow(history_df) == 0) {
    return("Introduced")
  }

  milestones <- classify_action(history_df$action)
  floor_chambers <- floor_chamber(history_df$action, history_df$chamber) |>
    na.omit() |>
    unique()

  case_when(
    "signed" %in% milestones          ~ "Signed by Governor",
    length(floor_chambers) == 2       ~ "Passed Both Chambers",
    length(floor_chambers) == 1       ~ "Passed One Chamber",
    "committee" %in% milestones       ~ "Passed Committee",
    "subcommittee" %in% milestones    ~ "Passed Subcommittee",
    .default = "Introduced"
  )
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
