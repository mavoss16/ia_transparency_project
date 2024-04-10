#
# This is the server logic of a Shiny web application. You can run the
# application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
library(readr)
library(dplyr)
library(reactable)
library(htmltools)
library(leaflet)
library(sf)
library(stringr)
library(tidyr)
library(ggplot2)
library(ggpol)
library(ggparliament)
library(forcats)
library(scales)
library(lubridate)
# library(data.table)


# Reading from Github
legislators <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/legislators_90th_ga_clean.rds", "rb"))
legislation <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/legislation_90th_ga_clean.rds", "rb"))
legislation_actions <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/actions_legislation_90th_ga.rds", "rb"))
lobbyist_declarations <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/lobbyist_declarations_2023.rds", "rb"))
vote_records <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/floor_vote_records_90th_ga.rds", "rb"))
vote_summaries <- readRDS(url("https://github.com/mavoss16/iowa_legislature/raw/main/data/floor_vote_summaries_90th_ga.rds", "rb"))

# Reading from local files
# legislators <- read_rds("data/legislators_90th_ga_clean.rds")
# legislation <- read_rds("data/legislation_90th_ga_clean.rds")
# legislation_actions <- read_rds("data/actions_legislation_90th_ga.rds")
# lobbyist_declarations <- read_rds("data/lobbyist_declarations_2023.rds")
# vote_records <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_records_90th_ga.rds")
# vote_summaries <- read_rds("C:/Users/mavos/Documents/GitHub/iowa_legislature/data/floor_vote_summaries_90th_ga.rds")

