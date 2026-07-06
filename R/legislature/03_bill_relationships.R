library(dplyr)
library(stringr)
library(purrr)
library(tidyr)
library(rvest)
library(igraph)
library(jsonlite)
library(readr)

# Status levels in order of progression (higher = further along)
STATUS_LEVELS <- c(
  "Introduced" = 1,

  "Passed Subcommittee" = 2,
  "Passed Committee" = 3,
  "Passed One Chamber" = 4,
  "Passed Both Chambers" = 5,
  "Signed by Governor" = 6
)

# =============================================================================
# Bill Status Functions
# =============================================================================

#' Determine bill status from history actions
#' @param history_df Data frame with 'action' column from bill history
#' @return Character string with the furthest status reached
get_bill_status_from_history <- function(history_df) {
  if (is.null(history_df) || nrow(history_df) == 0) {
    return("Introduced")
  }

  actions <- history_df$action

  # Check each status level from highest to lowest
  if (any(str_detect(actions, "Signed by Governor"))) {
    return("Signed by Governor")
  }

  # Passed both chambers = has both "Passed House" and "Passed Senate"
  passed_house <- any(str_detect(actions, "^Passed House"))
  passed_senate <- any(str_detect(actions, "^Passed Senate"))
  if (passed_house && passed_senate) {
    return("Passed Both Chambers")
  }

  # Passed one chamber
  if (passed_house || passed_senate) {
    return("Passed One Chamber")
  }

  # Committee report recommending passage = passed committee
  if (any(str_detect(actions, "Committee report.*(recommending passage|approving bill)"))) {
    return("Passed Committee")
  }

  # Subcommittee recommends passage
  if (any(str_detect(actions, "Subcommittee recommends.*(passage|amendment and passage)"))) {
    return("Passed Subcommittee")
  }

  return("Introduced")
}

#' Get bill status for a single bill from its JSON file
#' @param bill_number Bill number (e.g., "HF1")
#' @param json_dir Directory containing bill JSON files
#' @return Character string with the furthest status reached
get_bill_status <- function(bill_number, json_dir = here::here("legiscan/files_ga91_json/bill")) {
  json_path <- file.path(json_dir, paste0(bill_number, ".json"))

  if (!file.exists(json_path)) {
    return("Introduced")
  }

  bill_data <- tryCatch(fromJSON(json_path), error = function(e) NULL)
  if (is.null(bill_data)) {
    return("Introduced")
  }

  history <- bill_data[["bill"]][["history"]]
  if (is.data.frame(history)) {
    return(get_bill_status_from_history(history))
  }

  return("Introduced")
}

#' Get all bill statuses from JSON files
#' @param json_dir Directory containing bill JSON files
#' @return Tibble with bill number, status, and status_level
get_all_bill_statuses <- function(json_dir = here::here("legiscan/files_ga91_json/bill")) {
  bill_files <- list.files(json_dir, pattern = "\\.json$", full.names = FALSE)
  bill_numbers <- str_remove(bill_files, "\\.json$")

  map_dfr(bill_numbers, function(bn) {
    status <- get_bill_status(bn, json_dir)
    tibble(
      bill = bn,
      status = status,
      status_level = STATUS_LEVELS[status]
    )
  }, .progress = TRUE)
}

# =============================================================================
# Web Scraping Functions
# =============================================================================

#' Scrape related bills from the Iowa Legislature bill history page
#' @param bill_number Bill number (e.g., "HF1")
#' @param ga General Assembly number (default 91)
#' @return Tibble with bill and related_bills columns
scrape_bill_relationships <- function(bill_number, ga = 91) {
  # Bill history pages are static HTML — no JS/chromote needed.
  # URL format requires a space between letters and digits: "HF 2511"
  bill_name_spaced <- str_replace(bill_number, "([A-Z]+)([0-9]+)", "\\1 \\2")
  url <- paste0(
    "https://www.legis.iowa.gov/legislation/billTracking/billHistory?billName=",
    utils::URLencode(bill_name_spaced, repeated = TRUE),
    "&ga=", ga
  )

  page <- NULL
  for (attempt in 1:3) {
    page <- tryCatch(read_html(url), error = function(e) NULL)
    if (!is.null(page)) break
    if (attempt < 3) {
      message("  Attempt ", attempt, " failed for ", bill_number, ", retrying...")
      Sys.sleep(2)
    }
  }

  if (is.null(page)) {
    warning("Failed to read page for ", bill_number)
    return(tibble(bill = bill_number, related_bills = list(character(0))))
  }

  # Links in the "All Related Bills to Selected Bill" section point to BillBook
  # with a "ba=" query parameter, e.g. href="...BillBook?ba=HF 2158&ga=91"
  related_links <- page |>
    html_elements(
      xpath = "//text()[contains(., 'All Related Bills to Selected Bill')]/following::a[contains(@href, 'BillBook')]"
    )

  related <- character(0)
  if (length(related_links) > 0) {
    hrefs <- html_attr(related_links, "href")
    related <- str_match(hrefs, "[?&]ba=([A-Z]+ ?[0-9]+)")[, 2] |>
      str_remove_all(" ") |>
      na.omit() |>
      unique()
    related <- related[related != bill_number]
  }

  tibble(bill = bill_number, related_bills = list(related))
}

