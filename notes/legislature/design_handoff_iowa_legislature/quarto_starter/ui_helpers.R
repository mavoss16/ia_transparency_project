# ui_helpers.R
# HTML-emitting helpers for the redesigned site components.
# All functions return htmltools tag objects — in a Quarto R chunk with
# `echo: false`, just make the call the last expression and it renders.
#
# Usage: source(here::here("R/legislature/ui_helpers.R"))
# Requires: htmltools, dplyr, stringr, scales (all already in renv)

library(htmltools)
library(stringr)

# ------------------------------------------------------------------
# Title cleanup
# ------------------------------------------------------------------

#' Strip LegiScan boilerplate from a bill title.
#' "A bill for an act relating to X, and including effective date
#'  provisions. (Formerly HF 1.) Effective date: 07/01/2026."
#'  -> list(title = "X", meta = "Formerly HF 1 · Effective 07/01/2026")
clean_bill_title <- function(title) {
  meta_parts <- character(0)

  formerly <- str_match(title, "\\(Formerly ([^)]+)\\.?\\)")[, 2]
  if (!is.na(formerly)) meta_parts <- c(meta_parts, paste("Formerly", str_remove(formerly, "\\.$")))

  eff <- str_match(title, "Effective date:\\s*([0-9/,\\s]+)\\.")[, 2]
  if (!is.na(eff)) meta_parts <- c(meta_parts, paste("Effective", str_squish(eff)))

  main <- title |>
    str_remove("\\(Formerly [^)]+\\.?\\)") |>
    str_remove("Effective date:\\s*[0-9/,\\s]+\\.") |>
    str_remove("Applicability date:\\s*[0-9/,\\s]+\\.") |>
    str_remove("^A (bill for an act|joint resolution|resolution|concurrent resolution)\\s*(relating to\\s*)?") |>
    str_remove(",?\\s*and including effective date( and applicability)? provisions") |>
    str_remove(",?\\s*and making penalties applicable") |>
    str_remove(",?\\s*and providing penalties") |>
    str_squish() |>
    str_remove("[.,]$")

  # Sentence-case the first letter
  substr(main, 1, 1) <- toupper(substr(main, 1, 1))

  list(title = main, meta = paste(meta_parts, collapse = " \u00b7 "))
}

# ------------------------------------------------------------------
# Pills
# ------------------------------------------------------------------

#' Generic pill. type: signed | vetoed | progress | neutral | yea | nay | absent | r | d
ui_pill <- function(text, type = "neutral") {
  span(class = paste0("ia-pill ia-pill-", type), text)
}

#' Map a bill status string to a pill.
status_pill <- function(status) {
  type <- dplyr::case_when(
    str_detect(status, regex("signed",  ignore_case = TRUE)) ~ "signed",
    str_detect(status, regex("vetoed",  ignore_case = TRUE)) ~ "vetoed",
    str_detect(status, regex("passed",  ignore_case = TRUE)) ~ "progress",
    TRUE ~ "neutral"
  )
  ui_pill(status, type)
}

#' Vote pill (Yea / Nay / Absent / NV)
vote_pill <- function(vote) {
  type <- dplyr::case_when(
    str_detect(vote, regex("^yea",    ignore_case = TRUE)) ~ "yea",
    str_detect(vote, regex("^nay",    ignore_case = TRUE)) ~ "nay",
    str_detect(vote, regex("absent|nv", ignore_case = TRUE)) ~ "absent",
    TRUE ~ "neutral"
  )
  ui_pill(vote, type)
}

# ------------------------------------------------------------------
# Stat cards
# ------------------------------------------------------------------

ui_stat_card <- function(label, value, sub = NULL) {
  div(class = "ia-stat-card",
    div(class = "ia-stat-label", label),
    div(class = "ia-stat-value", value),
    if (!is.null(sub)) div(class = "ia-stat-sub", sub)
  )
}

