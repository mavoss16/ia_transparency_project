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
library(bslib)
# library(forcats)


# Define UI for application that draws a histogram
ui <- function(request){
  
  
  tags$head(includeHTML("google-analytics.html"))
# bslib Implementation ----------------------------------------------------
  
  page_navbar(
    title = "Iowa Legislature",
    tags$head(includeHTML("google-analytics.html")),
    bg = "#C6C6C6",
    # nav_panel(
    #   title = "Summary",
    #   # Table of Legislation with short summary information; Make filterable on outcome
    #   # Legislator table: color party column, representative info
    # ),
    nav_panel(
      title = "Legislation",
      navset_underline(
        nav_panel(
          title = "Summary",
          reactableOutput("legislation_summary_table")
        ),
        nav_panel(
          title = "Explore Legislation",
          layout_sidebar(
            sidebar = sidebar(
              bg = "#C6C6C6",
              selectizeInput(
                "category_input", label = "Choose a Legislation Type:",
                choices = c("All Legislation", "Signed by Governor", "Passed Both Chambers", "Passed One Chamber", "Passed Committee", "Introduced"),
                selected = "All Legislation"
              ),
              selectizeInput("legislation_input", label = "Choose a File: ", choices = NULL)
            ),
            # h2("Summary"),
            # htmlOutput("leg_summary_text"),
            htmlOutput("legislation_header_text"),
            layout_column_wrap(
              width = 1/4,
              fill = FALSE,
              value_box(
                "House Vote",
                value = htmlOutput("house_vote_text")
              ),
              value_box(
                "Senate Vote",
                value = htmlOutput("senate_vote_text")
              ),
              value_box(
                "Related File Outcome",
                value = htmlOutput("related_leg_outcome_text")
              ),
              value_box(
                "Lobbying",
                value = htmlOutput("lobbying_text")
              )
            ),
            tabsetPanel(
              tabPanel(
                title = "Actions",
                reactableOutput("actions")
              ),
              tabPanel(
                title = "Senate Vote",
                selectizeInput("senate_vote_date_input", label = "Choose a Vote Date: ", choices = NULL),
                tabsetPanel(
                  tabPanel(
                    title = "Vote Table",
                    reactableOutput("senate_vote")
                  ),
                  tabPanel(
                    title = "Vote Map",
                    leafletOutput("senate_vote_map")
                  )#,
                  # tabPanel(
                  #   title = "Vote Plot",
                  #   plotOutput("senate_vote_seats")
                  # )
                )
              ),
              tabPanel(
                title = "House Vote",
                selectizeInput("house_vote_date_input", label = "Choose a Vote Date: ", choices = NULL),
                tabsetPanel(
                  tabPanel(
                    title = "Vote Table",
                    reactableOutput("house_vote")
                  ),
                  tabPanel(
                    title = "Vote Map",
                    leafletOutput("house_vote_map")
                  )#,
                  # tabPanel(
                  #   title = "Vote Plot",
                  #   plotOutput("house_vote_seats")
                  # )
                )
              ),
              tabPanel(
                title = "Lobbyist Declarations",
                reactableOutput("declarations")
              )
            )
          )
        )
      )
    ),
    nav_panel(
      title = "Legislators",
      navset_underline(
        nav_panel(
          title = "Summary",
          reactableOutput("legislator_summary_table")
        ),
        nav_panel(
          title = "Look at a Legislator",
          layout_sidebar(
            sidebar = sidebar(
              bg = "#C6C6C6",
              selectizeInput("chamber_input", label = "Chooose a Chamber:", choices = c("House", "Senate"), selected = "House"),
              selectizeInput("legislator_input", label = "Choose a Legislator:", choices = NULL)
            ),
            # htmlOutput("legislator_summary_text"),
            htmlOutput("legislator_header_text"),
            tabsetPanel(
              tabPanel(
                title = "Summary",
                layout_column_wrap(
                  width = 1,
                  value_box(
                    "Votes",
                    value = htmlOutput("legislator_vote_summary_text")
                  ),
                  value_box(
                    "Sponsored Files",
                    value = htmlOutput("legislator_sponsor_summary_text")
                  ),
                  value_box(
                    "Floor-Managed Files",
                    value = htmlOutput("legislator_floor_manager_summary_text")
                  )
                ),
              ),
              tabPanel(
                title = "Vote Record",
                layout_column_wrap(
                  width = 1/3,
                  value_box("Yes Votes", htmlOutput("legislator_vote_record_yes_text")),
                  value_box("No Votes", htmlOutput("legislator_vote_record_no_text")),
                  value_box("Percent of Votes with Party", htmlOutput("legislator_vote_record_with_party_text"))
                ),
                reactableOutput("legislator_vote_record_table")
              ),
              tabPanel(
                title = "Sponsored Files",
                layout_column_wrap(
                  width = 1/4,
                  value_box("# of Sponsored Files", htmlOutput("legislator_sponsor_num_text"), htmlOutput("legislator_sponsor_num_caption")),
                  value_box("# of Solo-Sponsored Files", htmlOutput("legislator_sponsor_sole_num_text"), htmlOutput("legislator_sponsor_sole_num_caption")),
                  value_box("# of Sponsored Files Advanced Through Committee", htmlOutput("legislator_sponsor_advance_num_text"), htmlOutput("legislator_sponsor_advance_num_caption")),
                  value_box("# of Sponsored-Related Files Signed", htmlOutput("legislator_sponsor_group_sign_num_text"), htmlOutput("legislator_sponsor_group_sign_num_caption")),
                ),
                reactableOutput("legislator_sponsor_table")
              ),
              tabPanel(
                title = "Floor-Managed Files",
                width = 1/2,
                value_box("# of Floor-Managed Files", htmlOutput("legislator_floor_manager_num_text"), htmlOutput("legislator_floor_manager_num_caption")),
                value_box("# of Floor-Managed Files Signed", htmlOutput("legislator_floor_manager_signed_num_text"), htmlOutput("legislator_floor_manager_signed_num_caption")),
                reactableOutput("legislator_floor_manager_table")
              )
            )
          )
        )
      )
    ),
    nav_panel(
      title = "About",
      htmlOutput("intro_text")
    )
  )
  
  
}









