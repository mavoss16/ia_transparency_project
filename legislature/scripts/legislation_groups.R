

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(readr)



linked_files <- read_rds("data/legislation_2023_clean.rds")


linked_files |>
  arrange(file_group_id) |>
  View()


linked_files <- linked_files |>
  group_by(file_group_id) |>
  mutate(
    file_group_sponsors = paste0(sponsor, collapse = ", "),
    .after = sponsor_count
  )


linked_files |> select(1:10) |> View()


