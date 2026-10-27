# R/ui_helpers.R
#
# Shared, domain-neutral UI components for the redesigned site. All functions
# return htmltools tag objects — in a Quarto R chunk with `echo: false`, make
# the call the last expression and it renders.
#
# Styling comes from the .ia-* classes in site/custom.scss.
#
# Usage: source(here::here("R/ui_helpers.R"))
# Requires: htmltools, dplyr, stringr, scales, gt (all already in renv)
#
# ── What belongs here ─────────────────────────────────────────────────────────
#
# Components with NO domain vocabulary — nothing that names a bill, a vote, a
# legislator, a donor, or a committee. Anything that hardcodes domain labels or
# maps domain values to styles belongs in R/{domain}/ui_helpers.R instead.
#
# Rule of thumb: if a campaign finance page and a legislation page could both
# call it without either one reading oddly, it goes here.
#
# Domain layers source this file, so templates only ever source their own
# domain's helpers (e.g. R/legislature/ui_helpers.R) and get both halves.

library(htmltools)
library(stringr)

# ------------------------------------------------------------------
# Palette
# ------------------------------------------------------------------

#' Theme colors for R-generated graphics (ggplot, leaflet, gt).
#'
#' HTML components inherit their colors from site/custom.scss automatically,
#' but charts and maps can't reach SCSS variables, so they read them here.
#' These are duplicated literals, not derived values — if the variables at the
#' top of custom.scss change, change them here too.
IA_PALETTE <- list(
  ink         = "#23211d",
  ink_soft    = "#55524a",
  muted       = "#6d6a62",
  faint       = "#706c63",
  bg          = "#f7f6f3",
  card_bg     = "#ffffff",
  border      = "#e4e2da",
  border_soft = "#efeee8",
  party_r     = "#A8433A",
  party_d     = "#3F5B93",
  green       = "#256a43",
  bar_fill    = "#8f8b80",
  bar_light   = "#c5c1b4",
  bar_track   = "#f0efe9"
)

#' Neutral sequential ramp (light → dark) for choropleths and gradients.
ia_ramp <- function(n = 2) {
  grDevices::colorRampPalette(c(IA_PALETTE$bar_track, IA_PALETTE$ink_soft))(n)
}

#' Integer year breaks for a continuous x axis.
#'
#' scales::breaks_pretty() happily emits half-years ("2025.5") when a series
#' spans only two or three years, which is common for a single campaign. Use
#' the actual years when there are few, and thin them when there are many.
ia_year_breaks <- function(years, max_labels = 10) {
  u <- sort(unique(as.integer(years[!is.na(years)])))
  if (length(u) == 0) return(u)
  if (length(u) <= max_labels) return(u)
  unique(as.integer(pretty(u, n = max_labels)))
}

# ------------------------------------------------------------------
# Pills
# ------------------------------------------------------------------

