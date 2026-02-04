# render_site.R
# Script to render all bill and legislator pages from templates
# Supports incremental rendering using LegiScan hash values
#
# Usage: Run this script from the project root directory
#   source("R/render_site.R")
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

source(here("R/utils.R"))

# Configuration
OUTPUT_DIR <- here("docs")
LEGISLATION_DIR <- file.path(OUTPUT_DIR, "legislation")
LEGISLATORS_DIR <- file.path(OUTPUT_DIR, "legislators")
COMMITTEES_DIR <- file.path(OUTPUT_DIR, "committees")
MANIFEST_FILE <- here("render_manifest.csv")

# Ensure output directories exist
ensure_dirs <- function() {
  dir.create(LEGISLATION_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(LEGISLATORS_DIR, recursive = TRUE, showWarnings = FALSE)
  dir.create(COMMITTEES_DIR, recursive = TRUE, showWarnings = FALSE)
}

#' Load or create the render manifest
#' Tracks which items have been rendered and their hash at render time
load_manifest <- function() {
  if (file.exists(MANIFEST_FILE)) {
    read_csv(MANIFEST_FILE, show_col_types = FALSE)
  } else {
    tibble(
      type = character(),
      id = character(),
      hash = character(),
      rendered_at = character()
    )
  }
}

#' Save the render manifest
save_manifest <- function(manifest) {
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

#' Get the hash for a bill from its JSON file
get_bill_hash <- function(bill_number) {
  json_path <- here("legiscan/files_ga91_json/bill", paste0(bill_number, ".json"))
  if (file.exists(json_path)) {
    bill_data <- read_json(json_path)
    return(bill_data$bill$change_hash)
  }
  return(NA_character_)
}

#' Get the hash for a legislator from their JSON file
get_legislator_hash <- function(people_id) {
  json_path <- here("legiscan/files_ga91_json/people", paste0(people_id, ".json"))
  if (file.exists(json_path)) {
    person_data <- read_json(json_path)
    return(person_data$person$person_hash)
  }
  return(NA_character_)
}

#' Check if a bill needs rendering (hash changed or never rendered)
needs_render_bill <- function(bill_number, manifest) {
  current_hash <- get_bill_hash(bill_number)
  if (is.na(current_hash)) return(FALSE)  # No JSON file

  existing <- manifest |>
    filter(type == "bill", id == bill_number)

  if (nrow(existing) == 0) return(TRUE)  # Never rendered

  return(existing$hash[1] != current_hash)  # Hash changed
}

#' Check if a legislator needs rendering (hash changed or never rendered)
needs_render_legislator <- function(people_id, manifest) {
  current_hash <- get_legislator_hash(people_id)
  if (is.na(current_hash)) return(FALSE)  # No JSON file

  existing <- manifest |>
    filter(type == "legislator", id == as.character(people_id))

  if (nrow(existing) == 0) return(TRUE)  # Never rendered

  return(existing$hash[1] != current_hash)  # Hash changed
}

#' Render a single bill page
#' @param bill_number Character string like "HF856"
#' @param template_path Path to bill_template.qmd
render_bill <- function(bill_number, template_path = here("site/templates/bill_template.qmd")) {
  output_file <- file.path(LEGISLATION_DIR, paste0(bill_number, ".html"))

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = basename(output_file),
      execute_params = list(bill_num = bill_number),
      output_format = "html"
    )

    # Move rendered file to correct location
    rendered_file <- here("docs/templates", basename(output_file))
    if (file.exists(rendered_file)) {
      file.rename(rendered_file, output_file)
    }

    message(paste("Rendered:", bill_number))
    return(TRUE)
  }, error = function(e) {
    warning(paste("Failed to render", bill_number, ":", e$message))
    return(FALSE)
  })
}

#' Render a single legislator page
#' @param people_id Numeric ID for the legislator
#' @param template_path Path to legislator_template.qmd
render_legislator <- function(people_id, template_path = here("site/templates/legislator_template.qmd")) {
  filename <- get_legislator_filename(people_id)
  output_file <- file.path(LEGISLATORS_DIR, paste0(filename, ".html"))

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = basename(output_file),
      execute_params = list(people_id = people_id),
      output_format = "html"
    )

    # Move rendered file to correct location
    rendered_file <- here("docs/templates", basename(output_file))
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
get_committee_hash <- function(people_id) {
  get_legislator_hash(people_id)  # Same JSON structure
}