# =============================================================================
# Edge List Management (Incremental Updates)
# =============================================================================

#' Load cached relationship edges or return empty tibble
#' @param edges_path Path to edges RDS file
#' @return Tibble with from_bill and to_bill columns
load_relationship_edges <- function(edges_path = here::here("data/bills/relationship_edges.rds")) {
  if (file.exists(edges_path)) {
    readRDS(edges_path)
  } else {
    tibble(from_bill = character(), to_bill = character(), scraped_date = as.Date(character()))
  }
}

#' Save relationship edges to RDS file
#' @param edges Tibble with from_bill and to_bill columns
#' @param edges_path Path to save edges RDS file
save_relationship_edges <- function(edges, edges_path = here::here("data/bills/relationship_edges.rds")) {
  saveRDS(edges, edges_path)
  message("Saved ", nrow(edges), " relationship edges to ", edges_path)
}

#' Update relationship edges by scraping new/changed bills
#' @param bill_numbers Vector of bill numbers to scrape (NULL = determine automatically)
#' @param edges_path Path to edges RDS file
#' @param ga General Assembly number
#' @param rate_limit Seconds between requests
#' @param save_interval Save progress every N bills (default 50)
#' @return Updated edges tibble
update_relationship_edges <- function(
    bill_numbers = NULL,
    edges_path = here::here("data/bills/relationship_edges.rds"),
    json_dir = here::here("legiscan/files_ga91_json/bill"),
    ga = 91,
    rate_limit = 1.5,
    save_interval = 50
) {
  # Load existing edges
  existing_edges <- load_relationship_edges(edges_path)
  already_scraped <- unique(existing_edges$from_bill)

  # Determine which bills to scrape
  if (is.null(bill_numbers)) {
    # Get all bills from JSON directory
    all_bills <- list.files(json_dir, pattern = "\\.json$") |>
      str_remove("\\.json$")

    # Only scrape bills we haven't scraped yet
    bill_numbers <- setdiff(all_bills, already_scraped)
  }

  if (length(bill_numbers) == 0) {
    message("No new bills to scrape.")
    return(existing_edges)
  }

  message("Scraping relationships for ", length(bill_numbers), " bills...")
  message("Progress will be saved every ", save_interval, " bills.")

  # Track accumulated edges for this batch
  batch_relationships <- list()
  failed_bills <- character()
  processed_count <- 0

  # Helper to save current batch
  save_batch <- function() {
    if (length(batch_relationships) == 0) return()

    new_relationships <- bind_rows(batch_relationships)

    # Convert to edge format
    new_edges <- new_relationships |>
      unnest(related_bills) |>
      filter(length(related_bills) > 0, !is.na(related_bills), related_bills != "") |>
      transmute(
        from_bill = bill,
        to_bill = related_bills,
        scraped_date = Sys.Date()
      )

    # Also add "from" bills with no relationships so we know they were scraped
    scraped_no_rels <- new_relationships |>
      filter(map_int(related_bills, length) == 0) |>
      transmute(
        from_bill = bill,
        to_bill = NA_character_,
        scraped_date = Sys.Date()
      )

    # Reload existing edges (in case another process updated)
    existing <- load_relationship_edges(edges_path)

    # Combine with existing edges
    all_edges <- bind_rows(existing, new_edges, scraped_no_rels) |>
      distinct(from_bill, to_bill, .keep_all = TRUE)

    # Save updated edges
    save_relationship_edges(all_edges, edges_path)

    # Clear batch
    batch_relationships <<- list()
  }

  # Process each bill with error handling
  for (i in seq_along(bill_numbers)) {
    bn <- bill_numbers[i]
    message(sprintf("  [%d/%d] Processing: %s", i, length(bill_numbers), bn))

    result <- tryCatch({
      res <- scrape_bill_relationships(bn, ga)
      Sys.sleep(rate_limit)
      res
    }, error = function(e) {
      message(sprintf("    ERROR scraping %s: %s", bn, e$message))
      NULL
    })

    if (!is.null(result)) {
      batch_relationships[[length(batch_relationships) + 1]] <- result
      processed_count <- processed_count + 1
    } else {
      failed_bills <- c(failed_bills, bn)
    }

    # Save progress at intervals and free memory
    if (processed_count > 0 && processed_count %% save_interval == 0) {
      message(sprintf("  -- Saving progress (%d bills processed) --", processed_count))
      save_batch()
      gc()
    }
  }

  # Save any remaining
  if (length(batch_relationships) > 0) {
    message("  -- Saving final batch --")
    save_batch()
  }

  # Report failures
  if (length(failed_bills) > 0) {
    message("\nFailed to scrape ", length(failed_bills), " bills:")
    message("  ", paste(head(failed_bills, 20), collapse = ", "))
    if (length(failed_bills) > 20) {
      message("  ... and ", length(failed_bills) - 20, " more")
    }
    message("Run rescrape_bills() with these bills to retry.")
  }

  message("\nDone! Successfully processed ", processed_count, " bills.")

  return(load_relationship_edges(edges_path))
}

