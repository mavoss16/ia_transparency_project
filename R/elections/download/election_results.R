# election_results.R
# Download precinct-level primary and general results for every Iowa election
# with spreadsheet results (2006–2026) from the Iowa Secretary of State.
#
# Two sources, listed per election in RESULT_SOURCES:
#   sos_county    — per-county files linked from an SOS index page
#                   (https://sos.iowa.gov/precinct-results-county-{year}-{type})
#   sos_statewide — one statewide file (2006, 2008, 2010 and 2014 generals)
#   enr           — Election Night Reporting (electionresults.iowa.gov), 2024 on;
#                   the election ID is in the SOS results page's
#                   "Precinct Results by County - Excel Format" link
#
# Output: data/elections/raw/precinct_results/{year}_{type}/{county}.{ext}
#   ext is the real format, read from the file's first bytes:
#     xls  — legacy BIFF workbook (2010, 2012)
#     xlsx — Office Open XML (2014, 2016, 2020 general, statewide files)
#     xml  — SpreadsheetML, served as .xls/.xlsx but not readable by readxl
#            (2018–2022 SOS, ENR 2024), or ENR's detail.xml report (2026
#            primary, which has no Excel report)
#     pdf  — a county SOS published only as PDF (Scott, 2020 general)
#   A response that is none of these (e.g. the HTML page SOS returns with
#   status 200 for a missing file) is reported and not saved.
#
# Usage:
#   source("R/elections/download/election_results.R")
#   download_all_results()                  # everything missing
#   download_results(2026, "general")       # one election (add it to RESULT_SOURCES first)
#   results_inventory()                     # files per election, by format

library(httr2)
library(rvest)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(here)

RESULTS_DIR <- here("data/elections/raw/precinct_results")

SOS_PRECINCT_URL <- "https://sos.iowa.gov/elections/pdf/precinctresults"

# location: index page slug (sos_county), file URL (sos_statewide), or election ID (enr)
RESULT_SOURCES <- tribble(
  ~year, ~type,     ~source,         ~location,
  2006,  "general", "sos_statewide", "https://sos.iowa.gov/elections/pdf/results/2006genstatewidepct.xlsx",
  2008,  "general", "sos_statewide", paste0(SOS_PRECINCT_URL, "/2008general/statewidegenpct.xlsx"),
  2010,  "primary", "sos_county",    "precinct-results-county-2010-primary",
  2010,  "general", "sos_statewide", paste0(SOS_PRECINCT_URL, "/2010general/statewidepct.xlsx"),
  2012,  "primary", "sos_county",    "precinct-results-county-2012-primary",
  2012,  "general", "sos_county",    "precinct-results-county-2012-general",
  2014,  "primary", "sos_county",    "precinct-results-county-2014-primary",
  2014,  "general", "sos_statewide", paste0(SOS_PRECINCT_URL, "/2014general/statewide.xlsx"),
  2016,  "primary", "sos_county",    "precinct-results-county-2016-primary",
  2016,  "general", "sos_county",    "precinct-results-county-2016-general",
  2018,  "primary", "sos_county",    "precinct-results-county-2018-primary",
  2018,  "general", "sos_county",    "precinct-results-county-2018-general",
  2020,  "primary", "sos_county",    "precinct-results-county-2020-primary",
  2020,  "general", "sos_county",    "precinct-results-county-2020-general",
  2022,  "primary", "sos_county",    "precinct-results-county-2022-primary",
  2022,  "general", "sos_county",    "precinct-results-county-2022-general-0",
  2024,  "primary", "enr",           "121508",
  2024,  "general", "enr",           "122322",
  2026,  "primary", "enr",           "126082"
)

# ---- Requests ----

# sos.iowa.gov runs Akamai bot detection: this short User-Agent passes, a full
# Chrome string is blocked (403).
sos_request <- function(url) {
  request(url) |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      `Referer`    = "https://sos.iowa.gov/"
    ) |>
    req_throttle(rate = 2) |>
    req_retry(max_tries = 3)
}

# electionresults.iowa.gov (CloudFront) needs the Referer (503 without it) and
# blocks curl's default User-Agent; the full Chrome string is fine here.
enr_request <- function(url) {
  request(url) |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      `Referer`    = "https://electionresults.iowa.gov/"
    ) |>
    req_throttle(rate = 2) |>
    req_retry(max_tries = 3)
}

