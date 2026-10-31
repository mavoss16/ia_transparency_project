# R/elections/ui_helpers.R
# Elections UI: race results, a legislator's electoral history (the Elections
# tab on legislator pages) and the one-line latest result for the district
# card. Data comes from R/elections/legislator_history.R, sourced below.
#
# Legislator pages are the one place two domains' helpers meet: the template
# sources R/legislature/ui_helpers.R and this file. Neither names the other's
# URLs; links to legislator pages come in through a `page_href` function.
#
# Design: notes/site/2026-10-31_elections-tab-design.md. Neutral wording only
# (no "landslide", no "close race"); candidates by votes; party colors label
# data and never carry meaning alone.
#
# Usage: source(here::here("R/elections/ui_helpers.R"))

source(here::here("R/ui_helpers.R"))
source(here::here("R/elections/legislator_history.R"))

library(htmltools)

fmt_votes <- \(x) format(x, big.mark = ",", trim = TRUE)
fmt_pct <- \(x) sprintf("%.1f%%", 100 * x)
fmt_date_long <- \(d) str_squish(format(d, "%B %e, %Y"))

#' "r" / "d" for the two major parties, else NA (no party color)
party_class <- function(party) {
  case_when(party == "Republican" ~ "r", party == "Democratic" ~ "d", .default = NA_character_)
}

#' "(R)" label shown beside a name at phone width, where the party column hides
party_short <- function(party) {
  cls <- party_class(party)
  if (is.na(cls)) return(NULL)
  span(class = paste("ia-party-short", cls), paste0("(", toupper(cls), ")"))
}

#' No whitespace around the span (.noWS), so "(Republican)" has none inside
party_tag <- function(party) {
  if (is.na(party)) return("—")
  span(class = paste(c("ia-party-tag", party_class(party)[!is.na(party_class(party))]), collapse = " "),
       party, .noWS = "outside")
}

#' "General election", "Special election", "Republican primary"
race_title <- function(type, primary_party) {
  switch(type,
    general = "General election",
    special = "Special election",
    primary = paste(primary_party, "primary"))
}

#' A candidate's name cell: winner check, name (linked if another legislator),
#' party (`party`: "short" for the phone-only label, "full" for the
#' unopposed line, "none" in primaries), "incumbent"
candidate_cell <- function(row, page_href, party = c("short", "full", "none")) {
  party <- match.arg(party)
  href <- if (!is.na(row$people_id) && !row$is_self) page_href(row$people_id) else NULL
  name <- if (!is.null(href)) a(href = href, row$candidate) else row$candidate
  tagList(
    if (isTRUE(row$winner)) span(class = "ia-winner", role = "img", `aria-label` = "Winner", "✓"),
    if (row$is_self) strong(name) else name,
    switch(party,
      short = party_short(row$party),
      full  = if (!is.na(row$party)) tagList(" (", party_tag(row$party), ")"),
      none  = NULL),
    if (isTRUE(row$incumbent)) span(class = "ia-incumbent", "incumbent")
  )
}

#' Thin bar of the named candidates' shares; color is party in generals, and
#' neutral tones in primaries, where every candidate shares one party
race_bar <- function(named, is_primary) {
  neutral <- c(IA_PALETTE$ink_soft, IA_PALETTE$bar_fill, IA_PALETTE$bar_light)
  colors <- if (is_primary) {
    rep_len(neutral, nrow(named))
  } else {
    case_when(named$party == "Republican" ~ IA_PALETTE$party_r,
              named$party == "Democratic" ~ IA_PALETTE$party_d,
              .default = IA_PALETTE$bar_fill)
  }
  label <- paste(paste(word(named$candidate, -1), fmt_pct(named$pct)), collapse = ", ")
  div(class = "ia-share-bar", role = "img", `aria-label` = label,
      lapply(seq_len(nrow(named)), \(i)
        div(style = sprintf("width:%.1f%%; background:%s", 100 * named$pct[i], colors[i]))))
}

