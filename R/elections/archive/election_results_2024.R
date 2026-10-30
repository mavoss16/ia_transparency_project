# Download precinct-level election results for all 99 Iowa counties (2024 General Election).
#
# Source: Iowa Secretary of State Election Night Reporting system
# https://electionresults.iowa.gov/IA/122322/web.345435/#/reporting
#
# Process:
#   1. Fetch current_ver.txt to get the statewide data version
#   2. Parse electionsettings.json to get all county election IDs and version IDs
#   3. Download each county's detailxls.zip and extract the XLS
#   4. Save as {county}_2024.xlsx to data/elections/raw/precinct_elections_2024/

library(httr2)
library(stringr)
library(purrr)
library(dplyr)
library(here)

# ---- Configuration ----
STATEWIDE_ELECTION_ID <- "122322"  # 2024 General Election
BASE_URL               <- "https://electionresults.iowa.gov"
OUTPUT_DIR             <- here("data/elections/raw/precinct_elections_2024")
YEAR                   <- "2024"

if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# ---- Helper ----
iowa_request <- function(url) {
  request(url) |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      `Referer`    = "https://electionresults.iowa.gov/"
    )
}

# ---- Step 1: Get statewide current version ----
ver_url     <- paste0(BASE_URL, "/IA/", STATEWIDE_ELECTION_ID, "/current_ver.txt")
current_ver <- iowa_request(ver_url) |>
  req_perform() |>
  resp_body_string() |>
  str_trim()

message("Statewide data version: ", current_ver)

# ---- Step 2: Parse county info from electionsettings.json ----
# Each county is encoded as "CountyName|ElectionID|VersionID|Timestamp|16"
settings_url <- paste0(
  BASE_URL, "/IA/", STATEWIDE_ELECTION_ID, "/", current_ver,
  "/json/en/electionsettings.json"
)

settings_raw <- iowa_request(settings_url) |>
  req_perform() |>
  resp_body_string()

county_strings <- str_extract_all(
  settings_raw,
  "[A-Za-z_']+\\|\\d{6}\\|\\d{6}\\|[^\\\\\"<>]+"
)[[1]]

counties <- tibble(raw = county_strings) |>
  separate(raw, into = c("county_url_name", "election_id", "version_id", "rest"),
           sep = "\\|", extra = "merge", fill = "right") |>
  select(county_url_name, election_id, version_id) |>
  mutate(
    # Filename follows existing convention: lowercase, underscores preserved
    county_file_name = str_to_lower(county_url_name),
    download_url = paste0(
      BASE_URL, "/IA/",
      URLencode(county_url_name, reserved = FALSE), "/",
      election_id, "/",
      version_id, "/reports/detailxls.zip"
    ),
    dest_zip  = file.path(OUTPUT_DIR, paste0(county_file_name, "_", YEAR, ".zip")),
    dest_xlsx = file.path(OUTPUT_DIR, paste0(county_file_name, "_", YEAR, ".xlsx"))
  )

message("Found ", nrow(counties), " counties")

# ---- Step 3: Download and extract ----
download_county <- function(county_url_name, download_url, dest_zip, dest_xlsx, ...) {
  if (file.exists(dest_xlsx)) {
    message("  Skipping ", county_url_name, " (already exists)")
    return(invisible(NULL))
  }

  message("  Downloading ", county_url_name, " ...")

  result <- tryCatch({
    iowa_request(download_url) |>
      req_error(is_error = \(r) FALSE) |>   # handle manually
      req_perform()
  }, error = function(e) {
    message("    ERROR fetching: ", conditionMessage(e))
    return(NULL)
  })

  if (is.null(result)) return(invisible(NULL))

  if (resp_status(result) != 200) {
    message("    HTTP ", resp_status(result), " for ", download_url)
    return(invisible(NULL))
  }

  writeBin(resp_body_raw(result), dest_zip)

  # Extract the XLS from the ZIP
  extracted <- tryCatch(
    unzip(dest_zip, exdir = dirname(dest_zip)),
    error = function(e) {
      message("    ERROR unzipping: ", conditionMessage(e))
      character(0)
    }
  )

  # Rename the extracted file to our standard name
  xls_files <- extracted[str_detect(extracted, regex("\\.xlsx?$", ignore_case = TRUE))]

  if (length(xls_files) == 0) {
    message("    WARNING: no XLS file found in ZIP for ", county_url_name)
    message("    ZIP contents: ", paste(extracted, collapse = ", "))
    unlink(dest_zip)
    return(invisible(NULL))
  }

  # Use first XLS file found (there should only be one)
  file.rename(xls_files[[1]], dest_xlsx)

  # Clean up: remove the zip and any leftover extracted files
  unlink(dest_zip)
  leftover <- setdiff(extracted, xls_files[[1]])
  if (length(leftover) > 0) unlink(leftover)

  message("    Saved: ", basename(dest_xlsx))
  invisible(dest_xlsx)
}

pwalk(counties, download_county)

message("\nDone! Files saved to: ", OUTPUT_DIR)
