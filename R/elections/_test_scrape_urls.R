library(httr2)
library(rvest)

html <- request("https://sos.iowa.gov/shapefiles-county-precincts") |>
  req_headers(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer` = "https://sos.iowa.gov/"
  ) |>
  req_perform() |>
  resp_body_string() |>
  read_html()

links <- html_elements(html, "a[href$='.zip']")
urls  <- html_attr(links, "href")
texts <- html_text2(links)

urls <- ifelse(startsWith(urls, "http"), urls, paste0("https://sos.iowa.gov", urls))

shapefile_urls <- setNames(urls, texts)

message("Found ", length(shapefile_urls), " zip links:")
print(shapefile_urls)
