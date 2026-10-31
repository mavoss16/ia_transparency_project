# parsers.R
# Read one precinct results file (from download/election_results.R) into long
# rows: county, precinct, contest, candidate, party, votes. Votes are each
# candidate's precinct total (election day + absentee); over and under votes
# are dropped, write-ins kept as "Write-in".
#
# Four layouts, chosen from the file's contents by detect_layout():
#   contest_sheets — one sheet per contest: title row, candidate row (each name
#                    spans its vote-type columns), vote-type row with
#                    "Total Votes", precinct rows, "Total:" row.
#                    SpreadsheetML 2018–2026 (.xml) and 2020 general (.xlsx).
#   clarity_wide   — one row per candidate (RaceTitle, CandidateName,
#                    [PoliticalPartyName]), one column per county-precinct and
#                    vote type ("Adair-1NW Absentee"). 2014, 2016.
#   race_blocks    — blocks headed "Race/contest | County | Precinct | candidates
#                    ... | Over Votes | Under Votes | Total", one row per
#                    precinct. 2010 primary (per county), 2010 general (statewide).
#   county_canvass — the county's printed canvass: a title row per contest,
#                    candidate names (generals add the party on a second line),
#                    then precinct rows. Generals split each precinct into
#                    Election Day / Absentee / Total rows. 2012.
#   canvass_pdf    — the same printed canvass as a PDF, read as text. Scott,
#                    2020 general.
#   clarity_xml    — ENR's detail.xml report: <Contest>, <Choice party=...>,
#                    one <VoteType> per vote type with a <Precinct> each.
#                    2026 primary (ENR published no Excel report).
#
# Usage:
#   source("R/elections/legislative_results/parsers.R")
#   parse_results_file("data/elections/raw/precinct_results/2012_general/adair.xls")

library(readxl)
library(xml2)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)

IOWA_COUNTIES <- c(
  "Adair", "Adams", "Allamakee", "Appanoose", "Audubon",
  "Benton", "Black Hawk", "Boone", "Bremer", "Buchanan",
  "Buena Vista", "Butler", "Calhoun", "Carroll", "Cass",
  "Cedar", "Cerro Gordo", "Cherokee", "Chickasaw", "Clarke",
  "Clay", "Clayton", "Clinton", "Crawford", "Dallas",
  "Davis", "Decatur", "Delaware", "Des Moines", "Dickinson",
  "Dubuque", "Emmet", "Fayette", "Floyd", "Franklin",
  "Fremont", "Greene", "Grundy", "Guthrie", "Hamilton",
  "Hancock", "Hardin", "Harrison", "Henry", "Howard",
  "Humboldt", "Ida", "Iowa", "Jackson", "Jasper",
  "Jefferson", "Johnson", "Jones", "Keokuk", "Kossuth",
  "Lee", "Linn", "Louisa", "Lucas", "Lyon",
  "Madison", "Mahaska", "Marion", "Marshall", "Mills",
  "Mitchell", "Monona", "Monroe", "Montgomery", "Muscatine",
  "O'Brien", "Osceola", "Page", "Palo Alto", "Plymouth",
  "Pocahontas", "Polk", "Pottawattamie", "Poweshiek", "Ringgold",
  "Sac", "Scott", "Shelby", "Sioux", "Story",
  "Tama", "Taylor", "Union", "Van Buren", "Wapello",
  "Warren", "Washington", "Wayne", "Webster", "Winnebago",
  "Winneshiek", "Woodbury", "Worth", "Wright"
)

# Header labels that are tallies, not candidates
NOT_CANDIDATES <- c(
  "over votes", "under votes", "total", "total votes", "precinct totals",
  "final data?", "registered voters", "ballots cast", "precinct", "county", "race"
)

# "black_hawk", "BLACK HAWK", "O'Brien", "obrien" → official county name
canonical_county <- function(x) {
  key <- \(s) str_remove_all(str_to_lower(s), "[^a-z]")
  out <- IOWA_COUNTIES[match(key(x), key(IOWA_COUNTIES))]
  if (anyNA(out)) stop("Unknown county: ", paste(unique(x[is.na(out)]), collapse = ", "))
  out
}

is_legislative <- function(contest) {
  str_detect(str_squish(contest), regex("^state\\s+(rep|sen)", ignore_case = TRUE))
}

clean_candidate <- function(x) {
  x <- str_squish(x)
  if_else(str_detect(x, regex("^write[- ]?in$", ignore_case = TRUE)), "Write-in", x)
}