#' Generic pill. Domain layers wrap this to map their own values to types.
#' type: signed | vetoed | progress | neutral | yea | nay | absent | r | d
ui_pill <- function(text, type = "neutral") {
  span(class = paste0("ia-pill ia-pill-", type), text)
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
#'
#' highlight: optional label whose bar is drawn green
#' format_value: how to render the trailing number. Defaults to a comma-grouped
#'   integer; pass scales::dollar for money, scales::percent for shares. Bar
#'   widths always come from the raw `count`, so the formatter only affects the
#'   printed label.
ui_bar_list <- function(df, highlight = NULL,
                        format_value = function(x) format(x, big.mark = ",")) {
  max_n <- max(df$count)
  rows <- lapply(seq_len(nrow(df)), function(i) {
    w <- sprintf("%.1f%%", 100 * df$count[i] / max_n)
    fill_class <- if (!is.null(highlight) && df$label[i] == highlight)
      "ia-bar-fill ia-bar-fill-green" else "ia-bar-fill"
    div(class = "ia-bar-row",
      div(class = "ia-bar-label", df$label[i]),
      div(class = "ia-bar-track", div(class = fill_class, style = paste0("width:", w))),
      div(class = "ia-bar-count", format_value(df$count[i]))
    )
  })
  div(class = "ia-bar-list", rows)
}

# ------------------------------------------------------------------
# Progress stepper
# ------------------------------------------------------------------

#' stages: character vector of stage labels, in order
#' reached: index of furthest stage reached (0 = none)
#' dates: optional character vector, same length as stages ("" for unknown)
ui_stepper <- function(stages, reached, dates = NULL) {
  n <- length(stages)
  steps <- lapply(seq_len(n), function(i) {
    done <- i <= reached
    node <- div(class = paste("ia-step-node"),
      div(class = "ia-step-dot", if (done) "✓" else ""),
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
# Stacked share bar
# ------------------------------------------------------------------

#' segments: named numeric vector, e.g. c(For = 12, Against = 0, Undecided = 10)
#' colors:   named character vector matching names(segments)
#' empty_message: shown when every segment is zero
#' format_value: how to render each segment's number in the legend. Defaults to
#'   a plain count; pass scales::dollar for money. Segment widths always come
#'   from the raw value.
ui_share_bar <- function(segments, colors,
                         empty_message = "No data available.",
                         format_value = function(x) format(x, big.mark = ",")) {
  total <- sum(segments)
  if (total == 0) return(div(class = "ia-card-sub", empty_message))
  segs <- lapply(names(segments), function(nm) {
    if (segments[[nm]] == 0) return(NULL)
    div(style = sprintf("width:%.1f%%; background:%s", 100 * segments[[nm]] / total, colors[[nm]]))
  })
  legend <- lapply(names(segments), function(nm) {
    # swatch dot carries the color; label text stays ink for contrast
    span(
      span(style = paste0("color:", colors[[nm]]), "●"),
      paste0(" ", format_value(segments[[nm]]), " ", nm)
    )
  })
  tagList(
    div(class = "ia-share-bar", segs),
    div(class = "ia-share-legend", legend)
  )
}

# ------------------------------------------------------------------
# Tables and empty states
# ------------------------------------------------------------------

#' Empty state: a quiet sentence in place of a table or chart.
ui_empty <- function(message) div(class = "ia-empty", message)

#' Static HTML table, styled by .ia-table in custom.scss. For small tables that
#' need no sorting or search; the styling lives in the stylesheet, so pages
#' carry none per table (gt writes ~9 KB of CSS into every table).
#'
#' df: one column per table column. A cell is text, a number, or a tag: build
#'   links and pills as a list column of htmltools tags. NA shows as "—".
#' labels: header text, named by column (default: the column name)
#' numeric: columns right-aligned with tabular figures
#' nowrap: columns kept on one line (dates, short codes)
#' row_header: column whose cells head their row (<th scope="row">)
#' empty: shown instead of the table when df has no rows
ui_table <- function(df, labels = NULL, numeric = NULL, nowrap = NULL,
                     row_header = NULL, empty = "No data available.") {
  if (is.null(df) || nrow(df) == 0) return(ui_empty(empty))
  cols <- names(df)
  header <- cols
  labelled <- cols %in% names(labels)
  header[labelled] <- labels[cols[labelled]]

  col_class <- function(col) {
    cls <- c(if (col %in% numeric) "ia-num", if (col %in% nowrap) "ia-nowrap")
    if (length(cls) > 0) paste(cls, collapse = " ")
  }
  cell <- function(col, i) {
    value <- df[[col]][[i]]
    if (is.atomic(value) && length(value) == 1 && is.na(value)) value <- "—"
    if (identical(col, row_header)) {
      tags$th(scope = "row", class = col_class(col), value)
    } else {
      tags$td(class = col_class(col), value)
    }
  }

  div(class = "ia-table-scroll",
    tags$table(class = "ia-table",
      tags$thead(tags$tr(lapply(seq_along(cols), function(j)
        tags$th(scope = "col", class = col_class(cols[j]), header[j])))),
      tags$tbody(lapply(seq_len(nrow(df)), function(i)
        tags$tr(lapply(cols, cell, i = i))))
    )
  )
}

# ------------------------------------------------------------------
# Chart and table themes
# ------------------------------------------------------------------

#' ggplot theme matching the site: no chart junk, ink-colored type, horizontal
#' gridlines only. Series colors come from IA_PALETTE at the call site.
theme_ia <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      text             = ggplot2::element_text(color = IA_PALETTE$ink_soft),
      plot.title       = ggplot2::element_text(color = IA_PALETTE$ink, face = "bold",
                                               size = base_size * 1.1,
                                               margin = ggplot2::margin(b = 10)),
      axis.text        = ggplot2::element_text(color = IA_PALETTE$muted),
      panel.grid.major.x = ggplot2::element_blank(),
      panel.grid.minor   = ggplot2::element_blank(),
      panel.grid.major.y = ggplot2::element_line(color = IA_PALETTE$border_soft),
      legend.position  = "bottom",
      legend.title     = ggplot2::element_blank()
    )
}

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
