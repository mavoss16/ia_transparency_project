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
# library(data.table)


legislators <- read_rds("data/legislators_90th_ga_clean.rds")
legislation <- read_rds("data/legislation_2023_clean.rds")
senate_map <- st_read("data/Districts/Plan2_Senate.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)
house_map <- st_read("data/Districts/Plan2_House.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)

# contributions <- fread("")


function(input, output, session) {
  

# Legislation Server ------------------------------------------------------
  
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
  
  # Get selected file name
  selected_leg_name <- reactive({
    selected_leg() |> pull(file) |> unlist()
  })
  
  # Create summary text for selected file's senate vote
  senate_vote <- reactive({
    if(is.na(selected_leg()$senate_vote_date)){
      return("No Senate Vote")
    } else{
      text <- paste0(
        selected_leg()$senate_vote_outcome, "<br/>",
        "Yes: ", selected_leg()$senate_vote_yes_count, 
        " (", selected_leg()$senate_vote_gop_yes, " R, ", selected_leg()$senate_vote_dem_yes, " D), ",
        "No: ", selected_leg()$senate_vote_no_count,
        " (", selected_leg()$senate_vote_gop_no, " R, ", selected_leg()$senate_vote_dem_no, " D)"
      )
      return(text)
    }
  })
  
  # Create summary text for selected file's house vote
  house_vote <- reactive({
    if(is.na(selected_leg()$house_vote_date)){
      return("No House Vote")
    } else{
      text <- paste0(
        selected_leg()$house_vote_outcome, "<br/>",
        "Yes: ", selected_leg()$house_vote_yes_count, 
        " (", selected_leg()$house_vote_gop_yes, " R, ", selected_leg()$house_vote_dem_yes, " D), ",
        "No: ", selected_leg()$house_vote_no_count,
        " (", selected_leg()$house_vote_gop_no, " R, ", selected_leg()$house_vote_dem_no, " D)"
      )
      return(text)
    }
  })
  
  
  # Create summary text for selected file
  output$leg_summary_text <- renderUI({
    paste0(
      strong("File Number: "), selected_leg()$file, "<br/>",
      strong("Title: "), selected_leg()$file_title, "<br/>",
      strong("Sponsor: "), selected_leg()$sponsor, "<br/>",
      strong("Last Action: "), selected_leg()$last_action, "<br/>",
      strong("Final Senate Vote: "), "<br/>",
      senate_vote(), "<br/>",
      strong("Final House Vote: "), "<br/>", 
      house_vote(), "<br/>",
      strong("# Lobbyists For: "), selected_leg()$num_dec_for, "<br/>",
      strong("# Lobbyists Against: "), selected_leg()$num_dec_against, "<br/>",
      strong("BillBook Link: "), 
        a(
          paste0("https://www.legis.iowa.gov/legislation/BillBook?ga=90&ba=", str_remove_all(selected_leg_name(), " ")), 
          href = paste0("https://www.legis.iowa.gov/legislation/BillBook?ga=90&ba=", str_remove_all(selected_leg_name(), " ")),
          target = "_blank"
        )
    ) |> HTML()
  })
  
  # Create table of actions
  output$actions <- renderReactable(
    reactable(selected_leg()$actions |> as.data.frame())
  )
  
  # Create senate vote record table
  output$senate_vote <- renderReactable(
    reactable(
      selected_leg()$senate_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote),
      filterable = TRUE, searchable = TRUE
    )
  )
  
  # Create map of senate vote
  output$senate_vote_map <- renderLeaflet({
    
    # Get vote record data from list-column
    senate_vote <- selected_leg()$senate_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote) |>
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
        opacity = 0.9, title = paste0(selected_leg_name(), " Final Senate Vote")
      )
    
  })
  
  # Create house vote record table
  output$house_vote <- renderReactable(
    reactable(
      selected_leg()$house_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote),
      filterable = TRUE, searchable = TRUE
    )
  )
  
  # Create map of house vote
  output$house_vote_map <- renderLeaflet({
    
    # Get vote record data from list-column
    house_vote <- selected_leg()$house_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote) |>
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
        opacity = 0.9, title = paste0(selected_leg_name(), " Final House Vote")
      )
  })
  
  # Create lobbyist declaration table
  output$declarations <- renderReactable(
    reactable(
      selected_leg()$lobbyist_declarations |> as.data.frame() |> select(client, lobbyist, declaration),
      filterable = TRUE, searchable = TRUE
    )
  )
  
  

# Legislator Server -------------------------------------------------------
  
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
  
  # Create summary text for selected file
  output$legislator_summary_text <- renderUI({
    paste0(
      strong(selected_legislator()$Name), "<br/>",
      strong("District: "), selected_legislator()$District, "<br/>",
      strong("Party: "), selected_legislator()$Party, "<br/>",
      strong("Home County: "), selected_legislator()$County, "<br/>",
      strong("Number of Sponsored Files: "), selected_legislator()$sponsor_count, "<br/>",
      strong("Number of Sponsored Files Advanced Through Committee: "), selected_legislator()$sponsor_advanced_count, "<br/>",
      strong("Number of Floor-Managed Files: "), selected_legislator()$floor_manager_count, "<br/>",
      strong("Link: "), 
      a(
        paste0("https://www.legis.iowa.gov/", selected_legislator()$link), 
        href = paste0("https://www.legis.iowa.gov/", selected_legislator()$link),
        target = "_blank"
      )
    ) |> HTML()

  })


  # Create sponsor table
  output$legislator_sponsor_table <- renderReactable({
    reactable(
      selected_legislator()$sponsor |> as.data.frame() |> select(file, file_title, sponsor, action_list, categorization),
      filterable = TRUE, searchable = TRUE
    )
  })

  # Create floor manager table
  output$legislator_floor_manager_table <- renderReactable({
    reactable(
      selected_legislator()$floor_manager |> as.data.frame() |> select(file, file_title, sponsor, action_list, categorization),
      filterable = TRUE, searchable = TRUE
    )
  })
  
}
