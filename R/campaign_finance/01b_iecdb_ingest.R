# R/campaign_finance/01b_iecdb_ingest.R
#
# Phase B of the IECDB migration: change-detection ingest.
#
# Source this file; it performs no requests on load. Every function that costs
# API calls is named and called explicitly, and the planning step is separate
# from the executing step so you always see the price before paying it.
#
# See notes/campaign_finance/2026-07-25_iecdb-api-data-sources.md for the plan and the endpoint
# reconnaissance this builds on.
#
# ── The idea ──────────────────────────────────────────────────────────────────
#
# /api/search/table requires a committee filter, so there is no bulk pull: a
# full refresh means ~7,900 requests. But POST /api/publicreports/state returns
# every filing ever made — all 17,873 of them, with `filedOn` — in ONE request.
# That makes it a change feed. Diff it against a manifest and re-pull only the
# committees whose filings actually moved. A first sweep costs hours; a normal
# day costs a handful of calls.
#
# ── What it produces ──────────────────────────────────────────────────────────
#
#   data/campaign_finance/iecdb_manifest.csv        one row per committee (committed)
#   data/campaign_finance/source/iecdb_api/
#       filings_index.parquet                       last full filings pull
#       transactions/{code}_{TYPE}.parquet          per-committee transactions (git-ignored)
#
# The manifest is committed deliberately: it is the state that makes the next
# run cheap, and it is small. The transaction cache is not — it is raw source
# data, and it is large.
#
# ── Typical use ───────────────────────────────────────────────────────────────
#
#   source(here::here("R/campaign_finance/01b_iecdb_ingest.R"))
#   iecdb_health_check()                    # 2 requests — always run this first
#   filings <- iecdb_refresh_filings()      # 1 request  — the change feed
#   plan    <- iecdb_plan_refresh(filings)  # 0 requests — what moved, and the cost
#   iecdb_run_refresh(plan, limit = 5)      # start small, then widen
#
#   iecdb_ingest_status()                   # 0 requests — where things stand

library(here)
library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(tibble)
library(readr)
library(arrow)

source(here("R/campaign_finance/iecdb_api.R"))

# ── Paths ─────────────────────────────────────────────────────────────────────

IECDB_CACHE_DIR    <- here("data/campaign_finance/source/iecdb_api")
IECDB_TX_DIR       <- file.path(IECDB_CACHE_DIR, "transactions")
IECDB_FILINGS_PATH <- file.path(IECDB_CACHE_DIR, "filings_index.parquet")
IECDB_MANIFEST_PATH <- here("data/campaign_finance/iecdb_manifest.csv")

# ── Manifest ──────────────────────────────────────────────────────────────────
#
# One row per committee, describing what we have pulled and how current it is.
#
#   n_filings         how many filings the index showed at pull time
#   last_filed_on     timestamp of the most recent filing
#   last_filing_id    id of that filing (catches a same-timestamp replacement)
#   reported_through  end of the period the latest filing covers — the date a
#                     page should display, instead of implying it is current
#   pulled_at         when we last pulled transactions
#   pull_status       "ok" or an error string; anything else is retried

IECDB_MANIFEST_COLS <- cols(
  committee_code   = col_character(),
  committee_uuid   = col_character(),
  committee_name   = col_character(),
  n_filings        = col_integer(),
  last_filed_on    = col_datetime(),
  last_filing_id   = col_character(),
  period_year      = col_integer(),
  period_description = col_character(),
  reported_through = col_date(),
  pulled_at        = col_datetime(),
  n_transactions   = col_integer(),
  pull_status      = col_character()
)

iecdb_empty_manifest <- function() {
  tibble(
    committee_code = character(), committee_uuid = character(),
    committee_name = character(), n_filings = integer(),
    last_filed_on = as.POSIXct(character()), last_filing_id = character(),
    period_year = integer(), period_description = character(),
    reported_through = as.Date(character()),
    pulled_at = as.POSIXct(character()), n_transactions = integer(),
    pull_status = character()
  )
}

