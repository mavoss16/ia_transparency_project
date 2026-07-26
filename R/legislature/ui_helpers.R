# R/legislature/ui_helpers.R
# Legislature-specific UI helpers: components that carry bill / vote /
# legislator vocabulary, or map legislature values onto shared components.
#
# The domain-neutral components (ui_pill, ui_stat_card, ui_stat_grid,
# ui_bar_list, ui_stepper, ui_share_bar, gt_theme_ia) live in R/ui_helpers.R
# and are sourced below, so templates need only source this file to get both.
#
# Usage: source(here::here("R/legislature/ui_helpers.R"))
# Requires: htmltools, dplyr, stringr, scales, reactable (all already in renv)

source(here::here("R/ui_helpers.R"))

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

  list(title = main, meta = paste(meta_parts, collapse = " · "))
}

# ------------------------------------------------------------------
# Domain pills (wrap the shared ui_pill)
# ------------------------------------------------------------------

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
# Paired bars: individual bill vs bill group
# ------------------------------------------------------------------

#' Stays domain-specific: the legend labels name bills.
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
    div(class = "ia-profile-meta", paste0(role_label, " · District ", district, " · Iowa")),
    if (!is.null(notice)) div(class = "ia-notice", HTML(notice)),
    if (!is.null(links)) div(style = "margin-top:0.9rem", links)
  )
}

# ------------------------------------------------------------------
# Legislator table (reactable, replaces the static gt version)
# ------------------------------------------------------------------

#' df must have: name_link (HTML), party, district, bills_sponsored,
#' sole_sponsored, votes_cast, with_party_pct, participation_rate (0-1).
#' Optional: is_former (logical) renders a gray "FORMER" chip after the name.
legislator_table <- function(df) {
  pct_bar <- function(value) {
    if (is.na(value)) {
      return(htmltools::div(class = "ia-cellbar-num", style = "color:#8a877e", "—"))
    }
    low <- value < 0.6
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
    chip <- if (!is.null(df$is_former) && isTRUE(df$is_former[index]))
      "<span class=\"ia-chip-former\">FORMER</span>" else ""
    # Return a single raw-HTML string (colDef html = TRUE); a tagList wrapping
    # HTML() gets escaped by reactable, so build the markup directly.
    paste0("<span class=\"", dot, "\"></span>", value, chip)
  }

  reactable::reactable(
    df |> dplyr::select(-party, -dplyr::any_of("is_former")),
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
