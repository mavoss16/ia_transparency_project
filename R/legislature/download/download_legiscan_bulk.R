# download_legiscan_bulk.R
#
# Bulk-download one General Assembly's LegiScan dataset (JSON and CSV zips
# from getDatasetRaw) into the session layout from session.R:
#   legiscan/ga{N}/json/{bill,vote,people}/
#   legiscan/ga{N}/csv/
#
# Used for a session's first load (a backfill, or a new GA once LegiScan has
# it); after that the daily incremental_update() keeps the JSON current.
# Two API calls for the dataset list plus two downloads, so it's cheap.
# Requires LEGISCAN_API_KEY. Replaces archive/01_download_legiscan_data.R,
# which was hardcoded to the 91st.
#
# Usage:
#   source("R/legislature/download/download_legiscan_bulk.R")
#   download_legiscan_bulk(90)

library(httr2)
library(purrr)
library(here)

source(here("R/legislature/session.R"))

#' Find the extracted folder that holds bill/, people/ and vote/ (JSON) or
#' bills.csv (CSV); LegiScan nests them under IA/{years}_{name}/
find_dataset_root <- function(dir, format) {
  dirs <- list.dirs(dir, recursive = TRUE)
  hit <- if (format == "JSON") {
    dirs[basename(dirs) == "bill" & dir.exists(file.path(dirname(dirs), "vote"))]
  } else {
    dirs[file.exists(file.path(dirs, "bills.csv"))]
  }
  if (length(hit) != 1) stop("Could not find the ", format, " dataset inside the zip.")
  if (format == "JSON") dirname(hit) else hit
}

#' Download one format of a dataset into a temp dir; returns the dataset root
fetch_dataset <- function(api_key, session_id, access_key, format) {
  tmp <- tempfile(paste0("legiscan_", tolower(format), "_"))
  dir.create(tmp)
  zip_path <- file.path(tmp, "dataset.zip")

  message("Downloading ", format, " dataset...")
  resp <- request("https://api.legiscan.com/") |>
    req_url_query(key = api_key, op = "getDatasetRaw", id = session_id,
                  access_key = access_key, format = format) |>
    req_retry(max_tries = 3) |>
    req_timeout(600) |>
    req_perform(path = zip_path)
  if (resp_content_type(resp) != "application/zip") {
    stop("getDatasetRaw did not return a zip (", resp_content_type(resp), ").")
  }

  unzip(zip_path, exdir = file.path(tmp, "x"))
  find_dataset_root(file.path(tmp, "x"), format)
}

#' Bulk-download a General Assembly's LegiScan data
#' @param ga General Assembly number
#' @param overwrite Replace an existing legiscan/ga{N}/json and csv
#' @return The session's ga_paths(), invisibly
download_legiscan_bulk <- function(ga, overwrite = FALSE) {
  ga <- as.integer(ga)
  if (ga_frozen(ga)) stop("The ", ga_label(ga), " is frozen; its raw data must not change.")

  paths <- ga_paths(ga)
  if (!overwrite && (dir.exists(paths$json) || dir.exists(paths$bulk_csv))) {
    stop(paths$legiscan, " already has raw data. Pass overwrite = TRUE to replace it.")
  }

  api_key <- Sys.getenv("LEGISCAN_API_KEY")
  if (nchar(api_key) == 0L) stop("LEGISCAN_API_KEY is not set.")

  session_id <- legiscan_session_id(ga)

  message("Fetching dataset list for the ", ga_label(ga), "...")
  datasets <- request("https://api.legiscan.com/") |>
    req_url_query(key = api_key, op = "getDatasetList", state = "IA") |>
    req_retry(max_tries = 3) |>
    req_perform() |>
    resp_body_json()
  if (!identical(datasets$status, "OK")) stop("getDatasetList returned status ", datasets$status)

  dataset <- keep(datasets$datasetlist, \(d) as.integer(d$session_id) == session_id)
  if (length(dataset) != 1) stop("No LegiScan dataset for session ", session_id, ".")
  dataset <- dataset[[1]]
  message("Dataset dated ", dataset$dataset_date, " (session ", session_id, ").")

  json_root <- fetch_dataset(api_key, session_id, dataset$access_key, "JSON")
  csv_root  <- fetch_dataset(api_key, session_id, dataset$access_key, "CSV")

  # Move into place only once both downloads succeeded
  dir.create(paths$json, recursive = TRUE, showWarnings = FALSE)
  for (folder in c("bill", "people", "vote")) {
    dest <- file.path(paths$json, folder)
    if (dir.exists(dest)) unlink(dest, recursive = TRUE)
    dir.create(dest)
    file.copy(list.files(file.path(json_root, folder), full.names = TRUE), dest)
  }
  if (dir.exists(paths$bulk_csv)) unlink(paths$bulk_csv, recursive = TRUE)
  dir.create(paths$bulk_csv, recursive = TRUE)
  file.copy(list.files(csv_root, full.names = TRUE), paths$bulk_csv)
  # LegiScan puts README/LICENSE beside the csv/ folder; keep them with the CSVs
  extras <- list.files(dirname(csv_root), pattern = "^(README|LICENSE)", full.names = TRUE)
  file.copy(extras, paths$bulk_csv)

  counts <- map_int(c("bill", "people", "vote"), \(f) length(list.files(file.path(paths$json, f))))
  message("Wrote ", paths$legiscan, ": ", counts[1], " bills, ", counts[2],
          " people, ", counts[3], " roll calls.")
  invisible(paths)
}
