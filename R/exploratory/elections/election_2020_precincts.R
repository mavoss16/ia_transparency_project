

library(dplyr)
library(readr)
library(sf)
library(readxl)


elections = read_csv("data/statewide/precinct_elections_2020.csv")

elections_mit = read_csv("data/statewide/2020-ia-precinct-general_mit.csv", col_types = cols(.default = "c"))


precincts = st_read("data/precincts_2010s/Precincts041714.shp") %>% st_transform(crs = 4269) %>% select(-c(Shape_Leng, Shape_Le_1, Shape_Area))
precincts$unique_id = 1:nrow(precincts)

match_data_entry = read_excel("data/precinct_match_2020_data_entry.xlsx", sheet = "precinct_match_2020_data_entry")

match_data_entry = match_data_entry %>%
  mutate(
    match_linking_id = ifelse(
      !is.na(notes) & is.na(manual_match_id),
      yes = NA,
      no = ifelse(
        !is.na(manual_match_id),
        yes = manual_match_id,
        no = linking_id
      )
    )
  )


