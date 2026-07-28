# R/campaign_finance/iecdb_api.R
#
# Single client for the IECDB web app's JSON API (webapp.iecdb.iowa.gov).
# Source this file; do not run it directly. Nothing else in the pipeline should
# call the API directly — every request goes through iecdb_post() so that
# throttling, retry, the request budget, and schema validation apply uniformly.
#
# Phase A of the IECDB migration. See notes/2026-07-25_iecdb-api-data-sources.md
# for endpoint reconnaissance, the plan, and the cautions this module implements.
#
# ── What this API is ──────────────────────────────────────────────────────────
#
# An undocumented internal API behind a React portal. It is public (permissive
# robots.txt, no automated-access clause in Iowa.gov policy, Chapter 22 open
# records) but carries no stability guarantee. Treat every response as
# potentially reshaped: this module fails loudly on missing required fields
# rather than quietly ingesting partial data.
#
# ── Endpoints wrapped ─────────────────────────────────────────────────────────
#
#   iecdb_committee_search()  POST /api/search/committee
#   iecdb_transactions()      POST /api/search/table
#   iecdb_filings()           POST /api/publicreports/state
#   iecdb_statements()        POST /api/publicreports/statements
#
# ── Rate limiting ─────────────────────────────────────────────────────────────
#
# Defaults are deliberately polite, not fast. A first full committee sweep
# (~7,900 calls) takes hours by design; it is meant to be run once, after which
# iecdb_filings() acts as a change feed and daily traffic is a handful of calls.
# Tune with options() if you must, but do not remove the delay:
#
#   options(iecdb.delay = 0.5)          # seconds between requests (default 1)
#   options(iecdb.max_requests = 250)   # per-session budget  (default 10000)
#   options(iecdb.verbose = FALSE)
#
# Usage: source(here::here("R/campaign_finance/iecdb_api.R"))

library(httr2)
library(dplyr)
library(purrr)
library(tibble)

# ── Configuration ─────────────────────────────────────────────────────────────

IECDB_BASE_URL <- "https://webapp.iecdb.iowa.gov"

# Identify ourselves. If IECDB ever wants to throttle or contact us, they can.
IECDB_USER_AGENT <- paste0(
  "ia-transparency-project/1.0 ",
  "(+https://github.com/mavoss16/ia_transparency_project; ",
  "public campaign finance research) httr2/R"
)

iecdb_opts <- function() {
  list(
    delay        = getOption("iecdb.delay",        1.0),
    max_requests = getOption("iecdb.max_requests", 10000L),
    max_tries    = getOption("iecdb.max_tries",    4L),
    timeout      = getOption("iecdb.timeout",      600L),
    verbose      = getOption("iecdb.verbose",      TRUE)
  )
}

# ── Session state: request budget and throttle clock ──────────────────────────

.iecdb <- new.env(parent = emptyenv())
.iecdb$n_requests <- 0L
.iecdb$last_at    <- NULL

#' Requests issued since the last reset.
iecdb_request_count <- function() .iecdb$n_requests

#' Reset the per-session request budget. Call at the start of a long ingest.
iecdb_reset_budget <- function() {
  .iecdb$n_requests <- 0L
  .iecdb$last_at    <- NULL
  invisible(TRUE)
}

# Sleep only for the remainder of the delay window — time already spent waiting
# on the server counts toward it, so a slow endpoint isn't penalized twice.
iecdb_throttle <- function(delay) {
  if (!is.null(.iecdb$last_at)) {
    elapsed <- as.numeric(difftime(Sys.time(), .iecdb$last_at, units = "secs"))
    if (elapsed < delay) Sys.sleep(delay - elapsed)
  }
  .iecdb$last_at <- Sys.time()
  invisible(NULL)
}

# ── Schema contracts ──────────────────────────────────────────────────────────
#
# Only the fields the pipeline actually depends on are required. The API
# legitimately omits others depending on filer type — a lobbyist client has no
# committeeCode, a contribution from an individual has no secondaryCommitteeCode
# — so requiring the full observed field set would produce false alarms.

IECDB_REQUIRED_FIELDS <- list(
  committee    = c("id", "name", "filerTypeName"),
  transaction  = c("transactionId", "date", "primaryCommitteeCode",
                   "transactionType", "amount"),
  filing       = c("id", "committeeCode", "committeeName", "periodDescription",
                   "periodYear", "reportType", "filedOn", "fileUrl"),
  statement    = c("committeeCode", "committeeName", "filedOn")
)