#' Force re-scrape specific bills (e.g., if relationships changed)
#' @param bill_numbers Vector of bill numbers to re-scrape
#' @param edges_path Path to edges RDS file
#' @param ga General Assembly number
#' @param rate_limit Seconds between requests
#' @return Updated edges tibble
rescrape_bills <- function(
    bill_numbers,
    edges_path = here::here("data/bills/relationship_edges.rds"),
    ga = 91,
    rate_limit = 1.5
) {
  # Load existing edges
  existing_edges <- load_relationship_edges(edges_path)

  # Remove old edges for these bills
  existing_edges <- existing_edges |>
    filter(!from_bill %in% bill_numbers)

  # Save temporarily
  save_relationship_edges(existing_edges, edges_path)

  # Now scrape them fresh
  update_relationship_edges(
    bill_numbers = bill_numbers,
    edges_path = edges_path,
    ga = ga,
    rate_limit = rate_limit
  )
}

# =============================================================================
# Group Building Functions
# =============================================================================

#' Calculate group status based on the furthest-along bill in the group
#' @param bill_statuses Tibble with bill, status, status_level columns
#' @param group_members Vector of bill numbers in the group
#' @return Named list with group_status and lead_bill
get_group_status <- function(bill_statuses, group_members) {
  group_bills <- bill_statuses |> filter(bill %in% group_members)

  if (nrow(group_bills) == 0) {
    return(list(group_status = "Introduced", lead_bill = NA_character_))
  }

  # Find the bill with the highest status level
  lead <- group_bills |> slice_max(status_level, n = 1, with_ties = FALSE)

  list(
    group_status = lead$status,
    lead_bill = lead$bill
  )
}

#' Build bill groups from edge list
#' @param edges_path Path to edges RDS file
#' @param json_dir Directory containing bill JSON files
#' @return Tibble with bills, groups, and group status
build_bill_groups <- function(
    edges_path = here::here("data/bills/relationship_edges.rds"),
    json_dir = here::here("legiscan/files_ga91_json/bill")
) {
  # Load edges
  edges <- load_relationship_edges(edges_path) |>
    filter(!is.na(to_bill))  # Remove self-references for bills with no relationships

  # Get all bills and their statuses
  message("Getting bill statuses...")
  bill_statuses <- get_all_bill_statuses(json_dir)

  message("Building relationship graph...")

  if (nrow(edges) == 0) {
    # No relationships - each bill is its own group
    result <- bill_statuses |>
      mutate(
        bill_group_id = row_number(),
        group_size = 1,
        group_members = map(bill, ~.x),
        group_status = status,
        lead_bill = bill
      )
    return(result)
  }

  # Create undirected graph from edges
  edge_df <- edges |> select(from_bill, to_bill)
  g <- graph_from_data_frame(edge_df, directed = FALSE)

  # Add isolated bills (those with no relationships) as vertices
  isolated_bills <- setdiff(bill_statuses$bill, names(V(g)))
  if (length(isolated_bills) > 0) {
    g <- add_vertices(g, length(isolated_bills), name = isolated_bills)
  }

  # Find connected components
  components <- components(g)

  group_membership <- tibble(
    bill = names(components$membership),
    bill_group_id = as.integer(components$membership)
  )

  # Calculate group statistics including group status
  message("Calculating group statuses...")
  group_stats <- group_membership |>
    group_by(bill_group_id) |>
    summarize(
      group_size = n(),
      group_members = list(sort(bill)),
      .groups = "drop"
    ) |>
    rowwise() |>
    mutate(
      group_status_info = list(get_group_status(bill_statuses, group_members)),
      group_status = group_status_info$group_status,
      lead_bill = group_status_info$lead_bill
    ) |>
    ungroup() |>
    select(-group_status_info)

  # Join everything together
  result <- bill_statuses |>
    left_join(group_membership, by = "bill") |>
    left_join(group_stats, by = "bill_group_id")

  # Bills not in the graph get their own group
  ungrouped <- result |> filter(is.na(bill_group_id))
  if (nrow(ungrouped) > 0) {
    max_group_id <- max(result$bill_group_id, na.rm = TRUE)
    result <- result |>
      mutate(
        bill_group_id = if_else(is.na(bill_group_id), row_number() + max_group_id, bill_group_id),
        group_size = if_else(is.na(group_size), 1L, group_size),
        group_members = if_else(map_lgl(group_members, is.null), map(bill, ~.x), group_members),
        group_status = if_else(is.na(group_status), status, group_status),
        lead_bill = if_else(is.na(lead_bill), bill, lead_bill)
      )
  }

  message("Done. Found ", n_distinct(result$bill_group_id), " bill groups.")

  return(result)
}

