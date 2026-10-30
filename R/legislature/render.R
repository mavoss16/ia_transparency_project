# render.R
# Script to render all bill and legislator pages from templates
# Supports incremental rendering using LegiScan hash values
#
# Usage: Run this script from the project root directory
#   source("R/legislature/render.R")
#
# Or run specific functions:
#   render_all_bills()
#   render_all_legislators()
#   render_site()  # renders everything

library(readr)
library(dplyr)
library(stringr)
library(jsonlite)
library(quarto)
library(here)

source(here("R/legislature/utils.R"))

# Configuration
OUTPUT_DIR <- here("docs")
LEGISLATORS_DIR <- file.path(OUTPUT_DIR, "legislators")
# Weekly activity pages. Kept one level below docs/, like the legislator
# pages: Quarto writes site_libs and navbar paths relative to the template's
# render location, so a page must end up exactly as deep as it was rendered.
ACTIVITY_DIR <- file.path(OUTPUT_DIR, "activity")
MANIFEST_FILE <- here("render_manifest.csv")

# Bill and committee pages sit two levels down (docs/legislation/ga91/), so
# their templates live one level deeper too (site/templates/session/) and
# render to docs/templates/session/, giving them ../../ asset paths.
SESSION_TEMPLATE_DIR <- here("site/templates/session")
SESSION_RENDER_DIR <- here("docs/templates/session")

#' A session's bill page directory: docs/legislation/ga91
bill_output_dir <- function(ga = CURRENT_GA) file.path(OUTPUT_DIR, "legislation", ga_slug(ga))

#' A session's committee page directory: docs/committees/ga91
committee_output_dir <- function(ga = CURRENT_GA) file.path(OUTPUT_DIR, "committees", ga_slug(ga))