#' Fail loudly if a response is missing fields we depend on.
#'
#' Checks the union of keys across rows rather than the first row alone: field
#' presence varies per row, so a required field missing from row 1 but present
#' elsewhere is normal, whereas one absent from every row is drift.
iecdb_validate <- function(rows, contract, endpoint) {
  if (length(rows) == 0) return(invisible(NULL))
  required <- IECDB_REQUIRED_FIELDS[[contract]]
  observed <- unique(unlist(lapply(rows, names), use.names = FALSE))
  missing  <- setdiff(required, observed)

  if (length(missing) > 0) {
    stop(sprintf(
      paste0(
        "IECDB schema drift at %s.\n",
        "  Missing required field(s): %s\n",
        "  Observed fields: %s\n",
        "The API changed shape. Do NOT work around this by relaxing the ",
        "contract — inspect the response, update IECDB_REQUIRED_FIELDS and the ",
        "parser together, and re-check anything already ingested."
      ),
      endpoint, paste(missing, collapse = ", "), paste(observed, collapse = ", ")
    ), call. = FALSE)
  }

  # New fields are not an error, but they're worth surfacing: they often mean
  # the upstream model gained something useful (or is mid-migration).
  if (isTRUE(iecdb_opts()$verbose)) {
    extra <- setdiff(observed, c(required, IECDB_KNOWN_FIELDS[[contract]]))
    if (length(extra) > 0)
      message(sprintf("  note: %s returned unrecognized field(s): %s",
                      endpoint, paste(extra, collapse = ", ")))
  }
  invisible(NULL)
}

# Fields seen during reconnaissance on 2026-07-25. Not required — used only to
# keep the "unrecognized field" notice quiet for things we already know about.
IECDB_KNOWN_FIELDS <- list(
  committee = c("type", "committeeTypeCd", "description", "descriptionId",
                "politicalParty", "districtNumber", "county", "electionYear",
                "nameOfOfficeSought", "electionDate", "committeeEmail",
                "committeeCode"),
  transaction = c("primaryName", "primaryAddress1", "primaryCity",
                  "primaryState", "primaryZip", "secondaryCommitteeCode",
                  "secondaryName", "secondaryAddress1", "secondaryAddress2",
                  "secondaryCity", "secondaryState", "secondaryZip",
                  "checkNumber", "referenceId", "referenceType",
                  "referenceDR2Id"),
  filing = c("periodDescription", "organizationType", "candidateName",
             "fileName"),
  statement = c("candidateName", "organizationType", "reportType", "isClosed",
                "yearClosed", "fileUrl", "committeeId")
)

# ── Core request ──────────────────────────────────────────────────────────────

#' POST JSON to the IECDB API with throttling, retry, and a request budget.
#'
#' Returns the parsed body, or NULL for HTTP 204 (which this API uses both for
#' "no results" and for "you omitted a required filter").
iecdb_perform <- function(path, body) {
  opts <- iecdb_opts()

  if (.iecdb$n_requests >= opts$max_requests) {
    stop(sprintf(
      paste0("IECDB request budget exhausted (%d requests).\n",
             "Raise it deliberately with options(iecdb.max_requests = N) after ",
             "confirming the loop is doing what you intend."),
      opts$max_requests
    ), call. = FALSE)
  }

  iecdb_throttle(opts$delay)
  .iecdb$n_requests <- .iecdb$n_requests + 1L

  resp <- request(paste0(IECDB_BASE_URL, path)) |>
    req_method("POST") |>
    req_headers(Accept = "application/json") |>
    req_user_agent(IECDB_USER_AGENT) |>
    req_body_json(body) |>
    req_timeout(opts$timeout) |>
    # Retry only what is plausibly transient. A 4xx means we sent something
    # wrong; repeating it just adds load.
    req_retry(
      max_tries    = opts$max_tries,
      backoff      = \(i) min(60, 2^i),
      is_transient = \(resp) resp_status(resp) %in% c(408, 429, 500, 502, 503, 504)
    ) |>
    req_perform()

  if (resp_status(resp) == 204L) return(NULL)
  resp
}

#' Parse a response as a nested list. Fine for the small endpoints.
iecdb_post <- function(path, body) {
  resp <- iecdb_perform(path, body)
  if (is.null(resp)) return(NULL)
  resp_body_json(resp)
}