# One tibble from a matrix block: precinct per row, candidate per column
long_votes <- function(precinct, candidate, votes, party = NA_character_) {
  votes <- as.matrix(votes)
  party <- rep_len(party, length(candidate))
  tibble(
    precinct  = rep(str_squish(precinct), times = ncol(votes)),
    candidate = rep(candidate, each = nrow(votes)),
    party     = rep(party, each = nrow(votes)),
    votes     = suppressWarnings(as.integer(c(votes)))
  )
}

detect_layout <- function(path) {
  ext <- tools::file_ext(path)
  if (ext == "xml") {
    head <- rawToChar(readBin(path, "raw", 500))
    return(if (str_detect(head, fixed("<ElectionResult>"))) "clarity_xml" else "contest_sheets")
  }
  if (ext == "pdf") return("canvass_pdf")
  if (ext == "xlsx" && excel_sheets(path)[1] == "Table of Contents") return("contest_sheets")

  top <- suppressMessages(read_excel(path, col_names = FALSE, col_types = "text", n_max = 1))
  if (identical(top[[1]][1], "RaceTitle")) return("clarity_wide")
  if (ncol(top) > 1 && identical(top[[2]][1], "County")) return("race_blocks")
  if (any(str_detect(unlist(top), "CANVASS SUMMARY"), na.rm = TRUE)) return("county_canvass")
  stop("Unrecognized layout: ", path)
}

# ---- contest_sheets ----

# SpreadsheetML row → values, with MergeAcross cells repeated and Index gaps filled
xml_row_values <- function(row) {
  vals <- character(0)
  for (cell in xml_find_all(row, "./*[local-name()='Cell']")) {
    idx <- xml_attr(cell, "Index")
    if (!is.na(idx)) {
      gap <- as.integer(idx) - 1L - length(vals)
      if (gap > 0L) vals <- c(vals, rep(NA_character_, gap))
    }
    d   <- xml_find_first(cell, "./*[local-name()='Data']")
    val <- if (inherits(d, "xml_missing")) NA_character_ else xml_text(d)
    span <- xml_attr(cell, "MergeAcross")
    vals <- c(vals, rep(val, if (is.na(span)) 1L else as.integer(span) + 1L))
  }
  vals
}

xml_sheet_grid <- function(ws) {
  rows  <- map(xml_find_all(ws, ".//*[local-name()='Row']"), xml_row_values)
  width <- max(lengths(rows))
  do.call(rbind, map(rows, \(r) { length(r) <- width; r }))
}

# Grid of one contest sheet → long votes, using only the "Total Votes" columns
parse_contest_grid <- function(title, grid) {
  header <- which(apply(grid, 1, \(r) any(r == "Total Votes", na.rm = TRUE)))[1]
  if (is.na(header) || header == nrow(grid)) return(NULL)
  cols <- which(grid[header, ] == "Total Votes")
  body <- grid[(header + 1):nrow(grid), , drop = FALSE]
  body <- body[!is.na(body[, 1]) & !str_detect(body[, 1], "^Total"), , drop = FALSE]
  if (!nrow(body)) return(NULL)

  long_votes(body[, 1], clean_candidate(grid[header - 1, cols]), body[, cols, drop = FALSE]) |>
    mutate(contest = str_squish(str_remove(title, "\\(\\s*\\d+\\s*\\)\\s*$")))
}

read_contest_sheets <- function(path, keep) {
  if (tools::file_ext(path) == "xml") {
    sheets <- xml_find_all(read_xml(path), "//*[local-name()='Worksheet']")
    titles <- map_chr(sheets, \(ws) {
      first <- xml_find_first(ws, ".//*[local-name()='Row']")
      if (inherits(first, "xml_missing")) NA_character_ else xml_row_values(first)[1]
    })
    wanted <- which(!is.na(titles) & keep(titles))
    grids  <- map(sheets[wanted], xml_sheet_grid)
  } else {
    sheets <- excel_sheets(path)
    read   <- \(s, ...) suppressMessages(read_excel(path, s, col_names = FALSE, col_types = "text", ...))
    titles <- map_chr(sheets, \(s) read(s, n_max = 1)[[1]][1] %||% NA_character_)
    wanted <- which(!is.na(titles) & keep(titles))
    grids  <- map(sheets[wanted], \(s) {
      grid <- as.matrix(read(s))
      # readxl leaves merged cells empty: carry each candidate name across its columns
      header <- which(apply(grid, 1, \(r) any(r == "Total Votes", na.rm = TRUE)))[1]
      if (!is.na(header) && header > 1) {
        names_row <- grid[header - 1, ]
        for (j in seq_along(names_row)[-1]) if (is.na(names_row[j])) names_row[j] <- names_row[j - 1]
        grid[header - 1, ] <- names_row
      }
      grid
    })
  }
  map2(titles[wanted], grids, parse_contest_grid) |> list_rbind()
}

