# 03a_resume_scrape_relationships.R
#
# Picks up relationship scraping where it left off.
# Processes in batches with saves + gc() between each batch.
#
# Usage:
#   source("R/data_pipeline/03a_resume_scrape_relationships.R")
#   resume_scrape()                    # default 50-bill batches, all remaining
#   resume_scrape(batch_size = 25)     # smaller batches if still crashing
#   resume_scrape(max_bills = 200)     # cap at 200 bills this session
#
# You can Ctrl+C at any time -- progress is saved after each batch.

library(dplyr)
library(stringr)
library(tidyr)
library(rvest)
library(jsonlite)
library(here)
library(purrr)

EDGES_PATH <- here("data/bills/relationship_edges.rds")
JSON_DIR   <- here("legiscan/files_ga91_json/bill")

# --- Core scrape function ---
scrape_one_bill <- function(bill_number, ga = 91) {
  # Bill history pages are static HTML — no JS/chromote needed.
  bill_name_spaced <- str_replace(bill_number, "([A-Z]+)([0-9]+)", "\\1 \\2")
  url <- paste0(
    "https://www.legis.iowa.gov/legislation/billTracking/billHistory?billName=",
    utils::URLencode(bill_name_spaced, repeated = TRUE),
    "&ga=", ga
  )

  page <- NULL
  for (attempt in 1:3) {
    page <- tryCatch(read_html(url), error = function(e) NULL)
    if (!is.null(page)) break
    if (attempt < 3) {
      message("    Attempt ", attempt, " failed for ", bill_number, ", retrying...")
      Sys.sleep(2)
    }
  }

  if (is.null(page)) {
    warning("Failed to read page for ", bill_number)
    return(list(
      result = tibble(bill = bill_number, related_bills = list(character(0))),
      success = FALSE
    ))
  }

  related_links <- tryCatch(
    page |>
      html_elements(
        xpath = "//text()[contains(., 'All Related Bills to Selected Bill')]/following::a[contains(@href, 'BillBook')]"
      ),
    error = function(e) list()
  )

  related <- character(0)
  if (length(related_links) > 0) {
    hrefs <- html_attr(related_links, "href")
    related <- str_match(hrefs, "[?&]ba=([A-Z]+ ?[0-9]+)")[, 2] |>
      str_remove_all(" ") |>
      na.omit() |>
      unique()
    related <- related[related != bill_number]
  }

  list(
    result = tibble(bill = bill_number, related_bills = list(related)),
    success = TRUE
  )
}

# --- Save a batch of results to the edges file ---
save_batch_results <- function(batch_results) {
  if (length(batch_results) == 0) return(invisible(NULL))

  new_relationships <- bind_rows(lapply(batch_results, `[[`, "result"))

  # Bills with relationships -> edges
  new_edges <- new_relationships |>
    unnest(related_bills) |>
    filter(length(related_bills) > 0, !is.na(related_bills), related_bills != "") |>
    transmute(from_bill = bill, to_bill = related_bills, scraped_date = Sys.Date())

  # Bills with no relationships -> NA row so we know they were scraped
  no_rels <- new_relationships |>
    filter(map_int(related_bills, length) == 0) |>
    transmute(from_bill = bill, to_bill = NA_character_, scraped_date = Sys.Date())

  # Load existing, merge, save
  existing <- if (file.exists(EDGES_PATH)) readRDS(EDGES_PATH) else {
    tibble(from_bill = character(), to_bill = character(), scraped_date = as.Date(character()))
  }

  all_edges <- bind_rows(existing, new_edges, no_rels) |>
    distinct(from_bill, to_bill, .keep_all = TRUE)

  saveRDS(all_edges, EDGES_PATH)
  message("  Saved. Total edges: ", nrow(all_edges),
          " | Unique bills scraped: ", n_distinct(all_edges$from_bill))
}

# --- Main resume function ---
resume_scrape <- function(batch_size = 50, max_bills = Inf, rate_limit = 1.5) {
  # Figure out what's left
  all_bills <- tools::file_path_sans_ext(list.files(JSON_DIR, pattern = "\\.json$"))
  already_scraped <- if (file.exists(EDGES_PATH)) {
    unique(readRDS(EDGES_PATH)$from_bill)
  } else {
    character(0)
  }
  remaining <- setdiff(all_bills, already_scraped)

  # Cap if requested
  if (max_bills < length(remaining)) {
    remaining <- remaining[seq_len(max_bills)]
  }

  cat("=== Relationship Scrape Status ===\n")
  cat("Total bills:      ", length(all_bills), "\n")
  cat("Already scraped:  ", length(already_scraped), "\n")
  cat("Remaining:        ", length(remaining), "\n")
  cat("This session:     ", length(remaining), " bills in ",
      ceiling(length(remaining) / batch_size), " batches of ", batch_size, "\n")
  cat("Estimated time:   ~", round(length(remaining) * rate_limit / 60, 1), " minutes\n")
  cat("==================================\n\n")

  if (length(remaining) == 0) {
    message("Nothing left to scrape!")
    return(invisible(NULL))
  }

  # Split into batches
  batches <- split(remaining, ceiling(seq_along(remaining) / batch_size))
  total_processed <- 0
  total_failed <- 0
  start_time <- Sys.time()

  for (b in seq_along(batches)) {
    batch <- batches[[b]]
    message(sprintf("--- Batch %d/%d (%d bills) ---", b, length(batches), length(batch)))

    batch_results <- list()
    for (i in seq_along(batch)) {
      bn <- batch[i]
      message(sprintf("  [%d/%d] %s", total_processed + i, length(remaining), bn))

      out <- tryCatch(
        scrape_one_bill(bn),
        error = function(e) {
          message("    ERROR: ", e$message)
          list(
            result = tibble(bill = bn, related_bills = list(character(0))),
            success = FALSE
          )
        }
      )

      if (out$success) {
        n_rel <- length(out$result$related_bills[[1]])
        if (n_rel > 0) message("    Found ", n_rel, " related bill(s)")
      } else {
        total_failed <- total_failed + 1
      }

      batch_results[[i]] <- out

      # Small sleep between requests (on top of the JS wait)
      Sys.sleep(0.5)
    }

    total_processed <- total_processed + length(batch)

    # Save this batch
    save_batch_results(batch_results)

    # Free memory between batches
    rm(batch_results)
    gc(verbose = FALSE)

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    rate <- total_processed / elapsed
    remaining_est <- (length(remaining) - total_processed) / rate
    message(sprintf("  Elapsed: %.1f min | Rate: %.0f bills/min | Est remaining: %.1f min\n",
                    elapsed, rate, remaining_est))
  }

  cat("\n=== Done ===\n")
  cat("Processed:", total_processed, "\n")
  cat("Failed:   ", total_failed, "\n")
  cat("Time:     ", round(as.numeric(difftime(Sys.time(), start_time, units = "mins")), 1), " min\n")
}
