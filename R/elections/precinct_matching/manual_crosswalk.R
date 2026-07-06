# Interactive console tool for completing the precinct crosswalk manually.
#
# Source once per session — state is kept in .cw environment and reloaded
# from the progress file so work survives between sessions.
#
# The original precinct_crosswalk_manual.csv is never modified.
# All manual matches accumulate in precinct_crosswalk_manual_progress.csv.
#
# Typical workflow:
#   source("R/elections/manual_crosswalk.R")
#   show_remaining()               # overview of counties still needing work
#   county("Adams")                # inspect one county + print assign skeleton
#   assign_matches(c(              # fill in the skeleton and run it
#     "Adams 1" = "Precinct 1",
#     "Adams 2" = "Precinct 2"
#   ))
#   no_match()                     # whole county has no usable shapefile data
#   note("missing Carlisle precincts in shapefile")  # free-form note for current county
#   save_progress()                # persist to disk
#   show_progress()                # summary of what's been done
#   show_notes()                   # all notes recorded so far

library(dplyr)
library(tidyr)
library(readr)
library(stringr)
library(here)

.TEMPLATE <- here("data/elections/processed/precinct_crosswalk_manual.csv")
.PROGRESS <- here("data/elections/processed/precinct_crosswalk_manual_progress.csv")
.AUTO     <- here("data/elections/processed/precinct_crosswalk_auto.csv")
.ENRICHED <- here("data/elections/processed/precincts_2020s_enriched.rds")
.NOTES    <- here("data/elections/processed/precinct_crosswalk_notes.csv")

# ---- Load state ----

.cw <- new.env(parent = emptyenv())
.cw$template <- read_csv(.TEMPLATE, show_col_types = FALSE)
.cw$auto     <- read_csv(.AUTO, show_col_types = FALSE) |> select(county, shp_longname = shp_name)
.cw$current  <- NULL

if (file.exists(.ENRICHED)) {
  .cw$enriched <- readRDS(.ENRICHED) |>
    as.data.frame() |>
    dplyr::select(county, longname = LONGNAME, places, townships) |>
    dplyr::filter(!is.na(longname)) |>
    dplyr::mutate(county = stringr::str_to_title(stringr::str_replace_all(county, c(
      "Buchananan" = "Buchanan", "O Brien" = "O'Brien"
    ))))
} else {
  .cw$enriched <- NULL
  message("Note: enriched shapefile not found — run enrich_precinct_shapefiles.R for place/township context.")
}

if (file.exists(.PROGRESS)) {
  .cw$progress <- read_csv(.PROGRESS, show_col_types = FALSE)
  n_done <- nrow(.cw$progress)
  n_total <- nrow(.cw$template)
  message("Resumed: ", n_done, " / ", n_total, " precincts resolved (",
          round(100 * n_done / n_total), "%).")
} else {
  .cw$progress <- tibble(county = character(), elec_name = character(),
                         shp_longname = character())
  message("No progress file found — starting fresh.")
}

if (file.exists(.NOTES)) {
  .cw$notes <- read_csv(.NOTES, show_col_types = FALSE,
                        col_types = cols(timestamp = col_datetime()))
  message("Loaded ", nrow(.cw$notes), " note(s) across ",
          dplyr::n_distinct(.cw$notes$county), " counties.")
} else {
  .cw$notes <- tibble(county = character(),
                      timestamp = as.POSIXct(character()),
                      note = character())
}

# ---- Internal helpers ----

.unmatched <- function(co = NULL) {
  done_keys <- paste(.cw$progress$county, .cw$progress$elec_name)
  um <- filter(.cw$template, !paste(county, elec_name) %in% done_keys)
  if (!is.null(co)) um <- filter(um, county == co)
  um
}

.resolve_county <- function(name) {
  all_counties <- unique(.cw$template$county)
  exact <- all_counties[str_to_lower(all_counties) == str_to_lower(name)]
  if (length(exact) == 1) return(exact)
  partial <- all_counties[str_detect(all_counties, regex(name, ignore_case = TRUE))]
  if (length(partial) == 1) return(partial)
  if (length(partial) > 1) { cat("Multiple matches:", paste(partial, collapse = ", "), "\n"); return(NULL) }
  cat("No county matching '", name, "'\n", sep = ""); NULL
}

.shp_opts <- function(co) {
  raw <- .cw$template$available_shp_names[.cw$template$county == co][1]
  if (is.na(raw)) return(character(0))
  str_split(raw, " \\| ")[[1]]
}

# ---- Public API ----