#' Timestamps are held in UTC throughout this module.
#'
#' The API client parses IECDB stamps as America/Chicago, and write_csv emits
#' UTC, so a manifest round-trip changes the `tzone` attribute even though the
#' instant is preserved exactly. R then warns "'tzone' attributes are
#' inconsistent" on every single comparison — thousands of them in a full plan —
#' and the noise would bury a real message. The instants are what change
#' detection compares, so both sides are normalized to UTC and the local-time
#' presentation is left to whatever displays it.
iecdb_as_utc <- function(x) {
  if (!inherits(x, "POSIXct")) return(x)
  attr(x, "tzone") <- "UTC"
  x
}

iecdb_read_manifest <- function(path = IECDB_MANIFEST_PATH) {
  if (!file.exists(path)) return(iecdb_empty_manifest())
  read_csv(path, col_types = IECDB_MANIFEST_COLS, progress = FALSE) |>
    mutate(across(where(\(x) inherits(x, "POSIXct")), iecdb_as_utc))
}

iecdb_write_manifest <- function(manifest, path = IECDB_MANIFEST_PATH) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  manifest |>
    arrange(.data$committee_code) |>
    write_csv(path, na = "")
  invisible(path)
}

# ── Reporting period parsing ──────────────────────────────────────────────────

# `reported_through` is the point of this: a committee page should say what it
# actually knows ("reported through May 14, 2026") rather than showing a total
# and letting the reader assume it is current.
#
# The period is carried as free text (`periodDescription`) plus `periodYear`.
# The real vocabulary, surveyed across all 17,876 filings on 2026-08-01, is
# messier than the tidy forms quoted in CLAUDE.md:
#
#   "January 1 through December 31"                       ← "through", not a dash
#   "Oct. 15 through Dec. 31 or Wed. Preceding General through Dec. 31"
#   "May 15 through Tuesday Preceding Primary"            ← end is an ELECTION, not a date
#   "January 19th Report for Special Elections"           ← ordinal, no separator
#   "HD6 Special Election"                                ← no date at all
#
# Two rules make this safe:
#
#   1. Split on the LAST separator and read the month/day out of the tail only.
#      Reading the whole string and taking the first match returns the period's
#      START date — for "January 1 through May 14" that is January 1, a date
#      that is both wrong and plausible-looking, which is the worst kind.
#   2. If the tail carries no month/day, return NA. Periods that end at a
#      relative boundary ("Tuesday Preceding Primary") have no fixed end date
#      without an election calendar, and 1,437 filings use that form. NA is
#      correct there; the start date would be a lie.
#
# Anything unrecognized stays NA and iecdb_plan_refresh() reports the count.
# Do not make this cleverer without checking the survey again — a wrong
# "reported through" date on a page is worse than an absent one.
IECDB_MONTHS <- c(january = 1, february = 2, march = 3, april = 4, may = 5,
                  june = 6, july = 7, august = 8, september = 9, october = 10,
                  november = 11, december = 12)

# Longest-first so "january" wins over "jan" and the day isn't read off "jan 1".
IECDB_MONTH_PATTERN <- paste0(
  "\\b(", paste(c(names(IECDB_MONTHS),
                  substr(names(IECDB_MONTHS), 1, 3)), collapse = "|"), ")\\b\\.?"
)

