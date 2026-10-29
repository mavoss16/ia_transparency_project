# 01_combine_precinct_shapefiles.R
# Read all per-county precinct shapefiles and combine into a single sf dataset.
# Input:  data/elections/raw/precincts_2020s/{county}/*.shp
# Output: data/elections/precincts_2020s.rds

library(here)
library(sf)
library(dplyr)
library(purrr)
library(stringr)

raw_dir  <- here("data/elections/raw/precincts_2020s")
out_file <- here("data/elections/processed/precincts_2020s.rds")

county_dirs <- list.dirs(raw_dir, recursive = FALSE, full.names = TRUE)

# Best-effort city/source label derived from the shapefile filename.
# Strips common boilerplate ("Precinct Boundaries", "City of", date stamps,
# "_-_FINAL" etc.) so the result is something like "Ankeny" or "Des Moines".
.derive_source_label <- function(filename) {
  stem <- tools::file_path_sans_ext(basename(filename))
  stem |>
    str_replace_all("_", " ") |>
    str_remove_all("(?i)\\bPrecinct(s)?\\b") |>
    str_remove_all("(?i)\\bBoundaries\\b") |>
    str_remove_all("(?i)\\bCity( of)?\\b") |>
    str_remove_all("(?i)\\bCounty\\b") |>
    str_remove_all("(?i)\\bMap(s)?\\b") |>
    str_remove_all("(?i)\\bOfficial\\b") |>
    str_remove_all("(?i)\\bversion\\b") |>
    str_remove_all("(?i)\\bAdopted\\b|\\bAdpoted\\b") |>
    str_remove_all("(?i)\\bFinal\\b") |>
    str_remove_all("(?i)\\bAmended\\b") |>
    str_remove_all("(?i)\\bdraft\\b") |>
    str_remove_all("(?i)\\bcopy\\b") |>
    str_remove_all("(?i)\\bplan\\b") |>
    str_remove_all("\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4}") |>      # 12-9-21, 1/10/22
    str_remove_all("\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}") |>        # 2022-03-07
    str_remove_all("\\b\\d{4}\\b") |>                          # bare year
    str_remove_all("[-_]+") |>
    str_squish()
}

read_county_shapefile <- function(dir) {
  shp_files <- list.files(dir, pattern = "\\.shp$", full.names = TRUE)
  if (length(shp_files) == 0) {
    message("  Skipping (no .shp found): ", basename(dir))
    return(NULL)
  }
  county_name <- gsub("_", " ", basename(dir))
  read_one <- function(f) {
    tryCatch({
      sf_obj <- st_read(f, quiet = TRUE) |>
        mutate(county = county_name, across(where(\(x) !inherits(x, "sfc")), as.character))
      # Some counties (e.g. Jasper) use "Name" instead of the standard "LONGNAME"
      if (!"LONGNAME" %in% names(sf_obj)) {
        alt <- intersect(c("Name", "NAME"), names(sf_obj))
        if (length(alt) > 0) sf_obj <- rename(sf_obj, LONGNAME = !!alt[[1]])
      }
      # Track origin so multi-file folders (city shapefiles aggregated under one
      # county) don't collide on identical LONGNAMEs ("Precinct 1" appears in
      # many city files).
      sf_obj |>
        mutate(
          source_file  = basename(f),
          source_label = .derive_source_label(f)
        )
    }, error = function(e) {
      message("  FAILED: ", basename(f), " — ", conditionMessage(e))
      NULL
    })
  }
  layers <- Filter(Negate(is.null), lapply(shp_files, read_one))
  if (length(layers) == 0) return(NULL)
  combined <- if (length(layers) == 1) layers[[1]] else bind_rows(layers)

  # Disambiguate within-county LONGNAME duplicates (e.g. multiple city shapefiles
  # each containing "Precinct 1") by prefixing the source label.
  if (!"LONGNAME" %in% names(combined)) return(combined)

  dup_keys <- combined |>
    st_drop_geometry() |>
    filter(!is.na(LONGNAME)) |>
    count(LONGNAME) |>
    filter(n > 1) |>
    pull(LONGNAME)

  if (length(dup_keys) > 0) {
    message("  ", basename(dir), ": disambiguating ", length(dup_keys),
            " duplicate LONGNAME(s) with source label")
    combined <- combined |>
      mutate(LONGNAME = if_else(
        !is.na(LONGNAME) & LONGNAME %in% dup_keys & nzchar(source_label),
        paste0(source_label, " ", LONGNAME),
        LONGNAME
      ))
  }
  combined
}

message("Reading shapefiles...")
shapefiles <- map(county_dirs, read_county_shapefile)
shapefiles <- Filter(Negate(is.null), shapefiles)

target_crs <- st_crs(shapefiles[[1]])
shapefiles <- map(shapefiles, \(x) {
  if (st_crs(x) != target_crs) st_transform(x, target_crs) else x
})

message("Combining ", length(shapefiles), " datasets...")
precincts <- bind_rows(shapefiles)

dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
saveRDS(precincts, out_file)
message("Done. ", nrow(precincts), " precincts saved to ", out_file)
