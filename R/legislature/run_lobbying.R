# run_lobbying.R
#
# Orchestrator for the lobbying data, run weekly by
# .github/workflows/lobbying-update.yml (not part of run_pipeline.R):
#
#   1. Full scrape of every bill's declarations (04), then one retry of the
#      bills that failed. 04 can't tell when a declaration lands on an idle
#      bill (the LegiScan change_hash doesn't move), so every run scrapes all.
#   2. 04a alignment, 04b clients, 05 salience, 04c organization tables, in
#      that order: 04c reads 05's stages and 04b's slugs.
#   3. Render organization pages, the lobbying index, then any bill pages
#      whose declarations changed (the bill hash includes lobby_digests()),
#      until the time budget runs out. Pages not reached render next run.
#
# Each script is sourced into its own environment: 04 and render.R both
# define get_bill_hash() with different arguments.
#
# Usage (interactive):
#   source("R/legislature/run_lobbying.R")
#   run_lobbying()                  # scrape, derive, render
#   run_lobbying(scrape = FALSE)    # rebuild derived data and pages only
#
# Usage (command line):
#   Rscript R/legislature/run_lobbying.R
#   # Budget from RENDER_TIME_BUDGET_MINUTES, counted from the start of the run

library(here)
library(readr)

source(here("R/legislature/session.R"))

#' Source a pipeline script into its own environment and call one function
#' @param file Script path relative to the project root
#' @param fn Function name defined by the script
#' @param ... Arguments passed to the function
run_script <- function(file, fn, ...) {
  env <- new.env()
  source(here(file), local = env)
  env[[fn]](...)
}

#' Scrape, rebuild and render the lobbying data for one session
#' @param ga General Assembly
#' @param scrape If FALSE, skip the scrape and rebuild from the saved filings
#' @param budget_minutes Stop starting new pages this many minutes after the
#'   run began (the scrape counts toward it)
run_lobbying <- function(ga = CURRENT_GA, scrape = TRUE,
                         budget_minutes = as.numeric(Sys.getenv("RENDER_TIME_BUDGET_MINUTES", "Inf"))) {
  if (ga_frozen(ga)) {
    message(ga_label(ga), " is frozen; nothing to scrape.")
    return(invisible(NULL))
  }
  deadline <- Sys.time() + budget_minutes * 60
  message("=== Lobbying update: ", ga_label(ga), " ===\n")

  if (scrape) {
    lobby <- new.env()
    source(here("R/legislature/04_lobbyist_declarations.R"), local = lobby)
    bills <- read_csv(ga_csv("bills", ga), show_col_types = FALSE)$bill_number
    lobby$update_lobbyist_declarations(bill_numbers = bills, ga = ga)

    # Every scraped bill has filings or an empty sentinel row; the rest failed
    missed <- setdiff(bills, lobby$load_lobbyist_filings(ga = ga)$bill)
    if (length(missed) > 0) {
      message("\nRetrying ", length(missed), " bills that failed...")
      lobby$rescrape_lobbyist_declarations(missed, ga = ga)
    }
    lobby$lobbyist_summary(ga = ga)
  }

  message("\n--- Derived data ---")
  run_script("R/legislature/04a_legislator_lobbyist_alignment.R",
             "compute_legislator_lobbyist_alignment", ga = ga)
  run_script("R/legislature/04b_lobbying_clients.R", "build_lobbying_clients", ga = ga)
  run_script("R/legislature/05_salience_scores.R", "compute_salience", ga = ga)
  run_script("R/legislature/04c_lobbying_organizations.R", "build_lobbying_organizations", ga = ga)

  message("\n--- Render ---")
  render <- new.env()
  source(here("R/legislature/render.R"), local = render)
  render$render_all_organizations(deadline = deadline, ga = ga)
  quarto::quarto_render(here("site/lobbying/index.qmd"), as_job = FALSE)
  render$render_all_bills(deadline = deadline, ga = ga)

  message("\n=== Lobbying update complete",
          if (Sys.time() > deadline) " (budget reached; pages left render next run)", " ===")
}

if (sys.nframe() == 0) {
  run_lobbying()
}
