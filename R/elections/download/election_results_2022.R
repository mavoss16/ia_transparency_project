# Download precinct-level election results for all 99 Iowa counties from the
# Iowa Secretary of State website.
#
# Source pages follow the pattern:
#   https://sos.iowa.gov/precinct-results-county-{year}-{type}-{n}
# File URLs follow:
#   https://sos.iowa.gov/elections/pdf/precinctresults/{year}{type}/{county}.xls
#
# Usage:
#   source("R/elections/03_download_precinct_elections_sos.R")
#   download_sos_election("2022", "general")

library(httr2)
library(rvest)
library(stringr)
library(here)

# ---- Helper ----
# NOTE: sos.iowa.gov requires a short User-Agent string; full Chrome UA strings
# trigger Akamai bot protection and return 403.
sos_request <- function(url) {
  request(url) |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      `Referer`    = "https://sos.iowa.gov/"
    )
}

# ---- Main function ----
download_sos_election <- function(year, type = "general", page_suffix = "0") {
  slug       <- paste0(year, type)
  page_url   <- paste0(
    "https://sos.iowa.gov/precinct-results-county-", year, "-", type, "-", page_suffix
  )
  output_dir <- here("data/elections/raw", paste0("precinct_elections_", year))

  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  # ---- Scrape county links ----
  message("Fetching index page: ", page_url)
  html <- sos_request(page_url) |>
    req_perform() |>
    resp_body_string() |>
    read_html()

  links <- html_elements(html, "a[href$='.xls'], a[href$='.xlsx']")
  hrefs <- html_attr(links, "href")
  texts <- html_text2(links)

  # Filter to the target year/type only (page contains stray links to other elections)
  keep  <- str_detect(hrefs, fixed(slug, ignore_case = TRUE))
  hrefs <- hrefs[keep]
  texts <- str_trim(texts[keep])

  message("Found ", length(hrefs), " county files for ", year, " ", type)

  if (length(hrefs) == 0) stop("No links found — check the page URL or slug.")

  # Derive output filename from link text (county name), falling back to URL basename
  county_names <- ifelse(
    nzchar(texts),
    str_to_lower(texts),
    str_to_lower(tools::file_path_sans_ext(basename(hrefs)))
  )
  ext       <- tools::file_ext(hrefs)        # "xls" or "xlsx"
  dest_files <- file.path(output_dir, paste0(county_names, "_", year, ".", ext))

  # ---- Download ----
  mapply(function(href, dest) {
    if (file.exists(dest)) {
      message("  Skipping ", basename(dest), " (already exists)")
      return(invisible(NULL))
    }

    message("  Downloading ", basename(dest), " ...")
    result <- tryCatch(
      sos_request(href) |>
        req_error(is_error = \(r) FALSE) |>
        req_perform(),
      error = function(e) {
        message("    ERROR: ", conditionMessage(e))
        NULL
      }
    )

    if (is.null(result)) return(invisible(NULL))

    if (resp_status(result) != 200) {
      message("    HTTP ", resp_status(result), " — ", href)
      return(invisible(NULL))
    }

    writeBin(resp_body_raw(result), dest)
    message("    Saved: ", basename(dest))
    invisible(dest)
  }, hrefs, dest_files, SIMPLIFY = FALSE)

  message("\nDone! ", length(hrefs), " files saved to: ", output_dir)
  invisible(dest_files)
}

# ---- Run ----
download_sos_election("2022", "general")
