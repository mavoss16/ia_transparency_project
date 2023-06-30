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


# Define UI for application that draws a histogram
fluidPage(


  # Application title
  titlePanel("Iowa Legislature"),

  mainPanel(
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
            leafletOutput("senate_vote_map"),
            reactableOutput("senate_vote")
          ),
          tabPanel(
            title = "House Vote",
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
        title = "Campaign Contributions"
      )
    )
  )
  
)