#' Save complete bill groups data to RDS file
#' @param output_path Path to save the RDS file
#' @param edges_path Path to edges RDS file
#' @param json_dir Directory containing bill JSON files
save_bill_groups <- function(
    output_path = here::here("data/bills/groups.rds"),
    edges_path = here::here("data/bills/relationship_edges.rds"),
    json_dir = here::here("legiscan/files_ga91_json/bill")
) {
  groups <- build_bill_groups(edges_path, json_dir)
  saveRDS(groups, output_path)
  message("Saved bill groups to ", output_path)
  return(groups)
}

# =============================================================================
# Convenience Functions
# =============================================================================

#' Full pipeline: scrape new bills, build groups, save
#' @param edges_path Path to edges RDS file
#' @param groups_path Path to groups RDS file
#' @param json_dir Directory containing bill JSON files
#' @param ga General Assembly number
#' @param rate_limit Seconds between scrape requests
update_bill_groups <- function(
    edges_path = here::here("data/bills/relationship_edges.rds"),
    groups_path = here::here("data/bills/groups.rds"),
    json_dir = here::here("legiscan/files_ga91_json/bill"),
    ga = 91,
    rate_limit = 1.5
) {
  # Step 1: Scrape any new bills
  update_relationship_edges(
    bill_numbers = NULL,
    edges_path = edges_path,
    json_dir = json_dir,
    ga = ga,
    rate_limit = rate_limit
  )

  # Step 2: Rebuild groups from full edge list
  save_bill_groups(groups_path, edges_path, json_dir)
}

#' View summary of current bill groups
#' @param groups_path Path to groups RDS file
bill_groups_summary <- function(groups_path = here::here("data/bills/groups.rds")) {
  if (!file.exists(groups_path)) {
    message("No bill groups file found. Run update_bill_groups() first.")
    return(invisible(NULL))
  }

  groups <- readRDS(groups_path)

  cat("=== Bill Groups Summary ===\n\n")
  cat("Total bills:", nrow(groups), "\n")
  cat("Total groups:", n_distinct(groups$bill_group_id), "\n")
  cat("Bills in multi-bill groups:", sum(groups$group_size > 1), "\n\n")

  cat("Group status distribution:\n")
  groups |>
    count(group_status) |>
    arrange(match(group_status, names(STATUS_LEVELS))) |>
    print()

  cat("\nBills where group status differs from individual status:\n")
  diff_status <- groups |>
    filter(group_size > 1, status != group_status) |>
    nrow()
  cat(diff_status, "bills\n")

  invisible(groups)
}

# =============================================================================
# Example Usage
# =============================================================================
#
# # First time: scrape all bills (this takes a while with rate limiting)
# update_bill_groups()
#
# # Later: only scrape new bills, then rebuild groups
# update_bill_groups()
#
# # Force re-scrape specific bills
# rescrape_bills(c("HF100", "SF50"))
#
# # View summary
# bill_groups_summary()
#
# # Load and use the groups data
# groups <- readRDS(here::here("data/bills/groups.rds"))
# groups |> filter(bill == "HF1")
