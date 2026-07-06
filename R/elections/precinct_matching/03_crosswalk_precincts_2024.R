# Build a precinct crosswalk between 2024 election results and precincts_2020s.rds
# shapefile (LONGNAME column).
#
# Applies normalization in seven escalating stages:
#   1. exact          — verbatim match
#   2. normalized     — upper-case, strip parentheticals, expand TWP, hyphen → space
#   3. strip_1        — normalized + remove 1 trailing code token from election name
#   4. strip_2        — normalized + remove 2 trailing code tokens from election name
#   5. drop_twp       — remove TWP entirely from both sides (compound names like
#                       "HUXLEY 1/UNION TWP 2" and "Zearing/Lincoln Twp/Sherman Twp")
#   6. expand_pct     — replace "PCT" with "PRECINCT" in election name (Des Moines)
#   7. strip_pct      — strip leading "PCT " from election name to expose bare code
#
# Cases not resolved automatically go to a manual crosswalk template. Known
# county name typos in the shapefile are corrected before matching:
#   "Buchananan" → "Buchanan", "O Brien" → "O'Brien"
# Exact duplicate rows in the shapefile (Clinton county) are deduplicated.
#
# Outputs:
#   data/elections/processed/precinct_crosswalk_auto.csv
#     county, elec_name, shp_longname, match_method
#
#   data/elections/processed/precinct_crosswalk_manual.csv
#     county, elec_name, shp_longname (blank), available_shp_names

library(dplyr)
library(readr)
library(purrr)
library(stringr)
library(here)

SHAPEFILE <- here("data/elections/processed/precincts_2020s.rds")
ELEC_FILE <- here("data/elections/processed/2024/precinct_elections_2024.csv")
OUT_DIR   <- here("data/elections/processed")

# ---- Load ----

shp <- readRDS(SHAPEFILE) |>
  as.data.frame() |>
  select(county, shp_name = LONGNAME) |>
  filter(!is.na(shp_name)) |>
  mutate(county = str_to_title(str_replace_all(county, c(
    "Buchananan" = "Buchanan",
    "O Brien"    = "O'Brien"
  )))) |>
  distinct()  # Clinton county has exact duplicate rows

elec <- read_csv(ELEC_FILE, show_col_types = FALSE) |>
  distinct(county, elec_name = precinct)

# ---- Normalization helpers ----

normalize <- function(x) {
  x |>
    str_to_upper() |>
    str_remove("^\\([^)]+\\)\\s*") |>             # leading (CODE) in election names
    str_remove("\\s*\\([^)]+\\)$") |>             # trailing (note) in shapefile names
    str_replace_all("\\bTWP\\.?\\b", "TOWNSHIP") |>
    str_replace_all("-", " ") |>
    str_squish()
}

strip_trailing <- function(x, n) {
  words <- str_split(x, "\\s+")[[1]]
  if (length(words) <= n) return(NA_character_)
  paste(words[seq_len(length(words) - n)], collapse = " ")
}

# Remove TWP entirely (not expand) — handles compound names like
# "HUXLEY 1/UNION TWP 2" → "HUXLEY 1/UNION 2"
normalize_drop_twp <- function(x) {
  x |>
    str_to_upper() |>
    str_remove("^\\([^)]+\\)\\s*") |>
    str_remove("\\s*\\([^)]+\\)$") |>
    str_remove_all("\\bTWP\\.?\\b") |>
    str_replace_all("-", " ") |>
    str_replace_all("/\\s+", "/") |>
    str_squish()
}

# ---- Match stage helper ----
# transform_fn maps an election precinct name to a normalized key.
# Matches against shp_norm (which has a pre-computed `norm` column).
# Only accepts 1-to-1 matches to avoid ambiguous assignments.

match_stage <- function(unmatched, shp_norm, transform_fn, method_name) {
  # Warn if any shapefile keys are duplicated (would cause ambiguous matches)
  dup_keys <- shp_norm |>
    group_by(county, norm) |>
    filter(n() > 1) |>
    ungroup()
  if (nrow(dup_keys) > 0) {
    message("  Warning: ", nrow(dup_keys), " duplicate normalized shapefile keys — ",
            "ambiguous matches excluded.")
  }
  shp_dedup <- shp_norm |>
    group_by(county, norm) |>
    filter(n() == 1) |>
    ungroup()

  candidates <- unmatched |>
    mutate(norm = map_chr(elec_name, transform_fn))

  joined <- candidates |>
    left_join(shp_dedup |> select(county, shp_name, norm),
              by = c("county", "norm")) |>
    filter(!is.na(shp_name))

  # Exclude any election precinct that maps to multiple shapefile rows
  matched <- joined |>
    group_by(county, elec_name) |>
    filter(n() == 1) |>
    ungroup() |>
    mutate(match_method = method_name) |>
    select(county, elec_name, shp_name, match_method)

  matched_keys <- paste(matched$county, matched$elec_name)
  still_unmatched <- unmatched |>
    filter(!paste(county, elec_name) %in% matched_keys)

  list(matched = matched, unmatched = still_unmatched)
}

