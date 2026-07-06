# Enrich precincts_2020s.rds with Census place and township overlaps.
#
# For each precinct polygon, finds which Iowa incorporated places (cities/towns)
# and civil townships it spatially intersects, then adds those as collapsed
# comma-separated columns.
#
# Sources (downloaded via tigris, cached locally):
#   - places()              → incorporated cities, towns, CDPs (Census TIGER 2020)
#   - county_subdivisions() → civil townships (filtered to "% Township")
#
# Input:  data/elections/processed/precincts_2020s.rds
# Output: data/elections/processed/precincts_2020s_enriched.rds
#   Same sf object as input, with two new columns appended:
#     places    — comma-separated overlapping place names (NA if none)
#     townships — comma-separated overlapping township names (NA if none)

library(sf)
library(dplyr)
library(stringr)
library(tigris)
library(here)

options(tigris_use_cache = TRUE)
sf_use_s2(FALSE)  # use GEOS instead of S2 — avoids validity errors in Census geometries

INPUT  <- here("data/elections/processed/precincts_2020s.rds")
OUTPUT <- here("data/elections/processed/precincts_2020s_enriched.rds")

# ---- Load and clean precinct shapefile ----

message("Loading precinct shapefile...")
precincts <- readRDS(INPUT) |>
  mutate(county = str_to_title(str_replace_all(county, c(
    "Buchananan" = "Buchanan",
    "O Brien"    = "O'Brien"
  )))) |>
  filter(!is.na(LONGNAME)) |>
  mutate(precinct_id = row_number())  # unique key so spatial joins survive
                                      # duplicate (county, LONGNAME) values

message("  ", nrow(precincts), " precincts across ", n_distinct(precincts$county), " counties")

# ---- Download Census boundaries for Iowa ----

message("Downloading Census TIGER boundaries (2020)...")
ia_places <- places(state = "IA", cb = TRUE, year = 2020) |>
  select(place_name = NAME) |>
  st_transform(st_crs(precincts))

# Iowa townships use LSAD 44; NAMELSAD has the full label ("Adams township").
# Use NAME (base name) and add "Township" suffix for display clarity.
ia_townships <- county_subdivisions(state = "IA", cb = TRUE, year = 2020) |>
  filter(LSAD == "44") |>
  mutate(township_name = paste(NAME, "Township")) |>
  select(township_name) |>
  st_transform(st_crs(precincts))

message("  ", nrow(ia_places), " places, ", nrow(ia_townships), " townships")

# ---- Spatial joins ----

# Intersect-and-collapse: find overlapping names, sorted alphabetically
spatial_overlap <- function(precincts, ref_layer, name_col) {
  st_join(
    precincts |> select(county, LONGNAME),
    ref_layer,
    join = st_intersects
  ) |>
    st_drop_geometry() |>
    group_by(county, LONGNAME) |>
    summarise(
      overlap = {
        vals <- na.omit(unique(get(name_col)))
        if (length(vals) == 0) NA_character_ else paste(sort(vals), collapse = ", ")
      },
      .groups = "drop"
    ) |>
    rename(!!name_col := overlap)
}

# Area-ordered variant: computes actual intersection area so the most-overlapping
# name comes first. Labels include the percentage of the precinct covered by each
# reference polygon; entries covering < 5% of the precinct are dropped.
spatial_overlap_by_area <- function(precincts, ref_layer, name_col, min_pct = 5) {
  # Precinct total areas in projected CRS (needed for percentage denominator)
  precinct_areas <- precincts |>
    select(county, LONGNAME) |>
    st_transform(32615) |>
    mutate(precinct_area = as.numeric(st_area(geometry))) |>
    st_drop_geometry()

  st_intersection(
    precincts |> select(county, LONGNAME),
    ref_layer |> select(all_of(name_col))
  ) |>
    st_transform(32615) |>           # UTM zone 15N — Iowa; needed for planar st_area()
    mutate(isect_area = as.numeric(st_area(geometry))) |>
    st_drop_geometry() |>
    left_join(precinct_areas, by = c("county", "LONGNAME"), relationship = "many-to-one") |>
    mutate(
      pct   = round(100 * isect_area / precinct_area),
      label = paste0(.data[[name_col]], " (", pct, "%)")
    ) |>
    filter(pct >= min_pct) |>
    arrange(county, LONGNAME, desc(isect_area)) |>
    group_by(county, LONGNAME) |>
    summarise(
      overlap = paste(label, collapse = ", "),
      .groups = "drop"
    ) |>
    rename(!!name_col := overlap)
}

message("Joining places...")
place_overlaps <- spatial_overlap(precincts, ia_places, "place_name")

message("Joining townships (by overlap area)...")
township_overlaps <- spatial_overlap_by_area(precincts, ia_townships, "township_name")

# ---- Enrich and save ----

message("Saving enriched shapefile...")
precincts_enriched <- precincts |>
  left_join(place_overlaps,    by = c("county", "LONGNAME")) |>
  left_join(township_overlaps, by = c("county", "LONGNAME")) |>
  rename(places = place_name, townships = township_name)

saveRDS(precincts_enriched, OUTPUT)
message("Done. Saved to ", basename(OUTPUT))

# Quick coverage summary
n_with_place    <- sum(!is.na(precincts_enriched$places))
n_with_township <- sum(!is.na(precincts_enriched$townships))
message("  Precincts with place overlap:    ", n_with_place,    " / ", nrow(precincts_enriched))
message("  Precincts with township overlap: ", n_with_township, " / ", nrow(precincts_enriched))
