

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(readr)
library(lubridate)
library(janitor)


lobbyists <- read_rds("lobbying/lobbyists_2023.rds")

df_to_char <- function(df){mutate(df, across(everything(), .fns = as.character))}
declarations <- lobbyists$declarations |>
  map(df_to_char)
lobbyist_declarations <- bind_rows(declarations) |>
  clean_names() |>
  filter(
    bill != "*** No declarations in the system ***"
  ) |>
  mutate(
    date_time = date |> mdy_hm(),
    date = date(date_time)
    # date = str_sub(date_time, start = 1, end = 10) |> mdy(),
    # time = str_sub(date_time, start = 12, end = -1)
  )

write_rds(lobbyist_declarations, "lobbying/lobbyist_declarations_2023.rds")