iecdb_parse_period_end <- function(period_description, period_year) {
  desc <- str_squish(str_to_lower(as.character(period_description)))
  yr   <- suppressWarnings(as.integer(period_year))
  out  <- as.Date(rep(NA_character_, length(desc)))

  # Greedy `^.*` consumes up to the LAST separator, so the tail is the final
  # clause: "...or Wed. Preceding General through Dec. 31" → "dec. 31".
  tail_txt <- str_trim(str_replace(desc, "^.*(\\bthrough\\b|\\bto\\b|[-–—])", ""))

  m_name <- str_extract(tail_txt, IECDB_MONTH_PATTERN)
  m_name <- str_remove(str_trim(coalesce(m_name, "")), "\\.$")
  # The day is whatever number follows the month name ("dec. 31", "19th").
  after  <- str_trim(str_replace(tail_txt, paste0("^.*?", IECDB_MONTH_PATTERN), ""))
  m_day  <- suppressWarnings(as.integer(str_extract(after, "^\\D*(\\d{1,2})", group = 1)))

  idx <- match(m_name, names(IECDB_MONTHS))
  idx[is.na(idx)] <- match(m_name[is.na(idx)], substr(names(IECDB_MONTHS), 1, 3))

  ok <- !is.na(idx) & !is.na(m_day) & !is.na(yr) & m_day >= 1 & m_day <= 31
  if (any(ok)) {
    out[ok] <- suppressWarnings(as.Date(sprintf(
      "%d-%02d-%02d", yr[ok], unname(IECDB_MONTHS[idx[ok]]), m_day[ok]
    )))
  }

  # An explicit ISO date wins over the prose reading — if the API ever starts
  # emitting them, that is more reliable than any of the above.
  iso <- str_extract(desc, "\\d{4}-\\d{2}-\\d{2}")
  has_iso <- !is.na(iso)
  if (any(has_iso)) out[has_iso] <- as.Date(iso[has_iso])

  out
}

# ── Committee state, derived from the filings index ───────────────────────────

#' Collapse the filings index to one row per committee: how many filings it has
#' and what its most recent one covers. This is the thing the manifest is diffed
#' against.
iecdb_committee_state <- function(filings) {
  stopifnot(is.data.frame(filings), nrow(filings) > 0)

  filings |>
    filter(!is.na(.data$committee_code), nzchar(.data$committee_code)) |>
    group_by(.data$committee_code) |>
    arrange(.data$filed_on, .by_group = TRUE) |>
    summarize(
      committee_name     = last(.data$committee_name),
      n_filings          = n(),
      last_filed_on      = max(.data$filed_on, na.rm = TRUE),
      last_filing_id     = last(.data$filing_id),
      period_year        = last(.data$period_year),
      period_description = last(.data$period_description),
      last_file_url      = last(.data$file_url),
      .groups = "drop"
    ) |>
    mutate(
      last_filed_on    = iecdb_as_utc(.data$last_filed_on),
      reported_through = iecdb_parse_period_end(.data$period_description,
                                                .data$period_year)
    )
}

# ── Step 1: refresh the change feed (1 request) ───────────────────────────────

#' Pull the full filings index and cache it. One request.
#'
#' Cached so that planning, re-planning, and inspection cost nothing. Pass
#' `use_cache = TRUE` to re-read the last pull without touching the network.
iecdb_refresh_filings <- function(use_cache = FALSE) {
  if (use_cache) {
    if (!file.exists(IECDB_FILINGS_PATH))
      stop("No cached filings index at ", IECDB_FILINGS_PATH,
           " — run iecdb_refresh_filings() without use_cache first.", call. = FALSE)
    return(read_parquet(IECDB_FILINGS_PATH))
  }

  message("Pulling filings index (1 request)...")
  filings <- iecdb_filings()
  if (nrow(filings) == 0)
    stop("Filings index came back empty. That is not a normal result — ",
         "check the API before assuming there is nothing to do.", call. = FALSE)

  dir.create(IECDB_CACHE_DIR, recursive = TRUE, showWarnings = FALSE)
  write_parquet(filings, IECDB_FILINGS_PATH)

  message(sprintf("  %s filings across %s committees; most recent filed %s.",
                  format(nrow(filings), big.mark = ","),
                  format(n_distinct(filings$committee_code), big.mark = ","),
                  format(max(filings$filed_on, na.rm = TRUE), "%Y-%m-%d")))
  filings
}