# Ensure output directories exist
ensure_dirs <- function(ga = CURRENT_GA) {
  dir.create(bill_output_dir(ga), recursive = TRUE, showWarnings = FALSE)
  dir.create(LEGISLATORS_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(committee_output_dir(ga), recursive = TRUE, showWarnings = FALSE)
  dir.create(ACTIVITY_DIR, recursive = TRUE, showWarnings = FALSE)
}

#' Load or create the render manifest
#' Tracks which items have been rendered and their hash at render time.
#' Bills and committees are keyed by session_item_id() ("ga91/HF1"), since
#' their numbers and IDs repeat across General Assemblies; legislators
#' (people_id) and weeks (a date) are unique on their own.
load_manifest <- function() {
  if (file.exists(MANIFEST_FILE)) {
    # Explicit types so a manifest holding only numeric ids (legislators,
    # committees) still reads `id` as character, matching update_manifest()
    read_csv(MANIFEST_FILE, col_types = cols(
      type = col_character(),
      id = col_character(),
      hash = col_character(),
      rendered_at = col_datetime()
    ))
  } else {
    # rendered_at must be a datetime, as update_manifest() writes Sys.time();
    # a character column here makes the first bind_rows() after
    # clear_manifest() fail
    tibble(
      type = character(),
      id = character(),
      hash = character(),
      rendered_at = as.POSIXct(character())
    )
  }
}

#' Save the render manifest (with retry for Windows file locks)
save_manifest <- function(manifest, max_retries = 5, wait_seconds = 2) {
  for (i in seq_len(max_retries)) {
    result <- tryCatch({
      write_csv(manifest, MANIFEST_FILE)
      TRUE
    }, error = function(e) {
      if (i < max_retries) {
        message(sprintf("Manifest write failed (attempt %d/%d), retrying in %ds...",
                        i, max_retries, wait_seconds))
        Sys.sleep(wait_seconds)
      }
      FALSE
    })
    if (result) return(invisible(NULL))
  }
  # Final attempt — let the error propagate
  write_csv(manifest, MANIFEST_FILE)
}

#' Update manifest with a rendered item
update_manifest <- function(manifest, type, id, hash) {
  # Remove existing entry if present
  manifest <- manifest |>
    filter(!(type == !!type & id == !!id))

  # Add new entry
  manifest <- manifest |>
    bind_rows(tibble(
      type = type,
      id = id,
      hash = hash,
      rendered_at = Sys.time()
    ))

  manifest
}

#' Fingerprint each bill's lobbyist declarations
#'
#' Bill pages show lobbyist declarations, which change independently of
#' LegiScan's change_hash (a declaration can be filed on a bill that hasn't
#' moved), so the bill hash has to cover them too.
#' @param ga General Assembly
#' @param path Lobbyist declarations RDS
#' @return Named character vector: bill number -> hash of its declarations
lobby_digests <- function(ga = CURRENT_GA,
                          path = file.path(ga_paths(ga)$lobbying, "lobbyist_declarations.rds")) {
  if (!file.exists(path)) return(character(0))

  digests <- readRDS(path) |>
    filter(!is.na(client)) |>
    # Hash plain text, not the data frame, so column attributes (timezone,
    # tibble class) can't change the fingerprint when the content hasn't
    mutate(row = paste(client, most_recent_declaration,
                       format(date, "%Y-%m-%d %H:%M"), sep = "\t")) |>
    arrange(bill, row) |>
    group_by(bill) |>
    summarise(digest = rlang::hash(row), .groups = "drop")

  setNames(digests$digest, digests$bill)
}

# Read once per R session and General Assembly, not once per bill
.lobby_digest_cache <- new.env()

get_lobby_digest <- function(bill_number, ga = CURRENT_GA) {
  key <- ga_slug(ga)
  if (is.null(.lobby_digest_cache[[key]])) {
    .lobby_digest_cache[[key]] <- lobby_digests(ga)
  }
  digest <- .lobby_digest_cache[[key]][bill_number]
  if (is.na(digest)) "none" else unname(digest)
}

#' Get the hash for a bill: LegiScan change_hash + lobbying fingerprint
get_bill_hash <- function(bill_number, ga = CURRENT_GA) {
  json_path <- file.path(ga_paths(ga)$bill_json, paste0(bill_number, ".json"))
  if (file.exists(json_path)) {
    bill_data <- read_json(json_path)
    return(paste0(bill_data$bill$change_hash, "|", get_lobby_digest(bill_number, ga)))
  }
  return(NA_character_)
}

#' Fingerprint every weekly activity page
#'
#' A week page shows its own actions, but also each active group's lead
#' bill, title and *current* status, links to its neighbouring weeks, and
#' (newest week only) the date the data runs through. Any of those can change
#' without the week's actions changing, so the hash covers all of them.
#' Hashes plain text, as lobby_digests() does, so object attributes can't
#' move the fingerprint.
#' @param ga General Assembly
#' @return Named character vector: "YYYY-MM-DD" (week's Monday) -> hash
week_digests <- function(ga = CURRENT_GA) {
  bill_actions <- readRDS(file.path(ga_paths(ga)$bills, "bill_actions.rds"))
  groups <- readRDS(file.path(ga_paths(ga)$bills, "groups.rds"))
  bills <- read_csv(ga_csv("bills", ga),
                    col_select = c(bill_number, title), show_col_types = FALSE)

  weeks <- sort(unique(bill_actions$week_start))
  data_through <- max(bill_actions$date)

  group_text <- groups |>
    distinct(bill_group_id, lead_bill, group_status) |>
    left_join(bills, by = c("lead_bill" = "bill_number")) |>
    transmute(bill_group_id, group_row = paste(lead_bill, group_status, title, sep = "\t"))

  per_week <- bill_actions |>
    left_join(group_text, by = "bill_group_id") |>
    mutate(row = paste(bill, bill_group_id, date, sequence, chamber, action,
                       milestone, counts_as_introduction, group_row, sep = "\t")) |>
    arrange(week_start, row) |>
    group_by(week_start) |>
    summarise(rows = list(row), .groups = "drop")

  digests <- vapply(seq_along(weeks), function(i) {
    context <- c(
      prev = if (i > 1) format(weeks[i - 1]) else "",
      `next` = if (i < length(weeks)) format(weeks[i + 1]) else "",
      through = if (i == length(weeks)) format(data_through) else ""
    )
    rlang::hash(c(context, per_week$rows[[i]]))
  }, character(1))

  setNames(digests, format(weeks))
}

#' Get the hash for a legislator from their JSON file
get_legislator_hash <- function(people_id, ga = CURRENT_GA) {
  json_path <- file.path(ga_paths(ga)$people_json, paste0(people_id, ".json"))
  if (file.exists(json_path)) {
    person_data <- read_json(json_path)
    return(person_data$person$person_hash)
  }
  return(NA_character_)
}

#' Check if a bill needs rendering (hash changed or never rendered)
needs_render_bill <- function(bill_number, manifest, ga = CURRENT_GA) {
  current_hash <- get_bill_hash(bill_number, ga)
  if (is.na(current_hash)) return(FALSE)  # No JSON file

  existing <- manifest |>
    filter(type == "bill", id == session_item_id(ga, bill_number))

  if (nrow(existing) == 0) return(TRUE)  # Never rendered

  return(existing$hash[1] != current_hash)  # Hash changed
}

#' Check if a legislator needs rendering (hash changed or never rendered)
needs_render_legislator <- function(people_id, manifest, ga = CURRENT_GA) {
  current_hash <- get_legislator_hash(people_id, ga)
  if (is.na(current_hash)) return(FALSE)  # No JSON file

  existing <- manifest |>
    filter(type == "legislator", id == as.character(people_id))

  if (nrow(existing) == 0) return(TRUE)  # Never rendered

  return(existing$hash[1] != current_hash)  # Hash changed
}

#' Render a single bill page
#' @param bill_number Character string like "HF856"
#' @param ga General Assembly
#' @param template_path Path to bill_template.qmd
render_bill <- function(bill_number, ga = CURRENT_GA,
                        template_path = file.path(SESSION_TEMPLATE_DIR, "bill_template.qmd")) {
  output_file <- file.path(bill_output_dir(ga), paste0(bill_number, ".html"))
  # Prefixed with the session so two sessions' HF1 never share a render
  # name (and with it a figure directory) in docs/templates/session/
  render_name <- paste0(ga_slug(ga), "-", bill_number, ".html")
  rendered_file <- file.path(SESSION_RENDER_DIR, render_name)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = render_name,
      execute_params = list(bill_num = bill_number, ga = ga),
      output_format = "html",
      metadata = list(search = FALSE),  # Avoid search.json file lock on Windows
      as_job = FALSE
    )

    # Move rendered file to correct location
    if (!file.exists(rendered_file) || !file.rename(rendered_file, output_file)) {
      stop("rendered page could not be moved to ", output_file)
    }

    message(paste("Rendered:", bill_number))
    return(TRUE)
  }, error = function(e) {
    warning(paste("Failed to render", bill_number, ":", e$message))
    return(FALSE)
  })
}

