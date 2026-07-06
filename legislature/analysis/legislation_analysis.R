
library(readr)
library(dplyr)


bills = read_rds("data/ga89_legislation.rds")

unique(bills$status)

signed = bills %>%
  filter(
    status == "Signed by Governor"
  )

bills %>%
  filter(
    senate_no == 0 & house_no == 0
  ) %>%
  nrow()

bills %>%
  filter(
    senate_yes >= 45 & house_yes >= 90
  ) %>%
  nrow()

bills %>%
  filter(
    senate_no >= 10 & house_no >= 20
  ) %>%
  nrow()