# ---- clarity_wide ----

read_clarity_wide <- function(path, keep) {
  d <- suppressMessages(read_excel(path, col_types = "text", .name_repair = "minimal"))
  d <- d[!is.na(d$RaceTitle) & keep(d$RaceTitle), , drop = FALSE]
  if (!nrow(d)) return(NULL)

  # Vote columns are "{County}-{Precinct} {VoteType}"; "{County} Total" has no hyphen
  parts <- str_match(names(d), "^([^-]+)-(.+) (\\S+)$")
  cols  <- which(!is.na(parts[, 1]) & parts[, 4] != "Total")
  votes <- as.matrix(d[, cols])
  party <- if ("PoliticalPartyName" %in% names(d)) d$PoliticalPartyName else NA_character_

  tibble(
    contest   = rep(str_squish(d$RaceTitle), times = length(cols)),
    candidate = rep(clean_candidate(d$CandidateName), times = length(cols)),
    party     = rep(rep_len(party, nrow(d)), times = length(cols)),
    county    = rep(parts[cols, 2], each = nrow(d)),
    precinct  = rep(str_squish(parts[cols, 3]), each = nrow(d)),
    votes     = suppressWarnings(as.integer(c(votes)))
  ) |>
    # County files leave contests outside the county blank
    filter(!is.na(votes)) |>
    # Sum Polling + Absentee into the precinct total
    summarise(votes = sum(votes), .by = c(county, precinct, contest, candidate, party))
}

# ---- clarity_xml ----

# ENR party codes → the names the other layouts print
ENR_PARTIES <- c(REP = "Republican", DEM = "Democratic", LIB = "Libertarian", IND = "Independent")

read_clarity_xml <- function(path, keep) {
  contests <- xml_find_all(read_xml(path), "//Contest")
  contests <- contests[keep(xml_attr(contests, "text"))]

  map(contests, \(contest) {
    choices <- xml_find_all(contest, "./Choice")
    map(choices, \(choice) {
      pcts <- xml_find_all(choice, "./VoteType/Precinct")
      party <- xml_attr(choice, "party")
      tibble(
        precinct  = str_squish(xml_attr(pcts, "name")),
        candidate = clean_candidate(xml_attr(choice, "text")),
        party     = coalesce(unname(ENR_PARTIES[party]), na_if(party, "")),
        votes     = as.integer(xml_attr(pcts, "votes"))
      )
    }) |>
      list_rbind() |>
      mutate(contest = str_squish(xml_attr(contest, "text")))
  }) |>
    list_rbind() |>
    # Sum Election Day + Absentee into the precinct total
    summarise(votes = sum(votes), .by = c(precinct, contest, candidate, party))
}

# ---- race_blocks ----

read_race_blocks <- function(path, keep) {
  grid    <- as.matrix(suppressMessages(read_excel(path, col_names = FALSE, col_types = "text")))
  headers <- which(grid[, 2] %in% "County" & grid[, 3] %in% "Precinct")
  block   <- findInterval(seq_len(nrow(grid)), headers)
  rows    <- which(block > 0 & !seq_len(nrow(grid)) %in% headers &
                   !is.na(grid[, 1]) & !is.na(grid[, 2]) & !is.na(grid[, 3]))
  rows    <- rows[keep(grid[rows, 1])]

  map(split(rows, block[rows]), \(r) {
    header <- grid[headers[block[r[1]]], ]
    cols   <- which(seq_along(header) > 3 & !is.na(header) & !str_to_lower(header) %in% NOT_CANDIDATES)
    map(split(r, grid[r, 1]), \(rr) {
      long_votes(grid[rr, 3], clean_candidate(header[cols]), grid[rr, cols, drop = FALSE]) |>
        mutate(contest = str_squish(grid[rr[1], 1]), county = grid[rr[1], 2])
    }) |> list_rbind()
  }) |> list_rbind()
}

# ---- county_canvass ----