# Perform a request; return the body as raw bytes, or NULL on any failure.
fetch_bytes <- function(req, quiet_404 = FALSE) {
  resp <- tryCatch(
    req |> req_error(is_error = \(r) FALSE) |> req_perform(),
    error = function(e) {
      message("    ERROR: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(resp)) return(NULL)
  if (resp_status(resp) != 200) {
    if (!(quiet_404 && resp_status(resp) == 404)) message("    HTTP ", resp_status(resp), " — ", resp$url)
    return(NULL)
  }
  resp_body_raw(resp)
}

# ---- Files ----

# File format from the first bytes: "xls", "xlsx", "xml" (SpreadsheetML), "pdf",
# or NA for anything else (HTML error pages included).
sniff_format <- function(bytes) {
  if (length(bytes) < 8) return(NA_character_)
  if (identical(bytes[1:4], as.raw(c(0xD0, 0xCF, 0x11, 0xE0)))) return("xls")
  if (identical(bytes[1:4], as.raw(c(0x50, 0x4B, 0x03, 0x04)))) return("xlsx")
  if (identical(bytes[1:5], charToRaw("%PDF-"))) return("pdf")
  head <- bytes[seq_len(min(500, length(bytes)))]
  head <- rawToChar(head[head != as.raw(0)])
  # SpreadsheetML, or ENR's detail.xml report (<ElectionResult>)
  if (str_detect(head, fixed("<?xml")) && str_detect(head, "Excel\\.Sheet|office:spreadsheet|<ElectionResult>")) {
    return("xml")
  }
  NA_character_
}

results_dir <- function(year, type) file.path(RESULTS_DIR, paste0(year, "_", type))

# "Black  Hawk" / "black%20hawk" / "Black_Hawk" → "black_hawk"; O'Brien keeps its apostrophe.
county_slug <- function(x) {
  x |>
    URLdecode() |>
    str_replace_all("_", " ") |>
    str_squish() |>
    str_to_lower() |>
    str_replace_all(" ", "_")
}

existing_file <- function(dir, name) {
  hits <- list.files(dir, full.names = TRUE)
  hits[tools::file_path_sans_ext(basename(hits)) == name]
}

# Save bytes as {dir}/{name}.{format}; returns the path, or NULL if not a results file.
save_result <- function(bytes, dir, name, source_url) {
  fmt <- sniff_format(bytes)
  if (is.na(fmt)) {
    message("    Not a results file (", length(bytes), " bytes) — ", source_url)
    return(NULL)
  }
  path <- file.path(dir, paste0(name, ".", fmt))
  writeBin(bytes, path)
  path
}

# ---- SOS ----

# County file links on an SOS index page: one row per link, spreadsheets first.
# Some pages link the same county twice (adair.xls and adair.xlsx); a county
# may have only a PDF.
sos_county_links <- function(year, type, page_slug) {
  html <- sos_request(paste0("https://sos.iowa.gov/", page_slug)) |>
    req_perform() |>
    resp_body_string() |>
    read_html()

  # Pages also carry stray links to other elections (the 2022 general page
  # links 2020 and 2022 primary files), so keep only this election's folder.
  links <- html_elements(html, "a[href$='.xls'], a[href$='.xlsx'], a[href$='.pdf']")
  tibble(url = html_attr(links, "href")) |>
    filter(str_detect(url, regex(paste0("/precinctresults/", year, type, "/"), ignore_case = TRUE))) |>
    distinct() |>
    mutate(county = county_slug(tools::file_path_sans_ext(basename(url)))) |>
    arrange(str_ends(url, regex("\\.pdf", ignore_case = TRUE)))
}

download_sos_county <- function(year, type, page_slug) {
  dir   <- results_dir(year, type)
  links <- sos_county_links(year, type, page_slug)
  message("  ", n_distinct(links$county), " counties linked")

  links |>
    group_by(county) |>
    group_walk(\(urls, key) {
      if (length(existing_file(dir, key$county))) return(invisible())
      message("  ", key$county)
      # Try each linked URL until one is a real results file
      for (url in urls$url) {
        # Some hrefs contain literal spaces ("2022general/black  hawk.xls")
        bytes <- fetch_bytes(sos_request(str_replace_all(url, " ", "%20")))
        if (!is.null(bytes) && !is.null(save_result(bytes, dir, key$county, url))) break
      }
    })
}

download_sos_statewide <- function(year, type, url) {
  dir <- results_dir(year, type)
  if (length(existing_file(dir, "statewide"))) return(invisible())
  message("  statewide")
  bytes <- fetch_bytes(sos_request(url))
  if (!is.null(bytes)) save_result(bytes, dir, "statewide", url)
}

# ---- ENR ----

# County list for an ENR election: county_url_name, election_id, version_id.
# electionsettings.json embeds each county as "CountyName|ElectionID|VersionID|Timestamp|16".
enr_counties <- function(election_id) {
  base <- paste0("https://electionresults.iowa.gov/IA/", election_id)
  version <- enr_request(paste0(base, "/current_ver.txt")) |>
    req_perform() |>
    resp_body_string() |>
    str_trim()
  settings <- enr_request(paste0(base, "/", version, "/json/en/electionsettings.json")) |>
    req_perform() |>
    resp_body_string()

  str_match_all(settings, "([A-Za-z_']+)\\|(\\d{6})\\|(\\d{6})\\|")[[1]][, -1, drop = FALSE] |>
    as_tibble(.name_repair = \(x) c("county_url_name", "election_id", "version_id")) |>
    distinct()
}

download_enr <- function(year, type, election_id) {
  dir      <- results_dir(year, type)
  counties <- enr_counties(election_id)
  message("  ", nrow(counties), " counties listed")

  pwalk(counties, \(county_url_name, election_id, version_id) {
    name <- county_slug(county_url_name)
    if (length(existing_file(dir, name))) return(invisible())
    message("  ", name)

    reports <- paste0(
      "https://electionresults.iowa.gov/IA/", URLencode(county_url_name), "/",
      election_id, "/", version_id, "/reports/", c("detailxls.zip", "detailxml.zip")
    )
    # Some elections (2026 primary) publish only the XML report
    url   <- reports[1]
    bytes <- fetch_bytes(enr_request(url), quiet_404 = TRUE)
    if (is.null(bytes)) {
      url   <- reports[2]
      bytes <- fetch_bytes(enr_request(url))
    }
    if (is.null(bytes)) return(invisible())

    # Each zip holds one file: a SpreadsheetML workbook (despite its .xlsx
    # name) or detail.xml
    zip <- tempfile(fileext = ".zip")
    out <- tempfile()
    on.exit(unlink(c(zip, out), recursive = TRUE), add = TRUE)
    writeBin(bytes, zip)
    extracted <- tryCatch(unzip(zip, exdir = out), error = \(e) character(0))
    if (length(extracted) != 1) {
      message("    Expected one file in the zip, got ", length(extracted), " — ", url)
      return(invisible())
    }
    save_result(readBin(extracted, "raw", file.size(extracted)), dir, name, url)
  })
}

# ---- Run ----

download_results <- function(year, type) {
  src <- filter(RESULT_SOURCES, year == !!year, type == !!type)
  if (nrow(src) != 1) stop("No RESULT_SOURCES row for ", year, " ", type)

  message(year, " ", type, " (", src$source, ")")
  dir.create(results_dir(year, type), recursive = TRUE, showWarnings = FALSE)
  switch(src$source,
    sos_county    = download_sos_county(year, type, src$location),
    sos_statewide = download_sos_statewide(year, type, src$location),
    enr           = download_enr(year, type, src$location)
  )
  invisible(results_dir(year, type))
}

download_all_results <- function() {
  pwalk(select(RESULT_SOURCES, year, type), download_results)
  results_inventory()
}

# Files per election and format; `invalid` counts files that aren't results files.
results_inventory <- function() {
  files <- list.files(RESULTS_DIR, recursive = TRUE, full.names = TRUE)
  tibble(path = files) |>
    mutate(
      election = basename(dirname(path)),
      ext      = tools::file_ext(path),
      valid    = map_lgl(path, \(p) !is.na(sniff_format(readBin(p, "raw", 500))))
    ) |>
    summarise(
      files   = n(),
      formats = paste(sort(unique(ext)), collapse = ", "),
      invalid = sum(!valid),
      .by     = election
    ) |>
    arrange(election)
}

if (sys.nframe() == 0) {
  print(download_all_results(), n = Inf)
}
