# run_backfill.R
#
# Builds the data layer for an earlier General Assembly whose raw LegiScan
# JSON is already in legiscan/ga{N}/ (R/legislature/download/
# download_legiscan_bulk.R). Run by .github/workflows/backfill-session.yml,
# or locally. Renders nothing: pages are a separate step.
#
#   01c  derived CSVs (fills placeholder roll call dates)   ~1 min
#   02   vote tables, 02b similarity                         ~1 min
#   03   bill relationships: scrapes legis.iowa.gov once per
#        bill at 1.5 s apart, then rebuilds the bill groups  ~2-2.5 h for 3,500 bills
#   06   weekly activity actions                             ~1 min
#
# Every step is safe to re-run. 03 saves its scrape every 50 bills and skips
# bills already scraped, so a run cut short resumes where it stopped.
#
# Each script is sourced into its own environment (as in run_lobbying.R),
# and every step gets `ga` explicitly, since several scripts default to
# CURRENT_GA.
#
# Usage (interactive):
#   source("R/legislature/run_backfill.R")
#   run_backfill(90)
#   run_backfill(90, steps = "weekly_activity")
#
# Usage (command line):
#   Rscript R/legislature/run_backfill.R 90 [step ...]

library(here)

source(here("R/legislature/session.R"))

BACKFILL_STEPS <- list(
  generate_csvs = list(file = "R/legislature/01c_generate_csvs.R", fn = "generate_csvs"),
  process_votes = list(file = "R/legislature/02_process_votes.R", fn = "process_votes"),
  legislator_similarity = list(file = "R/legislature/02b_legislator_similarity.R",
                               fn = "compute_legislator_similarity"),
  bill_relationships = list(file = "R/legislature/03_bill_relationships.R", fn = "update_bill_groups"),
  weekly_activity = list(file = "R/legislature/06_weekly_activity.R", fn = "build_bill_actions")
)

#' Build an earlier session's data layer
#' @param ga General Assembly (not the current one: the daily pipeline owns it)
#' @param steps Names from BACKFILL_STEPS, run in that order
run_backfill <- function(ga, steps = names(BACKFILL_STEPS)) {
  ga <- as.integer(ga)
  if (ga == CURRENT_GA) stop("The ", ga_label(ga), " is CURRENT_GA; run_pipeline.R handles it.")
  if (!dir.exists(ga_paths(ga)$bill_json)) {
    stop("No raw data for the ", ga_label(ga), ". Run download_legiscan_bulk(", ga, ") first.")
  }
  unknown <- setdiff(steps, names(BACKFILL_STEPS))
  if (length(unknown) > 0) stop("Unknown step(s): ", paste(unknown, collapse = ", "))

  message("=== Backfill: ", ga_label(ga), " ===")
  for (step in intersect(names(BACKFILL_STEPS), steps)) {
    spec <- BACKFILL_STEPS[[step]]
    message("\n--- ", step, " (", basename(spec$file), ") ---")
    started <- Sys.time()
    env <- new.env()
    source(here(spec$file), local = env)
    env[[spec$fn]](ga = ga)
    message(sprintf("--- %s done in %.1f min", step, difftime(Sys.time(), started, units = "mins")))
  }
  message("\n=== Backfill complete: ", ga_label(ga), " ===")
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) stop("Usage: Rscript R/legislature/run_backfill.R <ga> [step ...]")
  steps <- if (length(args) > 1) args[-1] else names(BACKFILL_STEPS)
  run_backfill(args[1], steps)
}
