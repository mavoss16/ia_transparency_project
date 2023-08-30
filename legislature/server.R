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
# library(data.table)


legislators <- read_rds("shiny_data/legislators_90th_ga_clean.rds")
legislation <- read_rds("shiny_data/legislation_2023_clean.rds")
senate_map <- st_read("shiny_data/Plan2_Senate.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)
house_map <- st_read("shiny_data/Plan2_House.shp") |> st_transform(crs = 4326) |> transmute(District = as.numeric(DISTRICT), geometry = geometry)

contributions <- read_rds("shiny_data/cleaned_contributions_post_2016.rds")
# committees <- read_rds("shiny_data/candidate_committees.rds")
ia_zips <- read_rds("shiny_data/ia_zctas.rds")
# us_zips <- read_rds("data/us_zctas.rds")


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
      strong("Last Data Update: "), "7/12/2023", "<br/>",
      strong("Primary Data Source: "),
      a(
        "https://www.legis.iowa.gov/",
        href = "https://www.legis.iowa.gov/",
        target = "_blank"
      ), "<br/>", "<br/>", "<br/>"
    ) |> HTML()
  })

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
  
  # Create long df for seat plot
  selected_leg_long <- reactive({
    selected_leg() |>
      select(
        file, file_title, sponsor, 
        senate_vote_gop_yes, senate_vote_gop_no, senate_vote_gop_na, senate_vote_dem_yes, senate_vote_dem_no, senate_vote_dem_na,
        house_vote_gop_yes, house_vote_gop_no, house_vote_gop_na, house_vote_dem_yes, house_vote_dem_no, house_vote_dem_na
      ) |>
      pivot_longer(senate_vote_gop_yes:house_vote_dem_na, names_to = "vote", values_to = "vote_num")
  })
  
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
      strong("Related Files: "), ifelse(is.na(selected_leg()$related_file_list), yes = "No Related Files", no = selected_leg()$related_file_list), "<br/>",
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
  output$actions <- renderReactable({
    reactable(
      selected_leg()$actions |> as.data.frame(),
      columns = list(
        action = colDef(name = "Action"),
        date = colDef(name = "Date"),
        action_notes = colDef(name = "Notes")
      )
    )
  })
  
  # Create senate vote record table
  output$senate_vote <- renderReactable({
    reactable(
      selected_leg()$senate_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        vote = colDef(name = "Vote")
      )
    )
  })
  
  # Create senate seats plot
  output$senate_vote_seats <- renderPlot({

    data <- selected_leg_long() |>
      filter(
        str_detect(vote, "senate")
      )
    par_data <- parliament_data(
      election_data = data, parl_rows = 4,
      party_seats = data$vote_num,
      type = "semicircle"
    )

    par_data |>
      ggplot(aes(x = x, y = y, color = vote)) +
      geom_parliament_seats() +
      scale_color_manual(
        values = c("#DC0309", "#EE8181", "grey", "#A4A3F6", "#2320E6", "grey"), 
        limits = c("senate_vote_gop_yes", "senate_vote_gop_no", "senate_vote_gop_na", "senate_vote_dem_no", "senate_vote_dem_yes", "senate_vote_dem_na"),
        labels = c("GOP: Yes", "GOP: No", "GOP: NA", "Dem: No", "Dem: Yes", "Dem: NA")
      ) +
      theme_ggparliament()
  })
  
  
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
  output$house_vote <- renderReactable({
    reactable(
      selected_leg()$house_vote_record |> as.data.frame() |> select(Name, Party, District, County, vote),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        vote = colDef(name = "Vote")
      )
    )
  })
  
  # Create house seats plot
  output$house_vote_seats <- renderPlot({
    data <- selected_leg_long() |>
      filter(
        str_detect(vote, "house")
      )
    par_data <- parliament_data(
      election_data = data, parl_rows = 5,
      party_seats = data$vote_num,
      type = "semicircle"
    )
    
    par_data |>
      ggplot(aes(x = x, y = y, color = vote)) +
      geom_parliament_seats() +
      scale_color_manual(
        values = c("#DC0309", "#EE8181", "grey", "#A4A3F6", "#2320E6", "grey"), 
        limits = c("house_vote_gop_yes", "house_vote_gop_no", "house_vote_gop_na", "house_vote_dem_no", "house_vote_dem_yes", "house_vote_dem_na"),
        labels = c("GOP: Yes", "GOP: No", "GOP: NA", "Dem: No", "Dem: Yes", "Dem: NA")
      ) +
      theme_ggparliament()
  })
  
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
  output$declarations <- renderReactable({
    reactable(
      selected_leg()$lobbyist_declarations |> as.data.frame() |> select(client, lobbyist, declaration),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        client = colDef(name = "Client"),
        lobbyist = colDef(name = "Lobbyist Name"),
        declaration = colDef(name = "Declaration")
      )
    )
  })
  
  

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
      filterable = TRUE, searchable = TRUE,
      columns = list(
        file = colDef(name = "File Name"),
        file_title = colDef(name = "File Title"),
        sponsor = colDef(name = "Sponsor(s)"),
        action_list = colDef(name = "List of Actions"),
        categorization = colDef(name = "Furthest Action")
      )
    )
  })

  # Create floor manager table
  output$legislator_floor_manager_table <- renderReactable({
    reactable(
      selected_legislator()$floor_manager |> as.data.frame() |> select(file, file_title, sponsor, action_list, categorization),
      filterable = TRUE, searchable = TRUE,
      columns = list(
        file = colDef(name = "File Name"),
        file_title = colDef(name = "File Title"),
        sponsor = colDef(name = "Sponsor(s)"),
        action_list = colDef(name = "List of Actions"),
        categorization = colDef(name = "Furthest Action")
      )
    )
  })
  
  

