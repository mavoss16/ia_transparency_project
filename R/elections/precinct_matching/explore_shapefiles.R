# Interactive exploration helpers for diagnosing shapefile / election-precinct
# matching problems. Source this file, then call any of:
#
#   list_county_files("Polk")            list all shapefiles in a county folder
#   shp_fields("Polk")                   show DBF column names per file
#   shp_preview("Polk")                  show LONGNAME (or fallback) values per file
#   shp_preview("Polk", n = 30)          show more rows per file
#   shp_long("Polk")                     all LONGNAMEs across files, with source
#   elec_precincts("Polk")               election-data precinct names for a county
#   compare_names("Polk")                side-by-side: election names vs shapefile names
#   shp_map("Polk")                      leaflet map of all polygons across files
#
# All functions accept either a county name in title case ("Polk", "Black Hawk")
# or with underscores matching the folder name ("Black_Hawk").

library(here)
library(dplyr)
library(stringr)
library(readr)
library(sf)
library(purrr)
library(tidyr)

.RAW_DIR  <- here("data/elections/raw/precincts_2020s")
.ELEC     <- here("data/elections/processed/2024/precinct_elections_2024.csv")
.AUTO     <- here("data/elections/processed/precinct_crosswalk_auto.csv")
.MANUAL   <- here("data/elections/processed/precinct_crosswalk_manual.csv")

.county_dir <- function(county) {
  folder <- gsub(" ", "_", county)
  candidates <- c(
    file.path(.RAW_DIR, folder),
    file.path(.RAW_DIR, str_to_title(folder))
  )
  hit <- candidates[dir.exists(candidates)]
  if (length(hit) == 0) stop("No folder found for county '", county, "'")
  hit[[1]]
}

# ---- File listing ----

list_county_files <- function(county) {
  d <- .county_dir(county)
  files <- list.files(d, full.names = FALSE, recursive = TRUE)
  cat("=== ", basename(d), " (", length(files), " files) ===\n", sep = "")
  for (f in files) cat("  ", f, "\n", sep = "")
  invisible(files)
}

# ---- DBF inspection (using sf, no shapefile geometry needed) ----

.read_dbf_attrs <- function(shp_path) {
  # st_read on a .shp also reads the .dbf; we just drop geometry.
  suppressWarnings(suppressMessages(
    sf::st_read(shp_path, quiet = TRUE) |> sf::st_drop_geometry() |> as_tibble()
  ))
}

shp_fields <- function(county) {
  d <- .county_dir(county)
  shps <- list.files(d, pattern = "\\.shp$", full.names = TRUE)
  if (length(shps) == 0) { cat("No .shp files in ", d, "\n"); return(invisible(NULL)) }

  cat("=== ", basename(d), " — ", length(shps), " shapefile(s) ===\n", sep = "")
  for (s in shps) {
    df <- tryCatch(.read_dbf_attrs(s), error = function(e) NULL)
    cat("\n[", basename(s), "] ", nrow(df), " rows\n", sep = "")
    if (is.null(df)) { cat("  (failed to read)\n"); next }
    cat("  Columns: ", paste(names(df), collapse = ", "), "\n", sep = "")
  }
  invisible(NULL)
}

shp_preview <- function(county, n = 10) {
  d <- .county_dir(county)
  shps <- list.files(d, pattern = "\\.shp$", full.names = TRUE)
  if (length(shps) == 0) { cat("No .shp files in ", d, "\n"); return(invisible(NULL)) }

  cat("=== ", basename(d), " ===\n", sep = "")
  for (s in shps) {
    df <- tryCatch(.read_dbf_attrs(s), error = function(e) NULL)
    if (is.null(df)) next
    cat("\n[", basename(s), "] ", nrow(df), " rows\n", sep = "")

    # Pick best-looking name column to preview
    name_col <- intersect(c("LONGNAME", "Name", "NAME", "PRECINCT", "Precinct"), names(df))
    if (length(name_col) > 0) {
      name_col <- name_col[[1]]
      cat("  Preview of '", name_col, "':\n", sep = "")
      print(head(df[[name_col]], n))
    } else {
      cat("  (no obvious name column — showing full first ", min(n, nrow(df)), " rows)\n", sep = "")
      print(head(df, n))
    }
  }
  invisible(NULL)
}

