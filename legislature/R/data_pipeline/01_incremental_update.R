# 01b_incremental_update.R
#
# Incremental JSON update using getMasterListRaw -> getBill strategy.
# Compares each bill's change_hash against the locally stored JSON, then fetches
# only the bills that have changed or are new. Also picks up any missing roll
# call or person JSON files referenced by updated bills.
#
# Intended to be run daily; use 01_download_legiscan_data.R for the initial
# (or weekly) bulk load so the CSV files stay current.
#
# Usage:
#   source("R/data_pipeline/01b_incremental_update.R")
#   incremental_update()

library(httr2)
library(jsonlite)
library(here)

# =============================================================================
# Helpers
# =============================================================================

#' Make a single LegiScan API call and return the parsed JSON body
#' Uses httr2's built-in retry with exponential backoff.
legiscan_get <- function(base_url, ...) {
  request(base_url) |>
    req_url_query(...) |>
    req_retry(max_tries = 3, backoff = \(i) 2 ^ i) |>
    req_perform() |>
    resp_body_json()
}

# Path to the bill hash cache (bill_number -> change_hash)
HASH_CACHE_PATH <- here("data/bill_hash_cache.rds")

#' Build a named list of bill_number -> change_hash from local bill JSON files.
#' Fallback used when no cache exists yet.
build_local_bill_index <- function(bill_dir) {
  files <- list.files(bill_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(files) == 0L) return(list())

  results <- lapply(files, function(f) {
    tryCatch({
      d <- read_json(f, simplifyVector = FALSE)
      list(bill_number = d$bill$bill_number,
           change_hash = d$bill$change_hash)
    }, error = function(e) NULL)
  })
  results <- Filter(Negate(is.null), results)

  setNames(
    lapply(results, `[[`, "change_hash"),
    sapply(results, `[[`, "bill_number")
  )
}

#' Load the hash cache, falling back to reading all local bill JSONs if needed.
#' @param bill_dir Directory containing local bill JSON files
#' @param force    If TRUE, ignore any existing cache and rebuild from JSONs
#' @return Named list: bill_number -> change_hash
load_hash_cache <- function(bill_dir, force = FALSE) {
  if (!force && file.exists(HASH_CACHE_PATH)) {
    message("  Loading hash cache from disk...")
    return(readRDS(HASH_CACHE_PATH))
  }
  message("  No cache found (or force = TRUE). Building index from local bill JSONs...")
  build_local_bill_index(bill_dir)
}

#' Persist the in-memory hash cache to disk
save_hash_cache <- function(cache) {
  dir.create(dirname(HASH_CACHE_PATH), recursive = TRUE, showWarnings = FALSE)
  saveRDS(cache, HASH_CACHE_PATH)
  message(sprintf("  Hash cache saved (%d entries).", length(cache)))
}

# =============================================================================
# Main
# =============================================================================

