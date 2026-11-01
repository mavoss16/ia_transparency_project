# One-off: full lobbying re-scrape to fill lobbyist_filings.rds (2026-10-31)
source(here::here("R/legislature/04_lobbyist_declarations.R"))
update_lobbyist_declarations()
lobbyist_summary()