#' Parse a response as a data frame, column-wise.
#'
#' Used for /api/search/table, which can return a quarter of a million rows for
#' one committee. Building those row-by-row (map() over tibble()) takes minutes
#' and dominates the request time; jsonlite's simplifyDataFrame does it
#' column-wise in about a second. Returns a data.frame, or NULL for 204.
iecdb_post_df <- function(path, body) {
  resp <- iecdb_perform(path, body)
  if (is.null(resp)) return(NULL)
  parsed <- jsonlite::fromJSON(resp_body_string(resp), simplifyDataFrame = TRUE)
  if (is.data.frame(parsed)) return(parsed)
  if (!is.null(parsed$results) && is.data.frame(parsed$results)) return(parsed$results)
  if (is.list(parsed) && length(parsed) == 0) return(NULL)
  stop(sprintf(
    "IECDB response at %s did not simplify to a data frame (got: %s).",
    path, paste(class(parsed), collapse = "/")
  ), call. = FALSE)
}

#' Column from a data frame, or a typed NA vector if the API omitted it.
#' Field presence varies by row type, so absent columns are normal.
col_or_na <- function(df, name, type = c("chr", "num", "int")) {
  type <- match.arg(type)
  n <- nrow(df)
  if (is.null(df[[name]])) {
    return(switch(type, chr = rep(NA_character_, n),
                        num = rep(NA_real_, n),
                        int = rep(NA_integer_, n)))
  }
  switch(type, chr = as.character(df[[name]]),
                num = as.numeric(df[[name]]),
                int = as.integer(df[[name]]))
}

#' Extract the row list from a response body.
#'
#' The API is not consistent about envelopes:
#'   /api/search/table            → a bare JSON array
#'   /api/publicreports/state     → {totalCount, filteredCount, echo, results}
#'   /api/publicreports/statements→ {…, results}
#'
#' Both shapes are accepted, but anything else is an error rather than an empty
#' result. Returning list() for an unrecognized shape is how you silently ingest
#' nothing and never find out — which is precisely what happened the first time
#' this module ran against the bare-array endpoint.
iecdb_rows <- function(parsed, endpoint) {
  if (is.null(parsed)) return(list())            # HTTP 204
  if (!is.null(parsed$results)) return(parsed$results)
  if (is.list(parsed) && is.null(names(parsed))) return(parsed)  # bare array
  stop(sprintf(
    paste0("IECDB response shape not recognized at %s.\n",
           "  Expected a bare JSON array or an object with `results`.\n",
           "  Got an object with fields: %s"),
    endpoint, paste(names(parsed), collapse = ", ")
  ), call. = FALSE)
}

# ── Parsing helpers ───────────────────────────────────────────────────────────

pluck_chr <- function(x, key) {
  v <- purrr::pluck(x, key, .default = NA_character_)
  if (is.null(v)) NA_character_ else as.character(v)
}
pluck_int <- function(x, key) {
  v <- purrr::pluck(x, key, .default = NA_integer_)
  if (is.null(v)) NA_integer_ else as.integer(v)
}
# IECDB timestamps are ISO with no zone: "2026-07-20T17:06:03.657"
parse_iecdb_stamp <- function(x) as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS", tz = "America/Chicago")
parse_iecdb_day   <- function(x) as.Date(substr(x, 1, 10))

# ── Endpoint: committee search ────────────────────────────────────────────────

#' Search committees by name or exact committee code.
#'
#' `criteria` is the ONLY field the endpoint honors — any other key is silently
#' ignored and returns an unfiltered list of 20, which looks like a working
#' query but is not. Returns both `committee_uuid` (the GUID the transaction
#' endpoint requires) and `committee_code` (our key everywhere else).
iecdb_committee_search <- function(criteria, filer_type_ids = list()) {
  stopifnot(is.character(criteria), length(criteria) == 1L, nzchar(criteria))

  rows <- iecdb_post("/api/search/committee",
                     list(criteria = criteria, filerTypeIds = filer_type_ids))
  if (is.null(rows) || length(rows) == 0) return(iecdb_empty_committees())

  iecdb_validate(rows, "committee", "/api/search/committee")

  map(rows, \(r) tibble(
    committee_code    = pluck_chr(r, "committeeCode"),
    committee_uuid    = pluck_chr(r, "id"),
    committee_name    = pluck_chr(r, "name"),
    political_party   = pluck_chr(r, "politicalParty"),
    filer_type        = pluck_chr(r, "filerTypeName"),
    committee_type_cd = pluck_chr(r, "committeeTypeCd"),
    description       = pluck_chr(r, "description"),
    office_sought     = pluck_chr(r, "nameOfOfficeSought"),
    district_number   = pluck_int(r, "districtNumber"),
    county_cd         = pluck_chr(r, "county"),
    election_year     = pluck_int(r, "electionYear"),
    election_date     = parse_iecdb_day(pluck_chr(r, "electionDate")),
    committee_email   = pluck_chr(r, "committeeEmail")
  )) |> list_rbind()
}

