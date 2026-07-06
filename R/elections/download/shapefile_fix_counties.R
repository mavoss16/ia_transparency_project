# Fix shapefile downloads for counties missing usable precinct geometry.
#
# Jasper  — SOS shapefile uses "Name" column instead of standard "LONGNAME".
#            combine_precinct_shapefiles.R remaps this automatically; existing
#            file is fine as-is. No download needed.
#
# Polk    — SOS "Polk County Precinct Boundaries.zip" is a legislative-district
#            redistricting file (5 rows, empty NAME column) — not usable. Partial
#            coverage assembled from individual city shapefiles downloaded here.
#            Unincorporated/rural precincts will need no_match().
#
# Kossuth — No county shapefile on SOS. Partial coverage via Algona city file.
#            Non-Algona precincts will need no_match().
#
# Lyon    — No county shapefile on SOS. The only available city files (Rock Rapids
#            Precincts 3 & 4) contain only an "Id" column — no precinct name.
#            No usable shapefile data exists for Lyon; use no_match() for all.
#
# After running this script, re-run in order:
#   source("R/elections/precinct_matching/01_combine_precinct_shapefiles.R")
#   source("R/elections/precinct_matching/02_enrich_precinct_shapefiles.R")
#   source("R/elections/precinct_matching/03_crosswalk_precincts_2024.R")
#   source("R/elections/precinct_matching/manual_crosswalk.R")

library(here)
library(httr2)

dest_dir <- here("data/elections/raw/precincts_2020s")

download_zip <- function(url, out_dir) {
  zip_path <- tempfile(fileext = ".zip")
  request(url) |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      `Referer`    = "https://sos.iowa.gov/"
    ) |>
    req_perform() |>
    resp_body_raw() |>
    writeBin(zip_path)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  unzip(zip_path, exdir = out_dir)
  file.remove(zip_path)
  message("  Extracted to: ", out_dir)
}

city_url <- function(city) {
  paste0(
    "https://sos.iowa.gov/elections/pdf/shapefiles/City%20Precincts/",
    URLencode(city, reserved = TRUE), ".zip"
  )
}

# ---- Polk: city shapefiles for incorporated cities in Polk County ----
# The SOS has no usable county-wide shapefile for Polk. These city files cover
# the incorporated areas; unincorporated/rural precincts will need no_match().
message("Polk (city shapefiles)...")
polk_dir <- file.path(dest_dir, "Polk")

# Remove the old redistricting file — it has no precinct data
old_files <- list.files(polk_dir, full.names = TRUE)
if (length(old_files) > 0) {
  file.remove(old_files)
  message("  Removed ", length(old_files), " old redistricting file(s)")
}

polk_cities <- c(
  "Altoona Precinct Boundaries",
  "Ankeny Precinct Boundaries",
  "Bondurant Precinct Boundaries",
  "Clive Precinct Boundaries",
  "Des Moines Precinct Boundaries",
  "Grimes Precinct Boundaries",
  "Johnston Precinct Boundaries",
  "Norwalk Precinct Boundaries",
  "Pleasant Hill Precinct Boundaries",
  "Polk City Precinct Boundaries",
  "Urbandale Precinct Boundaries",
  "West Des Moines Precinct Boundaries",
  "Windsor Heights Precinct Boundaries"
)

for (city in polk_cities) {
  message("  ", city, "...")
  tryCatch(
    download_zip(city_url(city), polk_dir),
    error = function(e) message("    FAILED: ", conditionMessage(e))
  )
}

# ---- Kossuth: no county shapefile; download Algona city file ----
message("Kossuth (Algona city only)...")
kossuth_dir <- file.path(dest_dir, "Kossuth")
if (!dir.exists(kossuth_dir) || length(list.files(kossuth_dir)) == 0) {
  download_zip(city_url("Algona Precinct Boundaries"), kossuth_dir)
} else {
  message("  Already present, skipping.")
}

# Lyon: Rock Rapids city files contain only an "Id" column with no precinct names.
# Nothing to download — use no_match() for all Lyon precincts in manual_crosswalk.R.
message("Lyon: no usable shapefile source. Use no_match() for all Lyon precincts.")

message("\nDone. Re-run in order:")
message("  source('R/elections/precinct_matching/01_combine_precinct_shapefiles.R')")
message("  source('R/elections/precinct_matching/02_enrich_precinct_shapefiles.R')  # slow")
message("  source('R/elections/precinct_matching/03_crosswalk_precincts_2024.R')")
message("  source('R/elections/precinct_matching/manual_crosswalk.R')")
