


library(sf)
library(tigris)
library(stringdist)
library(dplyr)
library(readxl)


match_data_entry = read_excel("data/precinct_match_2020_data_entry.xlsx", sheet = "precinct_match_2020_data_entry")

ia_places = places(state = 19) %>% select(NAMELSAD, geometry)
subdiv = county_subdivisions(state = 19) %>% select(COUNTYFP, NAMELSAD, geometry)


precincts = st_read("data/precincts_2010s/Precincts041714.shp") %>% st_transform(crs = 4269) %>% select(-c(Shape_Leng, Shape_Le_1, Shape_Area))
precincts$precinct_area = st_area(precincts) %>% units::drop_units()
precincts$unique_id = 1:nrow(precincts)


precinct_places = st_intersection(precincts %>% st_make_valid(), ia_places)
precinct_places$precinct_place_area = st_area(precinct_places) %>% units::drop_units()


precinct_townships = st_intersection(precincts %>% st_make_valid(), subdiv)
precinct_townships$precinct_township_area = st_area(precinct_townships) %>% units::drop_units()


precinct_places_collapse = precinct_places %>%
  st_drop_geometry() %>%
  mutate(
    place_area_pct = (precinct_place_area/precinct_area)*100 %>% round(digits = 2)
  ) %>%
  filter(
    place_area_pct > 1
  ) %>%
  group_by(unique_id, DISTRICT, NAME) %>%
  summarize(places = paste0(NAMELSAD, collapse = ", "))


precinct_townships_collapse = precinct_townships %>%
  st_drop_geometry() %>%
  mutate(
    township_area_pct = (precinct_township_area/precinct_area)*100 %>% round(digits = 2)
  ) %>%
  filter(
    township_area_pct > 1
  ) %>%
  group_by(unique_id, DISTRICT, NAME) %>%
  summarize(townships = paste0(NAMELSAD, collapse = ", "))



places_townships = full_join(precinct_townships_collapse, precinct_places_collapse) %>% 
  left_join(
    precincts %>% select(unique_id, DISTRICT, NAME, House_Dist) %>% st_drop_geometry(), 
    by = c("unique_id" = "unique_id", "DISTRICT" = "DISTRICT", "NAME" = "NAME")
  ) %>%
  relocate(House_Dist, .before = unique_id) %>%
  mutate(
    unique_id = as.character(unique_id),
    House_Dist = as.character(House_Dist)
  )


