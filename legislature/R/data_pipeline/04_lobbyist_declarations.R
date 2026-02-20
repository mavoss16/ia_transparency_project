# 04_lobbyist_declarations.R
#
# Scrapes lobbyist declarations from legis.iowa.gov for all bills and saves
# as a single RDS file. Templates read from the RDS instead of scraping at
# render time.
#
# Bills are re-scraped when their LegiScan change_hash differs from what was
# stored at scrape time, so updated bills get fresh lobby data automatically.
#
# Usage:
#   source("R/data_pipeline/04_lobbyist_declarations.R")
#
#   # First run or incremental update (scrapes new + changed bills)
#   update_lobbyist_declarations()
#
#   # Re-scrape specific bills (e.g., force refresh)
#   rescrape_lobbyist_declarations(c("HF1", "SF100"))
#
#   # View summary
#   lobbyist_summary()

library(dplyr)
library(stringr)
library(purrr)
library(rvest)
library(readr)
library(lubridate)
library(janitor)
library(jsonlite)

source(here::here("R/utils.R"))

# =============================================================================
# Hash Utilities
# =============================================================================

#' Get the change_hash for a bill from its JSON file
#' @param bill_number Bill number (e.g., "HF1")
#' @param json_dir Directory containing bill JSON files
#' @return Character string hash, or NA if file not found
get_bill_hash <- function(bill_number, json_dir = here::here("legiscan/files_ga91_json/bill")) {
  json_path <- file.path(json_dir, paste0(bill_number, ".json"))
  if (file.exists(json_path)) {
    bill_data <- read_json(json_path)
    return(bill_data$bill$change_hash)
  }
  NA_character_
}

#' Get change_hash for all bills
#' @param json_dir Directory containing bill JSON files
#' @return Tibble with bill and change_hash columns
get_all_bill_hashes <- function(json_dir = here::here("legiscan/files_ga91_json/bill")) {
  bill_files <- list.files(json_dir, pattern = "\\.json$", full.names = FALSE)
  bill_numbers <- str_remove(bill_files, "\\.json$")

  tibble(
    bill = bill_numbers,
    change_hash = map_chr(bill_numbers, get_bill_hash, json_dir = json_dir)
  )
}

# =============================================================================
# Core Scraping
# =============================================================================

#' Scrape lobbyist declarations for a single bill
#' Wrapper around scrape_lobbyist_declarations() from utils.R with
#' graceful failure handling
#' @param bill_number Bill number (e.g., "HF1")
#' @param ga General Assembly number
#' @return Tibble with lobbyist data, or NULL on failure
scrape_lobby_safe <- function(bill_number, ga = 91) {
  tryCatch(
    scrape_lobbyist_declarations(bill_number, ga = ga),
    error = function(e) {
      # "No tables found" means the page loaded but bill has no declarations
      if (str_detect(e$message, "No tables found|Could not find the declarations table")) {
        return(tibble(
          bill = character(),
          most_recent_declaration = character(),
          client = character(),
          date = as.POSIXct(character())
        ))
      }
      # Actual failures (network, etc.)
      message(sprintf("    ERROR: %s", e$message))
      NULL
    }
  )
}

# =============================================================================
# Incremental Update
# =============================================================================

#' Load cached lobbyist declarations or return empty tibble
#' @param path Path to lobbyist declarations RDS file
#' @return Tibble with lobbyist declarations
load_lobbyist_declarations <- function(path = here::here("data/lobbying/lobbyist_declarations.rds")) {
  if (file.exists(path)) {
    readRDS(path)
  } else {
    tibble(
      bill = character(),
      most_recent_declaration = character(),
      client = character(),
      date = as.POSIXct(character()),
      change_hash = character(),
      scraped_date = as.Date(character())
    )
  }
}

#' Save lobbyist declarations to RDS
#' @param declarations Tibble with lobbyist data
#' @param path Path to save
save_lobbyist_declarations <- function(declarations, path = here::here("data/lobbying/lobbyist_declarations.rds")) {
  saveRDS(declarations, path)
  message("Saved ", nrow(declarations), " lobbyist declaration records to ", path)
}