# Overview of unfinished counties.
show_remaining <- function() {
  um <- .unmatched()
  if (nrow(um) == 0) { cat("All precincts matched!\n"); return(invisible(NULL)) }
  summary <- um |>
    count(county, name = "remaining") |>
    left_join(count(.cw$template, county, name = "total"), by = "county") |>
    mutate(pct_left = round(100 * remaining / total)) |>
    arrange(county)
  cat(sprintf("%-22s  %6s / %-6s\n", "County", "Left", "Total"))
  cat(strrep("-", 38), "\n")
  for (i in seq_len(nrow(summary))) {
    cat(sprintf("%-22s  %6d / %-6d  (%d%% left)\n",
                summary$county[i], summary$remaining[i],
                summary$total[i], summary$pct_left[i]))
  }
  cat("\nTotal:", nrow(um), "unmatched /", nrow(.cw$template), "in template\n")
  invisible(summary)
}

# Inspect a county: show unmatched precincts, available shapefile names,
# and a pre-filled assign_matches() skeleton ready to copy-edit.
# show_map = TRUE opens an interactive leaflet map with labelled precinct polygons.
county <- function(name, show_map = FALSE) {
  co <- .resolve_county(name)
  if (is.null(co)) return(invisible(NULL))
  .cw$current <- co

  um   <- .unmatched(co)
  done <- filter(.cw$progress, county == co)
  opts <- .shp_opts(co)

  cat("\n===", co, "===\n")

  co_notes <- filter(.cw$notes, county == co)
  if (nrow(co_notes) > 0) {
    cat("\nNotes (", nrow(co_notes), "):\n", sep = "")
    for (i in seq_len(nrow(co_notes))) {
      cat("  [", format(co_notes$timestamp[i], "%Y-%m-%d"), "] ",
          co_notes$note[i], "\n", sep = "")
    }
  }

  if (nrow(done) > 0) {
    cat("\nAlready recorded (", nrow(done), "):\n", sep = "")
    for (i in seq_len(nrow(done))) {
      label <- if (is.na(done$shp_longname[i])) "[no match]" else done$shp_longname[i]
      cat("  ", done$elec_name[i], " -> ", label, "\n", sep = "")
    }
  }

  if (nrow(um) == 0) {
    cat("\nAll precincts in this county are resolved.\n")
    return(invisible(list(unmatched = um, available = opts)))
  }

  if (length(opts) > 0) {
    already_used <- bind_rows(
      filter(.cw$auto,     county == co) |> select(shp_longname),
      filter(.cw$progress, county == co) |> select(shp_longname)
    ) |> pull(shp_longname) |> na.omit()

    if (!is.null(.cw$enriched)) {
      tbl <- filter(.cw$enriched, county == co) |>
        mutate(
          Precinct  = paste0(longname, ifelse(longname %in% already_used, " *", "")),
          Places    = ifelse(is.na(places),    "-", places),
          Townships = ifelse(is.na(townships), "-", str_remove_all(townships, " Township"))
        ) |>
        select(Precinct, Places, Townships)

      # Column widths: cap Places and Townships at 40 chars to keep table readable
      trunc40 <- function(x) ifelse(nchar(x) > 40, paste0(substr(x, 1, 37), "..."), x)
      tbl$Places    <- trunc40(tbl$Places)
      tbl$Townships <- trunc40(tbl$Townships)

      w1 <- max(nchar(c("Precinct",  tbl$Precinct)))
      w2 <- max(nchar(c("Places",    tbl$Places)))
      w3 <- max(nchar(c("Townships", tbl$Townships)))

      cat("\nShapefile precincts (", nrow(tbl), "; * = already matched):\n", sep = "")
      cat(sprintf("  %-*s  %-*s  %s\n", w1, "Precinct", w2, "Places", "Townships"))
      cat("  ", strrep("-", w1 + w2 + w3 + 4), "\n", sep = "")
      for (i in seq_len(nrow(tbl))) {
        cat(sprintf("  %-*s  %-*s  %s\n", w1, tbl$Precinct[i], w2, tbl$Places[i], tbl$Townships[i]))
      }
    } else {
      cat("\nAvailable shapefile names (", length(opts), "; * = already matched):\n", sep = "")
      for (opt in opts) {
        marker <- if (opt %in% already_used) " *" else ""
        cat("  ", opt, marker, "\n", sep = "")
      }
    }
  } else {
    cat("\n[No shapefile data for this county — use no_match()]\n")
  }

  # Optional leaflet map
  if (show_map) {
    ok <- requireNamespace("leaflet", quietly = TRUE) && requireNamespace("sf", quietly = TRUE)
    if (!ok) {
      cat("\nInstall missing packages: install.packages(c('leaflet', 'sf'))\n")
    } else {
      county_fixes <- c("Buchananan" = "Buchanan", "O Brien" = "O'Brien")
      shp_sf <- readRDS(here("data/elections/processed/precincts_2020s.rds")) |>
        dplyr::mutate(county = stringr::str_to_title(stringr::str_replace_all(county, county_fixes))) |>
        dplyr::filter(county == co, !is.na(LONGNAME))

      if (nrow(shp_sf) == 0) {
        cat("\nNo shapefile polygons found for", co, "\n")
      } else {
        shp_sf <- sf::st_transform(shp_sf, 4326)
        labels <- ifelse(
          !is.na(shp_sf$SHORTNAME) & shp_sf$SHORTNAME != shp_sf$LONGNAME,
          paste0(shp_sf$LONGNAME, " (", shp_sf$SHORTNAME, ")"),
          shp_sf$LONGNAME
        )
        m <- leaflet::leaflet(shp_sf) |>
          leaflet::addProviderTiles("CartoDB.Positron") |>
          leaflet::addPolygons(
            weight     = 1.5,
            color      = "#444",
            fillColor  = "#88aacc",
            fillOpacity = 0.2,
            label      = labels,
            labelOptions = leaflet::labelOptions(
              permanent  = TRUE,
              textsize   = "11px",
              direction  = "center",
              noHide     = TRUE,
              style      = list("font-weight" = "bold", "background" = "transparent",
                                "border" = "none", "box-shadow" = "none")
            )
          )
        print(m)
      }
    }
  }

  # Build assign_matches() skeleton and copy to clipboard
  nms <- um$elec_name
  lines <- character(length(nms))
  for (i in seq_along(nms)) {
    comma <- if (i < length(nms)) "," else ""
    lines[i] <- paste0('  "', nms[i], '" = ""', comma)
  }
  skeleton <- paste0(c("assign_matches(c(", lines, "))"), collapse = "\n")
  writeClipboard(skeleton)
  cat("\nassign_matches() template copied to clipboard (", nrow(um), " precincts).\n", sep = "")

  invisible(list(unmatched = um, available = opts))
}

