

library(Microsoft365R)

od <- get_personal_onedrive()

od$list_items()





# Test Shiny --------------------------------------------------------------


tenant <- "6e5eb335-e1a0-4d3c-a38a-4667e2cf426c"

# the application/client ID of your app registration
# - not to be confused with the 'object ID' or 'service principal ID'
app <- "eb5c658a-70fb-4541-ad4f-04d716c1f8aa"

# the client secret of your app registration
# - NEVER put secrets in code:
# - here we get it from an environment variable
# - unnecessary if you have a 'desktop & mobile' redirect
pwd <- Sys.getenv("SHINY_CLIENT_SECRET", "")
if(pwd == "") pwd <- NULL

# get the Graph permissions listed for the app, plus an ID token
resource <- c("https://graph.microsoft.com/.default", "openid")


user <- "mavoss16_gmail.com#EXT#@mavoss16gmail.onmicrosoft.com"

gr <- create_graph_login(tenant = tenant, app = app, password = pwd, auth_type = "client_credentials")
drv <- gr$get_user(user)$get_drive()



tenant2 <- "6e5eb335-e1a0-4d3c-a38a-4667e2cf426c"

app2 <- "f37e6559-8ac4-4e36-babc-3c28888bef06"

pwd2 <- "8VY8Q~SRvy8bvdkD_Ew-RM6Rm0MUzOe.qrOauagK"

user <- "mavoss16_gmail.com#EXT#@mavoss16gmail.onmicrosoft.com"

gr2 <- create_graph_login(tenant = "common", app = app2, password = pwd2, auth_type = "client_credentials")
drv <- gr2$get_user(user)$get_drive()


drv <- get_personal_onedrive(app = app2, scopes = c("User.Read.All", "Files.Read.All"), username = user, password = pwd2)