read_county_canvass <- function(path, keep) {
  grid <- as.matrix(suppressMessages(read_excel(path, col_names = FALSE, col_types = "text")))
  # Each contest's title row has a "\n\n\nTotal" cell over the total column
  is_total <- matrix(str_detect(grid, "^\\s*\\n+\\s*Total\\s*$"), nrow(grid)) & !is.na(grid)
  titles   <- which(rowSums(is_total) > 0)
  ends     <- c(titles[-1] - 1L, nrow(grid))

  map2(titles, ends, \(t, end) {
    total_col <- which(is_total[t, ])[1]
    title_col <- which(!is.na(grid[t, ]) & !is_total[t, ])[1]
    contest   <- str_squish(grid[t, title_col])
    if (!keep(contest)) return(NULL)

    # Candidate row: the first row after the title with a value under the title
    name_row <- (t + 1):end
    name_row <- name_row[!is.na(grid[name_row, title_col])][1]
    cols     <- title_col:(total_col - 1)
    cells    <- grid[name_row, cols]
    cols     <- cols[!str_to_lower(str_squish(cells)) %in% NOT_CANDIDATES]
    cells    <- grid[name_row, cols]
    # Generals: "Clel Baudler\nRepublican"; primaries and write-ins: name only
    lines     <- str_split(str_trim(cells), "\\s*\\n\\s*")
    candidate <- clean_candidate(map_chr(lines, \(l) paste(head(l, max(1, length(l) - 1)), collapse = " and ")))
    party     <- map_chr(lines, \(l) if (length(l) > 1) tail(l, 1) else NA_character_)

    body <- (name_row + 1):end
    vt   <- which(apply(grid[body, seq_len(title_col - 1), drop = FALSE], 2, \(x) any(x == "Election Day", na.rm = TRUE)))
    if (length(vt)) {
      # General: precinct name on its Election Day row; the county total block has none
      precinct <- NA_character_
      keep_row <- logical(length(body))
      label    <- character(length(body))
      for (i in seq_along(body)) {
        r <- body[i]
        if (grid[r, vt[1]] %in% "Election Day") precinct <- grid[r, 1]
        if (grid[r, vt[1]] %in% "Total" && !is.na(precinct)) {
          keep_row[i] <- TRUE
          label[i]    <- precinct
        }
      }
      rows <- body[keep_row]
      precincts <- label[keep_row]
    } else {
      rows <- body[!is.na(grid[body, 1]) & !grid[body, 1] %in% c("Precinct", "Total")]
      precincts <- grid[rows, 1]
    }
    if (!length(rows)) return(NULL)
    long_votes(precincts, candidate, grid[rows, cols, drop = FALSE], party) |>
      mutate(contest = contest)
  }) |> list_rbind()
}

# ---- canvass_pdf ----

# The county's printed canvass as PDF (Scott, 2020 general), read with
# `pdftotext -raw` (Poppler; on PATH in Git Bash): one line per text row.
# A contest starts at its title; each page repeats the candidate header
# ("Name," then the party, then "[Name] Write-in Undervotes Overvotes Total").
# Precincts have Election Day / Absentee / Total rows; the contest's last Total
# row (one that follows another Total) is the county total, used as a check.
CANVASS_PARTIES <- c(DEM = "Democratic", REP = "Republican", LIB = "Libertarian")