# Combine LONGNAME (or alternative) across all shapefiles in the county folder,
# tagged with which file each name came from. Useful for spotting duplicates.
shp_long <- function(county) {
  d <- .county_dir(county)
  shps <- list.files(d, pattern = "\\.shp$", full.names = TRUE)
  if (length(shps) == 0) return(tibble())

  out <- map_dfr(shps, function(s) {
    df <- tryCatch(.read_dbf_attrs(s), error = function(e) return(NULL))
    if (is.null(df)) return(NULL)
    name_col <- intersect(c("LONGNAME", "Name", "NAME"), names(df))
    if (length(name_col) == 0) return(NULL)
    tibble(
      source   = basename(s),
      longname = df[[name_col[[1]]]]
    )
  })

  cat("=== ", basename(d), " — ", nrow(out), " name rows from ",
      n_distinct(out$source), " file(s) ===\n", sep = "")

  # Highlight duplicates that would cause crosswalk ambiguity
  dups <- out |> count(longname, name = "occurrences") |> filter(occurrences > 1)
  if (nrow(dups) > 0) {
    cat("\nDuplicate longnames across files (cause matching ambiguity):\n")
    print(dups, n = nrow(dups))
  }

  print(out, n = nrow(out))
  invisible(out)
}

# ---- Election precinct data ----

elec_precincts <- function(county) {
  if (!file.exists(.ELEC)) stop("Election file not found: ", .ELEC)
  elec <- read_csv(.ELEC, show_col_types = FALSE)
  hits <- elec |>
    filter(str_to_lower(county) == str_to_lower(!!county)) |>
    distinct(precinct) |>
    arrange(precinct)
  cat("=== Election precincts for ", county, " (", nrow(hits), ") ===\n", sep = "")
  print(hits, n = nrow(hits))
  invisible(hits)
}

# ---- Side-by-side comparison ----

compare_names <- function(county) {
  shp_names <- shp_long(county)$longname |> sort() |> unique()
  elec_names <- {
    if (!file.exists(.ELEC)) character(0) else
      read_csv(.ELEC, show_col_types = FALSE) |>
        filter(str_to_lower(county) == str_to_lower(!!county)) |>
        pull(precinct) |> sort() |> unique()
  }

  m <- max(length(shp_names), length(elec_names))
  pad <- function(x) c(x, rep("", m - length(x)))
  side <- tibble(
    election  = pad(elec_names),
    shapefile = pad(shp_names)
  )

  cat("\n=== ", county, " — election (", length(elec_names),
      ") vs shapefile (", length(shp_names), ") ===\n", sep = "")
  print(side, n = m)
  invisible(side)
}

# ---- Optional leaflet map ----

shp_map <- function(county) {
  ok <- requireNamespace("leaflet", quietly = TRUE)
  if (!ok) stop("Install with install.packages('leaflet')")

  d <- .county_dir(county)
  shps <- list.files(d, pattern = "\\.shp$", full.names = TRUE)
  if (length(shps) == 0) { cat("No shapefiles in ", d, "\n"); return(invisible(NULL)) }

  layers <- map(shps, function(s) {
    sf_obj <- suppressWarnings(suppressMessages(st_read(s, quiet = TRUE))) |>
      st_transform(4326) |>
      mutate(.source = basename(s))
    sf_obj
  })

  # Use whichever name column exists in each layer for labels
  label_layers <- map(layers, function(L) {
    nm_col <- intersect(c("LONGNAME", "Name", "NAME"), names(L))
    L$.label <- if (length(nm_col) > 0) {
      paste0(L[[nm_col[[1]]]], "  [", L$.source, "]")
    } else {
      paste0("(no name)  [", L$.source, "]")
    }
    L
  })

  palette <- c("#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
               "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
               "#aec7e8", "#ffbb78", "#98df8a")

  m <- leaflet::leaflet() |> leaflet::addProviderTiles("CartoDB.Positron")
  for (i in seq_along(label_layers)) {
    L <- label_layers[[i]]
    m <- leaflet::addPolygons(
      m, data = L,
      weight = 1.5, color = palette[((i - 1) %% length(palette)) + 1],
      fillOpacity = 0.25,
      label = L$.label,
      group = unique(L$.source)
    )
  }
  m |> leaflet::addLayersControl(
    overlayGroups = unlist(map(label_layers, ~ unique(.x$.source))),
    options = leaflet::layersControlOptions(collapsed = FALSE)
  )
}

message("Functions: list_county_files(), shp_fields(), shp_preview(), shp_long(), ",
        "elec_precincts(), compare_names(), shp_map()")
