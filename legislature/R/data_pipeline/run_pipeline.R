#' Run Full Data Pipeline
#'
#' Sources and runs each pipeline step in order:
#'   1. Download LegiScan data (requires LEGISCAN_API_KEY)
#'   2. Process votes into summary/record/stats RDS files
#'   3. Scrape bill relationships and build bill groups
#'   4. Scrape lobbyist declarations for new/changed bills
#'
#' Usage:
#'   source("R/data_pipeline/run_pipeline.R")
#'   run_pipeline()                    # Run all steps
#'   run_pipeline(steps = c(2, 3))     # Skip download, just reprocess
#'   run_pipeline(steps = 1)           # Download only
#'   run_pipeline(use_resume = TRUE)   # Use resumable scraper for step 3

library(here)

run_pipeline <- function(steps = 1:4, use_resume = FALSE, verbose = TRUE) {

  log_msg <- function(...) if (verbose) message("[pipeline] ", ...)

  # Step 1: Download LegiScan data
  if (1 %in% steps) {
    log_msg("=== Step 1: Downloading LegiScan data ===")

    api_key <- Sys.getenv("LEGISCAN_API_KEY")
    if (api_key == "") {
      stop("LEGISCAN_API_KEY environment variable is not set. ",
           "Set it with Sys.setenv(LEGISCAN_API_KEY = 'your_key') before running.")
    }

    source(here("R/data_pipeline/01_download_legiscan_data.R"), local = TRUE)
    log_msg("Step 1 complete. Data saved to legiscan/files_ga91/ and legiscan/files_ga91_json/")
  }

  # Step 2: Process votes
  if (2 %in% steps) {
    log_msg("=== Step 2: Processing votes ===")

    # Source the script in a fresh local environment so its sys.nframe() check
    # doesn't auto-execute; then call the function ourselves.
    env <- new.env(parent = globalenv())
    source(here("R/data_pipeline/02_process_votes.R"), local = env)
    env$process_votes(verbose = verbose)
    log_msg("Step 2 complete. RDS files saved to data/")
  }

  # Step 3: Bill relationships & groups
  if (3 %in% steps) {
    log_msg("=== Step 3: Scraping bill relationships & building groups ===")

    if (use_resume) {
      source(here("R/data_pipeline/03a_resume_scrape_relationships.R"), local = TRUE)
      resume_scrape()
      # Still need to build groups after scraping edges
      source(here("R/data_pipeline/03_bill_relationships.R"), local = TRUE)
      save_bill_groups()
    } else {
      source(here("R/data_pipeline/03_bill_relationships.R"), local = TRUE)
      update_bill_groups()
    }
    log_msg("Step 3 complete. Bill groups saved to data/")
  }

  # Step 4: Lobbyist declarations
  if (4 %in% steps) {
    log_msg("=== Step 4: Scraping lobbyist declarations ===")
    source(here("R/data_pipeline/04_lobbyist_declarations.R"), local = TRUE)
    update_lobbyist_declarations()
    log_msg("Step 4 complete. Lobbyist declarations saved to data/")
  }

  log_msg("=== Pipeline finished ===")
  invisible(TRUE)
}

# Run automatically when executed as a script (not when sourced)
if (sys.nframe() == 0) {
  run_pipeline()
}