#' Render a single weekly activity page
#' @param week_start Date or "YYYY-MM-DD" string: the week's Monday
#' @param template_path Path to week_template.qmd
render_week <- function(week_start, ga = CURRENT_GA,
                        template_path = here("site/templates/week_template.qmd")) {
  week_id <- format(as.Date(week_start), "%Y-%m-%d")
  output_file <- file.path(ACTIVITY_DIR, paste0(week_id, ".html"))
  rendered_file <- here("docs/templates", basename(output_file))
  dir.create(ACTIVITY_DIR, recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = basename(output_file),
      execute_params = list(week_start = week_id, ga = ga),
      output_format = "html",
      metadata = list(search = FALSE),  # Avoid search.json file lock on Windows
      as_job = FALSE
    )

    if (file.exists(rendered_file)) {
      file.rename(rendered_file, output_file)
    }

    message(paste("Rendered week:", week_id))
    return(TRUE)
  }, error = function(e) {
    warning(paste("Failed to render week", week_id, ":", e$message))
    return(FALSE)
  })
}

#' Render a single legislator page
#' @param people_id Numeric ID for the legislator
#' @param template_path Path to legislator_template.qmd
render_legislator <- function(people_id, ga = CURRENT_GA,
                              template_path = here("site/templates/legislator_template.qmd")) {
  filename <- get_legislator_filename(people_id, read_csv(ga_csv("people", ga), show_col_types = FALSE))
  output_file <- file.path(LEGISLATORS_DIR, paste0(filename, ".html"))
  rendered_file <- here("docs/templates", basename(output_file))

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = basename(output_file),
      execute_params = list(people_id = people_id, ga = ga),
      output_format = "html",
      metadata = list(search = FALSE),  # Avoid search.json file lock on Windows
      as_job = FALSE
    )

    # Move rendered file to correct location
    if (file.exists(rendered_file)) {
      file.rename(rendered_file, output_file)
    }

    message(paste("Rendered legislator:", filename))
    return(TRUE)
  }, error = function(e) {
    warning(paste("Failed to render legislator", people_id, ":", e$message))
    return(FALSE)
  })
}