senate_map <- st_read("shiny_data/Plan2_Senate.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)
house_map <- st_read("shiny_data/Plan2_House.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)

percent <- percent_format(accuracy = 0.1)


function(input, output, session) {


  output$out <- renderText({
    if (input$caps)
      toupper(input$txt)
    else
      input$txt
  })
  
  # observe({
  #   reactiveValuesToList(input)
  #   session$doBookmark()
  # })
  # # Update the query string
  # onBookmarked(updateQueryString)
  
  output$intro_text <- renderUI({
    paste0(
      paste0(
        "This is a preliminary dashboard designed to consolidate a variety of Iowa political data. ",
        "The dashboard is in development and as such will be changing as new features are added. ",
        "There also may be errors with certain selections. With time, these errors will be resolved.",
        "<br/>"
      ), "<br/>",
      strong("Last Data Update: "), "1/16/2024", "<br/>",
      strong("Primary Data Source: "),
      a(
        "https://www.legis.iowa.gov/",
        href = "https://www.legis.iowa.gov/",
        target = "_blank"
      ), "<br/>", "<br/>", "<br/>"
    ) |> HTML()
  })

# Legislation Data ------------------------------------------------------
  
  # Create choice vector for legislation dropdown
  file_choices <- reactive({
    category = input$category_input
    
    if(category == "All Legislation"){
      choices <- unique(legislation$file)
    } else {
      choices <- legislation |>
        filter(categorization == category) |>
        pull(file) |>
        unique()
    }
    return(choices)
  })
  
  # Update legislation dropdown
  observe({
    updateSelectizeInput(
      inputId = "legislation_input", choices = file_choices(), server = TRUE
    )
  })
  
  # Filter legislation data to selected file
  selected_leg <- reactive({
    legislation |>
      filter(file == input$legislation_input)
  })
  
  # Create long df for seat plot
  # selected_leg_long <- reactive({
  #   selected_leg() |>
  #     select(
  #       file, file_title, sponsor, 
  #       senate_vote_gop_yes, senate_vote_gop_no, senate_vote_gop_na, senate_vote_dem_yes, senate_vote_dem_no, senate_vote_dem_na,
  #       house_vote_gop_yes, house_vote_gop_no, house_vote_gop_na, house_vote_dem_yes, house_vote_dem_no, house_vote_dem_na
  #     ) |>
  #     pivot_longer(senate_vote_gop_yes:house_vote_dem_na, names_to = "vote", values_to = "vote_num")
  # })
  
  selected_leg_parliament <- reactive({
    parliament_data(
      election_data = selected_leg_long(),
      parl_rows = 
    )
  })
  
  # Get selected file name
  selected_leg_name <- reactive({
    selected_leg() |> pull(file) |> unlist()
  })
  
  # Filter actions data
  selected_leg_actions <- reactive({
    legislation_actions |>
      filter(
        file == selected_leg_name()
      )
  })
  
  # Filter Lobbyist Data
  selected_leg_declarations <- reactive({
    lobbyist_declarations |>
      filter(
        bill == selected_leg_name()
      )
  })

  

# Legislation Output ------------------------------------------------------
  
  output$legislation_summary_table <- renderReactable({
    legislation |>
      select(
        file, file_title, file_introduced_date, categorization, related_file_list_sorted, group_categorization
      ) |>
      arrange(
        file_introduced_date, file
      ) |>
      reactable(
        filterable = TRUE, searchable = TRUE,
        defaultPageSize = 25, showPageSizeOptions = TRUE,
        columns = list(
          file = colDef(
            name = "File", minWidth = 80
          ),
          file_title = colDef(
            name = "File Description", minWidth = 250
          ),
          file_introduced_date = colDef(
            name = "Date Introduced", minWidth = 110
          ),
          categorization = colDef(
            name = "Outcome", minWidth = 100
          ),
          related_file_list_sorted = colDef(
            name = "Related File Group", minWidth = 100
          ),
          group_categorization = colDef(
            name = "File Group Outcome", minWidth = 100
          )
        )
      )
  })
  
  
  # Create header text for selected file
  output$legislation_header_text <- renderUI({
    paste0(
      h2(selected_leg()$file),
      selected_leg()$file_title, "<br/>",
      strong("Sponsor(s): "), selected_leg()$sponsor, "<br/>",
      strong("Final Action: "), selected_leg()$last_action, "<br/>",
      a(
        paste0("https://www.legis.iowa.gov/legislation/BillBook?ga=90&ba=", str_remove_all(selected_leg_name(), " ")), 
        href = paste0("https://www.legis.iowa.gov/legislation/BillBook?ga=90&ba=", str_remove_all(selected_leg_name(), " ")),
        target = "_blank"
      )
    ) |> HTML()
  })
  
  output$house_vote_text <- renderUI({
    
    last_vote <- vote_summaries |>
      filter(chamber == "House" & file_name == selected_leg_name()) |>
      arrange(datetime) |>
      slice_tail(n = 1)
    
    if(nrow(last_vote) == 0){
      h5("No House Vote")
    } else{
      paste0(
        h5(last_vote$vote_outcome),
        h5(
          paste0(
            "Yes: ", last_vote$vote_yes_count, 
            " (", last_vote$vote_gop_yes, " R, ", last_vote$vote_dem_yes, " D)"
          )
        ),
        h5(
          paste0(
            "No: ", last_vote$vote_no_count,
            " (", last_vote$vote_gop_no, " R, ", last_vote$vote_dem_no, " D)"
          )
        )
      ) |> HTML()
    }
  })
  
  output$senate_vote_text <- renderUI({
    
    last_vote <- vote_summaries |>
      filter(chamber == "Senate" & file_name == selected_leg_name()) |>
      arrange(datetime) |>
      slice_tail(n = 1)
    
    if(nrow(last_vote) == 0){
      h5("No Senate Vote")
    } else{
      paste0(
        h5(last_vote$vote_outcome),
        h5(
          paste0(
            "Yes: ", last_vote$vote_yes_count, 
            " (", last_vote$vote_gop_yes, " R, ", last_vote$vote_dem_yes, " D)"
          )
        ),
        h5(
          paste0(
            "No: ", last_vote$vote_no_count,
            " (", last_vote$vote_gop_no, " R, ", last_vote$vote_dem_no, " D)"
          )
        )
      ) |> HTML()
    }
  })
  
  output$related_leg_outcome_text <- renderUI({
    ifelse(
      is.na(selected_leg()$related_file_list), 
      yes = "No Related Files", 
      no = paste0(selected_leg()$group_final_file, ", ", selected_leg()$group_categorization)
    ) |> h5()
  })
  
  output$lobbying_text <- renderUI({
    
    declarations <- selected_leg_declarations() |>
      group_by(lobbyist) |>
      arrange(date) |>
      slice_tail(n = 1) |>
      ungroup() |>
      pull(declaration)
    
    paste0(
      h5("# For: ", sum(declarations == "For", na.rm = TRUE)),
      h5("# Against: ", sum(declarations == "Against", na.rm = TRUE))
    ) |> HTML()
  })
  
  # Create table of actions
  output$actions <- renderReactable({
    reactable(
      selected_leg_actions() |> select(action, date),
      columns = list(
        action = colDef(name = "Action"),
        date = colDef(name = "Date")
      )
    )
  })
  
  # Create list of Senate Vote Datetimes
  senate_vote_list <- reactive({
    
    list <- vector()
    if(!is.null(selected_leg_name()) & length(selected_leg_name()) != 0){
      list <- vote_summaries |> filter(chamber == "Senate" & file_name == selected_leg_name()) |> pull(datetime)
    }
    
    if(length(list) == 0){
      return("No Senate Votes")
    } else{
      return(as.character(list))
    }
  })
  
  # Update selectizeInput for vote dates
  observe({
    updateSelectizeInput(inputId = "senate_vote_date_input", choices = senate_vote_list())
  })
  
  senate_vote_record_selection <- reactive({
    print(class(input$senate_vote_date_input))
    print(input$senate_vote_date_input)
    input_sequence_number <- vote_summaries |> filter(datetime == ymd_hms(input$senate_vote_date_input)) |> pull(sequence_no)
    if(length(input_sequence_number) == 0){
      input_sequence_number <- "No Vote"
    }
    vote_records |>
      filter(
        Chamber == "Senate", sequence_no == input_sequence_number
      ) |>
      select(Name, Party, District, County, vote)
  })
  
  # Create senate vote record table
  output$senate_vote <- renderReactable({
    reactable(
      senate_vote_record_selection(),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        vote = colDef(name = "Vote")
      )
    )
  })
  
  # Create senate seats plot
  # output$senate_vote_seats <- renderPlot({
  # 
  #   data <- selected_leg_long() |>
  #     filter(
  #       str_detect(vote, "senate")
  #     )
  #   par_data <- parliament_data(
  #     election_data = data, parl_rows = 4,
  #     party_seats = data$vote_num,
  #     type = "semicircle"
  #   )
  # 
  #   par_data |>
  #     ggplot(aes(x = x, y = y, color = vote)) +
  #     geom_parliament_seats() +
  #     scale_color_manual(
  #       values = c("#DC0309", "#EE8181", "grey", "#A4A3F6", "#2320E6", "grey"), 
  #       limits = c("senate_vote_gop_yes", "senate_vote_gop_no", "senate_vote_gop_na", "senate_vote_dem_no", "senate_vote_dem_yes", "senate_vote_dem_na"),
  #       labels = c("GOP: Yes", "GOP: No", "GOP: NA", "Dem: No", "Dem: Yes", "Dem: NA")
  #     ) +
  #     theme_ggparliament()
  # })
  
  
  # Create map of senate vote
  output$senate_vote_map <- renderLeaflet({
    
    # Get vote record data from list-column
    senate_vote <- senate_vote_record_selection() |>
      mutate(
        vote_outcome = paste0(Party, ": ", vote),
        labels = paste0(
          Name, ", Senate District ", District, "<br>",
          Party, "<br>",
          selected_leg_name(), ": ", vote
        )
      )
    
    # Add geospatial data
    senate_vote <- left_join(senate_map |> select(District, geometry), senate_vote, by = c("District"))
    
    # Create palette
    pal <- colorFactor(
      c("#2320E6", "#A4A3F6", "#DC0309", "#EE8181"),
      levels = c("Democrat: Yes", "Democrat: No", "Republican: Yes", "Republican: No")
    )
    
    # Create and output map
    leaflet() |>
      addTiles() |>
      addPolygons(
        data = senate_vote, fillColor = pal(senate_vote$vote_outcome), fillOpacity = 0.9,
        color = "black", weight = 1,
        label = lapply(senate_vote$labels, HTML)
      ) |>
      addLegend(
        position = "bottomright", pal = pal, values = c("Democrat: Yes", "Democrat: No", "Republican: Yes", "Republican: No"),
        opacity = 0.9, title = paste0(selected_leg_name(), " Senate Vote")
      )
    
  })
  
  # Create list of House Vote Datetimes
  house_vote_list <- reactive({
    
    list <- vector()
    if(!is.null(selected_leg_name()) & length(selected_leg_name()) != 0){
      list <- vote_summaries |> filter(chamber == "House" & file_name == selected_leg_name()) |> pull(datetime)
    }
    
    if(length(list) == 0){
      return("No House Votes")
    } else{
      return(as.character(list))
    }
  })
  
  # Update selectizeInput for vote dates
  observe({
    updateSelectizeInput(inputId = "house_vote_date_input", choices = house_vote_list())
  })
  
  house_vote_record_selection <- reactive({
    input_sequence_number <- vote_summaries |> filter(datetime == ymd_hms(input$house_vote_date_input)) |> pull(sequence_no)
    if(length(input_sequence_number) == 0){
      input_sequence_number <- "No Vote"
    }
    vote_records |>
      filter(
        Chamber == "House", sequence_no == input_sequence_number
      ) |>
      select(Name, Party, District, County, vote)
  })
  
  # Create house vote record table
  output$house_vote <- renderReactable({
    reactable(
      house_vote_record_selection(),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        vote = colDef(name = "Vote")
      )
    )
  })
  
  # Create house seats plot
  # output$house_vote_seats <- renderPlot({
  #   data <- selected_leg_long() |>
  #     filter(
  #       str_detect(vote, "house")
  #     )
  #   par_data <- parliament_data(
  #     election_data = data, parl_rows = 5,
  #     party_seats = data$vote_num,
  #     type = "semicircle"
  #   )
  #   
  #   par_data |>
  #     ggplot(aes(x = x, y = y, color = vote)) +
  #     geom_parliament_seats() +
  #     scale_color_manual(
  #       values = c("#DC0309", "#EE8181", "grey", "#A4A3F6", "#2320E6", "grey"), 
  #       limits = c("house_vote_gop_yes", "house_vote_gop_no", "house_vote_gop_na", "house_vote_dem_no", "house_vote_dem_yes", "house_vote_dem_na"),
  #       labels = c("GOP: Yes", "GOP: No", "GOP: NA", "Dem: No", "Dem: Yes", "Dem: NA")
  #     ) +
  #     theme_ggparliament()
  # })
  
  # Create map of house vote
  output$house_vote_map <- renderLeaflet({
    
    # Get vote record data from list-column
    house_vote <- house_vote_record_selection() |>
      mutate(
        vote_outcome = paste0(Party, ": ", vote),
        labels = paste0(
          Name, ", House District ", District, "<br>",
          Party, "<br>",
          selected_leg_name(), ": ", vote
        )
      )
    
    # Add geospatial data
    house_vote <- left_join(house_map |> select(District, geometry), house_vote, by = c("District"))
    
    # Create palette
    pal <- colorFactor(
      c("#2320E6", "#A4A3F6", "#DC0309", "#EE8181"),
      levels = c("Democrat: Yes", "Democrat: No", "Republican: Yes", "Republican: No")
    )
    
    # Create and output map
    leaflet() |>
      addTiles() |>
      addPolygons(
        data = house_vote, fillColor = pal(house_vote$vote_outcome), fillOpacity = 0.9,
        color = "black", weight = 1,
        label = lapply(house_vote$labels, HTML)
      ) |>
      addLegend(
        position = "bottomright", pal = pal, values = c("Democrat: Yes", "Democrat: No", "Republican: Yes", "Republican: No"),
        opacity = 0.9, title = paste0(selected_leg_name(), " House Vote")
      )
  })
  
  # Create lobbyist declaration table
  output$declarations <- renderReactable({
    table_data <- lobbyist_declarations |>
      filter(bill == selected_leg_name()) |>
      select(date, client, lobbyist, declaration)
    reactable(
      table_data,
      filterable = TRUE, searchable = TRUE,
      columns = list(
        date = colDef(name = "Date"),
        client = colDef(name = "Client"),
        lobbyist = colDef(name = "Lobbyist Name"),
        declaration = colDef(name = "Declaration")
      )
    )
  })
  
  

# Legislator Data -------------------------------------------------------
  
  # Create choice vector for legislation dropdown
  legislator_choices <- reactive({

    legislators |>
      filter(
        Chamber == input$chamber_input
      ) |>
      pull(
        Name
      )
  })
  
  # Update legislation dropdown
  observe({
    updateSelectizeInput(
      inputId = "legislator_input", choices = legislator_choices(), server = TRUE
    )
  })
  
  # Filter legislation data to selected file
  selected_legislator <- reactive({
    legislators |>
      filter(Name == input$legislator_input)
  })
  

# Legislator Output -------------------------------------------------------
  
  output$legislator_summary_table <- renderReactable({
    legislators |>
      select(
        Name, Chamber, District, County, Party, 
        sponsor_count, floor_manager_count, 
        yes_count, no_count, with_party_pct
      ) |>
      arrange(
        Chamber, District
      ) |>
      reactable(
        filterable = TRUE, searchable = TRUE, resizable = TRUE,
        defaultPageSize = 25, showPageSizeOptions = TRUE,
        columns = list(
          Name = colDef(
            name = "Name", minWidth = 175
          ),
          Chamber = colDef(
            name = "Chamber", minWidth = 100
          ),
          District = colDef(
            name = "District", align = "left", minWidth = 75
          ),
          County = colDef(
            name = "County", minWidth = 100
          ),
          Party = colDef(
            name = "Party", minWidth = 90,
            style = function(value){
              color <- case_when(
                value == "Republican" ~ "#fc7272",
                value == "Democrat" ~ "#70a3fa",
                TRUE ~ "#c9ced6"
              )
              list(background = color)
            }
          ),
          sponsor_count = colDef(
            name = "Sponsored File Count", minWidth = 90
          ),
          floor_manager_count = colDef(
            name = "Floor-Managed File Count", minWidth = 85
          ),
          yes_count = colDef(
            name = "Yes Votes", minWidth = 70
          ),
          no_count = colDef(
            name = "No Votes", minWidth = 70
          ),
          with_party_pct = colDef(
            name = "Party Agreement Pct.", minWidth = 95,
            format = colFormat(percent = TRUE, digits = 1)
          )
        )
      )
  })
  
  # Legislator header text
  output$legislator_header_text <- renderUI({
    paste0(
      h2(
        paste0(selected_legislator()$Name, " (", selected_legislator()$Party, ", ", selected_legislator()$County, " County)")
      ), # "<br/>",
      selected_legislator()$Chamber, " District ", selected_legislator()$District, "<br/>",
      a(
        paste0("https://www.legis.iowa.gov/", selected_legislator()$link),
        href = paste0("https://www.legis.iowa.gov/", selected_legislator()$link),
        target = "_blank"
      )
    ) |> HTML()
  })
  
  # Create summary text for selected file
  output$legislator_summary_text <- renderUI({
    paste0(
      strong(selected_legislator()$Name), "<br/>",
      strong("District: "), selected_legislator()$District, "<br/>",
      strong("Party: "), selected_legislator()$Party, "<br/>",
      strong("Home County: "), selected_legislator()$County, "<br/>",
      strong("Number of Sponsored Files: "), selected_legislator()$sponsor_count, "<br/>",
      strong("Number of Sponsored Files Advanced Through Committee: "), selected_legislator()$sponsor_advanced_count, "<br/>",
      strong("Number of Sponsored-Related Files Signed: "), selected_legislator()$sponsor_group_signed_count, "<br/>",
      strong("Number of Floor-Managed Files: "), selected_legislator()$floor_manager_count, "<br/>",
      strong("Number of Floor-Managed Files Signed: "), selected_legislator()$floor_manager_signed_count, "<br/>",
      strong("Link: "), 
      a(
        paste0("https://www.legis.iowa.gov/", selected_legislator()$link), 
        href = paste0("https://www.legis.iowa.gov/", selected_legislator()$link),
        target = "_blank"
      )
    ) |> HTML()

  })
  
  # Create legislator summary vote text
  output$legislator_vote_summary_text <- renderUI({
    paste0(
      "Yes Votes: ", selected_legislator()$yes_count, "<br/>",
      "No Votes: ", selected_legislator()$no_count, "<br/>",
      "% With Party: ", percent(selected_legislator()$with_party_pct)
    ) |> HTML()
  })
  
  output$legislator_vote_record_yes_text <- renderUI({
    selected_legislator()$yes_count
  })
  output$legislator_vote_record_no_text <- renderUI({
    selected_legislator()$no_count
  })
  output$legislator_vote_record_with_party_text <- renderUI({
    percent(selected_legislator()$with_party_pct)
  })
  
  # Create legislator sponsor summary text
  output$legislator_sponsor_summary_text <- renderUI({
    paste0(
      "Number of Sponsored Files: ", selected_legislator()$sponsor_count, "<br/>",
      "Number of Solo-Sponsored Files: ", selected_legislator()$sponsor_sole_count, "<br/>",
      "Number of Sponsored Files Advanced Through Committee: ", selected_legislator()$sponsor_advanced_count, "<br/>",
      "Number of Sponsored-Related Files Signed: ", selected_legislator()$sponsor_group_signed_count, "<br/>"
    ) |> HTML()
  })
  
  output$legislator_sponsor_num_text <- renderUI({
    selected_legislator()$sponsor_count
  })
  output$legislator_sponsor_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$sponsor_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  output$legislator_sponsor_sole_num_text <- renderUI({
    selected_legislator()$sponsor_sole_count
  })
  output$legislator_sponsor_sole_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$sponsor_sole_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  output$legislator_sponsor_advance_num_text <- renderUI({
    selected_legislator()$sponsor_advanced_count
  })
  output$legislator_sponsor_advance_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$sponsor_advanced_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  output$legislator_sponsor_group_sign_num_text <- renderUI({
    selected_legislator()$sponsor_group_signed_count
  })
  output$legislator_sponsor_group_sign_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$sponsor_group_signed_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  
  # Create legislator floor manager summary text
  output$legislator_floor_manager_summary_text <- renderUI({
    paste0(
      "Number of Floor-Managed Files: ", selected_legislator()$floor_manager_count, "<br/>",
      "Number of Floor-Managed Files Signed: ", selected_legislator()$floor_manager_signed_count
    ) |> HTML()
  })
  
  output$legislator_floor_manager_num_text <- renderUI({
    selected_legislator()$floor_manager_count
  })
  output$legislator_floor_manager_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$floor_manager_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  output$legislator_floor_manager_signed_num_text <- renderUI({
    selected_legislator()$floor_manager_signed_count
  })
  output$legislator_floor_manager_signed_num_caption <- renderUI({
    paste0(
      "Chamber Rank: ", selected_legislator()$floor_manager_signed_count_rank, " of ", ifelse(selected_legislator()$Chamber == "House", yes = "100", no = "50")
    )
  })
  
  output$legislator_vote_record_table <- renderReactable({
    table_data <- vote_records |>
      filter(
        Name == input$legislator_input
      ) |>
      select(Chamber, sequence_no, file_name, vote, vote_agree) |>
      left_join(vote_summaries |> select(chamber, file_name, sequence_no, datetime, vote_outcome), by = c("Chamber" = "chamber", "file_name", "sequence_no")) |>
      select(-Chamber, -sequence_no) |>
      mutate(
        vote_agree = case_when(
          vote_agree == TRUE ~ "Yes",
          vote_agree == FALSE ~ "No"
        )
      )
    
    reactable(
      table_data,
      filterable = TRUE, searchable = TRUE,
      columns = list(
        file_name = colDef(name = "File Name"),
        vote = colDef(name = "Vote"),
        datetime = colDef(name = "Vote Date"),
        vote_outcome = colDef(name = "Vote Outcome"),
        vote_agree = colDef(name = "Agreement with Party Majority")
      )
    )
  })

  # Create sponsor table
  output$legislator_sponsor_table <- renderReactable({
    reactable(
      selected_legislator()$sponsor |> as.data.frame() |> select(file, file_title, sponsor, action_list, categorization, related_file_list, group_categorization),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        file = colDef(name = "File Name"),
        file_title = colDef(name = "File Title"),
        sponsor = colDef(name = "Sponsor(s)"),
        action_list = colDef(name = "List of Actions"),
        categorization = colDef(name = "Furthest Action"),
        related_file_list = colDef(name = "Related Files"),
        group_categorization = colDef(name = "Related File Action")
      )
    )
  })

  # Create floor manager table
  output$legislator_floor_manager_table <- renderReactable({
    reactable(
      selected_legislator()$floor_manager |> as.data.frame() |> select(file, file_title, sponsor, action_list, categorization, related_file_list, group_categorization),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        file = colDef(name = "File Name"),
        file_title = colDef(name = "File Title"),
        sponsor = colDef(name = "Sponsor(s)"),
        action_list = colDef(name = "List of Actions"),
        categorization = colDef(name = "Furthest Action"),
        related_file_list = colDef(name = "Related Files"),
        group_categorization = colDef(name = "Related File Action")
        
        
      )
    )
  })
  
  
  session$onSessionEnded(function() {
    stopApp()
  })
}