#' ui_stat_grid(ui_stat_card(...), ui_stat_card(...), ...)
ui_stat_grid <- function(...) div(class = "ia-stat-grid", ...)

# ------------------------------------------------------------------
# Bar lists
# ------------------------------------------------------------------

#' Horizontal bar list. df needs columns: label, count.
#' highlight: optional label whose bar is drawn green (e.g. "Signed by Governor")
ui_bar_list <- function(df, highlight = NULL) {
  max_n <- max(df$count)
  rows <- lapply(seq_len(nrow(df)), function(i) {
    w <- sprintf("%.1f%%", 100 * df$count[i] / max_n)
    fill_class <- if (!is.null(highlight) && df$label[i] == highlight)
      "ia-bar-fill ia-bar-fill-green" else "ia-bar-fill"
    div(class = "ia-bar-row",
      div(class = "ia-bar-label", df$label[i]),
      div(class = "ia-bar-track", div(class = fill_class, style = paste0("width:", w))),
      div(class = "ia-bar-count", format(df$count[i], big.mark = ","))
    )
  })
  div(class = "ia-bar-list", rows)
}

#' Paired bars: individual vs group status.
#' df needs columns: label, ind, grp.
ui_paired_bars <- function(df) {
  max_n <- max(c(df$ind, df$grp))
  rows <- lapply(seq_len(nrow(df)), function(i) {
    w_ind <- sprintf("%.1f%%", 100 * df$ind[i] / max_n)
    w_grp <- sprintf("%.1f%%", 100 * df$grp[i] / max_n)
    div(class = "ia-bar-row",
      div(class = "ia-bar-label", df$label[i]),
      div(class = "ia-bar-pair",
        div(class = "ia-bar-inline",
          div(class = "ia-bar-track", div(class = "ia-bar-fill", style = paste0("width:", w_ind, "; background:#55524a"))),
          span(class = "ia-bar-count", format(df$ind[i], big.mark = ","))
        ),
        div(class = "ia-bar-inline",
          div(class = "ia-bar-track", div(class = "ia-bar-fill ia-bar-fill-light", style = paste0("width:", w_grp))),
          span(class = "ia-bar-count-soft", format(df$grp[i], big.mark = ","))
        )
      ),
      div()  # third grid column unused here
    )
  })
  tagList(
    div(class = "ia-legend", style = "margin-bottom: 0.8rem",
      span(span(class = "ia-legend-swatch", style = "background:#55524a"), "Individual bill"),
      span(span(class = "ia-legend-swatch", style = "background:#c5c1b4"), "Bill group")
    ),
    div(class = "ia-bar-list", rows)
  )
}

# ------------------------------------------------------------------
# Progress stepper (bill detail pages)
# ------------------------------------------------------------------

#' stages: character vector of stage labels, in order
#' reached: index of furthest stage reached (0 = none)
#' dates: optional character vector, same length as stages ("" for unknown)
ui_stepper <- function(stages, reached, dates = NULL) {
  n <- length(stages)
  steps <- lapply(seq_len(n), function(i) {
    done <- i <= reached
    node <- div(class = paste("ia-step-node"),
      div(class = "ia-step-dot", if (done) "\u2713" else ""),
      div(class = "ia-step-label", stages[i]),
      if (!is.null(dates) && nzchar(dates[i])) div(class = "ia-step-date", dates[i])
    )
    line <- if (i < n) {
      div(class = paste("ia-step-line",
                        if (i < reached) "ia-step-line-done" else "ia-step-line-todo"))
    }
    div(class = paste("ia-step", if (done) "ia-step-done" else "ia-step-todo"), node, line)
  })
  div(class = "ia-stepper", steps)
}

# ------------------------------------------------------------------
# Stacked share bar (lobbyist declarations, party splits)
# ------------------------------------------------------------------