# Record manual matches for the current county (or specify co=).
# Values are shapefile LONGNAME strings. Use NA for "no match available".
#
# Example:
#   assign_matches(c("Adams 1" = "Precinct 1", "Adams 2" = NA))
assign_matches <- function(matches, co = .cw$current) {
  if (is.null(co)) stop("No county selected. Call county() first or pass co=.")
  co <- .resolve_county(co)
  if (is.null(co)) return(invisible(NULL))

  data <- filter(.cw$template, county == co)
  opts <- .shp_opts(co)

  elec_names <- names(matches)
  shp_names  <- unname(matches)

  # Validate election precinct names exist in template
  bad_elec <- setdiff(elec_names, data$elec_name)
  if (length(bad_elec) > 0) {
    cat("Election precinct(s) not found in template for", co, ":\n")
    cat(paste(" ", bad_elec, collapse = "\n"), "\n")
    stop("Fix names above.")
  }

  # Validate shapefile names (non-NA values must exist in available set)
  non_na_shp <- shp_names[!is.na(shp_names)]
  bad_shp <- if (length(opts) > 0) setdiff(non_na_shp, opts) else character(0)
  if (length(bad_shp) > 0) {
    cat("Shapefile name(s) not in available set for", co, ":\n")
    cat(paste(" ", bad_shp, collapse = "\n"), "\n")
    cat("Available:\n", paste(" ", opts, collapse = "\n"), "\n")
    stop("Fix shapefile names above.")
  }

  new_rows <- tibble(county = co, elec_name = elec_names, shp_longname = shp_names)

  # Allow corrections by replacing any existing entry for these precincts
  existing_keys <- paste(.cw$progress$county, .cw$progress$elec_name)
  new_keys      <- paste(new_rows$county, new_rows$elec_name)
  .cw$progress  <- .cw$progress[!existing_keys %in% new_keys, ]
  .cw$progress  <- bind_rows(.cw$progress, new_rows) |> arrange(county, elec_name)

  cat("Recorded:", sum(!is.na(shp_names)), "match(es),",
      sum(is.na(shp_names)), "no-match(es) for", co, "\n")
  cat("Run save_progress() to write to disk.\n")
  invisible(.cw$progress)
}

