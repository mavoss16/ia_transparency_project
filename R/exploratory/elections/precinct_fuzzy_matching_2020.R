


# https://sos.iowa.gov/shapefiles/
# https://sos.iowa.gov/shapefiles/County%20Precincts/

library(sf)
library(tigris)
library(stringdist)
library(dplyr)


precincts = st_read("data/precincts_2010s/Precincts041714.shp") %>% st_transform(crs = 4269)
precincts$unique_id = 1:nrow(precincts)
# ia_counties_sf = counties(state = "IA")
# 
# 
# precincts_county = st_join(precincts, ia_counties_sf)
# precincts_county = precincts_county %>%
#   mutate(
#     join_area = st_area(precincts_county)
#   )
# 
# 
# precincts_intersection = st_intersection(precincts %>% st_make_valid(), ia_counties_sf)
# precincts_intersection = precincts_intersection %>%
#   mutate(
#     join_area = st_area(precincts_county)
#   )

elections_2020 = readr::read_csv("data/statewide/precinct_elections_2020.csv")

precinct_info = elections_2020 %>% filter(election == "State Representative") %>% distinct(county, precinct, district)



# Precinct Name Fuzzy Matching --------------------------------------------


# Create new variables for linking by the "name" variable
precinct_info$linking_name_id = NA
precinct_info$linking_name = NA
precinct_info$name_score = NA
precinct_info$name_max_times = NA

# Create new variables for linking by the "district" variable
precinct_info$linking_district_id = NA
precinct_info$linking_district = NA
precinct_info$district_score = NA
precinct_info$district_max_times = NA


for(i in seq_along(precinct_info$precinct)){
  if(i %% 50 == 0){print(i)}
  precinct_name = precinct_info$precinct[i]
  dist_precincts = precincts %>% filter(House_Dist == precinct_info$district[i])
  
  sim_scores_name = stringsim(precinct_name %>% tolower(), dist_precincts$NAME %>% tolower())
  sim_scores_district = stringsim(precinct_name %>% tolower(), dist_precincts$DISTRICT %>% tolower())
  
  precinct_info$linking_name_id[i] = dist_precincts$unique_id[which.max(sim_scores_name)]
  precinct_info$linking_name[i] = dist_precincts$NAME[which.max(sim_scores_name)]
  precinct_info$name_score[i] = max(sim_scores_name) %>% round(digits = 3)
  precinct_info$name_max_times[i] = sum(sim_scores_name == max(sim_scores_name))
  
  precinct_info$linking_district_id[i] = dist_precincts$unique_id[which.max(sim_scores_district)]
  precinct_info$linking_district[i] = dist_precincts$DISTRICT[which.max(sim_scores_district)]
  precinct_info$district_score[i] = max(sim_scores_district) %>% round(digits = 3)
  precinct_info$district_max_times[i] = sum(sim_scores_district == max(sim_scores_district))

}

precinct_info = precinct_info %>%
  mutate(
    link = case_when(
      linking_name_id == linking_district_id ~ "Both",
      name_score > district_score ~ "Name",
      district_score > name_score ~ "District"
    ),
    linking_id = case_when(
      linking_name_id == linking_district_id ~ linking_name_id,
      name_score > district_score ~ linking_name_id,
      district_score > name_score ~ linking_district_id,
    ),
    linking_score = case_when(
      name_score >= district_score ~ name_score,
      district_score > name_score ~ district_score
    ),
    likely_match = case_when(
      linking_score >= 0.7 ~ "Yes",
      linking_score < 0.7 & linking_score >= 0.5 ~ "Maybe",
      linking_score < 0.5 ~ "No"
    )
  )


precinct_info = left_join(
  precinct_info,
  precincts %>% select(unique_id, DISTRICT, NAME),
  by = c("linking_id" = "unique_id")
)

match_info = precinct_info %>%
  transmute(
    scrape_county = county,
    scrape_house_district = district,
    scrape_name = precinct,
    shape_name = NAME,
    shape_district = DISTRICT,
    link = link,
    linking_id = linking_id,
    linking_score = linking_score,
    likely_match = likely_match
  )


readr::write_csv(match_info, "data/precinct_match_2020.csv")


View(precincts %>% st_drop_geometry() %>% select(House_Dist, NAME, DISTRICT, unique_id))




# Next Steps --------------------------------------------------------------

# Join precinct_match_2020_data_entry.xlsx with shapefile
# See how many precincts are left
# Use place US census file to do a spatial join with State shapefile
# Add place information to state shapefile, use to fill in more precincts