read_canvass_pdf <- function(path, keep) {
  lines <- str_squish(system2("pdftotext", c("-raw", shQuote(path), "-"), stdout = TRUE))
  lines <- lines[lines != ""]
  # A title follows the page header; a contest continued from the last page
  # follows it with a vote row, a precinct name or a candidate instead
  title_at <- which(lag(str_detect(lines, "^(General|Primary) Election - \\d{4}$"), default = FALSE) &
                    !str_detect(lines, "^(Total|Page) |^\\(|,$"))
  ends <- c(title_at[-1] - 1L, length(lines))

  map2(title_at, ends, \(t, end) {
    contest <- lines[t]
    if (!keep(contest)) return(NULL)
    body <- lines[(t + 1):end]

    # Candidates from the first header: "Name," + party line, then the tally row
    tally    <- which(str_detect(body, "Write-in Undervotes Overvotes Total$"))[1]
    head     <- body[seq_len(tally - 1)]
    named    <- which(str_ends(head, ","))
    candidate <- str_remove(head[named], ",$")
    party     <- unname(coalesce(CANVASS_PARTIES[head[named + 1]], head[named + 1]))
    no_party  <- str_squish(str_remove(body[tally], "Write-in Undervotes Overvotes Total$"))
    if (no_party != "") {
      candidate <- c(candidate, no_party)
      party     <- c(party, NA_character_)
    }
    candidate <- c(candidate, "Write-in")
    party     <- c(party, NA_character_)

    # Vote rows: optional label, then integers (candidates, write-in, under, over, total)
    m <- str_match(body, "^(.*?)\\s*((?:\\d[\\d,]*\\s*)+)$")
    is_votes <- !is.na(m[, 1]) & !str_starts(body, "Page ")
    precinct <- NA_character_
    label    <- character(0)
    totals   <- list()
    county_total <- NULL
    buffer   <- character(0)
    for (i in seq_along(body)) {
      if (!is_votes[i]) {
        buffer <- c(buffer, body[i])
        next
      }
      prefix <- m[i, 2]
      votes  <- as.integer(str_remove_all(str_split_1(str_squish(m[i, 3]), " "), ","))
      if (str_ends(prefix, "Election Day")) {
        # Long precinct names wrap onto earlier lines; the name starts at "("
        start  <- tail(which(str_starts(buffer, "\\(")), 1)
        pieces <- c(if (length(start) && !str_starts(prefix, "\\(")) buffer[start:length(buffer)],
                    str_remove(prefix, "\\s*Election Day$"))
        precinct <- str_squish(paste(pieces, collapse = " "))
      } else if (prefix == "Total") {
        if (is.na(precinct)) {
          county_total <- votes
        } else {
          label  <- c(label, precinct)
          totals <- c(totals, list(votes))
          precinct <- NA_character_
        }
      }
      buffer <- character(0)
    }

    n_cand <- length(candidate)
    if (any(lengths(totals) != n_cand + 3L)) stop("Column count mismatch in ", contest, ": ", path)
    votes <- do.call(rbind, totals)[, seq_len(n_cand), drop = FALSE]
    if (!is.null(county_total) && any(colSums(votes) != county_total[seq_len(n_cand)])) {
      stop("Precinct totals don't sum to the county total in ", contest, ": ", path)
    }
    long_votes(label, candidate, votes, party) |> mutate(contest = contest)
  }) |> list_rbind()
}

# ---- Contest labels ----

# "State Rep. Dist. 20 - Rep", "STATE SENATOR DISTRICT 29 - DEMOCRATIC PARTY",
# "State Representative District  20 - REP" → chamber, district, primary party
parse_legislative_contest <- function(contest) {
  contest <- str_squish(contest)
  suffix  <- str_match(contest, "\\s-\\s*([A-Za-z. ]+)$")[, 2]
  tibble(
    chamber  = case_when(
      str_detect(contest, regex("^state\\s+rep", ignore_case = TRUE)) ~ "house",
      str_detect(contest, regex("^state\\s+sen", ignore_case = TRUE)) ~ "senate"
    ),
    district = as.integer(str_match(contest, regex("dist(?:rict|\\.)?\\s*(\\d+)", ignore_case = TRUE))[, 2]),
    primary_party = case_when(
      str_detect(suffix, regex("^\\s*r", ignore_case = TRUE)) ~ "Republican",
      str_detect(suffix, regex("^\\s*d", ignore_case = TRUE)) ~ "Democratic",
      str_detect(suffix, regex("^\\s*l", ignore_case = TRUE)) ~ "Libertarian",
      !is.na(suffix) ~ str_squish(suffix)
    )
  )
}

# "Republican Party" → "Republican"
clean_party <- function(x) str_squish(str_remove(x, regex("\\s+party$", ignore_case = TRUE)))

# ---- Entry point ----

# One file → legislative rows: county, precinct, chamber, district, party,
# candidate, votes, contest (raw label). `county` is the file's county for
# per-county files; statewide files carry it per row. Primaries take the party
# from the contest label, generals from the source where it gives one.
parse_results_file <- function(path, type, county = NULL) {
  layout <- detect_layout(path)
  rows <- switch(layout,
    contest_sheets = read_contest_sheets(path, is_legislative),
    clarity_wide   = read_clarity_wide(path, is_legislative),
    clarity_xml    = read_clarity_xml(path, is_legislative),
    race_blocks    = read_race_blocks(path, is_legislative),
    county_canvass = read_county_canvass(path, is_legislative),
    canvass_pdf    = read_canvass_pdf(path, is_legislative)
  )
  if (is.null(rows) || !nrow(rows)) return(NULL)
  if (!"county" %in% names(rows)) rows$county <- county
  if (!"party" %in% names(rows)) rows$party <- NA_character_

  rows <- filter(rows, !is.na(candidate), !str_to_lower(candidate) %in% NOT_CANDIDATES)
  bind_cols(rows, parse_legislative_contest(rows$contest)) |>
    mutate(
      county = canonical_county(county),
      party  = if (type == "primary") primary_party else clean_party(party),
      votes  = coalesce(votes, 0L)
    ) |>
    select(county, precinct, chamber, district, party, candidate, votes, contest)
}