#' Incrementally update bill JSON files for sessions that have changed
#'
#' @param session_id LegiScan session ID (default: 2177 for 91st GA)
#' @param state     State abbreviation, used only in log messages (default: "IA")
#' @param pause_secs Seconds to sleep between API calls to stay within rate limits
#' @param force     If TRUE, rebuild the hash index from local JSONs instead of
#'   using the cache. Use this if bill JSON files have been manually modified or
#'   replaced outside of this script (e.g. after a bulk re-download).
#' @return Invisible list: bills_checked, bills_updated, votes_fetched, people_fetched
incremental_update <- function(
    session_id  = 2177,
    state       = "IA",
    pause_secs  = 0.5,
    force       = FALSE
) {
  api_key <- Sys.getenv("LEGISCAN_API_KEY")
  if (nchar(api_key) == 0L) stop("LEGISCAN_API_KEY environment variable is not set.")

  base_url   <- paste0("https://api.legiscan.com?key=", api_key)
  json_dir   <- here("legiscan/files_ga91_json")
  bill_dir   <- file.path(json_dir, "bill")
  vote_dir   <- file.path(json_dir, "vote")
  people_dir <- file.path(json_dir, "people")

  # --------------------------------------------------------------------------
  # 1. Fetch master list
  # --------------------------------------------------------------------------
  message(sprintf("Fetching master list for session %d (%s)...", session_id, state))

  master_resp <- tryCatch(
    legiscan_get(base_url, op = "getMasterListRaw", id = session_id),
    error = function(e) stop("getMasterListRaw failed: ", conditionMessage(e))
  )

  if (!identical(master_resp$status, "OK")) {
    stop("getMasterListRaw returned unexpected status: ", master_resp$status)
  }

  # masterlist is a named list; "session" is metadata, not a bill
  master_list <- master_resp$masterlist
  master_list$session <- NULL

  message(sprintf("  Master list: %d bills.", length(master_list)))

  # --------------------------------------------------------------------------
  # 2. Diff against hash cache (or local JSON files if no cache exists)
  # --------------------------------------------------------------------------
  local_index <- load_hash_cache(bill_dir, force = force)

  to_update <- Filter(function(entry) {
    # Master list may return numbers like "HF 117"; normalize to match filenames
    bill_number <- gsub(" ", "", entry$number)
    local_hash  <- local_index[[bill_number]]
    is.null(local_hash) || !identical(local_hash, entry$change_hash)
  }, master_list)

  message(sprintf("  %d bill(s) to update.", length(to_update)))

  if (length(to_update) == 0L) {
    message("Nothing to update.")
    save_hash_cache(local_index)
    return(invisible(list(
      bills_checked  = length(master_list),
      bills_updated  = 0L,
      votes_fetched  = 0L,
      people_fetched = 0L
    )))
  }

  # Track what we already have locally so we don't re-fetch
  existing_votes  <- tools::file_path_sans_ext(list.files(vote_dir,   pattern = "\\.json$"))
  existing_people <- tools::file_path_sans_ext(list.files(people_dir, pattern = "\\.json$"))

  n_bills  <- 0L
  n_votes  <- 0L
  n_people <- 0L

  # --------------------------------------------------------------------------
  # 3. Fetch each changed bill
  # --------------------------------------------------------------------------
  for (i in seq_along(to_update)) {
    entry   <- to_update[[i]]
    bill_id <- entry$bill_id

    Sys.sleep(pause_secs)

    bill_resp <- tryCatch(
      legiscan_get(base_url, op = "getBill", id = bill_id),
      error = function(e) {
        message(sprintf("  [WARN] getBill failed for bill_id %d: %s", bill_id, conditionMessage(e)))
        NULL
      }
    )

    if (is.null(bill_resp) || !identical(bill_resp$status, "OK")) next

    bill        <- bill_resp$bill
    bill_number <- bill$bill_number  # e.g. "HF117"

    # Save bill JSON — strip the API status wrapper to match bulk download format
    bill_file <- file.path(bill_dir, paste0(bill_number, ".json"))
    write_json(list(bill = bill), bill_file, auto_unbox = TRUE, pretty = FALSE)
    local_index[[bill_number]] <- bill$change_hash  # keep cache in sync
    n_bills <- n_bills + 1L

    message(sprintf("  [%d/%d] Updated %s", i, length(to_update), bill_number))

    # ---- Fetch any roll calls not already stored locally ----
    for (vote_entry in bill$votes) {
      rc_id <- as.character(vote_entry$roll_call_id)
      if (rc_id %in% existing_votes) next

      Sys.sleep(pause_secs)

      rc_resp <- tryCatch(
        legiscan_get(base_url, op = "getRollCall", id = vote_entry$roll_call_id),
        error = function(e) {
          message(sprintf("    [WARN] getRollCall failed for %s: %s", rc_id, conditionMessage(e)))
          NULL
        }
      )

      if (is.null(rc_resp) || !identical(rc_resp$status, "OK")) next

      write_json(
        list(roll_call = rc_resp$roll_call),
        file.path(vote_dir, paste0(rc_id, ".json")),
        auto_unbox = TRUE, pretty = FALSE
      )
      existing_votes <- c(existing_votes, rc_id)
      n_votes <- n_votes + 1L
    }

    # ---- Fetch any sponsors not already stored locally ----
    # Skip committee_sponsor entries — they are committees, not individual people
    for (sponsor in bill$sponsors) {
      if (isTRUE(sponsor$committee_sponsor == 1L)) next

      pid <- as.character(sponsor$people_id)
      if (pid %in% existing_people) next

      Sys.sleep(pause_secs)

      person_resp <- tryCatch(
        legiscan_get(base_url, op = "getPerson", id = sponsor$people_id),
        error = function(e) {
          message(sprintf("    [WARN] getPerson failed for people_id %s: %s", pid, conditionMessage(e)))
          NULL
        }
      )

      if (is.null(person_resp) || !identical(person_resp$status, "OK")) next

      write_json(
        list(person = person_resp$person),
        file.path(people_dir, paste0(pid, ".json")),
        auto_unbox = TRUE, pretty = FALSE
      )
      existing_people <- c(existing_people, pid)
      n_people <- n_people + 1L
    }
  }

  message(sprintf(
    "\nDone. %d bill(s) updated, %d new roll call(s), %d new person record(s).",
    n_bills, n_votes, n_people
  ))

  save_hash_cache(local_index)

  invisible(list(
    bills_checked  = length(master_list),
    bills_updated  = n_bills,
    votes_fetched  = n_votes,
    people_fetched = n_people
  ))
}
