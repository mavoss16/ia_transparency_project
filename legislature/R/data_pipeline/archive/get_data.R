

library(readr)
library(dplyr)

library(httr2)
library(jsonlite)
library(purrr)


api_key <- Sys.getenv("LEGISCAN_API_KEY")
base_url <- paste0("https://api.legiscan.com?key=", api_key)



# Iowa Legislative Sessions -----------------------------------------------
request(base_url) |>
  req_url_query(op = "getSessionList", state = "IA") |>
  req_perform() |>
  resp_body_json()


# 91st General Assembly (Iowa) Session ID: 2177
session_id <- 2177

master_list <- request(base_url) |>
  req_url_query(op = "getMasterList", id = session_id) |>
  req_perform() |>
  resp_body_json() |>
  pluck("masterlist") |>
  discard_at("session") |>
  map(.f = as.data.frame) |>
  bind_rows()


sample_bills <- master_list |>
  sample_n(50) |>
  pull(bill_id)

bill_details <- map(
  sample_bills,
  function(bill_id){
    request(base_url) |>
      req_url_query(op = "getBill", id = bill_id) |>
      req_perform() |>
      resp_body_json()
  }
)


dataset_list <- request(base_url) |>
  req_url_query(op = "getDatasetList", state = "IA", year = 2025) |>
  req_perform() |>
  resp_body_json()

access_key_2025 <- "3IHnboW19fYEemzI5MoS0s"

query <- request(base_url) |>
  req_url_query(op = "getDatasetRaw", id = current_session, access_key = access_key_2025, format = "JSON")

download.file(query$url, "legiscan/files_2025_json.zip", mode = "wb")


bills <- read_csv("legiscan/files_2025/bills.csv")
hf1038 <- fromJSON("legiscan/files_2025_json/bill/HF1038.json")

listviewer::jsonedit(hf1038)


votes <- read_csv("legiscan/files_2025/votes.csv")