# Contributions Server ----------------------------------------------------
  
  date_rows <- reactive({
    contributions |>
      with(which(date >= min(input$contribution_date_input) & date <= max(input$contribution_date_input)))
  })

  committee_rows <- reactive({
    if(is.null(input$committee_input)){
      return(c(-1))
    }
    contributions |>
      with(which(committee_unique_name == input$committee_input))
  })

  contribution_type_rows <- reactive({
    if(input$contribution_type_input == "All"){
      rows <- 1:nrow(contributions)
    } else{
      rows <- contributions |>
        with(which(contribution_type == input$contribution_type_input))
    }

    return(rows)
  })

  contribution_geo_rows <- reactive({
    rows <- contributions |>
      with(which(contribution_geo == input$contribution_geo_input))
    return(rows)
  })

  final_rows <- reactive({
    final_rows <- intersect(date_rows(), committee_rows())
    final_rows <- intersect(final_rows, contribution_type_rows())
    final_rows <- intersect(final_rows, contribution_geo_rows())

    final_rows
  })

  date_committee_filtered_data <- reactive({
    final_rows <- intersect(date_rows(), committee_rows())
    contributions |>
      slice(final_rows)
  })

  contribution_data <- reactive({
    # final_rows <- intersect(date_rows, committee_rows)
    # final_rows <- intersect(final_rows, contribution_type_rows)
    # final_rows <- intersect(final_rows, contribution_geo_rows)
    #
    contributions |>
      slice(final_rows())

  })

  contribution_type_summary <- reactive({
    date_committee_filtered_data() |>
      group_by(contribution_type) |>
      summarize(
        total_contributions = sum(contribution_amount, na.rm = T),
        average_contribution = mean(contribution_amount, na.rm = T),
        num_contributions = n()
      ) |>
      ungroup() |>
      mutate(
        contribution_pct = total_contributions / sum(total_contributions, na.rm = T)
      )
  })

  contribution_geo_summary <- reactive({
    date_committee_filtered_data() |>
      group_by(contribution_geo) |>
      summarize(
        total_contributions = sum(contribution_amount, na.rm = T),
        average_contribution = mean(contribution_amount, na.rm = T),
        num_contributions = n()
      ) |>
      mutate(
        contribution_pct = total_contributions / sum(total_contributions, na.rm = T)
      )
  })

  committee_choices <- reactive({
    if(input$committee_type_input == "All"){
      choices <- unique(contributions$committee_unique_name)
    } else{
      choices <- contributions |>
        select(committee_unique_name, committee_type2) |>
        filter(
          committee_type2 == input$committee_type_input
        ) |>
        pull(committee_unique_name) |>
        unique()
    }

    return(choices)
  })


  observe({
    updateSelectizeInput(
      inputId = "committee_input", choices = committee_choices(), server = TRUE
    )
  })

  # output$test_text <- renderUI({
  #   paste0(
  #     # class(committee_rows()), committee_rows()[1], "<br/>",
  #     # class(date_rows()), date_rows()[1], "<br/>",
  #     # class(contribution_type_rows()), contribution_type_rows()[1], "<br/>",
  #     # class(contribution_geo_rows()), contribution_geo_rows()[1], "<br/>",
  #     # # "Final: ", final_rows()[1], "<br/>",
  #     # class(final_rows()),
  #     paste0(input$contribution_date_input, collapse = "--"), "<br/>",
  #     input$committee_type_input, "<br/>",
  #     input$committee_input, "<br/>"
  #   ) |>
  #     HTML()
  # })

  # output$contribution_test <- renderReactable({
  #   reactable(contribution_data() |> slice(1:100))
  # })


  sf_zip_data <- reactive({

    if(input$contribution_geo_input == "Iowa"){
      data <- contribution_data() |>
        filter(
          zip5 %in% ia_zips$ZCTA5CE10
        )

      zips <- ia_zips |>
        filter(
          ZCTA5CE10 %in% unique(data$zip5)
        ) |>
        rename(zip5 = ZCTA5CE10)
    } # else{
    #   data <- contribution_data() |>
    #     filter(
    #       !(zip5 %in% ia_zips$ZCTA5CE10)
    #     )
    # 
    #   zips <- us_zips |>
    #     filter(
    #       ZCTA5CE20 %in% unique(data$zip5)
    #     ) |>
    #     rename(zip5 = ZCTA5CE20)
    # }

    data <- data |>
      group_by(zip5) |>
      summarize(
        total_contributions = sum(contribution_amount, na.rm = T)
      )

    dollar_function <- label_dollar()
    data <- left_join(
      zips, data,
      by = c("zip5" = "zip5")
    ) |>
      mutate(
        labels = paste0("ZIP: ", zip5, "<br/>", "Total Contributions: ", dollar_function(total_contributions))
      )

  })

  individual_total_data <- reactive({
    contribution_data() |>
      group_by(contribution_name, contribution_type, contribution_geo, zip5) |>
      summarize(
        total_contributions = sum(contribution_amount, na.rm = T),
        average_contribution = mean(contribution_amount, na.rm = T),
        num_contributions = n()
      ) |>
      ungroup()

  })

  # Summary of Date/Committee donations
  output$contribution_summary <- renderUI({
    dollar_function <- label_dollar()
    percent_function <- label_percent(accuracy = 0.01)

    individual <- paste0(
      contribution_type_summary() |> filter(contribution_type == "Individual") |> pull(contribution_pct) |> percent_function(),
      " (",
      contribution_type_summary() |> filter(contribution_type == "Individual") |> pull(total_contributions) |> dollar_function(),
      ")"
    )
    iowa <- paste0(
      contribution_geo_summary() |> filter(contribution_geo == "Iowa") |> pull(contribution_pct) |> percent_function(),
      " (",
      contribution_geo_summary() |> filter(contribution_geo == "Iowa") |> pull(total_contributions) |> dollar_function(),
      ")"
    )

    paste0(
      strong("Total Contribtutions: "), sum(date_committee_filtered_data()$contribution_amount, na.rm = T) |> dollar_function(), "<br/>",
      strong("Individual: "), individual, "<br/>",
      strong("In-State: "), iowa, "<br/>"
    ) |> HTML()
  })

  # Bar graph of top donors by total
  output$total_contribution_donor_bar <- renderPlot({
    individual_total_data() |>
      filter(total_contributions >= 100) |>
      arrange(-total_contributions) |>
      slice(1:10) |>
      ggplot(
        aes(x = fct_reorder(str_wrap(contribution_name, width = 25), total_contributions), y = total_contributions, fill = contribution_type)
      ) +
      geom_col() +
      scale_y_continuous(labels = scales::label_dollar()) +
      labs(title = "Top 10 Donors by Total Donations", x = "Donor", y = "Total Donations", fill = "Contribution Type") +
      coord_flip() +
      theme_minimal() +
      theme(text = element_text(size = 3.5), legend.key.size = unit(0.15, 'cm'))

  }, res = 300)

  # Bar graph of top donors by average
  output$avg_contribution_donor_bar <- renderPlot({
    individual_total_data() |>
      filter(total_contributions >= 100) |>
      arrange(-average_contribution) |>
      slice(1:10) |>
      ggplot(
        aes(x = fct_reorder(str_wrap(contribution_name, width = 25), average_contribution), y = average_contribution, fill = contribution_type)
      ) +
      geom_col() +
      scale_y_continuous(labels = scales::label_dollar()) +
      labs(title = "Top 10 Donors by Average Donation", x = "Donor", y = "Average Donation", fill = "Contribution Type") +
      coord_flip() +
      theme_minimal() +
      theme(text = element_text(size = 3.5), legend.key.size = unit(0.15, 'cm'))

  }, res = 300)


  # Table of donors
  output$donor_table <- renderReactable({
    reactable(
      individual_total_data() |>
        filter(total_contributions >= 100) |>
        arrange(-total_contributions),
      columns = list(
        contribution_name = colDef(name = "Name"),
        contribution_type = colDef(name = "Type"),
        contribution_geo = colDef(name = "Location"),
        zip5 = colDef(name = "ZIP"),
        total_contributions = colDef(name = "Total Contribution Amount", format = colFormat(prefix = "$", separators = TRUE)),
        num_contributions = colDef(name = "Number of Contributions"),
        average_contribution = colDef(name = "Average Contribution", format = colFormat(digits = 2, prefix = "$", separators = TRUE))
      ),
      filterable = TRUE,
      searchable = TRUE
    )
  })


  # Map of zip codes
  output$contribution_zip_map <- renderLeaflet({

    data <- sf_zip_data()

    # Create palette
    pal <- colorNumeric(
      "viridis",
      range(data$total_contributions)
    )

    # Create and output map
    leaflet() |>
      addTiles() |>
      addPolygons(
        data = data, fillColor = pal(data$total_contributions), fillOpacity = 0.9,
        color = "black", weight = 1,
        label = lapply(data$labels, HTML)
      ) |>
      addLegend(
        position = "bottomright", pal = pal, values = data$total_contributions,
        opacity = 0.9, title = "Total Contributions"
      )
  })
  
}