iecdb_empty_committees <- function() {
  tibble(committee_code = character(), committee_uuid = character(),
         committee_name = character(), political_party = character(),
         filer_type = character(), committee_type_cd = character(),
         description = character(), office_sought = character(),
         district_number = integer(), county_cd = character(),
         election_year = integer(), election_date = as.Date(character()),
         committee_email = character())
}

#' Resolve a single committee code to its row, requiring an exact match.
iecdb_committee_by_code <- function(committee_code) {
  hits <- iecdb_committee_search(committee_code)
  exact <- filter(hits, .data$committee_code == !!committee_code)
  if (nrow(exact) == 0) return(iecdb_empty_committees())
  exact[1, ]
}

# ── Endpoint: transactions ────────────────────────────────────────────────────

#' Contributions or expenditures for one committee.
#'
#' A committee GUID is MANDATORY: the endpoint returns 204 No Content without
#' one, with or without a date window, so there is no bulk "give me everything"
#' query. We check locally rather than spending a request to be told no.
#'
#' Returns the complete result set in one response — no paging. Sand's committee
#' is ~257k rows, so expect large payloads and cache the result.
#'
#' @param committee_uuid GUID from iecdb_committee_search() (or the
#'   `committee_uuid` column of committee_lookup.rds).
#' @param transaction_type "CON" contributions or "EXP" expenditures.
#' @param date_from,date_to optional "YYYY-MM-DD" bounds (inclusive).
#' @param transaction_option Portal's "Transaction Option" selector. 1 = to a
#'   committee, which is what the UI sends by default. Other values unverified.
iecdb_transactions <- function(committee_uuid,
                               transaction_type   = c("CON", "EXP"),
                               date_from          = NULL,
                               date_to            = NULL,
                               transaction_option = 1L) {
  transaction_type <- match.arg(transaction_type)

  if (is.null(committee_uuid) || is.na(committee_uuid) || !nzchar(committee_uuid)) {
    stop(paste0(
      "iecdb_transactions() requires a committee_uuid. The API returns 204 ",
      "No Content when primaryCommitteeId is null — there is no unfiltered ",
      "bulk query. Iterate committees instead, driven by iecdb_filings()."
    ), call. = FALSE)
  }

  body <- list(
    primaryCommitteeId  = committee_uuid,
    secondaryCommitteeId = NULL,
    transactionType     = transaction_type,
    primaryCommittee    = NULL,
    dateFrom            = date_from,
    dateTo              = date_to,
    transactionOption   = transaction_option,
    secondaryCommittee  = NULL
  )

  df <- iecdb_post_df("/api/search/table", body)
  if (is.null(df) || nrow(df) == 0) return(iecdb_empty_transactions())

  iecdb_validate_df(df, "transaction", "/api/search/table")

  tibble(
    transaction_id     = col_or_na(df, "transactionId"),
    date               = parse_iecdb_day(col_or_na(df, "date")),
    transaction_type   = col_or_na(df, "transactionType"),
    amount             = col_or_na(df, "amount", "num"),
    committee_code     = col_or_na(df, "primaryCommitteeCode"),
    committee_name     = col_or_na(df, "primaryName"),
    counterparty_code  = col_or_na(df, "secondaryCommitteeCode"),
    counterparty_name  = col_or_na(df, "secondaryName"),
    counterparty_addr1 = col_or_na(df, "secondaryAddress1"),
    counterparty_addr2 = col_or_na(df, "secondaryAddress2"),
    counterparty_city  = col_or_na(df, "secondaryCity"),
    counterparty_state = col_or_na(df, "secondaryState"),
    counterparty_zip   = col_or_na(df, "secondaryZip"),
    check_number       = col_or_na(df, "checkNumber"),
    reference_type     = na_if(col_or_na(df, "referenceType"), ""),
    # NOT reporting-period attribution. Despite the name, this is the all-zeros
    # GUID on every ordinary contribution (checked across all 1,175 Lahn rows),
    # with referenceType empty alongside it. It appears to be reserved for
    # earmarked/referred transactions and is unpopulated for normal ones.
    # Period attribution has to be inferred from `date` against the period
    # boundaries in iecdb_filings(). Normalized to NA so it can't be mistaken
    # for a real key.
    reference_dr2_id   = na_if(na_if(col_or_na(df, "referenceDR2Id"),
                                     "00000000-0000-0000-0000-000000000000"), "")
  )
}