#' Determine which bills need scraping (new or hash changed)
#' @param existing Existing declarations tibble
#' @param json_dir Directory containing bill JSON files
#' @return Character vector of bill numbers to scrape
bills_needing_scrape <- function(existing, json_dir = here::here("legiscan/files_ga91_json/bill")) {
  current_hashes <- get_all_bill_hashes(json_dir)

  # Get the hash stored at scrape time for each bill we've already scraped
  scraped_hashes <- existing |>
    distinct(bill, change_hash)

  # Bills needing scrape: new bills OR bills whose hash has changed
  needs_scrape <- current_hashes |>
    left_join(scraped_hashes, by = "bill", suffix = c("_current", "_scraped")) |>
    filter(
      is.na(change_hash_scraped) |              # never scraped
        change_hash_current != change_hash_scraped  # hash changed
    ) |>
    pull(bill)

  needs_scrape
}

#' Update lobbyist declarations by scraping new and changed bills
#' @param bill_numbers Vector of bill numbers to scrape (NULL = auto-detect from hashes)
#' @param limit Maximum number of bills to scrape (NULL = no limit). Useful for
#'   test runs and estimating total runtime.
#' @param output_path Path to lobbyist declarations RDS file
#' @param json_dir Directory containing bill JSON files
#' @param ga General Assembly number
#' @param rate_limit Seconds between requests
#' @param save_interval Save progress every N bills
#' @return Updated declarations tibble
update_lobbyist_declarations <- function(
    bill_numbers = NULL,
    limit = NULL,
    output_path = here::here("data/lobbying/lobbyist_declarations.rds"),
    json_dir = here::here("legiscan/files_ga91_json/bill"),
    ga = 91,
    rate_limit = 1.5,
    save_interval = 50
) {
  existing <- load_lobbyist_declarations(output_path)

  # Determine which bills to scrape
  if (is.null(bill_numbers)) {
    bill_numbers <- bills_needing_scrape(existing, json_dir)
  }

  if (length(bill_numbers) == 0) {
    message("No new or changed bills to scrape.")
    return(existing)
  }

  # Apply limit if specified
  total_needed <- length(bill_numbers)
  if (!is.null(limit) && limit < total_needed) {
    bill_numbers <- bill_numbers[seq_len(limit)]
    message(sprintf("Limiting to %d of %d bills needing scrape.", limit, total_needed))
  }

  # Remove stale data for bills we're about to re-scrape
  existing <- existing |>
    filter(!bill %in% bill_numbers)
  save_lobbyist_declarations(existing, output_path)

  message("Scraping lobbyist declarations for ", length(bill_numbers), " bills...")
  message("Progress will be saved every ", save_interval, " bills.")

  start_time <- Sys.time()
  batch_results <- list()
  batch_empty <- character()
  # Store hashes alongside bills so we can tag rows with the hash at scrape time
  bill_hashes <- set_names(
    map_chr(bill_numbers, get_bill_hash, json_dir = json_dir),
    bill_numbers
  )
  failed_bills <- character()
  processed_count <- 0

  save_batch <- function() {
    if (length(batch_results) == 0 && length(batch_empty) == 0) return()

    new_declarations <- bind_rows(batch_results) |>
      mutate(scraped_date = Sys.Date())

    # For bills with no declarations, add a sentinel row so we know they were scraped
    empty_rows <- tibble(
      bill = batch_empty,
      most_recent_declaration = NA_character_,
      client = NA_character_,
      date = as.POSIXct(NA),
      change_hash = bill_hashes[batch_empty],
      scraped_date = Sys.Date()
    )

    # Reload existing (in case another process updated)
    current <- load_lobbyist_declarations(output_path)

    all_declarations <- bind_rows(current, new_declarations, empty_rows) |>
      distinct(bill, client, .keep_all = TRUE)

    save_lobbyist_declarations(all_declarations, output_path)

    batch_results <<- list()
    batch_empty <<- character()
  }

  for (i in seq_along(bill_numbers)) {
    bn <- bill_numbers[i]
    message(sprintf("  [%d/%d] %s", i, length(bill_numbers), bn))

    result <- scrape_lobby_safe(bn, ga = ga)
    Sys.sleep(rate_limit)

    if (is.null(result)) {
      failed_bills <- c(failed_bills, bn)
    } else if (nrow(result) == 0) {
      batch_empty <- c(batch_empty, bn)
      processed_count <- processed_count + 1
    } else {
      # Use our bill number (no spaces) and hash rather than the scraped bill column
      result <- result |>
        mutate(bill = bn, change_hash = bill_hashes[[bn]])
      batch_results[[length(batch_results) + 1]] <- result
      processed_count <- processed_count + 1
    }

    if (processed_count > 0 && processed_count %% save_interval == 0) {
      message(sprintf("  -- Saving progress (%d bills processed) --", processed_count))
      save_batch()
    }
  }

  if (length(batch_results) > 0 || length(batch_empty) > 0) {
    message("  -- Saving final batch --")
    save_batch()
  }

  if (length(failed_bills) > 0) {
    message("\nFailed to scrape ", length(failed_bills), " bills:")
    message("  ", paste(head(failed_bills, 20), collapse = ", "))
    if (length(failed_bills) > 20) {
      message("  ... and ", length(failed_bills) - 20, " more")
    }
    message("Run rescrape_lobbyist_declarations() with these bills to retry.")
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  per_bill <- if (processed_count > 0) elapsed / processed_count else NA
  message(sprintf("\nDone! Processed %d bills in %.1f seconds (%.1f sec/bill).",
                  processed_count, elapsed, per_bill))
  if (!is.null(limit) && limit < total_needed) {
    remaining <- total_needed - limit
    est_minutes <- (remaining * per_bill) / 60
    message(sprintf("Estimated time for remaining %d bills: %.0f minutes.", remaining, est_minutes))
  }

  return(load_lobbyist_declarations(output_path))
}

#' Force re-scrape specific bills
#' @param bill_numbers Vector of bill numbers to re-scrape
#' @param output_path Path to lobbyist declarations RDS file
#' @param ga General Assembly number
#' @param rate_limit Seconds between requests
#' @return Updated declarations tibble
rescrape_lobbyist_declarations <- function(
    bill_numbers,
    output_path = here::here("data/lobbying/lobbyist_declarations.rds"),
    ga = 91,
    rate_limit = 1.5
) {
  update_lobbyist_declarations(
    bill_numbers = bill_numbers,
    output_path = output_path,
    ga = ga,
    rate_limit = rate_limit
  )
}

# =============================================================================
# Summary
# =============================================================================

#' View summary of lobbyist declaration data
#' @param output_path Path to lobbyist declarations RDS file
lobbyist_summary <- function(output_path = here::here("data/lobbying/lobbyist_declarations.rds")) {
  if (!file.exists(output_path)) {
    message("No lobbyist data found. Run update_lobbyist_declarations() first.")
    return(invisible(NULL))
  }

  declarations <- readRDS(output_path)

  # Separate real declarations from sentinel rows
  real <- declarations |> filter(!is.na(client))
  empty <- declarations |> filter(is.na(client))

  cat("=== Lobbyist Declarations Summary ===\n\n")
  cat("Bills scraped:", n_distinct(declarations$bill), "\n")
  cat("Bills with declarations:", n_distinct(real$bill), "\n")
  cat("Bills with no declarations:", n_distinct(empty$bill), "\n")
  cat("Total declaration records:", nrow(real), "\n\n")

  cat("Declaration breakdown:\n")
  real |>
    count(most_recent_declaration) |>
    arrange(desc(n)) |>
    print()

  invisible(declarations)
}
