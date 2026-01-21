
library(httr2)



api_key <- Sys.getenv("LEGISCAN_API_KEY")
base_url <- paste0("https://api.legiscan.com?key=", api_key)


dataset_list <- request(base_url) |>
  req_url_query(op = "getDatasetList", state = "IA", year = 2025) |>
  req_perform() |>
  resp_body_json()


access_key_ga91 <- "3cj4MUiz5pWNpoKzM9AZrE"

# 91st General Assembly (Iowa) Session ID: 2177
session_id <- 2177


# ga91 Data ---------------------------------------------------------------

# Helper function to flatten nested LegiScan directory structure
flatten_legiscan_dir <- function(base_dir, nested_path, is_csv = FALSE) {
  source_dir <- file.path(base_dir, nested_path)

  if (is_csv) {
    # For CSV: move all files from csv/ subfolder to base_dir
    csv_dir <- file.path(source_dir, "csv")
    files <- list.files(csv_dir, full.names = TRUE)
    file.copy(files, base_dir, overwrite = TRUE)
    unlink(file.path(base_dir, "IA"), recursive = TRUE)
  } else {
    # For JSON: move bill/, people/, vote/ folders to base_dir
    for (folder in c("bill", "people", "vote")) {
      src <- file.path(source_dir, folder)
      dest <- file.path(base_dir, folder)
      if (dir.exists(src)) {
        if (dir.exists(dest)) unlink(dest, recursive = TRUE)
        file.rename(src, dest)
      }
    }
    unlink(file.path(base_dir, "IA"), recursive = TRUE)
  }
}

# Download and extract JSON data
query <- request(base_url) |>
  req_url_query(op = "getDatasetRaw", id = session_id, access_key = access_key_ga91, format = "JSON")
download.file(query$url, "legiscan/files_ga91_json.zip", mode = "wb")
unzip("legiscan/files_ga91_json.zip", exdir = "legiscan/files_ga91_json", overwrite = TRUE)
file.remove("legiscan/files_ga91_json.zip")
flatten_legiscan_dir("legiscan/files_ga91_json", "IA/2025-2026_91st_General_Assembly", is_csv = FALSE)

# Download and extract CSV data
query <- request(base_url) |>
  req_url_query(op = "getDatasetRaw", id = session_id, access_key = access_key_ga91, format = "CSV")
download.file(query$url, "legiscan/files_ga91.zip", mode = "wb")
unzip("legiscan/files_ga91.zip", exdir = "legiscan/files_ga91", overwrite = TRUE)
file.remove("legiscan/files_ga91.zip")
flatten_legiscan_dir("legiscan/files_ga91", "IA/2025-2026_91st_General_Assembly", is_csv = TRUE)



master_list <- request(base_url) |>
  req_url_query(op = "getMasterList", id = session_id) |>
  req_perform() |>
  resp_body_json() |>
  pluck("masterlist") |>
  discard_at("session") |>
  map(.f = as.data.frame) |>
  bind_rows()