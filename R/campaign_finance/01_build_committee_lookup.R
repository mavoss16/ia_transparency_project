# 01_build_committee_lookup.R
#
# Builds a committee_code → party/metadata lookup table by querying two
# IECDB web app APIs:
#
#   Step 1 — POST /api/publicreports/statements (one call, no limit)
#     Returns every Statement of Organization and Dissolution ever filed,
#     giving us the full universe of committee codes — including inactive/
#     dissolved committees not in the registered-committees CSV export.
#
#   Step 2 — POST /api/search/committee (one call per unique code)
#     Searching by exact committee code returns a single match with full
#     committee metadata, including political party affiliation.
#     Results are written to a checkpoint file every BATCH_SIZE codes so
#     the script can be safely interrupted and resumed.
#
# Coverage: ~7,900 unique codes vs. ~1,600 in the registered CSV export.
#
# Output: data/campaign_finance/processed/committee_lookup[_TEST].rds
#         (checkpoint: same directory, suffix _checkpoint.rds)

library(httr2)
library(dplyr)
library(purrr)
library(here)

# ── Config ────────────────────────────────────────────────────────────────────

TEST_MODE  <- FALSE  # FALSE for full run (~7,900 codes, ~15 min)
TEST_N     <- 25    # codes to sample in test mode; set.seed(42) for reproducibility
BATCH_SIZE <- 100   # rows written to checkpoint after each batch
RATE_LIMIT <- 0.1   # seconds between requests

BASE_URL   <- "https://webapp.iecdb.iowa.gov"

out_dir    <- here("data/campaign_finance/processed")
suffix     <- if (TEST_MODE) "_TEST" else ""
out_path   <- file.path(out_dir, paste0("committee_lookup", suffix, ".rds"))
ckpt_path  <- file.path(out_dir, paste0("committee_lookup", suffix, "_checkpoint.rds"))

# ── Helpers ───────────────────────────────────────────────────────────────────

post_json <- function(path, body) {
  request(paste0(BASE_URL, path)) |>
    req_method("POST") |>
    req_headers(Accept = "application/json", `Content-Type` = "application/json") |>
    req_body_json(body) |>
    req_perform() |>
    resp_body_json()
}

pluck_chr <- function(x, key) pluck(x, key, .default = NA_character_)
pluck_int <- function(x, key) {
  v <- pluck(x, key, .default = NA_integer_)
  if (is.null(v)) NA_integer_ else as.integer(v)
}

parse_committee <- function(r) {
  tibble(
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
    election_date_raw = pluck_chr(r, "electionDate"),
    committee_email   = pluck_chr(r, "committeeEmail"),
  )
}

lookup_one <- function(code) {
  Sys.sleep(RATE_LIMIT)
  tryCatch({
    results <- post_json("/api/search/committee", list(
      criteria     = code,
      filerTypeIds = list()
    ))
    match <- keep(results, \(r) identical(r[["committeeCode"]], code))
    if (length(match) == 0) {
      message(sprintf("    WARNING: no exact match for '%s'", code))
      tibble(committee_code = code)
    } else {
      parse_committee(match[[1]])
    }
  }, error = function(e) {
    message(sprintf("    ERROR for '%s': %s", code, conditionMessage(e)))
    tibble(committee_code = code)
  })
}

# ── Step 1: fetch all statements ──────────────────────────────────────────────

message("Step 1: Fetching all Statements of Organization and Dissolution...")

raw <- post_json("/api/publicreports/statements", list(
  table = list(
    pageLength   = 99999L,
    page         = 0L,
    sortField    = "committeeName",
    sortOrder    = "ascend",
    echo         = 1L,
    filters      = list(),
    globalFilter = NULL
  ),
  row = NULL
))

