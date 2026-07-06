#
# Author: Matthew Voss

library(dplyr)
library(tigris)
library(sf)
library(stringr)
library(curl)
library(httr)

# Address structure
# https://sos.iowa.gov/elections/results/xls/2020/general/Adair.xlsx
# County specifics:
# O'Brien, Buena%20Vista (%20 replace spaces in 2 word county names)


# Read in counties and arrange
ia_counties = counties(state = 19) %>% arrange(NAME)

# Store county names for URL
counties = ia_counties$NAME %>% str_replace_all(" ", "%20")

# Election Years
# election_years = seq(from = 2012, to = 2020, by = 2)
election_years <- c(2022, 2024)

# Loop through counties
for(county in counties){
  print(county)
  
  county_file_name = county %>% str_replace_all("%20", "_") %>% tolower()
  
  # Loop through election years
  for(year in election_years){
    
    # Check if folder exists, create folder if it does not
    if(!dir.exists(paste0("data/elections/raw/precinct_elections_", year))){
      dir.create(paste0("data/elections/raw/precinct_elections_", year))
    }
    
    # Check if .xlsx file exists, or if .xls extension needs to be used
    extension = ".xlsx"
    head = HEAD(
      paste0(
        "https://sos.iowa.gov/elections/results/xls/",
        year,
        "/general/",
        county,
        extension
      )
    )
    if(head$url == "https://sos.iowa.gov/error/404.aspx"){
      extension = ".xls"
    }
    
    # Download file and put in folder
    curl_download(
      url = paste0(
        "https://sos.iowa.gov/elections/results/xls/",
        year,
        "/general/",
        county,
        extension
      ),
      destfile = paste0(
        paste0(
          "data/precinct_elections_",
          year,
          "/",
          county_file_name,
          "_",
          year,
          extension
        )
      )
    )
    
    # Sleep between 0.5 and 3 seconds
    Sys.sleep(runif(1, min = 0.5, max = 3))
  }
}

curl_download(
  url = "https://sos.iowa.gov/elections/results/xls/2018/general/Adair.xls",
  destfile = "data/precinct_elections_2018/adair_2018.xls"
)
# 
# 
# x = curl("https://sos.iowa.gov/elections/results/xls/2018/general/Adair.xlsx")
# 
# y = curl("https://sos.iowa.gov/elections/results/xls/2020/general/Adair.xlsx")
# 
# 
# head_x = HEAD("https://sos.iowa.gov/elections/results/xls/2018/general/Adair.xlsx")
# head = HEAD("https://sos.iowa.gov/elections/results/xls/2020/general/Adair.xlsx")
test = readxl::read_excel("data/precinct_elections_2018/adair_2018.xls")
