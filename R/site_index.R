# site_index.R
#
# Last step of every render: rebuilds docs/sitemap.xml and docs/search.json
# from the pages actually in docs/, and removes the template output.
#
# Quarto can't do this itself. Most pages are rendered one at a time and moved
# out of docs/templates/, so Quarto's own sitemap and search index hold only
# the latest batch, plus the templates rendered with their default parameters.
# The templates have to stay in the project render: excluding them makes
# Quarto treat them as standalone documents, without the site theme.
#
# Neither file carries a timestamp, so they change only when pages do.
#
# Usage:
#   source("R/site_index.R")
#   finish_site_output()

library(dplyr)
library(purrr)
library(readr)
library(stringr)
library(xml2)
library(jsonlite)
library(here)

source(here("R/legislature/session.R"), local = TRUE)  # ga_label()

SITE_URL <- "https://iowatransparencyproject.org"
# Quarto's <title> suffixes, and the longest text kept for one search result
SITE_TITLE_SUFFIX <- " – (Lobbying – )?Iowa Transparency Project$"
SEARCH_TEXT_MAX_CHARS <- 300

#' Paths of the published pages, relative to docs_dir, in a stable order
site_page_paths <- function(docs_dir) {
  list.files(docs_dir, pattern = "\\.html$", recursive = TRUE) |>
    discard(\(p) str_detect(p, "^(site_libs|templates)/|_files/|^status\\.html$")) |>
    sort(method = "radix")  # the same order on Windows and in CI
}

#' What kind of page a path is; decides how its search entry is written
site_page_kind <- function(path) {
  case_when(
    str_detect(path, "^(legislation|legislators|lobbying)/ga\\d+\\.html$") ~ "session_index",
    str_detect(path, "^legislators/ga\\d+/") ~ "legislator_archive",
    str_detect(path, "^legislators/(index|compare)\\.html$") ~ "general",
    str_detect(path, "^legislators/") ~ "legislator",
    str_detect(path, "^legislation/ga\\d+/") ~ "bill",
    str_detect(path, "^committees/ga\\d+/") ~ "committee",
    str_detect(path, "^lobbying/ga\\d+/") ~ "organization",
    str_detect(path, "^activity/\\d{4}-\\d{2}-\\d{2}\\.html$") ~ "week",
    .default = "general"
  )
}

#' Read the fields the search index needs from one rendered page
read_site_page <- function(path, docs_dir) {
  page <- read_html(file.path(docs_dir, path), encoding = "UTF-8")
  has_class <- \(class) sprintf("contains(concat(' ', @class, ' '), ' %s ')", class)
  first_text <- \(xpath) str_squish(xml_text(xml_find_first(page, xpath)))

  tibble(
    path = path,
    is_redirect = !is.na(xml_attr(xml_find_first(page, "//meta[@http-equiv='refresh']"), "content")),
    page_title = first_text("//title"),
    heading = first_text("(//main//h1)[1]"),
    eyebrow = first_text(sprintf("(//*[%s])[1]", has_class("ia-bill-eyebrow"))),
    pill = first_text(sprintf("(//*[%s])[1]", has_class("ia-pill"))),
    profile_meta = first_text(sprintf("(//*[%s])[1]", has_class("ia-profile-meta"))),
    first_paragraph = first_text(sprintf("(//main//p[not(ancestor::*[%s])])[1]", has_class("ia-breadcrumb")))
  )
}

#' Read every page. Parsed HTML lives outside R's heap, where the garbage
#' collector can't see its size, so collect regularly or memory balloons.
read_site_pages <- function(paths, docs_dir) {
  imap(paths, \(path, i) {
    if (i %% 200 == 0) gc(verbose = FALSE)
    read_site_page(path, docs_dir)
  }) |>
    list_rbind()
}

#' "91st General Assembly" for a path containing ga91/, otherwise NA
general_assembly_label <- function(path) {
  ga <- as.integer(str_match(path, "ga(\\d+)/")[, 2])
  if_else(is.na(ga), NA_character_, ga_label(ga))
}

#' Join a row's non-missing pieces into one display line
join_parts <- function(...) {
  pmap_chr(list(...), \(...) paste(na.omit(c(...)), collapse = " · "))
}

#' One search record per page. A bill's `section`, shown under its title, spells
#' out the bill type and carries the no-space form, so "HF856" finds "HF 856".
build_search_records <- function(pages) {
  pages |>
    mutate(kind = site_page_kind(path)) |>
    filter(kind != "legislator_archive") |>  # the career page is the search result
    mutate(
      ga = general_assembly_label(path),
      title = str_remove(page_title, SITE_TITLE_SUFFIX),
      section = if_else(kind == "bill", str_glue("{str_to_title(eyebrow)} ({str_remove_all(title, ' ')})"), ""),
      text = case_when(
        kind == "bill" ~ join_parts(pill, ga, heading),
        kind == "legislator" ~ join_parts(str_to_title(pill), str_remove(profile_meta, " · Iowa$")),
        kind %in% c("committee", "organization") ~ join_parts(str_to_sentence(eyebrow), ga),
        kind == "week" ~ "Weekly legislative activity",
        .default = coalesce(first_paragraph, "")
      ),
      text = str_trunc(text, SEARCH_TEXT_MAX_CHARS, ellipsis = "…")
    ) |>
    transmute(objectID = path, href = path, title, section = coalesce(section, ""), text)
}

#' Write docs/sitemap.xml
write_sitemap <- function(paths, docs_dir) {
  urls <- sprintf("  <url><loc>%s/%s</loc></url>", SITE_URL, map_chr(paths, URLencode))
  write_lines(
    c('<?xml version="1.0" encoding="UTF-8"?>',
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
      urls,
      "</urlset>"),
    file.path(docs_dir, "sitemap.xml")
  )
}

#' Write docs/search.json in the format Quarto's search box reads
write_search_index <- function(records, docs_dir) {
  write_file(
    toJSON(records, dataframe = "rows", auto_unbox = TRUE),
    file.path(docs_dir, "search.json")
  )
}

#' Finish a render: drop the template output, then rebuild the sitemap and
#' search index from the pages in docs/. Every entry point that renders pages
#' calls this last.
#' @return The number of pages indexed, invisibly
finish_site_output <- function(docs_dir = here("docs")) {
  unlink(file.path(docs_dir, "templates"), recursive = TRUE)

  pages <- read_site_pages(site_page_paths(docs_dir), docs_dir) |>
    filter(!is_redirect)

  write_sitemap(pages$path, docs_dir)
  records <- build_search_records(pages)
  write_search_index(records, docs_dir)

  message("Site index: ", nrow(pages), " pages in the sitemap, ",
          nrow(records), " in search")
  invisible(nrow(pages))
}