#' Margin sentence from the person's side when they ran, else neutral
margin_line <- function(race_rows) {
  m <- race_rows$margin[1]
  if (is.na(m)) return(NULL)
  amount <- sprintf("%s votes (%.1f points)", fmt_votes(m), 100 * race_rows$margin_pct[1])
  self <- race_rows |> filter(is_self)
  text <- if (nrow(self) == 1 && isTRUE(self$winner)) {
    paste0("Won by ", amount, ".")
  } else if (nrow(self) == 1 && self$rank == 2) {
    paste0("Lost by ", amount, ".")
  } else {
    paste0("Margin between the top two: ", amount, ".")
  }
  div(class = "ia-race-margin", text)
}

#' One race: label, then a single line if uncontested, else a bar, a table and
#' the margin
ui_race <- function(race_rows, page_href = \(id) NULL) {
  first <- race_rows[1, ]
  is_primary <- first$type == "primary"
  named <- race_rows |> filter(candidate != "Write-in")
  write_in <- race_rows |> filter(candidate == "Write-in")
  write_in_votes <- sum(write_in$votes)
  write_in_text <- if (write_in_votes > 0) {
    paste0("; ", fmt_votes(write_in_votes), " write-in", if (write_in_votes != 1) "s")
  } else ""

  label <- div(class = "ia-race-label", race_title(first$type, first$primary_party),
               span(class = "ia-race-date", paste0(" · ", fmt_date_long(first$election_date))))

  body <- if (nrow(named) == 0) {
    p(class = "ia-race-line", paste0("No candidate was on the ballot", sub("^; ", ": ", write_in_text), "."))
  } else if (nrow(named) == 1) {
    p(class = "ia-race-line",
      candidate_cell(named, page_href, party = if (is_primary) "none" else "full"),
      paste0(" ran unopposed: ", fmt_votes(named$votes), " votes", write_in_text, "."))
  } else {
    rows <- bind_rows(named, write_in)
    cells <- tibble(
      candidate = map(seq_len(nrow(rows)), \(i) {
        if (rows$candidate[i] == "Write-in") span(class = "ia-writein", "Write-ins")
        else candidate_cell(rows[i, ], page_href, party = if (is_primary) "none" else "short")
      }),
      party = map(rows$party, party_tag),
      votes = fmt_votes(rows$votes),
      share = fmt_pct(rows$pct)
    )
    if (is_primary) cells <- select(cells, -party)
    tagList(
      race_bar(named, is_primary),
      div(class = if (is_primary) "ia-race-table" else "ia-race-table has-party",
          ui_table(cells, labels = c(candidate = "Candidate", party = "Party", votes = "Votes", share = "Share"),
                   numeric = c("votes", "share"))),
      margin_line(race_rows)
    )
  }
  div(class = "ia-race", label, body)
}

#' Notes from block_notes() as tags, the link placed at "{link}"
ui_notes <- function(notes) {
  lapply(notes, \(n) {
    if (is.null(n$link_text)) return(div(class = "ia-election-note", n$text))
    parts <- str_split_1(n$text, fixed("{link}"))
    link <- if (!is.null(n$href)) a(href = n$href, n$link_text) else n$link_text
    div(class = "ia-election-note", parts[1], link, parts[2])
  })
}

#' Source line: one link per results file the block draws on
ui_block_sources <- function(block_races) {
  srcs <- block_races |>
    distinct(source_url, year, type, election_date) |>
    filter(!is.na(source_url)) |>
    arrange(desc(election_date)) |>
    distinct(source_url, .keep_all = TRUE) |>
    mutate(text = if_else(type == "special", paste(fmt_date_long(election_date), "special election"),
                          paste(year, type)))
  if (nrow(srcs) == 0) return(NULL)
  links <- lapply(seq_len(nrow(srcs)), \(i)
    a(href = srcs$source_url[i], target = "_blank", srcs$text[i], .noWS = "outside"))
  div(class = "ia-source", "Source: Iowa Secretary of State (",
      head(unlist(lapply(links, \(l) list(l, "; ")), recursive = FALSE), -1), ")")
}

