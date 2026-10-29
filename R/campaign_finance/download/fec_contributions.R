# R/campaign_finance/download/fec_contributions.R
#
# Downloads FEC bulk data for configured election cycles and writes Iowa
# individual contributions plus the committee/candidate lookup files used
# by 02a_clean_normalize_federal.R.
#
# Outputs (data/campaign_finance/source/federal/{cycle}/):
#   indiv_iowa_cands.txt  — contributions TO Iowa House/Senate candidates (from any donor)
#   cm.txt                — Committee master (full; ~10k rows)
#   cn.txt                — Candidate master (full; ~20k rows)
#   ccl.txt               — Candidate-committee linkage (full; ~15k rows)
#
# Filter logic: cn.txt is read first to find Iowa H/S candidate IDs; ccl.txt maps
# those to authorized committee IDs; indiv*.zip is then filtered by CMTE_ID.
#
# The national indiv*.zip is ~3–4 GB compressed / ~12–15 GB unzipped. This
# script reads directly from the zip via an unz() connection to avoid writing
# the full extracted file to disk. readr::read_delim_chunked() bounds memory
# use during the filter pass.
#
# FEC data dictionary:
#   https://www.fec.gov/campaign-finance-data/contributions-individuals-file-description/
#
# Run: source("R/campaign_finance/download/fec_contributions.R")

library(httr2)
library(vroom)
library(readr)
library(dplyr)
library(stringr)
library(purrr)
library(here)

# ── Config ────────────────────────────────────────────────────────────────────

# 2-year election cycles to download (folder name = even year end of cycle).
CYCLES <- c(2020, 2022, 2024, 2026)

# Only Iowa House and Senate races. Excludes presidential (CAND_OFFICE = "P")
# since those are national committees, not Iowa-specific.
IOWA_OFFICES <- c("H", "S")

FEC_BASE     <- "https://www.fec.gov/files/bulk-downloads"
HEADERS_DIR  <- here("data/campaign_finance/source/federal/headers")
OUTPUT_BASE  <- here("data/campaign_finance/source/federal")

if (!dir.exists(HEADERS_DIR)) dir.create(HEADERS_DIR, recursive = TRUE)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Fetch column names from the FEC header CSV for a given file type and cache
# locally. FEC data files have no header row; names must be supplied separately.
fetch_fec_cols <- function(file_type) {
  cached <- file.path(HEADERS_DIR, paste0(file_type, "_cols.rds"))
  if (file.exists(cached)) return(readRDS(cached))

  url  <- paste0(
    "https://www.fec.gov/files/bulk-downloads/data_dictionaries/",
    file_type, "_header_file.csv"
  )
  cols <- request(url) |>
    req_perform() |>
    resp_body_string() |>
    str_split(",") |>
    pluck(1) |>
    str_trim() |>
    str_to_upper()

  saveRDS(cols, cached)
  message(sprintf("  Cached %d column names for '%s'.", length(cols), file_type))
  cols
}

fec_zip_url <- function(cycle, file_type) {
  yy <- sprintf("%02d", cycle %% 100)
  sprintf("%s/%d/%s%s.zip", FEC_BASE, cycle, file_type, yy)
}

# Download zip to out_dir; skip if already present. Returns local path.
download_zip <- function(url, out_dir) {
  dest <- file.path(out_dir, basename(url))
  if (file.exists(dest)) {
    message("    Already downloaded: ", basename(dest))
    return(dest)
  }
  message("    Downloading ", basename(url), " ...")
  request(url) |>
    req_timeout(3600) |>
    req_retry(max_tries = 3, backoff = \(i) 30) |>
    req_progress() |>
    req_perform(path = dest)
  dest
}

# Read a pipe-delimited FEC file from within a zip archive without full
# extraction. For large files, filter_fn triggers chunked reading.
read_zip_fec <- function(zip_path, col_names, filter_fn = NULL,
                         chunk_size = 500000) {
  contents <- unzip(zip_path, list = TRUE)
  txt_name <- contents$Name[str_detect(contents$Name, regex("\\.txt$", TRUE))][[1]]

  if (!is.null(filter_fn)) {
    con      <- unz(zip_path, txt_name)
    callback <- DataFrameCallback$new(filter_fn)
    result   <- read_delim_chunked(
      con,
      callback   = callback,
      delim      = "|",
      col_names  = col_names,
      col_types  = cols(.default = col_character()),
      chunk_size = chunk_size,
      progress   = FALSE
    )
    result
  } else {
    con <- unz(zip_path, txt_name)
    read_delim(
      con,
      delim      = "|",
      col_names  = col_names,
      col_types  = cols(.default = col_character()),
      progress   = FALSE
    )
  }
}

# ── Per-cycle processing ───────────────────────────────────────────────────────

