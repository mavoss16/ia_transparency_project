library(AzureAuth)
library(AzureGraph)
library(Microsoft365R)
library(shiny)

tenant <- "6e5eb335-e1a0-4d3c-a38a-4667e2cf426c"

# the application/client ID of your app registration
# - not to be confused with the 'object ID' or 'service principal ID'
app <- "eb5c658a-70fb-4541-ad4f-04d716c1f8aa"

# the address/redirect URI of your app
# - AAD allows only HTTPS for non-localhost redirects, not HTTP
redirect <- "https://mavoss.shinyapps.io/test_data_app"
port <- httr::parse_url(redirect)$port
options(shiny.port=if(is.null(port)) 443 else as.numeric(port))

# the client secret of your app registration
# - NEVER put secrets in code:
# - here we get it from an environment variable
# - unnecessary if you have a 'desktop & mobile' redirect
pwd <- Sys.getenv("SHINY_CLIENT_SECRET", "")
if(pwd == "") pwd <- NULL

# get the Graph permissions listed for the app, plus an ID token
resource <- c("https://graph.microsoft.com/.default", "openid")


user <- "mavoss16_gmail.com#EXT#@mavoss16gmail.onmicrosoft.com"

# a simple UI: display the user's OneDrive
ui <- fluidPage(
  verbatimTextOutput("drv")
)

ui_func <- function(req)
{
  opts <- parseQueryString(req$QUERY_STRING)
  if(is.null(opts$code))
  {
    auth_uri <- build_authorization_uri(resource, tenant, app,
                                        redirect_uri=redirect, version=2)
    redir_js <- sprintf("location.replace(\"%s\");", auth_uri)
    tags$script(HTML(redir_js))
  }
  else ui
}

server <- function(input, output, session)
{
  opts <- parseQueryString(isolate(session$clientData$url_search))
  if(is.null(opts$code))
    return()
  
  token <- get_azure_token(resource, tenant, app, password=pwd,
                           auth_type="authorization_code",
                           authorize_args=list(redirect_uri=redirect), version=2,
                           use_cache=FALSE, auth_code=opts$code)
  
  # display the contents of the user's OneDrive root folder
  drv <- ms_graph$
    new(token=token)$
    get_user()$
    get_drive()
  output$drv <- renderPrint(drv$list_files())
}

shinyApp(ui_func, server)