# ── Step 2: plan (0 requests) ─────────────────────────────────────────────────

#' Work out which committees need a transaction pull, and what it will cost.
#'
#' Costs nothing and hits nothing. Returns one row per committee to pull, with
#' the reason, so the plan can be inspected (and sliced) before running.
#'
#' @param filings from iecdb_refresh_filings().
#' @param only optional character vector of committee codes to restrict to.
#' @param force re-pull everything in `only` (or everything, if `only` is NULL)
#'   regardless of whether its filings moved.
iecdb_plan_refresh <- function(filings, only = NULL, force = FALSE,
                               manifest = iecdb_read_manifest()) {
  state <- iecdb_committee_state(filings)

  if (!is.null(only)) {
    only  <- as.character(only)
    state <- filter(state, .data$committee_code %in% only)
    missing_codes <- setdiff(only, state$committee_code)
    if (length(missing_codes) > 0)
      warning("Not in the filings index (no DR2 on file?): ",
              paste(missing_codes, collapse = ", "), call. = FALSE)
  }

  prior <- manifest |>
    select(committee_code, prior_n = n_filings, prior_filed = last_filed_on,
           prior_filing = last_filing_id, prior_status = pull_status)

  plan <- state |>
    left_join(prior, by = "committee_code") |>
    mutate(reason = case_when(
      force                                     ~ "forced",
      is.na(.data$prior_n)                      ~ "never-pulled",
      !is.na(.data$prior_status) &
        .data$prior_status != "ok"              ~ "previous-error",
      .data$n_filings > .data$prior_n           ~ "new-filing",
      .data$last_filed_on > .data$prior_filed   ~ "refiled",
      # Same count and same timestamp but a different filing id: an amendment
      # that replaced the latest filing in place. Rare, but it would otherwise
      # be invisible to both of the checks above.
      !is.na(.data$prior_filing) &
        .data$last_filing_id != .data$prior_filing ~ "refiled",
      TRUE                                      ~ NA_character_
    )) |>
    filter(!is.na(.data$reason))

  # Transactions need the GUID, not the code. committee_lookup.rds already has
  # it for essentially every committee; anything missing costs one extra search
  # request at run time, so it is surfaced here rather than discovered later.
  plan <- iecdb_attach_uuid(plan)

  n_unparsed <- sum(is.na(plan$reported_through))
  message(sprintf("Plan: %s committee(s) to pull.", format(nrow(plan), big.mark = ",")))
  if (nrow(plan) > 0) {
    for (r in sort(unique(plan$reason)))
      message(sprintf("  %-16s %s", r, format(sum(plan$reason == r), big.mark = ",")))
    n_nouuid <- sum(is.na(plan$committee_uuid))
    if (n_nouuid > 0)
      message(sprintf("  %-16s %s (each costs one extra lookup request)",
                      "no cached uuid", format(n_nouuid, big.mark = ",")))
    if (n_unparsed > 0)
      message(sprintf(
        "  note: reported_through unparsed for %s — inspect period_description and extend iecdb_parse_period_end().",
        format(n_unparsed, big.mark = ",")))
    message(sprintf("  estimated cost: ~%s requests, ~%s at %.1fs/request.",
                    format(nrow(plan) + sum(is.na(plan$committee_uuid)), big.mark = ","),
                    iecdb_fmt_duration((nrow(plan) + sum(is.na(plan$committee_uuid))) *
                                         iecdb_opts()$delay),
                    iecdb_opts()$delay))
  }
  plan
}

#' Attach committee_uuid from committee_lookup.rds (step 01's output).
iecdb_attach_uuid <- function(plan) {
  lookup_path <- here("data/campaign_finance/processed/committee_lookup.rds")
  if (!file.exists(lookup_path)) {
    warning("committee_lookup.rds not found — every committee will need a ",
            "lookup request. Run 01_build_committee_lookup.R first.", call. = FALSE)
    return(mutate(plan, committee_uuid = NA_character_))
  }
  lookup <- readRDS(lookup_path) |>
    select(committee_code, committee_uuid) |>
    filter(!is.na(.data$committee_uuid), nzchar(.data$committee_uuid)) |>
    distinct(committee_code, .keep_all = TRUE)

  left_join(plan, lookup, by = "committee_code")
}