#' segments: named numeric vector, e.g. c(For = 12, Against = 0, Undecided = 10)
#' colors:   named character vector matching names(segments)
ui_share_bar <- function(segments, colors) {
  total <- sum(segments)
  if (total == 0) return(div(class = "ia-card-sub", "No declarations filed."))
  segs <- lapply(names(segments), function(nm) {
    if (segments[[nm]] == 0) return(NULL)
    div(style = sprintf("width:%.1f%%; background:%s", 100 * segments[[nm]] / total, colors[[nm]]))
  })
  legend <- lapply(names(segments), function(nm) {
    span(style = paste0("color:", colors[[nm]]),
         sprintf("\u25cf %d %s", segments[[nm]], nm))
  })
  tagList(
    div(class = "ia-share-bar", segs),
    div(class = "ia-share-legend", legend)
  )
}

# ------------------------------------------------------------------
# Profile header (legislator detail pages)
# ------------------------------------------------------------------

ui_profile_header <- function(name, party, role_label, district, notice = NULL, links = NULL) {
  party_class <- if (party == "D") "ia-profile-header party-d" else "ia-profile-header"
  party_label <- if (party == "D") "DEMOCRAT" else "REPUBLICAN"
  div(class = party_class,
    div(class = "ia-profile-name-row",
      h1(name),
      ui_pill(party_label, tolower(party))
    ),
    div(class = "ia-profile-meta", paste0(role_label, " \u00b7 District ", district, " \u00b7 Iowa")),
    if (!is.null(notice)) div(class = "ia-notice", HTML(notice)),
    if (!is.null(links)) div(style = "margin-top:0.9rem", links)
  )
}

# ------------------------------------------------------------------
# Legislator table (reactable, replaces the static gt version)
# ------------------------------------------------------------------

#' df must have: name_link (HTML), party, district, bills_sponsored,
#' sole_sponsored, votes_cast, with_party_pct, participation_rate (0-1)
legislator_table <- function(df) {
  pct_bar <- function(value) {
    low <- !is.na(value) && value < 0.6
    htmltools::div(class = "ia-cellbar",
      htmltools::div(class = "ia-cellbar-track",
        htmltools::div(class = paste("ia-cellbar-fill", if (low) "low"),
                       style = sprintf("width:%.1f%%", 100 * value))),
      htmltools::div(class = "ia-cellbar-num",
                     style = if (low) "color:#7d5c17" else NULL,
                     sprintf("%.1f%%", 100 * value))
    )
  }
  name_cell <- function(value, index) {
    dot <- if (df$party[index] == "R") "ia-dot ia-dot-r" else "ia-dot ia-dot-d"
    htmltools::tagList(htmltools::span(class = dot), htmltools::HTML(value))
  }

  reactable::reactable(
    df |> dplyr::select(-party),
    columns = list(
      name_link = reactable::colDef(name = "Name", cell = name_cell, html = TRUE, minWidth = 170),
      district = reactable::colDef(name = "District", width = 90),
      bills_sponsored = reactable::colDef(name = "Sponsored", width = 100, align = "right"),
      sole_sponsored = reactable::colDef(name = "Sole", width = 70, align = "right"),
      votes_cast = reactable::colDef(name = "Votes", width = 80, align = "right"),
      with_party_pct = reactable::colDef(name = "Party Alignment", cell = pct_bar, minWidth = 140),
      participation_rate = reactable::colDef(name = "Participation", cell = pct_bar, minWidth = 140)
    ),
    defaultSorted = "district",
    searchable = TRUE,
    defaultPageSize = 25,
    highlight = TRUE
  )
}

# ------------------------------------------------------------------
# gt theme (for tables staying on gt)
# ------------------------------------------------------------------

gt_theme_ia <- function(gt_tbl) {
  gt_tbl |>
    gt::tab_options(
      table.font.size = gt::px(13),
      data_row.padding = gt::px(8),
      table.border.top.style = "hidden",
      column_labels.border.bottom.color = "#e4e2da",
      column_labels.font.weight = "600",
      table_body.hlines.color = "#efeee8"
    )
}