# ---- Run match pipeline ----

shp_norm        <- shp |> mutate(norm = normalize(shp_name))
shp_norm_no_twp <- shp |> mutate(norm = normalize_drop_twp(shp_name))

# Stage 1: exact
exact <- elec |>
  inner_join(shp |> select(county, shp_name), by = c("county", "elec_name" = "shp_name")) |>
  mutate(shp_name = elec_name, match_method = "exact") |>
  select(county, elec_name, shp_name, match_method)

remaining <- elec |>
  filter(!paste(county, elec_name) %in% paste(exact$county, exact$elec_name))

# Stage 2: normalize both sides (upper, strip parens, TWP→TOWNSHIP, hyphen→space)
s2 <- match_stage(remaining, shp_norm, normalize, "normalized")
remaining <- s2$unmatched

# Stage 3: normalize election name then strip 1 trailing token
s3 <- match_stage(remaining, shp_norm,
                  \(x) strip_trailing(normalize(x), 1), "strip_1")
remaining <- s3$unmatched

# Stage 4: normalize election name then strip 2 trailing tokens
s4 <- match_stage(remaining, shp_norm,
                  \(x) strip_trailing(normalize(x), 2), "strip_2")
remaining <- s4$unmatched

# Stage 5: drop TWP entirely from both sides — handles compound names like
# ELC "HUXLEY 1/UNION TWP 2" → "HUXLEY 1/UNION 2" = SHP "Huxley 1/Union 2"
# SHP "Zearing/Lincoln Twp/Sherman Twp" → "ZEARING/LINCOLN/SHERMAN" = ELC same
s5 <- match_stage(remaining, shp_norm_no_twp, normalize_drop_twp, "drop_twp")
remaining <- s5$unmatched

# Stage 6: expand "PCT" → "PRECINCT" in election name (Des Moines "PCT 1")
s6 <- match_stage(remaining, shp_norm,
                  \(x) normalize(str_replace_all(x, "\\bPCT\\b", "PRECINCT")),
                  "expand_pct")
remaining <- s6$unmatched

# Stage 7: strip leading "PCT " entirely to expose bare code (Des Moines "PCT BHJ")
s7 <- match_stage(remaining, shp_norm,
                  \(x) normalize(str_remove(x, "^PCT\\s+")),
                  "strip_pct")
remaining <- s7$unmatched

# ---- Combine ----

auto <- bind_rows(exact, s2$matched, s3$matched, s4$matched,
                  s5$matched, s6$matched, s7$matched)

# ---- Summary ----

cat("\n=== Match summary ===\n")
count(auto, match_method) |> print()
cat("\nAuto-matched:", nrow(auto), "/", nrow(elec), "(",
    round(100 * nrow(auto) / nrow(elec), 1), "%)\n")
cat("Needs manual:", nrow(remaining), "\n")

cat("\n--- Unmatched by county ---\n")
remaining |>
  count(county, name = "unmatched") |>
  left_join(count(elec, county, name = "total"), by = "county") |>
  mutate(pct = round(100 * unmatched / total, 1)) |>
  arrange(desc(pct)) |>
  print(n = 99)

cat("\n--- Auto-match rate by county (partial matches) ---\n")
auto |>
  count(county, match_method) |>
  left_join(count(elec, county, name = "total"), by = "county") |>
  group_by(county) |>
  summarise(matched = sum(n), total = first(total), .groups = "drop") |>
  filter(matched < total) |>
  mutate(pct = round(100 * matched / total, 1)) |>
  arrange(pct) |>
  print(n = 99)

# ---- Write outputs ----

write_csv(auto, file.path(OUT_DIR, "precinct_crosswalk_auto.csv"))
message("Wrote ", nrow(auto), " rows → precinct_crosswalk_auto.csv")

# Manual template: one row per unmatched election precinct.
# available_shp_names lists what the shapefile has for that county.
shp_by_county <- shp |>
  group_by(county) |>
  summarise(available_shp_names = paste(sort(shp_name), collapse = " | "), .groups = "drop")

manual_template <- remaining |>
  left_join(shp_by_county, by = "county") |>
  mutate(shp_longname = NA_character_) |>
  select(county, elec_name, shp_longname, available_shp_names) |>
  arrange(county, elec_name)

write_csv(manual_template, file.path(OUT_DIR, "precinct_crosswalk_manual.csv"))
message("Wrote ", nrow(manual_template), " rows → precinct_crosswalk_manual.csv")
