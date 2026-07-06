# render_all.R — top-level site render orchestrator
#
# Each domain exposes its own render entry point under R/{domain}/render.R;
# this script sources them all and provides render_all() to rebuild the
# full unified site.
#
# Usage:
#   source("R/render_all.R")
#   render_all()              # incremental render of every domain
#   render_all(force = TRUE)  # re-render everything regardless of manifest

source(here::here("R/legislature/render.R"))

# Future domains — source when each render.R exists:
# source(here::here("R/elections/render.R"))
# source(here::here("R/campaign_finance/render.R"))

render_all <- function(force = FALSE) {
  # Legislature: parameterized bill/legislator/committee pages + full quarto render
  render_site(force = force)

  # elections_render_site(force = force)
  # campaign_finance_render_site(force = force)

  invisible(NULL)
}
