library(here)

options(HTTPUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")

iowa_counties <- c("Black Hawk", "Muscatine", "O'Brien", "Polk", "Linn")

dest_dir <- here("data/elections/raw/precincts_2020s")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

base_url <- "https://sos.iowa.gov/elections/pdf/shapefiles/County%20Precincts/"

url_overrides <- c(
  "Muscatine" = "https://sos.iowa.gov/elections/pdf/shapefiles/County%20Precincts/Muscatine%20County%20Precinct%20Boundaries%20(1).zip"
)

results <- lapply(iowa_counties, function(county) {
  filename <- paste0(county, " County Precinct Boundaries.zip")
  url <- if (county %in% names(url_overrides)) {
    url_overrides[[county]]
  } else {
    paste0(base_url, gsub(" ", "%20", filename))
  }
  zip_path <- file.path(dest_dir, paste0(gsub(" ", "_", county), ".zip"))
  out_dir  <- file.path(dest_dir, gsub("[^A-Za-z0-9]", "_", county))

  message("Downloading: ", county)
  message("  URL: ", url)
  tryCatch({
    download.file(url, zip_path, mode = "wb", quiet = TRUE)
    dir.create(out_dir, showWarnings = FALSE)
    unzip(zip_path, exdir = out_dir)
    file.remove(zip_path)
    message("  OK")
    data.frame(county = county, status = "ok")
  }, error = function(e) {
    message("  FAILED: ", conditionMessage(e))
    data.frame(county = county, status = paste("error:", conditionMessage(e)))
  })
})

results_df <- do.call(rbind, results)
message("\nSummary:")
print(results_df)

## Troubleshooting

library(httr2)
req <- request(url) |>
  req_headers(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer` = "https://sos.iowa.gov/"
  ) |>
  req_perform() |>
  resp_body_raw() |>
  writeBin(zip_path)