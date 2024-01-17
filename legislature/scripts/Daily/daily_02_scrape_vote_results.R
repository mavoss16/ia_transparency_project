
# Author: Matthew Voss

library(dplyr)
library(stringr)
library(rvest)

# Brackets to allow exit if no votes
{
  # Get df with documentation of previously scraped vote files
  scraped_urls <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/Floor Votes/2024/downloaded_floor_votes.rds")
  
  # Get vote info from web page
  url <- "https://www.legis.iowa.gov/legislation/findLegislation/floorVotes"
  
  page <- read_html(url)
  
  votes <- html_elements(page, ".grid_8")
  
  if(length(votes == 0)){
    print("Stop Execution")
    quit()
  }
  
  print("Continued Execution")
  html_elements(votes, ".srow last")
  
  urls <- html_elements(votes, "a") |>
    html_attr("href") |>
    as.vector()
  
  # Combine scraped vote info from today with previous info
  vote_df <- data.frame(url_end = urls) |>
    filter(
      str_detect(url_end, "^\\?") & !is.na(url_end)
    ) |>
    left_join(scraped_urls, by = "url_end")
  
  copy <- vote_df
  
  # Keep urls that have not been downloaded to loop through
  download_urls <- vote_df |> 
    filter(is.na(file_name)) |>
    pull(url_end)
  
  
  download_url_pre <- "https://www.legis.iowa.gov/legislation/findLegislation/floorVotes"
  
  # Loop through urls to download
  for(url_end in download_urls){
    # download_url_end <- urls[i]
    item_id <- str_extract(url_end, "calendarItemID=\\d+") |> str_remove("calendarItemID=")
    chamber <- str_sub(url_end, start = -1, end = -1)
    full_url <- paste0(download_url_pre, url_end)
    file_path <- file.path("data", "Floor Votes", "2023", paste0("floor_vote_", item_id, "_", chamber, ".pdf"))
    download.file(
      url = full_url,
      destfile = file_path,
      mode = "wb"
    )
    
    # Add information to vote_df to help keep track
    vote_df[vote_df$url_end == url_end, "item_id"] <- item_id
    vote_df[vote_df$url_end == url_end, "chamber"] <- chamber
    vote_df[vote_df$url_end == url_end, "full_url"] <- full_url
    vote_df[vote_df$url_end == url_end, "file_name"] <- file_path
    vote_df[vote_df$url_end == url_end, "date_downloaded"] <- Sys.Date()
    Sys.sleep(runif(1, min = 0.2, max = 0.75))
  }
  
  
  # Write documented file of downloads
  write_rds(vote_df, "C:/Users/mavos/Documents/GitHub/iowa_legislature/data/Floor Votes/2024/downloaded_floor_votes.rds")
}
