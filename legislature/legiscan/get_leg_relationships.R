library(dplyr)
library(stringr)
library(purrr)
library(rvest)
library(igraph)

# Function to extract all related bills from a bill's page
get_bill_relationships <- function(bill_number, ga = 91) {
  
  print(paste("Processing:", bill_number))
  
  # Construct the URL
  base_url <- "https://www.legis.iowa.gov/legislation/BillBook"
  url <- paste0(base_url, "?ba=", bill_number, "&ga=", ga)
  
  # Read the HTML with retry logic
  page <- NULL
  for(attempt in 1:3) {
    page <- tryCatch(
      {read_html_live(url)},
      error = function(e) {
        last_err <<- e
        NULL
      }
    )
    if(!is.null(page)) break
    if(is.null(page) & attempt < 3) {
      print(paste0("Page reading failed, trying attempt #", attempt + 1))
      Sys.sleep(2)
    } else if(attempt == 3) {
      warning(paste("Failed to read page for", bill_number))
      return(tibble(
        bill = bill_number,
        related_bills = list(character(0)),
        companion_bills = list(character(0)),
        similar_bills = list(character(0)),
        formerly = NA_character_,
        see_also = NA_character_
      ))
    }
  }
  
  Sys.sleep(1)
  
  # Extract the related information section
  related_info <- page |>
    html_elements("table") |>
    html_elements(xpath = "//*[contains(@class, 'billRelatedInfo')]")
  
  # Initialize vectors for different relationship types
  companion_bills <- character(0)
  similar_bills <- character(0)
  formerly <- NA_character_
  see_also <- NA_character_
  
  # Extract companion and similar bills
  if(length(related_info) > 0) {
    # Get all links and text
    links <- related_info |>
      html_elements("a") |>
      html_text(trim = TRUE)
    
    all_related <- links[str_detect(links, "^[A-Z]+[0-9]+$")]
    
    # Get the full text to parse relationships
    full_text <- related_info |>
      html_text(trim = TRUE)
    
    # Extract companion bills (marked with (C))
    if(str_detect(full_text, "\\(C\\)")) {
      companion_section <- str_extract(full_text, "\\(C\\)[^(]+")
      companion_bills <- str_extract_all(companion_section, "[A-Z]+\\s*\\d+")[[1]]
      companion_bills <- companion_bills[companion_bills != bill_number]
    }
    
    # Extract similar bills (marked with (S))
    if(str_detect(full_text, "\\(S\\)")) {
      similar_section <- str_extract(full_text, "\\(S\\)[^(]+")
      similar_bills <- str_extract_all(similar_section, "[A-Z]+\\s*\\d+")[[1]]
      similar_bills <- similar_bills[similar_bills != bill_number]
    }
  }
  
  # Combine all related bills
  # all_related <- unique(c(
  #   companion_bills,
  #   similar_bills,
  #   if(!is.na(formerly)) str_split(formerly, ",\\s*")[[1]] else character(0),
  #   if(!is.na(see_also)) str_split(see_also, ",\\s*")[[1]] else character(0)
  # ))
  
  # Return structured data
  tibble(
    bill = bill_number,
    related_bills = list(all_related),
    companion_bills = list(companion_bills),
    similar_bills = list(similar_bills)
  )
}


# Function to build relationship groups using graph theory
build_bill_groups <- function(relationship_df) {
  
  # Create edge list from relationships
  edges <- relationship_df |>
    select(bill, related_bills) |>
    unnest(related_bills) |>
    filter(related_bills != "") |>
    mutate(
      bill = str_remove_all(bill, "\\s"),
      related_bills = str_remove_all(related_bills, "\\s")
    )
  
  # Handle case where there are no edges
  if(nrow(edges) == 0) {
    # All bills are in their own groups
    return(
      relationship_df |>
        mutate(
          bill_group_id = row_number(),
          group_size = 1,
          group_members = map(bill, ~.x)
        )
    )
  }
  
  # Create undirected graph
  g <- graph_from_data_frame(edges, directed = FALSE)
  
  # Find connected components (groups)
  components <- components(g)
  
  # Create group membership dataframe
  group_membership <- tibble(
    bill = names(components$membership),
    bill_group_id = as.integer(components$membership)
  )
  
  # Add group statistics
  group_stats <- group_membership |>
    group_by(bill_group_id) |>
    summarize(
      group_size = n(),
      group_members = list(sort(bill))
    )
  
  # Join back to original data
  result <- relationship_df |>
    mutate(bill = str_remove_all(bill, "\\s")) |>
    left_join(group_membership, by = "bill") |>
    left_join(group_stats, by = "bill_group_id") |>
    arrange(bill_group_id, bill)
  
  return(result)
}


# Main function to process all bills
create_bill_relationship_groups <- function(bill_list, ga = 91, rate_limit = 1) {
  
  # Get relationships for all bills
  relationships <- map_dfr(
    bill_list,
    ~{
      result <- get_bill_relationships(.x, ga = ga)
      Sys.sleep(rate_limit)
      result
    }
  )
  
  # Build groups
  grouped_bills <- build_bill_groups(relationships)
  
  return(grouped_bills)
}


# Example usage:
bill_list <- c("HF1038", "SF657", "HF231")
groups <- create_bill_relationship_groups(bill_list, ga = 91)

# View groups
groups |>
  select(bill, bill_group_id, group_size, group_members, formerly, see_also) |>
  View()

# Get summary of group sizes
groups |>
  distinct(bill_group_id, group_size) |>
  count(group_size)