# run_pipeline.R
#
# Orchestrator for the Iowa Legislature data pipeline.
# Runs all steps in order: download → process votes → bill relationships → render site
#
# Usage (interactive):
#   source("R/run_pipeline.R")
#   run_pipeline()                          # full pipeline
#   run_pipeline(steps = c("download", "process_votes"))  # subset of steps
#   run_pipeline(stop_on_error = TRUE)      # halt on first failure
#
# Usage (scheduled / command line):
#   Rscript R/run_pipeline.R
#   # Exit code 0 = all steps succeeded, 1 = at least one step failed

library(here)

# =============================================================================
# Logging
# =============================================================================

LOG_DIR <- here("logs")

#' Set up logging to a timestamped file
#' @param log_dir Directory to write log files
#' @param keep_days Number of days of log files to retain (NULL to keep all)
#' @return Path to the log file
setup_logging <- function(log_dir = LOG_DIR, keep_days = 30) {
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  timestamp <- format(Sys.time(), "%Y-%m-%d_%H-%M-%S")
  log_file <- file.path(log_dir, paste0("pipeline_", timestamp, ".log"))

  # Open connection for the log file
  log_con <- file(log_file, open = "wt")

  # Duplicate output to both console and log file
  sink(log_con, append = TRUE, split = TRUE)           # captures cat/print
  sink(log_con, append = TRUE, type = "message")       # captures message/warning

  # Clean up old logs
  if (!is.null(keep_days)) {
    cleanup_old_logs(log_dir, keep_days)
  }

  log_file
}

#' Stop logging and close the sink connections
teardown_logging <- function() {
  # Close message sink first (it was opened second)
  tryCatch(sink(type = "message"), error = function(e) NULL)
  # Close output sink
  tryCatch(sink(), error = function(e) NULL)
}

#' Remove log files older than keep_days
#' @param log_dir Directory containing log files
#' @param keep_days Number of days to retain
cleanup_old_logs <- function(log_dir, keep_days) {
  log_files <- list.files(log_dir, pattern = "^pipeline_.*\\.log$", full.names = TRUE)
  if (length(log_files) == 0) return(invisible(NULL))

  file_info <- file.info(log_files)
  cutoff <- Sys.time() - as.difftime(keep_days, units = "days")
  old_files <- log_files[file_info$mtime < cutoff]

  if (length(old_files) > 0) {
    file.remove(old_files)
    message(sprintf("Cleaned up %d old log file(s)", length(old_files)))
  }
}

# =============================================================================
# Pipeline step definitions
# =============================================================================

PIPELINE_STEPS <- list(
  download = list(
    name = "Incremental bill update",
    run = function() {
      source(here("R/data_pipeline/01_incremental_update.R"), local = TRUE)
      incremental_update()
    }
  ),
  generate_csvs = list(
    name = "Generate CSVs from JSON",
    run = function() {
      source(here("R/data_pipeline/01c_generate_csvs.R"), local = TRUE)
      generate_csvs()
    }
  ),
  process_votes = list(
    name = "Process votes",
    run = function() {
      source(here("R/data_pipeline/02_process_votes.R"), local = TRUE)
      process_votes()
    }
  ),
  bill_relationships = list(
    name = "Scrape bill relationships & build groups",
    run = function() {
      source(here("R/data_pipeline/03_bill_relationships.R"), local = TRUE)
      update_bill_groups()
    }
  ),
  render = list(
    name = "Render site",
    run = function() {
      source(here("R/render_site.R"), local = TRUE)
      render_site()
    }
  )
)

# Output directories to scan for modified files after each step completes.
# Used by count_modified_files() to populate the files_updated column in the
# run summary.
STEP_OUTPUT_DIRS <- list(
  download = list(
    dirs    = c("legiscan/files_ga91_json"),
    pattern = NULL          # count all files
  ),
  generate_csvs = list(
    dirs    = c("legiscan/files_ga91_derived"),
    pattern = "\\.csv$"
  ),
  process_votes = list(
    dirs    = c("data/votes"),
    pattern = "\\.rds$"
  ),
  bill_relationships = list(
    dirs    = c("data/bills"),
    pattern = "\\.rds$"
  ),
  render = list(
    dirs    = c("docs"),
    pattern = "\\.html$"
  )
)

# =============================================================================
# Run summary helpers
# =============================================================================

#' Count files modified after a given time in one or more directories
#' @param dirs Character vector of directory paths (relative to project root)
#' @param since_time POSIXct; files with mtime > this are counted
#' @param pattern Optional regex to filter file names
#' @return Integer count of modified files
count_modified_files <- function(dirs, since_time, pattern = NULL) {
  total <- 0L
  for (d in dirs) {
    full_d <- here(d)
    if (!dir.exists(full_d)) next
    files <- list.files(full_d, pattern = pattern, recursive = TRUE,
                        full.names = TRUE)
    if (length(files) == 0L) next
    info  <- file.info(files)
    total <- total + sum(info$mtime > since_time, na.rm = TRUE)
  }
  total
}

