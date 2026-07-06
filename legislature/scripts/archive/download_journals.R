# Download all Iowa House and Senate Journals
# Days vector specifies for which dates journals will be downloaded
# Author: Matthew Voss

library(stringr)


days <- seq(as.Date("2023/04/14"), Sys.Date(), by = "days") |>
  as.character() |>
  str_remove_all("-")

for(date in days){
  print(date)
  senate_url <- paste0("https://www.legis.iowa.gov/docs/publications/SJNL/", date, "_SJNL.pdf")
  senate_dest <- file.path("data", "Journals", "90th General Assembly", "Senate", paste0(date, "_SJNL.pdf"))
  house_url <- paste0("https://www.legis.iowa.gov/docs/publications/HJNL/", date, "_HJNL.pdf")
  house_dest <- file.path("data", "Journals", "90th General Assembly", "House", paste0(date, "_HJNL.pdf"))
  
  try(download.file(
    url = senate_url,
    destfile = senate_dest,
    mode = "wb"
  ))
  
  try(download.file(
    url = house_url,
    destfile = house_dest,
    mode = "wb"
  ))
}