#' Field contract check for the data-frame parse path.
iecdb_validate_df <- function(df, contract, endpoint) {
  required <- IECDB_REQUIRED_FIELDS[[contract]]
  missing  <- setdiff(required, names(df))
  if (length(missing) > 0) {
    stop(sprintf(
      paste0("IECDB schema drift at %s.\n",
             "  Missing required field(s): %s\n",
             "  Observed fields: %s\n",
             "Inspect the response and update IECDB_REQUIRED_FIELDS and the ",
             "parser together — do not relax the contract to make this pass."),
      endpoint, paste(missing, collapse = ", "), paste(names(df), collapse = ", ")
    ), call. = FALSE)
  }
  if (isTRUE(iecdb_opts()$verbose)) {
    extra <- setdiff(names(df), c(required, IECDB_KNOWN_FIELDS[[contract]]))
    if (length(extra) > 0)
      message(sprintf("  note: %s returned unrecognized field(s): %s",
                      endpoint, paste(extra, collapse = ", ")))
  }
  invisible(NULL)
}

iecdb_empty_transactions <- function() {
  tibble(transaction_id = character(), date = as.Date(character()),
         transaction_type = character(), amount = numeric(),
         committee_code = character(), committee_name = character(),
         counterparty_code = character(), counterparty_name = character(),
         counterparty_addr1 = character(), counterparty_addr2 = character(),
         counterparty_city = character(), counterparty_state = character(),
         counterparty_zip = character(), check_number = character(),
         reference_type = character(), reference_dr2_id = character())
}

# ── Endpoint: filings index (the change feed) ─────────────────────────────────

#' Every state DR2 filing, in one request.
#'
#' ~17,900 rows spanning 1999–present, each with `filed_on` and a direct PDF
#' URL. This is the only unfiltered call the API offers, and it is the basis of
#' change detection: diff `filed_on` per committee against a manifest and
#' re-pull transactions only for committees that moved.
#'
#' `file_url` points at unauthenticated blob storage. The timestamp embedded in
#' the filename is not derivable — this index is the only way to resolve it.
iecdb_filings <- function() {
  parsed <- iecdb_post("/api/publicreports/state", list())
  rows   <- iecdb_rows(parsed, "/api/publicreports/state")
  if (length(rows) == 0) return(tibble())

  iecdb_validate(rows, "filing", "/api/publicreports/state")

  map(rows, \(r) tibble(
    filing_id          = pluck_chr(r, "id"),
    committee_code     = pluck_chr(r, "committeeCode"),
    committee_name     = pluck_chr(r, "committeeName"),
    candidate_name     = pluck_chr(r, "candidateName"),
    organization_type  = pluck_chr(r, "organizationType"),
    report_type        = pluck_chr(r, "reportType"),
    period_year        = pluck_int(r, "periodYear"),
    period_description = pluck_chr(r, "periodDescription"),
    filed_on           = parse_iecdb_stamp(pluck_chr(r, "filedOn")),
    file_name          = pluck_chr(r, "fileName"),
    file_url           = pluck_chr(r, "fileUrl")
  )) |> list_rbind()
}

# ── Endpoint: statements of organization / dissolution ────────────────────────

#' Every Statement of Organization and Dissolution ever filed.
#'
#' The widest available universe of committee codes (~7,900), including
#' dissolved committees absent from the registered-committees CSV.
#' Extracted from 01_build_committee_lookup.R so both share one client.
iecdb_statements <- function(page_length = 99999L) {
  parsed <- iecdb_post("/api/publicreports/statements", list(
    table = list(
      pageLength   = page_length,
      page         = 0L,
      sortField    = "committeeName",
      sortOrder    = "ascend",
      echo         = 1L,
      filters      = list(),
      globalFilter = NULL
    ),
    row = NULL
  ))
  rows <- iecdb_rows(parsed, "/api/publicreports/statements")
  if (length(rows) == 0) return(tibble())

  iecdb_validate(rows, "statement", "/api/publicreports/statements")

  map(rows, \(r) tibble(
    committee_code = pluck_chr(r, "committeeCode"),
    committee_uuid = pluck_chr(r, "committeeId"),
    committee_name = pluck_chr(r, "committeeName"),
    candidate_name = pluck_chr(r, "candidateName"),
    org_type       = pluck_chr(r, "organizationType"),
    report_type    = pluck_chr(r, "reportType"),
    filed_on       = parse_iecdb_stamp(pluck_chr(r, "filedOn")),
    is_closed      = purrr::pluck(r, "isClosed", .default = NA),
    year_closed    = pluck_int(r, "yearClosed"),
    file_url       = pluck_chr(r, "fileUrl")
  )) |> list_rbind()
}