#' Append a one-row-per-step summary of the current run to data/pipeline_runs.rds
#' @param results Named list of step result lists from run_pipeline()
#' @param run_id  Character run identifier (timestamp string)
#' @param pipeline_start POSIXct start time of the full pipeline
save_run_summary <- function(results, run_id, pipeline_start) {
  summary_path <- here("data/pipeline_internal/pipeline_runs.rds")

  new_rows <- do.call(rbind, lapply(results, function(r) {
    data.frame(
      run_id        = run_id,
      run_start     = pipeline_start,
      step          = r$step,
      step_name     = r$name,
      success       = r$success,
      duration_mins = round(r$duration, 2),
      files_updated = r$files_updated,
      error         = if (r$success) NA_character_ else r$error,
      stringsAsFactors = FALSE
    )
  }))

  if (file.exists(summary_path)) {
    existing <- readRDS(summary_path)
    combined <- rbind(existing, new_rows)
  } else {
    combined <- new_rows
  }

  dir.create(dirname(summary_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(combined, summary_path)
  message(sprintf("  Run summary appended to: %s", summary_path))
}

# =============================================================================
# Main orchestrator
# =============================================================================

#' Run the full data pipeline
#'
#' @param steps Character vector of step names to run. Default runs all steps in order:
#'   "download", "process_votes", "bill_relationships", "render".
#'   Use a subset to run only specific steps.
#' @param stop_on_error If TRUE, stop the pipeline on the first failure.
#'   If FALSE (default), continue to the next step and report failures at the end.
#' @param log If TRUE (default), write output to a timestamped log file in logs/.
#' @param keep_days Number of days of log files to retain (default 30).
#' @return Invisible list with step results (name, success, duration, error)
run_pipeline <- function(
    steps = names(PIPELINE_STEPS),
    stop_on_error = FALSE,
    log = TRUE,
    keep_days = 30
) {
  pipeline_start <- Sys.time()
  log_file <- NULL

  # Set up logging
  if (log) {
    log_file <- setup_logging(keep_days = keep_days)
  }

  # Ensure logging is torn down even on error
  on.exit({
    if (log) teardown_logging()
  }, add = TRUE)

  message("==================================================")
  message("  Iowa Legislature Pipeline")
  message(sprintf("  Started: %s", format(pipeline_start, "%Y-%m-%d %H:%M:%S")))
  message(sprintf("  Steps:   %s", paste(steps, collapse = " -> ")))
  if (!is.null(log_file)) {
    message(sprintf("  Log:     %s", log_file))
  }
  message("==================================================\n")

  # Validate step names
  invalid_steps <- setdiff(steps, names(PIPELINE_STEPS))
  if (length(invalid_steps) > 0) {
    stop("Unknown pipeline step(s): ", paste(invalid_steps, collapse = ", "),
         "\nValid steps: ", paste(names(PIPELINE_STEPS), collapse = ", "))
  }

  # Run each step
  results <- list()

  for (step_key in steps) {
    step <- PIPELINE_STEPS[[step_key]]
    step_start <- Sys.time()

    message(sprintf("--- [%s] %s ---", format(step_start, "%H:%M:%S"), step$name))

    result <- tryCatch({
      step$run()
      list(
        step = step_key,
        name = step$name,
        success = TRUE,
        error = NULL
      )
    }, error = function(e) {
      list(
        step = step_key,
        name = step$name,
        success = FALSE,
        error = conditionMessage(e)
      )
    })

    step_end <- Sys.time()
    result$duration <- as.numeric(difftime(step_end, step_start, units = "mins"))

    out <- STEP_OUTPUT_DIRS[[step_key]]
    result$files_updated <- if (!is.null(out)) {
      count_modified_files(out$dirs, step_start, out$pattern)
    } else {
      NA_integer_
    }

    if (result$success) {
      message(sprintf("--- [%s] %s completed (%.1f min) ---\n",
                      format(step_end, "%H:%M:%S"), step$name, result$duration))
    } else {
      message(sprintf("*** [%s] %s FAILED (%.1f min): %s ***\n",
                      format(step_end, "%H:%M:%S"), step$name, result$duration, result$error))
      if (stop_on_error) {
        message("Stopping pipeline (stop_on_error = TRUE).")
        results[[step_key]] <- result
        break
      }
    }

    results[[step_key]] <- result
    gc()
  }

  # Unique identifier for this run (used in the summary RDS)
  run_id <- format(pipeline_start, "%Y-%m-%d_%H-%M-%S")

  # Summary
  pipeline_end <- Sys.time()
  total_mins <- as.numeric(difftime(pipeline_end, pipeline_start, units = "mins"))
  n_success <- sum(sapply(results, `[[`, "success"))
  n_failed <- sum(!sapply(results, `[[`, "success"))

  message("==================================================")
  message("  Pipeline Summary")
  message(sprintf("  Finished: %s", format(pipeline_end, "%Y-%m-%d %H:%M:%S")))
  message(sprintf("  Total time: %.1f minutes", total_mins))
  message(sprintf("  Steps: %d succeeded, %d failed", n_success, n_failed))
  message("")

  for (r in results) {
    status <- if (r$success) "OK" else "FAILED"
    message(sprintf("  [%s] %s (%.1f min)%s",
                    status, r$name, r$duration,
                    if (!r$success) paste0(" - ", r$error) else ""))
  }

  if (!is.null(log_file)) {
    message(sprintf("\n  Full log: %s", log_file))
  }
  message("==================================================")

  save_run_summary(results, run_id, pipeline_start)

  invisible(results)
}

# =============================================================================
# Run when called from command line: Rscript R/run_pipeline.R
# =============================================================================

if (sys.nframe() == 0) {
  results <- run_pipeline()
  any_failed <- any(!sapply(results, `[[`, "success"))
  quit(status = if (any_failed) 1L else 0L, save = "no")
}
