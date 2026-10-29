# shapefile_precincts.R
# Download per-county precinct boundary shapefiles from Iowa Secretary of State.
# Scrapes download links from: https://sos.iowa.gov/shapefiles-county-precincts
# Output: data/elections/raw/precincts_2020s/{county}/

library(here)
library(httr2)
library(rvest)

iowa_counties <- c(
  "Adair", "Adams", "Allamakee", "Appanoose", "Audubon",
  "Benton", "Black Hawk", "Boone", "Bremer", "Buchanan",
  "Buena Vista", "Butler", "Calhoun", "Carroll", "Cass",
  "Cedar", "Cerro Gordo", "Cherokee", "Chickasaw", "Clarke",
  "Clay", "Clayton", "Clinton", "Crawford", "Dallas",
  "Davis", "Decatur", "Delaware", "Des Moines", "Dickinson",
  "Dubuque", "Emmet", "Fayette", "Floyd", "Franklin",
  "Fremont", "Greene", "Grundy", "Guthrie", "Hamilton",
  "Hancock", "Hardin", "Harrison", "Henry", "Howard",
  "Humboldt", "Ida", "Iowa", "Jackson", "Jasper",
  "Jefferson", "Johnson", "Jones", "Keokuk", "Kossuth",
  "Lee", "Linn", "Louisa", "Lucas", "Lyon",
  "Madison", "Mahaska", "Marion", "Marshall", "Mills",
  "Mitchell", "Monona", "Monroe", "Montgomery", "Muscatine",
  "O'Brien", "Osceola", "Page", "Palo Alto", "Plymouth",
  "Pocahontas", "Polk", "Pottawattamie", "Poweshiek", "Ringgold",
  "Sac", "Scott", "Shelby", "Sioux", "Story",
  "Tama", "Taylor", "Union", "Van Buren", "Wapello",
  "Warren", "Washington", "Wayne", "Webster", "Winnebago",
  "Winneshiek", "Woodbury", "Worth", "Wright"
)

dest_dir <- here("data/elections/raw/precincts_2020s")
dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

scrape_shapefile_urls <- function() {
  html <- request("https://sos.iowa.gov/shapefiles-county-precincts") |>
    req_headers(
      `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      `Referer`    = "https://sos.iowa.gov/"
    ) |>
    req_perform() |>
    resp_body_string() |>
    read_html()

  links <- html_elements(html, "a[href$='.zip']")
  urls  <- html_attr(links, "href")
  texts <- html_text2(links)

  urls         <- ifelse(startsWith(urls, "http"), urls, paste0("https://sos.iowa.gov", urls))
  county_names <- sub(" County.*", "", texts)
  setNames(urls, county_names)
}

download_county_shapefile <- function(county, url) {
  zip_path <- file.path(dest_dir, paste0(gsub(" ", "_", county), ".zip"))
  out_dir  <- file.path(dest_dir, gsub("[^A-Za-z0-9]", "_", county))

  if (dir.exists(out_dir) && length(list.files(out_dir)) > 0) {
    message("Skipping (already downloaded): ", county)
    return(data.frame(county = county, status = "skipped"))
  }

  message("Downloading: ", county)
  tryCatch({
    request(url) |>
      req_headers(
        `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        `Referer` = "https://sos.iowa.gov/"
      ) |>
      req_perform() |>
      resp_body_raw() |>
      writeBin(zip_path)
    dir.create(out_dir, showWarnings = FALSE)
    unzip(zip_path, exdir = out_dir)
    file.remove(zip_path)
    data.frame(county = county, status = "ok")
  }, error = function(e) {
    message("  FAILED: ", conditionMessage(e))
    data.frame(county = county, status = paste("error:", conditionMessage(e)))
  })
}

message("Scraping shapefile URLs...")
shapefile_urls <- scrape_shapefile_urls()
message("Found ", length(shapefile_urls), " zip links.")

results <- Map(download_county_shapefile, names(shapefile_urls), shapefile_urls)

results_df <- do.call(rbind, results)
message("\nDone. Summary:")
print(table(results_df$status))