#' One block: a year and seat, the person's races, the other primaries
ui_election_block <- function(block_races, races, results, missing, page_href) {
  first <- block_races[1, ]
  own <- block_races |> filter(!other_primary)
  other <- block_races |> filter(other_primary)
  primary_missing <- first$year %in% missing$primary && any(own$type == "general")

  tags$section(class = "ia-election",
    div(class = "ia-election-head",
        span(class = "ia-election-year", first$year),
        span(class = "ia-election-seat", seat_label(first$chamber, first$district))),
    ui_notes(block_notes(block_races, races, results, page_href)),
    lapply(split(own, own$race, drop = TRUE)[unique(own$race)], ui_race, page_href = page_href),
    if (primary_missing) {
      div(class = "ia-race",
          div(class = "ia-race-label", "Primaries"),
          p(class = "ia-race-line ia-muted", paste("Primary results for", first$year, "are not yet included.")))
    },
    if (nrow(other) > 0) {
      tags$details(class = "ia-sub-races",
        tags$summary("Other primaries for this seat"),
        div(lapply(split(other, other$race, drop = TRUE)[unique(other$race)], ui_race, page_href = page_href)))
    },
    ui_block_sources(block_races)
  )
}

#' Footnote on what the data covers
coverage_footnote <- function(results) {
  missing <- missing_elections(results)
  span_text <- function(years) {
    if (length(years) == 0) return(NULL)
    if (length(years) > 2 && all(diff(years) == 2)) paste("from", min(years), "to", max(years))
    else paste("in", join_and(years))
  }
  n_general <- length(missing$general)
  gaps <- c(
    if (n_general > 0) paste0("the ", join_and(missing$general), " general election", if (n_general > 1) "s"),
    if (length(missing$primary) > 0) paste("primaries", span_text(missing$primary)),
    paste("special elections before", min(results$year[results$type == "special"]))
  )
  div(class = "ia-footnote", paste0(
    "Shares are of all votes cast in each race, write-ins included. Results from the Iowa ",
    "Secretary of State, ", min(results$year), " on. Not yet included: ", join_and(gaps), "."))
}

#' The Elections tab
#' @param races legislator_races() for the person
#' @param name Display name
#' @param chamber Their current chamber ("house" / "senate")
#' @param results The race table
#' @param page_href function(people_id) -> href or NULL
ui_elections_tab <- function(races, name, chamber, results, page_href = \(id) NULL) {
  if (nrow(races) == 0) {
    return(tagList(
      ui_empty(paste("No election results are matched to", name, "yet.")),
      coverage_footnote(results)
    ))
  }
  missing <- missing_elections(results)
  summary <- paste(c(tenure_text(races, name, chamber, "sentence"),
                     redistricting_text(races, name, chamber)), collapse = " ")
  blocks <- split(races, races$block)[unique(races$block)]
  tagList(
    if (nzchar(summary)) p(class = "ia-elections-summary", summary),
    lapply(blocks, ui_election_block, races = races, results = results,
           missing = missing, page_href = page_href),
    coverage_footnote(results)
  )
}

#' One line for the district card: "Won the 2024 general with 72.1% of the
#' vote." plus a link that opens the Elections tab. NULL without a result.
ui_latest_result <- function(races) {
  latest <- latest_result(races)
  if (is.null(latest)) return(NULL)
  what <- if (latest$type == "special") {
    paste(str_squish(format(latest$election_date, "%B %Y")), "special election")
  } else {
    paste(latest$year, "general")
  }
  verb <- if (isTRUE(latest$winner)) "Won" else "Lost"
  how <- if (isTRUE(latest$unopposed)) "unopposed" else paste("with", fmt_pct(latest$pct), "of the vote")
  div(class = "ia-district-result",
      paste0(verb, " the ", what, " ", how, ". "),
      a(href = "#elections", class = "ia-open-elections", "Electoral history →"))
}

#' Script that makes .ia-open-elections links open the Elections tab
#' (Quarto's panel-tabset is Bootstrap tabs, with no anchor per tab)
elections_tab_script <- function() {
  tags$script(HTML(
"document.addEventListener('click', function (e) {
  var link = e.target.closest('.ia-open-elections');
  if (!link) return;
  var tab = Array.from(document.querySelectorAll('.panel-tabset .nav-link'))
    .find(function (t) { return t.textContent.trim() === 'Elections'; });
  if (!tab) return;
  e.preventDefault();
  bootstrap.Tab.getOrCreateInstance(tab).show();
  tab.scrollIntoView({ behavior: 'smooth', block: 'start' });
  tab.focus({ preventScroll: true });
});"))
}
