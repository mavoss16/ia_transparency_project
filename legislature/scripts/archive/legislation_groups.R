

library(dplyr)
library(stringr)
library(tidyr)
library(purrr)
library(readr)
library(forcats)



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


linked_files <- linked_files |>
  mutate(
    categorization_fct = factor(categorization, c("Introduced", "Passed Committee", "Passed One Chamber", "Passed Both Chambers", "Signed by Governor"), ordered = TRUE),
    .after = categorization
  ) |>
  group_by(file_group_id) |>
  mutate(
    group_categorization = max(categorization_fct),
    group_final_file = file[which.max(categorization_fct)],
    .after = file_group_id
  ) |>
  ungroup()
