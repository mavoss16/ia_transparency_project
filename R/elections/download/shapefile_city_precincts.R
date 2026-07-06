# Download all city precinct boundary shapefiles from Iowa Secretary of State.
# Scrapes download links from: https://sos.iowa.gov/shapefiles-city-precincts
#
# Output: data/elections/raw/precincts_2020s_cities/{city_slug}/
#
# These files supplement the county-level shapefiles in precincts_2020s/. Several
# counties have incomplete coverage in their main shapefile (city precincts not
# included, or no county shapefile published at all), and the city files fill
# those gaps. Naming and column structure varies file-to-file — use the helpers
# in R/elections/precinct_matching/explore_shapefiles.R to inspect.

library(here)
library(httr2)
library(rvest)

dest_dir <- here("data/elections/raw/precincts_2020s_cities")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

PAGE_URL <- "https://sos.iowa.gov/shapefiles-city-precincts"

# Same browser-like headers as shapefile_precincts.R — short UA passes Akamai;
# full Chrome UA gets a 403.
SOS_HEADERS <- c(
  `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  `Referer`    = "https://sos.iowa.gov/"
)

# ---- Scrape ----

scrape_city_shapefile_urls <- function() {
  html <- request(PAGE_URL) |>
    req_headers(!!!SOS_HEADERS) |>
    req_perform() |>
    resp_body_string() |>
    read_html()

  links <- html_elements(html, "a[href$='.zip']")
  urls  <- html_attr(links, "href")
  texts <- html_text2(links)

  urls <- ifelse(startsWith(urls, "http"), urls, paste0("https://sos.iowa.gov", urls))
  setNames(urls, texts)
}

# Convert ".zip" link text into a clean folder slug:
#   "Adel Precinct Boundaries.zip"                   → "Adel"
#   "Bettendorf Ward Boundaries.zip"                 → "Bettendorf_Ward"
#   "Rock Rapids Precinct 3 Boundaries.zip"          → "Rock_Rapids_Precinct_3"
#   "City of Maquoketa Wards (Precincts 9-13).zip"   → "Maquoketa_Wards"
#   "Iowa Falls Precincts 7 & 8 Maps.zip"            → "Iowa_Falls_Precincts_7_8"
city_slug <- function(text) {
  text |>
    sub("\\.zip$", "", x = _) |>
    sub("(?i)^City of\\s+", "", x = _, perl = TRUE) |>
    gsub("(?i)\\s*Boundaries\\s*", " ", x = _, perl = TRUE) |>
    gsub("(?i)\\s*Maps?\\s*", " ", x = _, perl = TRUE) |>
    gsub("(?i)\\s*Precincts?\\s+(?=\\d|$)", " Precinct ", x = _, perl = TRUE) |>
    gsub("\\([^)]*\\)", " ", x = _) |>
    gsub("[^A-Za-z0-9]+", "_", x = _) |>
    gsub("^_+|_+$", "", x = _)
}

# ---- Download ----

download_city_shapefile <- function(text, url) {
  slug <- city_slug(text)
  if (!nzchar(slug)) {
    message("Skipping (could not derive slug): ", text)
    return(data.frame(text = text, slug = NA, status = "no-slug"))
  }

  out_dir  <- file.path(dest_dir, slug)
  zip_path <- file.path(dest_dir, paste0(slug, ".zip"))

  if (dir.exists(out_dir) && length(list.files(out_dir)) > 0) {
    message("Skipping (already downloaded): ", slug)
    return(data.frame(text = text, slug = slug, status = "skipped"))
  }

  message("Downloading: ", slug)
  tryCatch({
    request(url) |>
      req_headers(!!!SOS_HEADERS) |>
      req_perform() |>
      resp_body_raw() |>
      writeBin(zip_path)
    dir.create(out_dir, showWarnings = FALSE)
    unzip(zip_path, exdir = out_dir)
    file.remove(zip_path)
    data.frame(text = text, slug = slug, status = "ok")
  }, error = function(e) {
    message("  FAILED: ", conditionMessage(e))
    data.frame(text = text, slug = slug, status = paste("error:", conditionMessage(e)))
  })
}

# ---- Run ----

message("Scraping city precinct shapefile URLs...")
city_urls <- scrape_city_shapefile_urls()
message("Found ", length(city_urls), " zip links.")

results <- Map(download_city_shapefile, names(city_urls), city_urls)
results_df <- do.call(rbind, results)

message("\nDone. Summary:")
print(table(results_df$status))