# Straight Shiny Implementation -------------------------------------------

# fluidPage(
# 
# 
#   # Application title
#   titlePanel("Iowa Legislature"),
# 
#   mainPanel(
#     htmlOutput("intro_text"),
#     tabsetPanel(
#       tabPanel(
#         title = "Legislation",
#         selectizeInput(
#           "category_input", label = "",
#           choices = c("All Legislation", "Signed by Governor", "Passed Both Chambers", "Passed One Chamber", "Passed Committee", "Introduced"),
#           selected = "All Legislation"
#         ),
#         selectizeInput("legislation_input", label = "Choose a File: ", choices = NULL),
#         h2("Summary"),
#         htmlOutput("leg_summary_text"),
#         # textOutput("text")
#         tabsetPanel(
#           tabPanel(
#             title = "Actions",
#             reactableOutput("actions")
#           ),
#           tabPanel(
#             title = "Senate Vote",
#             plotOutput("senate_vote_seats"),
#             leafletOutput("senate_vote_map"),
#             reactableOutput("senate_vote")
#           ),
#           tabPanel(
#             title = "House Vote",
#             plotOutput("house_vote_seats"),
#             leafletOutput("house_vote_map"),
#             reactableOutput("house_vote")
#           ),
#           tabPanel(
#             title = "Lobbyist Declarations",
#             reactableOutput("declarations")
#           )
#         )
#       ),
#       tabPanel(
#         title = "Legislators",
#         selectizeInput("chamber_input", label = "Chooose a Chamber:", choices = c("House", "Senate"), selected = "House"),
#         selectizeInput("legislator_input", label = "Choose a Legislator:", choices = NULL),
#         htmlOutput("legislator_summary_text"),
#         tabsetPanel(
#           tabPanel(
#             title = "Sponsored Files",
#             reactableOutput("legislator_sponsor_table")
#           ),
#           tabPanel(
#             title = "Floor-Managed Files",
#             reactableOutput("legislator_floor_manager_table")
#           )
#         )
#       ),
#       tabPanel(
#         title = "Campaign Contributions",
#         dateRangeInput(
#           "contribution_date_input", label = "Choose a Date Range:",
#           start = "2020-01-01", end = "2023-07-01",
#           min = "2016-01-01", max = "2023-07-01"
#         ),
#         selectizeInput("committee_type_input", label = "Choose a Committee Type:", choices = c("All", "Party", "State Candidate", "Legislative Candidate", "PAC", "Local", "Unknown"), selected = "All"),
#         selectizeInput("committee_input", label = "Choose a Committee:", choices = NULL),
#         selectizeInput("contribution_type_input", label = "Choose a Contribution Type:", choices = c("All", "Individual", "Organization"), selected = "All"),
#         selectizeInput("contribution_geo_input", label = "Choose a Geography:", choices = c("Iowa", "Outside Iowa"), selected = "Iowa"),
#         # htmlOutput("test_text"),
#         # reactableOutput("contribution_test")
#         htmlOutput("contribution_summary"),
#         tabsetPanel(
#           tabPanel(
#             title = "Top Donors",
#             plotOutput("total_contribution_donor_bar"),
#             plotOutput("avg_contribution_donor_bar"),
#             reactableOutput("donor_table")
#           ),
#           tabPanel(
#             title = "Contribution Maps",
#             leafletOutput("contribution_zip_map")
#           )
#         )
#       )
#     )
#   )
# 
# )