#' Check if a committee needs rendering (hash changed or never rendered)
needs_render_committee <- function(people_id, manifest) {
  current_hash <- get_committee_hash(people_id)
  if (is.na(current_hash)) return(FALSE)

  existing <- manifest |>
    filter(type == "committee", id == as.character(people_id))

  if (nrow(existing) == 0) return(TRUE)

  return(existing$hash[1] != current_hash)
}

#' Render a single committee page
#' @param people_id Numeric ID for the committee (from people.csv)
#' @param template_path Path to committee_template.qmd
render_committee <- function(people_id, template_path = here("site/templates/committee_template.qmd")) {
  filename <- get_committee_filename(people_id)
  output_file <- file.path(COMMITTEES_DIR, paste0(filename, ".html"))

  tryCatch({
    quarto_render(
      input = template_path,
      output_file = basename(output_file),
      execute_params = list(people_id = people_id),
      output_format = "html"
    )

    # Move rendered file to correct location
    rendered_file <- here("docs/templates", basename(output_file))
    if (file.exists(rendered_file)) {
      file.rename(rendered_file, output_file)
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
render_all_committees <- function(limit = NULL, force = FALSE) {
  ensure_dirs()
  manifest <- load_manifest()

  people <- read_csv(here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)
  committees <- people |> filter(is.na(first_name) | first_name == "", committee_id > 0)
  committee_ids <- committees$people_id

  if (!is.null(limit)) {
    committee_ids <- head(committee_ids, limit)
  }

  if (!force) {
    needs_render <- sapply(committee_ids, needs_render_committee, manifest = manifest)
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
    return(invisible(NULL))
  }

  success_count <- 0
  fail_count <- 0

  for (people_id in committees_to_render) {
    success <- render_committee(people_id)

    if (success) {
      current_hash <- get_committee_hash(people_id)
      manifest <- update_manifest(manifest, "committee", as.character(people_id), current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }
    gc()
  }

  message(paste("\nCommittees completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count)))
}

#' Render all bill pages (incremental by default)
#' @param limit Optional limit for testing (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
render_all_bills <- function(limit = NULL, force = FALSE) {
  ensure_dirs()
  manifest <- load_manifest()

  bills <- read_csv(here("legiscan/files_ga91/bills.csv"), show_col_types = FALSE)
  bill_numbers <- bills$bill_number

  if (!is.null(limit)) {
    bill_numbers <- head(bill_numbers, limit)
  }

  # Filter to only bills that need rendering (unless force = TRUE)
  if (!force) {
    needs_render <- sapply(bill_numbers, needs_render_bill, manifest = manifest)
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
    return(invisible(NULL))
  }

  success_count <- 0
  fail_count <- 0

  for (bill_number in bills_to_render) {
    success <- render_bill(bill_number)

    if (success) {
      # Update manifest with new hash
      current_hash <- get_bill_hash(bill_number)
      manifest <- update_manifest(manifest, "bill", bill_number, current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }
    gc()
  }

  message(paste("\nBills completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count)))
}

#' Render all legislator pages (incremental by default)
#' @param limit Optional limit for testing (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
render_all_legislators <- function(limit = NULL, force = FALSE) {
  ensure_dirs()
  manifest <- load_manifest()

  people <- read_csv(here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)
  # Exclude committees (have empty first_name/last_name)
  legislators <- people |> filter(!is.na(first_name), first_name != "")
  people_ids <- legislators$people_id

  if (!is.null(limit)) {
    people_ids <- head(people_ids, limit)
  }

  # Filter to only legislators that need rendering (unless force = TRUE)
  if (!force) {
    needs_render <- sapply(people_ids, needs_render_legislator, manifest = manifest)
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
    return(invisible(NULL))
  }

  success_count <- 0
  fail_count <- 0

  for (people_id in legislators_to_render) {
    success <- render_legislator(people_id)

    if (success) {
      # Update manifest with new hash
      current_hash <- get_legislator_hash(people_id)
      manifest <- update_manifest(manifest, "legislator", as.character(people_id), current_hash)
      save_manifest(manifest)
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }
    gc()
  }

  message(paste("\nLegislators completed:", success_count, "success,", fail_count, "failed"))

  return(invisible(list(success = success_count, failed = fail_count)))
}

#' Render the main Quarto site (index pages)
render_index_pages <- function() {
  message("Rendering main site pages...")
  quarto_render(here("site"))
  message("Main site pages complete.")
}

#' Render everything: index pages, all bills, legislators, and committees
#' @param bills_limit Optional limit for bills (NULL for all)
#' @param legislators_limit Optional limit for legislators (NULL for all)
#' @param committees_limit Optional limit for committees (NULL for all)
#' @param force If TRUE, re-render all regardless of hash
render_site <- function(bills_limit = NULL, legislators_limit = NULL, committees_limit = NULL, force = FALSE) {
  message("=== Starting full site render ===\n")

  # Render main quarto site first
  render_index_pages()

  message("\n")

  # Render bills (incremental unless force = TRUE)
  render_all_bills(limit = bills_limit, force = force)

  message("\n")

  # Render legislators (incremental unless force = TRUE)
  render_all_legislators(limit = legislators_limit, force = force)

  message("\n")

  # Render committees (incremental unless force = TRUE)
  render_all_committees(limit = committees_limit, force = force)

  message("\n=== Site render complete ===")
}

#' Quick test render - renders 5 bills, 5 legislators, and 3 committees
test_render <- function() {
  message("Running test render (5 bills, 5 legislators, 3 committees)...\n")
  render_site(bills_limit = 5, legislators_limit = 5, committees_limit = 3, force = TRUE)
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
  bills <- read_csv(here("legiscan/files_ga91/bills.csv"), show_col_types = FALSE)
  if (random && n_bills < nrow(bills)) {
    bill_numbers <- sample(bills$bill_number, n_bills)
  } else {
    bill_numbers <- head(bills$bill_number, n_bills)
  }

  # Get legislators (exclude committees)
  people <- read_csv(here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)
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
      manifest <- update_manifest(manifest, "bill", bill_number, current_hash)
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
      manifest <- update_manifest(manifest, "committee", as.character(people_id), current_hash)
      save_manifest(manifest)
    }
  }

  message("\n=== Sample render complete ===")
}

#' Show render status - how many items need rendering
render_status <- function() {
  manifest <- load_manifest()

  bills <- read_csv(here("legiscan/files_ga91/bills.csv"), show_col_types = FALSE)
  people <- read_csv(here("legiscan/files_ga91/people.csv"), show_col_types = FALSE)

  # Separate legislators from committees
  legislators <- people |> filter(!is.na(first_name), first_name != "")
  committees <- people |> filter(is.na(first_name) | first_name == "", committee_id > 0)

  bills_need_render <- sum(sapply(bills$bill_number, needs_render_bill, manifest = manifest))
  legislators_need_render <- sum(sapply(legislators$people_id, needs_render_legislator, manifest = manifest))
  committees_need_render <- sum(sapply(committees$people_id, needs_render_committee, manifest = manifest))

  bills_rendered <- manifest |> filter(type == "bill") |> nrow()
  legislators_rendered <- manifest |> filter(type == "legislator") |> nrow()
  committees_rendered <- manifest |> filter(type == "committee") |> nrow()

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
    render_site()                - Render everything (incremental)

  Force Full Render:
    render_all_bills(force=TRUE) - Re-render all bills
    render_site(force=TRUE)      - Re-render everything

  Utilities:
    test_render()                - Quick test (5 bills, 5 legislators, 3 committees)
    render_sample(n_bills=10, n_legislators=5, n_committees=3)  - Render a custom sample
    render_sample(random=TRUE)   - Render a random sample
    render_status()              - Show how many items need rendering
    render_index_pages()         - Render main site index pages only
    clear_manifest()             - Clear render history (forces full re-render)

  Limiting:
    render_all_bills(limit=10)   - Process first 10 bills only
    render_all_committees(limit=5)  - Process first 5 committees only

The manifest file (render_manifest.csv) tracks:
  - Which items have been rendered (bills, legislators, committees)
  - The LegiScan hash at render time
  - Only items with changed hashes are re-rendered
")