# Mark all remaining unmatched precincts in a county as having no shapefile match.
no_match <- function(co = .cw$current) {
  if (is.null(co)) stop("No county selected. Call county() first or pass co=.")
  co <- .resolve_county(co)
  if (is.null(co)) return(invisible(NULL))

  um <- .unmatched(co)
  if (nrow(um) == 0) { cat("No unmatched precincts in", co, "\n"); return(invisible(NULL)) }

  assign_matches(setNames(rep(NA_character_, nrow(um)), um$elec_name), co = co)
}

# Record a free-form note about a county. Notes accumulate (multiple notes per
# county allowed) and are written to disk immediately — no save step needed.
# Defaults to the currently-inspected county; pass co= to override.
#
# Examples:
#   county("Polk"); note("Norwalk precincts missing from shapefile")
#   note("Iowa Falls 7 & 8 only available as map images", co = "Hardin")
note <- function(text, co = .cw$current) {
  if (is.null(co)) stop("No county selected. Call county() first or pass co=.")
  if (!nzchar(trimws(text))) stop("Note text is empty.")
  co <- .resolve_county(co)
  if (is.null(co)) return(invisible(NULL))

  .cw$notes <- bind_rows(
    .cw$notes,
    tibble(county = co, timestamp = Sys.time(), note = text)
  ) |> arrange(county, timestamp)

  write_csv(.cw$notes, .NOTES)
  n <- sum(.cw$notes$county == co)
  cat("Note recorded for ", co, " (", n, " total). Saved to disk.\n", sep = "")
  invisible(.cw$notes)
}

# Display recorded notes. Pass a county name to filter, or call with no
# arguments to see all notes grouped by county.
show_notes <- function(co = NULL) {
  if (nrow(.cw$notes) == 0) {
    cat("No notes recorded yet. Use note(\"...\") to add one.\n")
    return(invisible(NULL))
  }

  notes_df <- .cw$notes
  if (!is.null(co)) {
    co <- .resolve_county(co)
    if (is.null(co)) return(invisible(NULL))
    notes_df <- filter(notes_df, county == !!co)
    if (nrow(notes_df) == 0) {
      cat("No notes for ", co, ".\n", sep = "")
      return(invisible(NULL))
    }
  }

  for (current_co in unique(notes_df$county)) {
    cat("\n=== ", current_co, " ===\n", sep = "")
    rows <- filter(notes_df, county == current_co) |> arrange(timestamp)
    for (i in seq_len(nrow(rows))) {
      cat("  [", format(rows$timestamp[i], "%Y-%m-%d %H:%M"), "] ",
          rows$note[i], "\n", sep = "")
    }
  }
  cat("\n", nrow(notes_df), " note(s) across ",
      dplyr::n_distinct(notes_df$county), " counties.\n", sep = "")
  invisible(notes_df)
}

# Write current progress to disk.
save_progress <- function() {
  write_csv(.cw$progress, .PROGRESS)
  n <- nrow(.cw$progress)
  total <- nrow(.cw$template)
  message("Saved ", n, " / ", total, " rows to ", basename(.PROGRESS),
          " (", round(100 * n / total), "% complete).")
  invisible(.cw$progress)
}

# Summary table of matched vs unmatched by county.
# hide_complete = TRUE omits counties where all precincts are resolved.
show_progress <- function(hide_complete = TRUE) {
  done_keys <- paste(.cw$progress$county, .cw$progress$elec_name)
  note_counts <- .cw$notes |> count(county, name = "notes")

  tbl <- .cw$template |>
    mutate(resolved = paste(county, elec_name) %in% done_keys) |>
    count(county, resolved) |>
    mutate(status = if_else(resolved, "matched", "remaining")) |>
    select(-resolved) |>
    pivot_wider(names_from = status, values_from = n, values_fill = 0L)

  # Ensure both columns exist regardless of pivot pivot output
  if (!"matched"   %in% names(tbl)) tbl$matched   <- 0L
  if (!"remaining" %in% names(tbl)) tbl$remaining <- 0L

  tbl <- tbl |>
    mutate(total = matched + remaining,
           pct   = round(100 * matched / total)) |>
    left_join(note_counts, by = "county") |>
    mutate(notes = coalesce(notes, 0L)) |>
    arrange(county)

  if (hide_complete) tbl <- filter(tbl, remaining > 0 | notes > 0)

  print(tbl, n = 99)

  n <- nrow(.cw$progress)
  total <- nrow(.cw$template)
  cat("\nOverall: ", n, " / ", total, " (", round(100 * n / total), "% )",
      "  ·  ", nrow(.cw$notes), " note(s)\n", sep = "")
  invisible(.cw$progress)
}

message("Functions: show_remaining(), county(name), assign_matches(c(...)), ",
        "no_match(), note(text), show_notes(), save_progress(), show_progress()")
