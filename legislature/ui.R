#
# This is the user-interface definition of a Shiny web application. You can
# run the application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
library(htmltools)
library(reactable)
library(leaflet)
library(ggplot2)
# library(forcats)


# Define UI for application that draws a histogram
ui <- function(request){
  
  fluidPage(
    
    
    # Application title
    titlePanel("Iowa Legislature"),
    
    mainPanel(
      htmlOutput("intro_text"),
      tabsetPanel(
        tabPanel(
          title = "Legislation",
          selectizeInput(
            "category_input", label = "", 
            choices = c("All Legislation", "Signed by Governor", "Passed Both Chambers", "Passed One Chamber", "Passed Committee", "Introduced"),
            selected = "All Legislation"
          ),
          selectizeInput("legislation_input", label = "Choose a File: ", choices = NULL),
          h2("Summary"),
          htmlOutput("leg_summary_text"),
          # textOutput("text")
          tabsetPanel(
            tabPanel(
              title = "Actions",
              reactableOutput("actions")
            ),
            tabPanel(
              title = "Senate Vote",
              plotOutput("senate_vote_seats"),
              leafletOutput("senate_vote_map"),
              reactableOutput("senate_vote")
            ),
            tabPanel(
              title = "House Vote",
              plotOutput("house_vote_seats"),
              leafletOutput("house_vote_map"),
              reactableOutput("house_vote")
            ),
            tabPanel(
              title = "Lobbyist Declarations",
              reactableOutput("declarations")
            )
          )
        ),
        tabPanel(
          title = "Legislators",
          selectizeInput("chamber_input", label = "Chooose a Chamber:", choices = c("House", "Senate"), selected = "House"),
          selectizeInput("legislator_input", label = "Choose a Legislator:", choices = NULL),
          htmlOutput("legislator_summary_text"),
          tabsetPanel(
            tabPanel(
              title = "Sponsored Files",
              reactableOutput("legislator_sponsor_table")
            ),
            tabPanel(
              title = "Floor-Managed Files",
              reactableOutput("legislator_floor_manager_table")
            )
          )
        ),
        tabPanel(
          title = "Campaign Contributions",
          dateRangeInput(
            "contribution_date_input", label = "Choose a Date Range:",
            start = "2020-01-01", end = "2023-07-01",
            min = "2016-01-01", max = "2023-07-01"
          ),
          selectizeInput("committee_type_input", label = "Choose a Committee Type:", choices = c("All", "Party", "State Candidate", "Legislative Candidate", "PAC", "Local", "Unknown"), selected = "All"),
          selectizeInput("committee_input", label = "Choose a Committee:", choices = NULL),
          selectizeInput("contribution_type_input", label = "Choose a Contribution Type:", choices = c("All", "Individual", "Organization"), selected = "All"),
          selectizeInput("contribution_geo_input", label = "Choose a Geography:", choices = c("Iowa", "Outside Iowa"), selected = "Iowa"),
          # htmlOutput("test_text"),
          # reactableOutput("contribution_test")
          htmlOutput("contribution_summary"),
          tabsetPanel(
            tabPanel(
              title = "Top Donors",
              plotOutput("total_contribution_donor_bar"),
              plotOutput("avg_contribution_donor_bar"),
              reactableOutput("donor_table")
            ),
            tabPanel(
              title = "Contribution Maps",
              leafletOutput("contribution_zip_map")
            )
          )
        )
      )
    )
    
  )
  
  
}