statements <- raw$results |>
  map(\(r) tibble(
    committee_code = pluck_chr(r, "committeeCode"),
    committee_name = pluck_chr(r, "committeeName"),
    candidate_name = pluck_chr(r, "candidateName"),
    org_type       = pluck_chr(r, "organizationType"),
    report_type    = pluck_chr(r, "reportType"),
    filed_on       = pluck_chr(r, "filedOn"),
    is_closed      = pluck(r, "isClosed", .default = NA),
    year_closed    = pluck_int(r, "yearClosed"),
    file_url       = pluck_chr(r, "fileUrl"),
    committee_uuid = pluck_chr(r, "committeeId"),
  )) |>
  list_rbind()

all_codes <- unique(statements$committee_code)

message(sprintf(
  "  %d statement records → %d unique committee codes.",
  nrow(statements), length(all_codes)
))

if (TEST_MODE) {
  set.seed(42)
  all_codes <- sample(all_codes, min(TEST_N, length(all_codes)))
  message(sprintf("  TEST MODE: sampling %d codes.", length(all_codes)))
}

# ── Step 2: look up party and metadata (batched with checkpointing) ───────────

# Resume from checkpoint if one exists
if (file.exists(ckpt_path)) {
  accumulated <- readRDS(ckpt_path)
  done_codes  <- unique(accumulated$committee_code)
  remaining   <- setdiff(all_codes, done_codes)
  message(sprintf(
    "\nResuming from checkpoint: %d done, %d remaining.",
    length(done_codes), length(remaining)
  ))
} else {
  accumulated <- tibble()
  remaining   <- all_codes
}

batches   <- split(remaining, ceiling(seq_along(remaining) / BATCH_SIZE))
n_batches <- length(batches)

if (n_batches == 0) {
  message("\nAll codes already processed — skipping Step 2.")
} else {
  message(sprintf(
    "\nStep 2: Looking up %d committees in %d batch(es) of up to %d...",
    length(remaining), n_batches, BATCH_SIZE
  ))

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    message(sprintf("\n  Batch %d/%d — %d codes", i, n_batches, length(batch)))

    batch_results <- map(batch, lookup_one) |> list_rbind()

    accumulated <- bind_rows(accumulated, batch_results)
    saveRDS(accumulated, ckpt_path)
    message(sprintf(
      "  Checkpoint saved: %d total rows (codes %d–%d of %d).",
      nrow(accumulated),
      length(accumulated$committee_code) - nrow(batch_results) + 1,
      nrow(accumulated),
      length(all_codes)
    ))
  }
}

# ── Tidy: decode party codes, parse dates ────────────────────────────────────

party_labels <- c(
  R = "Republican",
  D = "Democratic",
  L = "Libertarian",
  G = "Green",
  I = "Independent",
  O = "Other",
  N = NA_character_   # nonpartisan / not applicable
)

committee_lookup <- accumulated |>
  mutate(
    party         = recode(political_party, !!!party_labels),
    election_date = as.Date(substr(election_date_raw, 1, 10))
  ) |>
  select(-election_date_raw) |>
  relocate(
    committee_code, party, political_party, committee_name,
    filer_type, office_sought, election_year, election_date,
    district_number, county_cd, committee_type_cd, description,
    committee_email, committee_uuid
  )

# ── Summary ───────────────────────────────────────────────────────────────────

message("\n── Party distribution ──────────────────────────────────────────────────")
committee_lookup |>
  count(party, sort = TRUE, name = "n_committees") |>
  print()

message("\n── Filer type distribution ─────────────────────────────────────────────")
committee_lookup |>
  count(filer_type, sort = TRUE) |>
  print()

n_unmatched <- sum(is.na(committee_lookup$committee_uuid))
if (n_unmatched > 0) {
  message(sprintf("\nWARNING: %d code(s) had no exact match in the search API.", n_unmatched))
}

# ── Save final output and clean up checkpoint ─────────────────────────────────

saveRDS(committee_lookup, out_path)
message(sprintf("\nSaved %d rows → %s", nrow(committee_lookup), out_path))

if (file.exists(ckpt_path)) {
  file.remove(ckpt_path)
  message("Checkpoint file removed.")
}