process_cycle <- function(cycle) {
  out_dir <- file.path(OUTPUT_BASE, as.character(cycle))
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  message(sprintf(
    "\n── Cycle %d ─────────────────────────────────────────────────────────────", cycle
  ))

  # ---- Small lookup files: committee master, candidate master, linkage --------

  small <- list(
    list(type = "cm",  label = "committee master",            out = file.path(out_dir, "cm.txt")),
    list(type = "cn",  label = "candidate master",            out = file.path(out_dir, "cn.txt")),
    list(type = "ccl", label = "candidate-committee linkage", out = file.path(out_dir, "ccl.txt"))
  )

  walk(small, function(f) {
    if (file.exists(f$out)) {
      message(sprintf("  Skipping %s (already exists)", f$label))
      return(invisible(NULL))
    }

    message(sprintf("  %s...", str_to_sentence(f$label)))
    cols <- fetch_fec_cols(f$type)
    zip  <- download_zip(fec_zip_url(cycle, f$type), out_dir)
    data <- read_zip_fec(zip, cols)
    vroom_write(data, f$out, delim = "|")
    unlink(zip)
    message(sprintf("    %s rows → %s", scales::comma(nrow(data)), basename(f$out)))
  })

  # ---- Build Iowa candidate committee ID set from just-downloaded lookups ------

  cn_data  <- vroom(file.path(out_dir, "cn.txt"),  delim = "|",
                    col_types = cols(.default = col_character()), show_col_types = FALSE)
  ccl_data <- vroom(file.path(out_dir, "ccl.txt"), delim = "|",
                    col_types = cols(.default = col_character()), show_col_types = FALSE)

  iowa_cand_ids <- cn_data |>
    filter(CAND_OFFICE_ST == "IA", CAND_OFFICE %in% IOWA_OFFICES) |>
    pull(CAND_ID)

  iowa_cmte_ids <- ccl_data |>
    filter(CAND_ID %in% iowa_cand_ids) |>
    pull(CMTE_ID) |>
    unique()

  message(sprintf("  %d Iowa H/S candidates → %d authorized committees",
                  length(iowa_cand_ids), length(iowa_cmte_ids)))

  if (length(iowa_cmte_ids) == 0) {
    message("  WARNING: no Iowa candidate committees found — skipping indiv download.")
    return(invisible(NULL))
  }

  # ---- Individual contributions: filter to Iowa candidate committees ----------

  indiv_out <- file.path(out_dir, "indiv_iowa_cands.txt")

  if (file.exists(indiv_out)) {
    message("  Skipping individual contributions (already exists)")
    return(invisible(NULL))
  }

  message("  Individual contributions (filtering to Iowa candidate committees)...")
  message("  Note: zip is ~3-4 GB; streaming avoids writing the full extracted file.")
  message("  Filtering... progress reported every 5M rows (~2-4 min total).")

  cols <- fetch_fec_cols("indiv")
  zip  <- download_zip(fec_zip_url(cycle, "indiv"), out_dir)

  # Track progress across chunks via a shared environment; print every 10 chunks
  # (chunk_size = 500k, so every 10 chunks = every ~5M rows read).
  .prog <- new.env(parent = emptyenv())
  .prog$chunks   <- 0L
  .prog$kept_rows <- 0L

  ia_data <- tryCatch(
    read_zip_fec(
      zip, cols,
      filter_fn = function(chunk, pos) {
        .prog$chunks <- .prog$chunks + 1L
        filtered <- filter(chunk, CMTE_ID %in% iowa_cmte_ids)
        .prog$kept_rows <- .prog$kept_rows + nrow(filtered)
        if (.prog$chunks %% 10L == 0L) {
          message(sprintf("    ... ~%sM rows read, %s kept so far",
                          scales::comma(round(.prog$chunks * 500000 / 1e6, 1)),
                          scales::comma(.prog$kept_rows)))
        }
        filtered
      }
    ),
    error = function(e) {
      message("  ERROR reading indiv file: ", conditionMessage(e))
      NULL
    }
  )

  if (!is.null(ia_data)) {
    vroom_write(ia_data, indiv_out, delim = "|")
    message(sprintf(
      "  %s rows → %s", scales::comma(nrow(ia_data)), basename(indiv_out)
    ))
  }

  unlink(zip)
  invisible(NULL)
}

# ── Run ───────────────────────────────────────────────────────────────────────

message("FEC bulk download — Iowa campaign contributions")
message(sprintf("Cycles: %s | Filter: Iowa candidates for office %s",
                paste(CYCLES, collapse = ", "),
                paste(IOWA_OFFICES, collapse = "/")))

walk(CYCLES, process_cycle)

message("\nDone. Outputs in: ", OUTPUT_BASE)
