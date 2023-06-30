
# Author: Matthew Voss

library(dplyr)
library(stringr)
library(rvest)


url <- "https://www.legis.iowa.gov/legislation/findLegislation/floorVotes"

page <- read_html(url)

votes <- html_elements(page, ".grid_8")

html_elements(votes, ".srow last")

urls <- html_elements(votes, "a") |>
  html_attr("href") |>
  as.vector()

urls <- urls[str_detect(urls, "^\\?") & !is.na(urls)]

html_elements(votes, ".amendments") |> View()

html_text(votes)


download_url_pre <- "https://www.legis.iowa.gov/legislation/findLegislation/floorVotes"

for(i in 1:length(urls)){
  download_url_end <- urls[i]
  download.file(
    url = paste0(download_url_pre, download_url_end),
    destfile = file.path("data", "Floor Votes", "2023", paste0("floor_vote_", i, ".pdf")),
    mode = "wb"
  )
  Sys.sleep(0.25)
}