iecdb_fmt_duration <- function(secs) {
  if (secs < 90) return(sprintf("%.0fs", secs))
  if (secs < 5400) return(sprintf("%.0f min", secs / 60))
  sprintf("%.1f hours", secs / 3600)
}

# ── Step 3: run (1+ requests per committee) ───────────────────────────────────

#' Pull transactions for the committees in `plan` and update the manifest.
#'
#' Writes each committee's parquet and updates the manifest as it goes, so an
#' interrupted run keeps everything it already fetched — a full sweep takes
#' hours and losing it to one timeout would be miserable. Re-running resumes,
#' because completed committees stop matching the plan.
#'
#' A failure on one committee is recorded and skipped, not fatal; the next run
#' retries it via reason = "previous-error". A budget exhaustion IS fatal,
#' because it means the run is bigger than intended.
#'
#' @param plan from iecdb_plan_refresh().
#' @param types which transaction categories to pull. "CON" (the contributions
#'   category, which carries CON/INK/LOANREC) is the default; adding "EXP"
#'   doubles the request count.
#' @param limit pull at most this many committees. Use it on the first run.
#' @param dry_run TRUE prints what would happen and performs no requests.
iecdb_run_refresh <- function(plan, types = "CON", limit = NULL,
                              dry_run = FALSE) {
  stopifnot(is.data.frame(plan), all(types %in% c("CON", "EXP")))
  if (nrow(plan) == 0) {
    message("Nothing to pull.")
    return(invisible(iecdb_read_manifest()))
  }
  if (!is.null(limit)) plan <- head(plan, limit)

  n_req <- nrow(plan) * length(types) + sum(is.na(plan$committee_uuid))
  message(sprintf("%s%s committee(s) × %s = ~%s requests (~%s).",
                  if (dry_run) "DRY RUN: " else "",
                  format(nrow(plan), big.mark = ","),
                  paste(types, collapse = "+"),
                  format(n_req, big.mark = ","),
                  iecdb_fmt_duration(n_req * iecdb_opts()$delay)))
  if (dry_run) return(invisible(plan))

  dir.create(IECDB_TX_DIR, recursive = TRUE, showWarnings = FALSE)
  manifest <- iecdb_read_manifest()

  # Persist whatever has been done so far even if the run dies or is
  # interrupted — the whole point of writing as we go.
  on.exit({
    iecdb_write_manifest(manifest)
    message(sprintf("Manifest saved (%s rows). %d request(s) used this session.",
                    format(nrow(manifest), big.mark = ","), iecdb_request_count()))
  }, add = TRUE)

  for (i in seq_len(nrow(plan))) {
    row  <- plan[i, ]
    code <- row$committee_code

    label <- if (is.na(row$committee_name)) "" else row$committee_name
    message(sprintf("[%d/%d] %s — %s (%s)", i, nrow(plan), code, label, row$reason))

    result <- tryCatch({
      uuid <- row$committee_uuid
      if (is.na(uuid) || !nzchar(uuid)) {
        hit  <- iecdb_committee_by_code(code)
        uuid <- if (nrow(hit) == 1) hit$committee_uuid[1] else NA_character_
        if (is.na(uuid))
          stop("could not resolve committee_uuid", call. = FALSE)
      }

      n_rows <- 0L
      for (tp in types) {
        tx <- iecdb_transactions(uuid, tp)
        write_parquet(tx, iecdb_tx_path(code, tp))
        n_rows <- n_rows + nrow(tx)
      }
      list(uuid = uuid, n = n_rows, status = "ok")
    }, error = function(e) {
      # Budget exhaustion means the run is larger than intended — stop rather
      # than marking every remaining committee as failed.
      if (grepl("request budget exhausted", conditionMessage(e), fixed = TRUE))
        stop(e)
      message("    FAILED: ", conditionMessage(e))
      list(uuid = row$committee_uuid, n = NA_integer_,
           status = paste0("error: ", conditionMessage(e)))
    })

    manifest <- iecdb_update_manifest_row(manifest, row, result)
    if (i %% 25 == 0) iecdb_write_manifest(manifest)
  }

  invisible(manifest)
}