#' Get the hash for a committee from its JSON file
get_committee_hash <- function(people_id, ga = CURRENT_GA) {
  get_legislator_hash(people_id, ga)  # Same JSON structure
}

#' Check if a committee needs rendering (hash changed or never rendered)
needs_render_committee <- function(people_id, manifest, ga = CURRENT_GA) {
  current_hash <- get_committee_hash(people_id, ga)
  if (is.na(current_hash)) return(FALSE)

  existing <- manifest |>
    filter(type == "committee", id == session_item_id(ga, people_id))

  if (nrow(existing) == 0) return(TRUE)

  return(existing$hash[1] != current_hash)
}

#' Render a single committee page
#' @param people_id Numeric ID for the committee (from people.csv)
#' @param ga General Assembly
#' @param template_path Path to committee_template.qmd
render_committee <- function(people_id, ga = CURRENT_GA,
                             template_path = file.path(SESSION_TEMPLATE_DIR, "committee_template.qmd")) {
  filename <- get_committee_filename(people_id, read_csv(ga_csv("people", ga), show_col_types = FALSE))
  output_file <- file.path(committee_output_dir(ga), paste0(filename, ".html"))
  render_name <- paste0(ga_slug(ga), "-", filename, ".html")
  rendered_file <- file.path(SESSION_RENDER_DIR, render_name)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = render_name,
      execute_params = list(people_id = people_id, ga = ga),
      output_format = "html",
      metadata = list(search = FALSE),  # Avoid search.json file lock on Windows
      as_job = FALSE
    )

    # Move rendered file to correct location
    if (!file.exists(rendered_file) || !file.rename(rendered_file, output_file)) {
      stop("rendered page could not be moved to ", output_file)
    }

    message(paste("Rendered committee:", filename))
    return(TRUE)
  }, error = function(e) {
    warning(paste("Failed to render committee", people_id, ":", e$message))
    return(FALSE)
  })
}

