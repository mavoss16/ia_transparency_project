# Simplify district shapefiles for use in leaflet maps
# Run once — output is saved to data/ and used by templates
#
# The original shapefiles have ~243K (Senate) and ~321K (House) coordinate pairs,
# which bloats every page that embeds a leaflet map. A tolerance of 0.0002 degrees
# (~22m) produces visually identical boundaries with significantly fewer vertices.

library(sf)
library(dplyr)

sf_use_s2(FALSE)

senate <- st_read(here::here("data/Districts/Plan2_Senate.shp"), quiet = TRUE) |>
  st_transform(crs = 4326) |>
  st_simplify(dTolerance = 0.0002, preserveTopology = TRUE) |>
  transmute(District = as.numeric(DISTRICT))

house <- st_read(here::here("data/Districts/Plan2_House.shp"), quiet = TRUE) |>
  st_transform(crs = 4326) |>
  st_simplify(dTolerance = 0.0002, preserveTopology = TRUE) |>
  transmute(District = as.numeric(DISTRICT))

saveRDS(senate, here::here("data/senate_districts.rds"))
saveRDS(house, here::here("data/house_districts.rds"))

cat("Senate:", nrow(senate), "districts\n")
cat("House:", nrow(house), "districts\n")
cat("Saved to data/senate_districts.rds and data/house_districts.rds\n")