iecdb_tx_path <- function(committee_code, type) {
  safe <- str_replace_all(committee_code, "[^A-Za-z0-9_-]", "_")
  file.path(IECDB_TX_DIR, sprintf("%s_%s.parquet", safe, type))
}

iecdb_update_manifest_row <- function(manifest, plan_row, result) {
  new_row <- tibble(
    committee_code     = plan_row$committee_code,
    committee_uuid     = result$uuid,
    committee_name     = plan_row$committee_name,
    n_filings          = as.integer(plan_row$n_filings),
    last_filed_on      = iecdb_as_utc(plan_row$last_filed_on),
    last_filing_id     = plan_row$last_filing_id,
    period_year        = as.integer(plan_row$period_year),
    period_description = plan_row$period_description,
    reported_through   = plan_row$reported_through,
    pulled_at          = iecdb_as_utc(Sys.time()),
    n_transactions     = as.integer(result$n),
    pull_status        = result$status
  )
  manifest |>
    filter(.data$committee_code != plan_row$committee_code) |>
    bind_rows(new_row)
}

# ── Reading the cache back ────────────────────────────────────────────────────

#' Read cached transactions. No requests.
#'
#' @param committee_codes optional restriction; defaults to everything cached.
iecdb_load_transactions <- function(committee_codes = NULL, type = "CON") {
  files <- list.files(IECDB_TX_DIR, pattern = sprintf("_%s\\.parquet$", type),
                      full.names = TRUE)
  if (!is.null(committee_codes)) {
    keep  <- iecdb_tx_path(as.character(committee_codes), type)
    files <- files[normalizePath(files, winslash = "/") %in%
                     normalizePath(keep, winslash = "/", mustWork = FALSE)]
  }
  if (length(files) == 0) return(iecdb_empty_transactions())
  map(files, read_parquet) |> list_rbind()
}

# ── Status (0 requests) ───────────────────────────────────────────────────────

#' Where the ingest stands, without touching the API.
iecdb_ingest_status <- function() {
  manifest <- iecdb_read_manifest()
  if (nrow(manifest) == 0) {
    message("No manifest yet — nothing has been ingested.")
    return(invisible(manifest))
  }

  ok <- manifest$pull_status == "ok"
  message(sprintf("Committees in manifest: %s", format(nrow(manifest), big.mark = ",")))
  message(sprintf("  ok:      %s", format(sum(ok, na.rm = TRUE), big.mark = ",")))
  message(sprintf("  errored: %s", format(sum(!ok, na.rm = TRUE), big.mark = ",")))
  message(sprintf("  transactions cached: %s",
                  format(sum(manifest$n_transactions, na.rm = TRUE), big.mark = ",")))
  message(sprintf("  last pull: %s",
                  format(max(manifest$pulled_at, na.rm = TRUE), "%Y-%m-%d %H:%M")))

  rt <- manifest$reported_through[!is.na(manifest$reported_through)]
  if (length(rt) > 0)
    message(sprintf("  reported_through: %s parsed, median %s, latest %s",
                    format(length(rt), big.mark = ","),
                    format(median(rt)), format(max(rt))))

  if (file.exists(IECDB_FILINGS_PATH))
    message(sprintf("  filings index cached: %s",
                    format(file.mtime(IECDB_FILINGS_PATH), "%Y-%m-%d %H:%M")))

  invisible(manifest)
}
