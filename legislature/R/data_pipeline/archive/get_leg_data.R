

library(readxl)
library(readr)

library(dplyr)
library(stringr)

library(httr2)
library(jsonlite)
library(purrr)


files <- read_excel("data/legislation_list.xlsx")

api_key <- Sys.getenv("LEGISCAN_API_KEY")
base_url <- str_glue("https://api.legiscan.com/?key={api_key}")


# request(base_url) |>
#   req_url_query(state = "IA", op = "getSessionList") |>
#   req_perform() |>
#   resp_body_json()

# 91st General Assembly (Iowa) Session ID: 2177
session_id <- 2177



# Get Bill IDs ------------------------------------------------------------

master_list_json <- request(base_url) |>
  req_url_query(op = "getMasterList", id = session_id) |>
  req_perform() |>
  resp_body_json()

master_list_df <- master_list_json |>
  pluck("masterlist") |>
  discard_at("session") |>
  map(.f = as.data.frame) |>
  bind_rows()


file_list <- master_list_df |>
  filter(number %in% files$file_num)


# Process Bill Details ----------------------------------------------------

process_bill_details <- function(.x){
  tibble(
    bill_id = .x$bill_id,
    change_hash = .x$change_hash,
    session_id = .x$session_id,
    session = .x$session |> as.data.frame() |> list(),
    url = .x$url,
    state_link = .x$state_link,
    completed = .x$completed,
    status = .x$status,
    status_date = .x$status_date,
    progress = .x$progress |> list(),
    state = .x$state,
    state_id = .x$state_id,
    bill_number = .x$bill_number,
    bill_type = .x$bill_type,
    bill_type_id = .x$bill_type_id,
    body = .x$body,
    body_id = .x$body_id,
    current_body = .x$current_body,
    current_body_id = .x$current_body_id,
    title = .x$title,
    description = .x$description,
    pending_committee_id = .x$pending_committee_id,
    committee = .x$committee |> list(),
    referrals = .x$referrals |> list(),
    history = .x$history |> list(),
    sponsors = .x$sponsors |> list(),
    sasts = .x$sasts |> list(),
    subjects = .x$subjects |> list(),
    texts = .x$texts |> list(),
    votes = .x$votes |> list(),
    amendments = .x$amendment |> list(),
    supplements = .x$supplements |> list(),
    calendar = .x$calendar |> list()
  )
}

detail_list <- map(
  file_list$bill_id,
  .f = function(.x){
    request(base_url) |>
      req_url_query(op = "getBill", id = .x) |>
      req_perform() |>
      resp_body_json() |>
      toJSON() |>
      fromJSON() |>
      pluck("bill")
  }
)

details <- map(
  detail_list,
  .f = process_bill_details
) |>
  bind_rows()


