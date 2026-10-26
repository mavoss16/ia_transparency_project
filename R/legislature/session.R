# session.R
#
# Which General Assembly the pipeline works on, and where each session's files
# live. Every script and template gets its session paths from ga_paths() and
# its session wording from ga_label() / ga_years(), so moving to a new General
# Assembly is a change to CURRENT_GA (plus a LegiScan session ID lookup), not
# a search-and-replace.
#
# Layout, per session:
#   legiscan/ga{N}/json/{bill,vote,people}/  raw LegiScan JSON
#   legiscan/ga{N}/derived/                  CSVs built from the JSON (01c)
#   legiscan/ga{N}/csv/                      LegiScan's own bulk CSV dataset
#   data/legislature/ga{N}/{votes,bills,lobbying,pipeline_internal}/
#
# Shared across sessions: data/legislature/districts/ (keyed by district plan,
# not session) and data/legislature/pipeline_internal/pipeline_runs.rds.

library(here)

#' The General Assembly the daily pipeline collects and the site leads with
CURRENT_GA <- 91L

# GA -> LegiScan session ID cache. legiscan_session_id() fills it from
# getSessionList the first time a session is asked for.
SESSION_ID_CACHE <- here("data/legislature/legiscan_sessions.csv")

#' First calendar year of a General Assembly (the 91st convened in 2025)
ga_start_year <- function(ga) 1843L + 2L * as.integer(ga)

#' Inverse of ga_start_year(), for LegiScan sessions identified by year
year_to_ga <- function(year_start) (as.integer(year_start) - 1843L) %/% 2L

#' Directory and URL slug for a session: "ga91"
ga_slug <- function(ga) paste0("ga", as.integer(ga))

#' English ordinal: 91 -> "91st", 92 -> "92nd", 113 -> "113th"
ga_ordinal <- function(ga) {
  ga <- as.integer(ga)
  suffix <- ifelse(ga %% 100 %in% 11:13, "th",
                   c("th", "st", "nd", "rd", rep("th", 6))[ga %% 10 + 1])
  paste0(ga, suffix)
}

#' "91st General Assembly"
ga_label <- function(ga) paste(ga_ordinal(ga), "General Assembly")

#' "2025–2026"
ga_years <- function(ga) {
  start <- ga_start_year(ga)
  paste0(start, "–", start + 1L)
}

#' Resolve a template's `ga` parameter: NULL or "" means the current session
resolve_ga <- function(ga = NULL) {
  if (is.null(ga) || length(ga) == 0 || is.na(ga) || identical(ga, "")) CURRENT_GA
  else as.integer(ga)
}

#' Every path that belongs to one session
#' @param ga General Assembly number (default: CURRENT_GA)
#' @return Named list of absolute paths
ga_paths <- function(ga = CURRENT_GA) {
  slug     <- ga_slug(ga)
  legiscan <- here("legiscan", slug)
  json     <- file.path(legiscan, "json")
  data     <- here("data/legislature", slug)

  list(
    ga          = as.integer(ga),
    legiscan    = legiscan,
    json        = json,
    bill_json   = file.path(json, "bill"),
    vote_json   = file.path(json, "vote"),
    people_json = file.path(json, "people"),
    derived     = file.path(legiscan, "derived"),
    bulk_csv    = file.path(legiscan, "csv"),
    data        = data,
    votes       = file.path(data, "votes"),
    bills       = file.path(data, "bills"),
    lobbying    = file.path(data, "lobbying"),
    internal    = file.path(data, "pipeline_internal")
  )
}

# URLs ----------------------------------------------------------------------
# Bill numbers restart every General Assembly and committee IDs are tied to
# one, so their pages live under a session directory:
#   docs/legislation/ga91/HF1.html
#   docs/committees/ga91/house-appropriations-7087.html
# Legislator pages stay at docs/legislators/{name}-{people_id}.html, because
# LegiScan's people_id is the same person across sessions.

#' Relative href of a session's bill directory, with a trailing slash
#' @param ga General Assembly
#' @param up How many directories the linking page sits below docs/
#'   (0 = site root, 1 = docs/legislators/, 2 = docs/committees/ga91/)
bill_dir_href <- function(ga = CURRENT_GA, up = 0) {
  paste0(strrep("../", up), "legislation/", ga_slug(ga), "/")
}

#' Render-manifest key for a page that belongs to one session: "ga91/HF1"
session_item_id <- function(ga, id) paste0(ga_slug(ga), "/", id)

#' Path to one of a session's derived CSVs: ga_csv("bills") -> .../derived/bills.csv
ga_csv <- function(name, ga = CURRENT_GA) {
  file.path(ga_paths(ga)$derived, paste0(name, ".csv"))
}

#' LegiScan session ID for a General Assembly
#'
#' Reads the cache first. On a miss, asks LegiScan's getSessionList (needs
#' LEGISCAN_API_KEY), records every regular Iowa session it returns, and
#' tries again. Special sessions are skipped: they carry their own IDs and
#' are not separate General Assemblies.
#' @param ga General Assembly number
#' @return Integer session ID
legiscan_session_id <- function(ga = CURRENT_GA) {
  ga <- as.integer(ga)
  cache <- if (file.exists(SESSION_ID_CACHE)) {
    readr::read_csv(SESSION_ID_CACHE, col_types = "iic")
  } else {
    tibble::tibble(ga = integer(), session_id = integer(), session_name = character())
  }

  hit <- cache$session_id[cache$ga == ga]
  if (length(hit) == 1) return(hit)

  api_key <- Sys.getenv("LEGISCAN_API_KEY")
  if (nchar(api_key) == 0L) {
    stop("No cached LegiScan session ID for the ", ga_label(ga),
         " and LEGISCAN_API_KEY is not set to look it up.")
  }

  message("Looking up LegiScan session IDs for Iowa (getSessionList)...")
  resp <- httr2::request("https://api.legiscan.com/") |>
    httr2::req_url_query(key = api_key, op = "getSessionList", state = "IA") |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  if (!identical(resp$status, "OK")) stop("getSessionList returned status ", resp$status)

  sessions <- purrr::map(resp$sessions, \(s) tibble::tibble(
    ga = year_to_ga(s$year_start),
    session_id = as.integer(s$session_id),
    session_name = s$session_name,
    special = as.integer(s$special)
  )) |>
    purrr::list_rbind() |>
    dplyr::filter(special == 0) |>
    dplyr::select(-special)

  cache <- dplyr::bind_rows(cache, sessions) |>
    dplyr::distinct(ga, .keep_all = TRUE) |>
    dplyr::arrange(ga)
  dir.create(dirname(SESSION_ID_CACHE), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(cache, SESSION_ID_CACHE)

  hit <- cache$session_id[cache$ga == ga]
  if (length(hit) != 1) stop("LegiScan has no regular session for the ", ga_label(ga), " yet.")
  hit
}
