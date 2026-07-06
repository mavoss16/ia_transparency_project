# Read Excel sheets for 2020 elections
# Author: Matthew Voss

library(readxl)
library(janitor)
library(dplyr)
library(tidyr)
library(tigris)
library(stringr)
library(unpivotr)

ia_counties = counties(state = "IA") %>% sf::st_drop_geometry()
ia_county_list = ia_counties$NAME %>% sort()


# Inputs:
  # election_cells: election_cells object from unpivotr
  # election_county: County in which the election took place
format_election_sheet = function(election_cells, election_county){
  beheaded = election_cells %>%
    filter(
      row != 1
    ) %>%
    behead(
      direction = "up-left",
      name = "candidate"
    ) %>%
    behead(
      direction = "up-left",
      name = "vote_type"
    ) %>%
    behead(
      direction = "left",
      name = "precinct"
    ) %>%
    behead(
      direction = "right",
      name = "precinct_total"
    ) %>%
    behead(
      direction = "down",
      name = "vote_type_total"
    )
    
  election = beheaded %>%
    mutate(
      # Numeric values and calculate percentages
      votes = chr %>% as.numeric(),
      precinct_total = precinct_total %>% as.numeric(),
      precinct_percent = (votes/precinct_total) * 100,
      
      # Get election & district information
      election = election_name %>% str_trim() %>% str_remove(" \\(.+\\)$") %>% str_remove(" District \\d+$"),
      district = election_name %>% str_remove(" \\(.+\\)$") %>% str_extract("\\d+"),
      county = election_county
    ) %>%
    select(
      county, precinct, election, district, candidate, vote_type,
      votes, precinct_total, vote_type_total, precinct_percent
    )
  
  election = election %>%
    select(
      precinct, district, election, candidate, vote_type,
      votes, precinct_total, vote_type_total, precinct_percent
    )
  
  return(election)
}


# Skip Scott, which is a pdf rather than an Excel workbook
# Loop through counties
for(i in c(1:81, 83:99)){
  print(ia_county_list[i])
  
  # County file path
  path = file.path(
    "data", "precinct_elections_2020",
    paste0(
      tolower(ia_county_list[i]) %>% str_replace_all(" ", "_"),
      "_2020.xlsx"
    )
  )
  # Read first sheet
  table_of_contents = read_excel(path, sheet = 1, skip = 3)
  # Names of worksheets
  sheet_names = table_of_contents$Contest
  # Find indices of worksheets to read
  election_indices = which(str_detect(sheet_names, "President") | str_detect(sheet_names, "United States") | str_detect(sheet_names, "State")) + 1
  
  remove(table_of_contents, sheet_names)
  
  # Loop through every worksheet to read
  for(j in seq_along(election_indices)){
    
    # Read worksheet
    election_info = read_excel(path, sheet = election_indices[j])
    # Unpivotr format
    election_cells = as_cells(election_info, col_names = TRUE)
    # Election name
    election_name = election_cells$chr[1]
    
    remove(election_info)
    
    # Use previous function to get long election information
    election = format_election_sheet(election_cells, ia_county_list[i])
    
    # Store data for election or bind to county data
    if(j == 1){
      county_elections = election
    } else{
      county_elections = bind_rows(county_elections, election)
    }
  }
  
  # Add county information
  county_elections$county = ia_county_list[i]
  
  # Rearrange
  county_elections = county_elections %>%
    relocate(
      county, .before = precinct 
    )
  
  # Store data for county or bind to year data
  if(i == 1){
    year_elections = county_elections
  } else{
    year_elections = bind_rows(year_elections, county_elections)
  }
}



elections_2020 = year_elections

readr::write_csv(elections_2020, "data/statewide/precinct_elections_2020.csv")



# Extra Code --------------------------------------------------------------

# county_data = read_excel("data/precinct_elections_2020/scott_2020.xlsx", sheet = 1, skip = 3)
# sheet_names = county_data$Contest
# elections = which(str_detect(sheet_names, "President") | str_detect(sheet_names, "United States") | str_detect(sheet_names, "State")) + 1
# 
# election = read_excel("data/precinct_elections_2020/linn_2020.xlsx", sheet = elections[5])
# election_cells = as_cells(election, col_names = TRUE)
# election_name = election_cells$chr[1]
# 
# 
# test = format_election_sheet(election_cells, "test")

# View(test %>% head(n = 50))