# ── Filing PDF download ───────────────────────────────────────────────────────

#' Download a filed DR2 report PDF from IECDB's blob storage.
#'
#' Despite the "Summary" in the filenames, these are the COMPLETE filed
#' reports: page 1 is the Statement of Cash On Hand (beginning/ending balance),
#' and the schedules follow with row-level detail — including Schedule F1
#' Loans Received, which is the only public source for loans the transaction
#' API omits. The PDFs are digitally generated (not scanned); pdftools::pdf_text()
#' extracts them cleanly.
#'
#' Counts against the same throttle and request budget as API calls even though
#' blob storage is a different host — a thousand PDF fetches is still a
#' thousand requests against state infrastructure.
#'
#' @param file_url `file_url` from iecdb_filings().
#' @param dest_path where to write the PDF. Skipped if it already exists
#'   (filenames embed a generation timestamp, so a same-named file is the
#'   same document).
iecdb_download_filing <- function(file_url, dest_path) {
  stopifnot(is.character(file_url), length(file_url) == 1L,
            startsWith(file_url, "https://iecdbblobstorage.blob.core.windows.net/"))
  if (file.exists(dest_path)) return(invisible(dest_path))

  opts <- iecdb_opts()
  if (.iecdb$n_requests >= opts$max_requests) {
    stop(sprintf("IECDB request budget exhausted (%d requests).", opts$max_requests),
         call. = FALSE)
  }
  iecdb_throttle(opts$delay)
  .iecdb$n_requests <- .iecdb$n_requests + 1L

  dir.create(dirname(dest_path), recursive = TRUE, showWarnings = FALSE)
  request(file_url) |>
    req_user_agent(IECDB_USER_AGENT) |>
    req_timeout(opts$timeout) |>
    req_retry(max_tries = opts$max_tries, backoff = \(i) min(60, 2^i)) |>
    req_perform(path = dest_path)
  invisible(dest_path)
}

# ── Canary ────────────────────────────────────────────────────────────────────

#' Cheap end-to-end check against known-good values. Two requests.
#'
#' Run before any long ingest: it catches an API that has changed shape,
#' started refusing us, or begun returning different data, before we spend
#' thousands of calls discovering that the hard way.
iecdb_health_check <- function(verbose = TRUE) {
  say <- function(...) if (verbose) message(...)
  checks <- list()

  cm <- iecdb_committee_by_code("5185")
  checks$committee_resolves <- nrow(cm) == 1L
  checks$uuid_stable <- identical(
    tolower(cm$committee_uuid[1]), "6a0d5912-88d5-431d-a00f-33e87237a523"
  )
  checks$name_stable <- identical(cm$committee_name[1], "Rob Sand for Iowa")

  # A short, bounded window — enough to prove transactions flow without
  # pulling a quarter-million rows.
  tx <- iecdb_transactions(cm$committee_uuid[1], "CON",
                           date_from = "2026-07-13", date_to = "2026-07-14")
  checks$transactions_return <- nrow(tx) > 0
  checks$code_joins          <- all(tx$committee_code == "5185", na.rm = TRUE)
  checks$dates_in_window     <- all(tx$date >= as.Date("2026-07-13") &
                                    tx$date <= as.Date("2026-07-14"), na.rm = TRUE)
  checks$amounts_numeric     <- is.numeric(tx$amount) && all(!is.na(tx$amount))
  # The contributions category mixes CON and INK; anything else is new.
  checks$types_as_expected   <- all(tx$transaction_type %in% c("CON", "INK"))

  ok <- unlist(checks)
  for (nm in names(ok)) say(sprintf("  [%s] %s", if (ok[[nm]]) "ok" else "FAIL", nm))
  say(sprintf("  %d/%d passed, %d request(s) used",
              sum(ok), length(ok), iecdb_request_count()))

  if (!all(ok)) {
    stop("IECDB health check failed: ",
         paste(names(ok)[!ok], collapse = ", "),
         ". Investigate before running an ingest.", call. = FALSE)
  }
  invisible(TRUE)
}
