#' Download LegiScan Data for Iowa 91st General Assembly
#'
#' Downloads both CSV and JSON datasets from the LegiScan API,
#' extracts them, and flattens the nested directory structure.
#'
#' Requires LEGISCAN_API_KEY environment variable to be set.
#'
#' Usage:
#'   source("R/data_pipeline/01_download_legiscan_data.R")
#'   download_legiscan_data()

library(httr2)
library(purrr)
library(dplyr)
library(here)

#' Flatten nested LegiScan directory structure after extraction
#' @param base_dir Base directory where files were extracted
#' @param nested_path Path within the nested structure (e.g., "IA/2025-2026_91st_General_Assembly")
#' @param is_csv If TRUE, flatten CSV structure; if FALSE, flatten JSON structure
flatten_legiscan_dir <- function(base_dir, nested_path, is_csv = FALSE) {
  source_dir <- file.path(base_dir, nested_path)

  if (is_csv) {
    csv_dir <- file.path(source_dir, "csv")
    files <- list.files(csv_dir, full.names = TRUE)
    file.copy(files, base_dir, overwrite = TRUE)
    unlink(file.path(base_dir, "IA"), recursive = TRUE)
  } else {
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

#' Download and extract LegiScan data
#'
#' @param session_id LegiScan session ID (default: 2177 for 91st GA)
#' @param state State abbreviation (default: "IA")
#' @param year Session year (default: 2025)
#' @param nested_path Nested directory path within the zip (default: "IA/2025-2026_91st_General_Assembly")
#' @return Invisible NULL on success
download_legiscan_data <- function(
    session_id = 2177,
    state = "IA",
    year = 2025,
    nested_path = "IA/2025-2026_91st_General_Assembly"
) {
  api_key <- Sys.getenv("LEGISCAN_API_KEY")
  if (api_key == "") {
    stop("LEGISCAN_API_KEY environment variable is not set.")
  }

  base_url <- paste0("https://api.legiscan.com?key=", api_key)

  # Get dataset access key
  message("Fetching dataset list...")
  dataset_list <- request(base_url) |>
    req_url_query(op = "getDatasetList", state = state, year = year) |>
    req_perform() |>
    resp_body_json()

  access_key <- dataset_list$datasetlist[[1]]$access_key

  # Download and extract JSON data
  message("Downloading JSON dataset...")
  json_dir <- here("legiscan/files_ga91_json")
  json_zip <- here("legiscan/files_ga91_json.zip")

  query <- request(base_url) |>
    req_url_query(op = "getDatasetRaw", id = session_id, access_key = access_key, format = "JSON")
  download.file(query$url, json_zip, mode = "wb")
  unzip(json_zip, exdir = json_dir, overwrite = TRUE)
  file.remove(json_zip)
  flatten_legiscan_dir(json_dir, nested_path, is_csv = FALSE)
  message("JSON data extracted to ", json_dir)

  # Download and extract CSV data
  message("Downloading CSV dataset...")
  csv_dir <- here("legiscan/files_ga91")
  csv_zip <- here("legiscan/files_ga91.zip")

  query <- request(base_url) |>
    req_url_query(op = "getDatasetRaw", id = session_id, access_key = access_key, format = "CSV")
  download.file(query$url, csv_zip, mode = "wb")
  unzip(csv_zip, exdir = csv_dir, overwrite = TRUE)
  file.remove(csv_zip)
  flatten_legiscan_dir(csv_dir, nested_path, is_csv = TRUE)
  message("CSV data extracted to ", csv_dir)

  message("LegiScan data download complete.")
  invisible(NULL)
}