#' Render all committee pages (incremental by default)
#' @param limit Optional limit for testing (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
render_all_committees <- function(limit = NULL, force = FALSE, ga = CURRENT_GA) {
  ensure_dirs(ga)
  manifest <- load_manifest()

  people <- read_csv(ga_csv("people", ga), show_col_types = FALSE)
  committees <- people |> filter(is.na(first_name) | first_name == "", committee_id > 0)
  committee_ids <- committees$people_id

  if (!is.null(limit)) {
    committee_ids <- head(committee_ids, limit)
  }

  if (!force) {
    needs_render <- sapply(committee_ids, needs_render_committee, manifest = manifest, ga = ga)
    committees_to_render <- committee_ids[needs_render]
    message(paste(
      "Found", length(committees_to_render), "committees needing render out of",
      length(committee_ids), "total"
    ))
  } else {
    committees_to_render <- committee_ids
    message(paste("Force rendering all", length(committees_to_render), "committees..."))
  }

  if (length(committees_to_render) == 0) {
    message("No committees need rendering. Use force = TRUE to re-render all.")
    return(invisible(list(success = 0, failed = 0, failed_items = character(0))))
  }

  success_count <- 0
  fail_count <- 0
  failed_items <- character(0)

  for (people_id in committees_to_render) {
    success <- render_committee(people_id, ga)

    if (success) {
      current_hash <- get_committee_hash(people_id, ga)
      manifest <- update_manifest(manifest, "committee", session_item_id(ga, people_id), current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
      failed_items <- c(failed_items, as.character(people_id))
    }
    gc()
  }

  message(paste("\nCommittees completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count, failed_items = failed_items)))
}

#' Render all bill pages (incremental by default)
#' @param limit Optional limit for testing (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
#' @param deadline POSIXct after which no new bill is started (Inf = no limit).
#'   Bills not reached stay out of the manifest, so the next run picks them up.
render_all_bills <- function(limit = NULL, force = FALSE, deadline = Inf, ga = CURRENT_GA) {
  ensure_dirs(ga)
  manifest <- load_manifest()

  # Most recently active first: when the time budget stops a run partway
  # (e.g. a backlog after a full re-render), the bills the home page and
  # recent-activity links point at are already done
  bills <- read_csv(ga_csv("bills", ga), show_col_types = FALSE) |>
    arrange(desc(last_action_date), bill_number)
  bill_numbers <- bills$bill_number

  if (!is.null(limit)) {
    bill_numbers <- head(bill_numbers, limit)
  }

  # Filter to only bills that need rendering (unless force = TRUE)
  if (!force) {
    needs_render <- sapply(bill_numbers, needs_render_bill, manifest = manifest, ga = ga)
    bills_to_render <- bill_numbers[needs_render]
    message(paste(
      "Found", length(bills_to_render), "bills needing render out of",
      length(bill_numbers), "total"
    ))
  } else {
    bills_to_render <- bill_numbers
    message(paste("Force rendering all", length(bills_to_render), "bills..."))
  }

  if (length(bills_to_render) == 0) {
    message("No bills need rendering. Use force = TRUE to re-render all.")
    return(invisible(list(success = 0, failed = 0, failed_items = character(0))))
  }

  success_count <- 0
  fail_count <- 0
  failed_items <- character(0)

  total_to_render <- length(bills_to_render)

  for (i in seq_along(bills_to_render)) {
    if (Sys.time() > deadline) {
      message(paste0(
        "
Time budget reached after ", i - 1, "/", total_to_render,
        " bills; ", total_to_render - i + 1, " left for the next run."
      ))
      break
    }

    bill_number <- bills_to_render[i]
    success <- render_bill(bill_number, ga)

    if (success) {
      # Update manifest with new hash
      current_hash <- get_bill_hash(bill_number, ga)
      manifest <- update_manifest(manifest, "bill", session_item_id(ga, bill_number), current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
      failed_items <- c(failed_items, bill_number)
    }
    gc()

    if (i %% 100 == 0 && i < total_to_render) {
      message(paste0("  Progress: ", i, "/", total_to_render))
    }
  }

  message(paste("\nBills completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count, failed_items = failed_items)))
}

#' Render all weekly activity pages (incremental by default)
#'
#' One page per week with any recorded action, newest first. Weeks run
#' before bills in render_site(): there are only ~50 per GA, the current
#' week changes daily, and the home page will link to it.
#' @param weeks Optional vector of week Mondays to consider (NULL = all)
#' @param force If TRUE, re-render regardless of hash
render_all_weeks <- function(weeks = NULL, force = FALSE, ga = CURRENT_GA) {
  ensure_dirs(ga)
  manifest <- load_manifest()
  digests <- week_digests(ga)

  week_ids <- rev(names(digests))  # newest first
  if (!is.null(weeks)) week_ids <- intersect(week_ids, format(as.Date(weeks)))

  if (!force) {
    rendered <- manifest |> filter(type == "week")
    old_hash <- rendered$hash[match(week_ids, rendered$id)]
    weeks_to_render <- week_ids[is.na(old_hash) | old_hash != digests[week_ids]]
    message(paste("Found", length(weeks_to_render), "weeks needing render out of",
                  length(week_ids), "total"))
  } else {
    weeks_to_render <- week_ids
    message(paste("Force rendering", length(weeks_to_render), "weeks..."))
  }

  success_count <- 0
  fail_count <- 0
  failed_items <- character(0)

  for (week_id in weeks_to_render) {
    if (render_week(week_id, ga)) {
      manifest <- update_manifest(manifest, "week", week_id, unname(digests[week_id]))
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
      failed_items <- c(failed_items, week_id)
    }
    gc()
  }

  message(paste("\nWeeks completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count, failed_items = failed_items)))
}

#' Render all legislator pages (incremental by default)
#' @param limit Optional limit for testing (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
render_all_legislators <- function(limit = NULL, force = FALSE, ga = CURRENT_GA) {
  ensure_dirs(ga)
  manifest <- load_manifest()

  people <- read_csv(ga_csv("people", ga), show_col_types = FALSE)
  # Exclude committees (have empty first_name/last_name)
  legislators <- people |> filter(!is.na(first_name), first_name != "")
  people_ids <- legislators$people_id

  if (!is.null(limit)) {
    people_ids <- head(people_ids, limit)
  }

  # Filter to only legislators that need rendering (unless force = TRUE)
  if (!force) {
    needs_render <- sapply(people_ids, needs_render_legislator, manifest = manifest, ga = ga)
    legislators_to_render <- people_ids[needs_render]
    message(paste(
      "Found", length(legislators_to_render), "legislators needing render out of",
      length(people_ids), "total"
    ))
  } else {
    legislators_to_render <- people_ids
    message(paste("Force rendering all", length(legislators_to_render), "legislators..."))
  }

  if (length(legislators_to_render) == 0) {
    message("No legislators need rendering. Use force = TRUE to re-render all.")
    return(invisible(list(success = 0, failed = 0, failed_items = character(0))))
  }

  success_count <- 0
  fail_count <- 0
  failed_items <- character(0)

  for (people_id in legislators_to_render) {
    success <- render_legislator(people_id, ga)

    if (success) {
      # Update manifest with new hash
      current_hash <- get_legislator_hash(people_id, ga)
      manifest <- update_manifest(manifest, "legislator", as.character(people_id), current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
      failed_items <- c(failed_items, as.character(people_id))
    }
    gc()
  }

  message(paste("\nLegislators completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count, failed_items = failed_items)))
}

#' Write a status JSON file to docs/ summarising the most recent render run
#' @param render_time POSIXct timestamp of when the render started
#' @param bills_result List with success, failed, failed_items from render_all_bills()
#' @param legislators_result List with success, failed, failed_items from render_all_legislators()
#' @param committees_result List with success, failed, failed_items from render_all_committees()
#' @param weeks_result List with success, failed, failed_items from render_all_weeks()
write_status <- function(render_time, bills_result, legislators_result, committees_result,
                         weeks_result = NULL) {
  normalize <- function(r) {
    if (is.null(r)) list(success = 0, failed = 0, failed_items = character(0))
    else r
  }
  bills_result       <- normalize(bills_result)
  legislators_result <- normalize(legislators_result)
  committees_result  <- normalize(committees_result)
  weeks_result       <- normalize(weeks_result)

  status <- list(
    last_render = format(render_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    session = ga_slug(CURRENT_GA),
    bills = list(
      rendered     = bills_result$success,
      failed       = bills_result$failed,
      failed_items = as.list(bills_result$failed_items)
    ),
    legislators = list(
      rendered     = legislators_result$success,
      failed       = legislators_result$failed,
      failed_items = as.list(legislators_result$failed_items)
    ),
    committees = list(
      rendered     = committees_result$success,
      failed       = committees_result$failed,
      failed_items = as.list(committees_result$failed_items)
    ),
    weeks = list(
      rendered     = weeks_result$success,
      failed       = weeks_result$failed,
      failed_items = as.list(weeks_result$failed_items)
    )
  )

  status_path <- file.path(OUTPUT_DIR, "status.json")
  write_json(status, status_path, auto_unbox = TRUE, pretty = TRUE)
  message(paste("Status written to", status_path))
}

#' Render the main Quarto site (index pages)
render_index_pages <- function() {
  message("Rendering main site pages...")
  withr::with_dir(here("site"), quarto_render(as_job = FALSE))
  message("Main site pages complete.")
}

#' Render everything: index pages, all bills, legislators, and committees
#' @param bills_limit Optional limit for bills (NULL for all)
#' @param legislators_limit Optional limit for legislators (NULL for all)
#' @param committees_limit Optional limit for committees (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
#' @param time_budget_minutes Stop starting new bills this many minutes after the
#'   render begins, so a CI job can commit its progress before the runner's time
#'   limit. Defaults to the RENDER_TIME_BUDGET_MINUTES env var, else no limit.
#'   Legislators and committees always render in full after the bills.
#' @param weeks Optional vector of week Mondays to limit weekly pages to
#'   (NULL = all weeks). Weeks render before bills and outside the budget.
render_site <- function(bills_limit = NULL, legislators_limit = NULL, committees_limit = NULL, force = FALSE,
                        time_budget_minutes = as.numeric(Sys.getenv("RENDER_TIME_BUDGET_MINUTES", "Inf")),
                        weeks = NULL) {
  render_start <- Sys.time()
  bills_deadline <- render_start + time_budget_minutes * 60
  message("=== Starting full site render ===\n")

  # Render main quarto site first (includes the weekly activity archive)
  render_index_pages()

  message("\n")

  # Weekly activity pages (incremental unless force = TRUE)
  weeks_result <- render_all_weeks(weeks = weeks, force = force)

  message("\n")

  # Render bills (incremental unless force = TRUE)
  bills_result <- render_all_bills(limit = bills_limit, force = force, deadline = bills_deadline)

  message("\n")

  # Render legislators (incremental unless force = TRUE)
  legislators_result <- render_all_legislators(limit = legislators_limit, force = TRUE)

  message("\n")

  # Render committees (incremental unless force = TRUE)
  committees_result <- render_all_committees(limit = committees_limit, force = TRUE)

  # Write status summary for the status page
  write_status(render_start, bills_result, legislators_result, committees_result, weeks_result)

  message("\n=== Site render complete ===")
}

#' Quick test render - renders 5 bills, 5 legislators, 3 committees, and 2
#' weeks (one committee-heavy, one floor/governor-heavy)
test_render <- function() {
  message("Running test render (5 bills, 5 legislators, 3 committees, 2 weeks)...\n")
  render_site(bills_limit = 5, legislators_limit = 5, committees_limit = 3, force = TRUE,
              weeks = c("2026-02-16", "2026-04-27"))
}

#' Render a sample of bills, legislators, and committees
#' @param n_bills Number of bills to render (default 5)
#' @param n_legislators Number of legislators to render (default 5)
#' @param n_committees Number of committees to render (default 3)
#' @param random If TRUE, sample randomly; if FALSE, take first n (default FALSE)
#' @param index_pages If TRUE, also render index pages (default FALSE)
render_sample <- function(n_bills = 5, n_legislators = 5, n_committees = 3, random = FALSE, index_pages = FALSE) {
  ensure_dirs()
  manifest <- load_manifest()

  message(paste0(
    "=== Rendering sample: ", n_bills, " bills, ", n_legislators, " legislators, ",
    n_committees, " committees",
    if (random) " (random)" else " (first n)", " ===\n"
  ))

  # Optionally render index pages
  if (index_pages) {
    render_index_pages()
    message("\n")
  }

  # Get bills
  bills <- read_csv(ga_csv("bills"), show_col_types = FALSE)
  if (random && n_bills < nrow(bills)) {
    bill_numbers <- sample(bills$bill_number, n_bills)
  } else {
    bill_numbers <- head(bills$bill_number, n_bills)
  }

  # Get legislators (exclude committees)
  people <- read_csv(ga_csv("people"), show_col_types = FALSE)
  legislators <- people |> filter(!is.na(first_name), first_name != "")
  if (random && n_legislators < nrow(legislators)) {
    people_ids <- sample(legislators$people_id, n_legislators)
  } else {
    people_ids <- head(legislators$people_id, n_legislators)
  }

  # Get committees
  committees <- people |> filter(is.na(first_name) | first_name == "", committee_id > 0)
  if (random && n_committees < nrow(committees)) {
    committee_ids <- sample(committees$people_id, n_committees)
  } else {
    committee_ids <- head(committees$people_id, n_committees)
  }

  # Render bills
  message(paste("Rendering", length(bill_numbers), "bills..."))
  for (bill_number in bill_numbers) {
    success <- render_bill(bill_number)
    if (success) {
      current_hash <- get_bill_hash(bill_number)
      manifest <- update_manifest(manifest, "bill", session_item_id(CURRENT_GA, bill_number), current_hash)
      save_manifest(manifest)
    }
  }

  message("\n")

  # Render legislators
  message(paste("Rendering", length(people_ids), "legislators..."))
  for (people_id in people_ids) {
    success <- render_legislator(people_id)
    if (success) {
      current_hash <- get_legislator_hash(people_id)
      manifest <- update_manifest(manifest, "legislator", as.character(people_id), current_hash)
      save_manifest(manifest)
    }
  }

  message("\n")

  # Render committees
  message(paste("Rendering", length(committee_ids), "committees..."))
  for (people_id in committee_ids) {
    success <- render_committee(people_id)
    if (success) {
      current_hash <- get_committee_hash(people_id)
      manifest <- update_manifest(manifest, "committee", session_item_id(CURRENT_GA, people_id), current_hash)
      save_manifest(manifest)
    }
  }

  message("\n=== Sample render complete ===")
}

#' Show render status - how many items need rendering
render_status <- function() {
  manifest <- load_manifest()

  bills <- read_csv(ga_csv("bills"), show_col_types = FALSE)
  people <- read_csv(ga_csv("people"), show_col_types = FALSE)

  # Separate legislators from committees
  legislators <- people |> filter(!is.na(first_name), first_name != "")
  committees <- people |> filter(is.na(first_name) | first_name == "", committee_id > 0)

  bills_need_render <- sum(sapply(bills$bill_number, needs_render_bill, manifest = manifest))
  legislators_need_render <- sum(sapply(legislators$people_id, needs_render_legislator, manifest = manifest))
  committees_need_render <- sum(sapply(committees$people_id, needs_render_committee, manifest = manifest))

  session_prefix <- paste0(ga_slug(CURRENT_GA), "/")
  bills_rendered <- manifest |> filter(type == "bill", startsWith(id, session_prefix)) |> nrow()
  legislators_rendered <- manifest |> filter(type == "legislator") |> nrow()
  committees_rendered <- manifest |> filter(type == "committee", startsWith(id, session_prefix)) |> nrow()

  week_hashes <- week_digests()
  rendered_weeks <- manifest |> filter(type == "week")
  old_week_hash <- rendered_weeks$hash[match(names(week_hashes), rendered_weeks$id)]
  weeks_need_render <- sum(is.na(old_week_hash) | old_week_hash != week_hashes)

  message(paste(
    "\n=== Render Status ===",
    paste("\nBills:"),
    paste("\n  Total:", nrow(bills)),
    paste("\n  Previously rendered:", bills_rendered),
    paste("\n  Need rendering:", bills_need_render),
    paste("\n\nLegislators:"),
    paste("\n  Total:", nrow(legislators)),
    paste("\n  Previously rendered:", legislators_rendered),
    paste("\n  Need rendering:", legislators_need_render),
    paste("\n\nCommittees:"),
    paste("\n  Total:", nrow(committees)),
    paste("\n  Previously rendered:", committees_rendered),
    paste("\n  Need rendering:", committees_need_render),
    paste("\n\nWeeks:"),
    paste("\n  Total:", length(week_hashes)),
    paste("\n  Previously rendered:", nrow(rendered_weeks)),
    paste("\n  Need rendering:", weeks_need_render),
    "\n"
  ))
}

#' Clear the manifest to force full re-render
clear_manifest <- function() {
  if (file.exists(MANIFEST_FILE)) {
    file.remove(MANIFEST_FILE)
    message("Manifest cleared. Next render will process all items.")
  } else {
    message("No manifest file exists.")
  }
}

# Print usage info when script is sourced
message("
render_site.R loaded. Available functions:

  Incremental Rendering (default):
    render_all_bills()           - Render only changed bills
    render_all_legislators()     - Render only changed legislators
    render_all_committees()      - Render only changed committees
    render_all_weeks()           - Render only changed weekly activity pages
    render_site()                - Render everything (incremental)

  Force Full Render:
    render_all_bills(force=TRUE) - Re-render all bills
    render_site(force=TRUE)      - Re-render everything

  Utilities:
    test_render()                - Quick test (5 bills, 5 legislators, 3 committees, 2 weeks)
    render_sample(n_bills=10, n_legislators=5, n_committees=3)  - Render a custom sample
    render_sample(random=TRUE)   - Render a random sample
    render_status()              - Show how many items need rendering
    render_index_pages()         - Render main site index pages only
    clear_manifest()             - Clear render history (forces full re-render)

  Limiting:
    render_all_bills(limit=10)   - Process first 10 bills only
    render_all_committees(limit=5)  - Process first 5 committees only

The manifest file (render_manifest.csv) tracks:
  - Which items have been rendered (bills, legislators, committees, weeks)
  - The LegiScan hash at render time (weeks: a fingerprint of the page's data)
  - Only items with changed hashes are re-rendered
")
