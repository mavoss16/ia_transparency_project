# maps.R
#
# Leaflet district maps that share one geometry file per (plan, chamber).
#
# Every map used to embed its chamber's full polygons (Senate ~264 KB, House
# ~353 KB), and bill pages carry one map per roll call, so district geometry
# was 440 MB of the 756 MB of bill pages (profiled 2026-10-25). Now:
#
#   - write_district_scripts() turns a plan's simplified geometry into
#     data/legislature/districts/web/{plan}_{chamber}.js, which registers
#     GeoJSON on window.IA_DISTRICTS. These files are committed: CI renders
#     from them and they only change with the district lines.
#   - district_map() builds a Leaflet map with no polygons of its own. It
#     attaches the chamber's script as an htmlDependency, so Quarto copies it
#     once into site_libs/ and every page links there, and it embeds only
#     per-district styles and labels. An onRender hook draws the shared
#     GeoJSON with them.
#
# A <script> dependency rather than fetching a .geojson file: it loads before
# the widget initializes, Quarto resolves its relative path at any page
# depth, and it works from file:// too.
#
# If the geometry changes, re-run write_district_scripts() AND bump
# DISTRICT_SCRIPT_VERSION: the version is part of the site_libs directory
# name, so browsers holding the old file in cache fetch the new one.

library(sf)
library(dplyr)
library(leaflet)
library(htmltools)
library(htmlwidgets)

source(here::here("R/legislature/session.R"))

DISTRICT_SCRIPT_DIR <- here::here("data/legislature/districts/web")
DISTRICT_SCRIPT_VERSION <- "1.0.0"

#' Write one JS file per chamber registering a plan's GeoJSON
#' @param plan District plan name (see DISTRICT_PLANS in session.R)
#' @param precision Decimal places kept in coordinates (5 = ~1 m)
write_district_scripts <- function(plan = ga_district_plan(), out_dir = DISTRICT_SCRIPT_DIR,
                                   precision = 5) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (chamber in c("senate", "house")) {
    tmp <- tempfile(fileext = ".geojson")
    st_write(district_geometry(chamber, plan), tmp, driver = "GeoJSON", quiet = TRUE,
             layer_options = c(paste0("COORDINATE_PRECISION=", precision), "RFC7946=YES"))
    geojson <- paste(readLines(tmp, warn = FALSE), collapse = "")
    key <- district_key(chamber, plan)
    js <- sprintf("window.IA_DISTRICTS = window.IA_DISTRICTS || {};\nwindow.IA_DISTRICTS[%s] = %s;\n",
                  jsonlite::toJSON(key, auto_unbox = TRUE), geojson)
    path <- file.path(out_dir, paste0(key, ".js"))
    writeLines(js, path, useBytes = TRUE)
    message(sprintf("Wrote %s (%.0f KB)", path, file.size(path) / 1e3))
  }
}

#' "senate" / "house" from any of the codes the data uses (S, Sen, H, Rep, ...)
chamber_name <- function(chamber) {
  if (tolower(chamber) %in% c("s", "sen", "senate")) "senate" else "house"
}

district_key <- function(chamber, plan) paste0(plan, "_", chamber)

#' htmlDependency carrying one chamber's geometry
district_dependency <- function(chamber, plan) {
  key <- district_key(chamber, plan)
  path <- file.path(DISTRICT_SCRIPT_DIR, paste0(key, ".js"))
  if (!file.exists(path)) stop("Missing ", path, "; run write_district_scripts(\"", plan, "\").")
  htmlDependency(
    name = paste0("ia-districts-", plan, "-", chamber),
    version = DISTRICT_SCRIPT_VERSION,
    src = c(file = DISTRICT_SCRIPT_DIR),
    script = basename(path)
  )
}

# Draws the shared geometry. `data.districts` holds parallel columns keyed by
# District: fill, fill_opacity, stroke, weight, label (text), popup (HTML),
# front (draw above its neighbours). Districts missing from it get the
# default style and a "District N" label.
DRAW_DISTRICTS_JS <- "
function(el, x, data) {
  var map = this;
  var arr = function(v) { return [].concat(v); };
  var key = arr(data.key)[0];
  var geo = window.IA_DISTRICTS && window.IA_DISTRICTS[key];
  if (!geo) {
    console.error('IA district map: geometry not loaded for ' + key);
    return;
  }
  var d = data.districts;
  var row = {};
  arr(d.District).forEach(function(v, i) { row[v] = i; });
  var val = function(name, i, fallback) {
    if (i === undefined || d[name] === undefined || d[name] === null) return fallback;
    var v = arr(d[name])[i];
    return v === null || v === undefined ? fallback : v;
  };
  var front = [];
  L.geoJSON(geo, {
    style: function(f) {
      var i = row[f.properties.District];
      return {
        fillColor: val('fill', i, '#CCCCCC'), fillOpacity: val('fill_opacity', i, 0.7),
        color: val('stroke', i, '#333333'), weight: val('weight', i, 1)
      };
    },
    onEachFeature: function(f, layer) {
      var i = row[f.properties.District];
      layer.bindTooltip(val('label', i, 'District ' + f.properties.District));
      var popup = val('popup', i, null);
      if (popup) layer.bindPopup(popup);
      if (val('front', i, false)) front.push(layer);
      if (data.hover) {
        var base;
        layer.on('mouseover', function() {
          base = { weight: layer.options.weight, fillOpacity: layer.options.fillOpacity };
          layer.setStyle({ weight: data.hover.weight, fillOpacity: data.hover.fillOpacity });
          layer.bringToFront();
        });
        layer.on('mouseout', function() { if (base) layer.setStyle(base); });
      }
    }
  }).addTo(map);
  front.forEach(function(layer) { layer.bringToFront(); });
}
"

#' Leaflet map of a chamber's districts, drawn from the shared geometry
#'
#' @param districts Data frame keyed by `District` with any of: fill,
#'   fill_opacity, stroke, weight, label (plain text; escaped here), popup
#'   (HTML), front (logical). Missing districts get the default style.
#' @param chamber Any chamber code ("S", "Sen", "senate", "H", "Rep", ...)
#' @param ga General Assembly, which picks the district plan
#' @param bounds Named bbox (xmin, ymin, xmax, ymax) for the initial view;
#'   defaults to the whole chamber. Set from R rather than fitted in JS, so
#'   Leaflet re-applies it when a map rendered in a hidden tab is shown.
#' @param hover NULL, or list(weight, fillOpacity) to restyle on mouseover
#' @param height Widget height (NULL = Leaflet's default)
#' @return A leaflet htmlwidget; add tiles, legends etc. as usual
district_map <- function(districts, chamber, ga = CURRENT_GA, bounds = NULL,
                         hover = NULL, height = NULL) {
  chamber <- chamber_name(chamber)
  plan <- ga_district_plan(ga)
  if (is.null(bounds)) bounds <- st_bbox(district_geometry(chamber, plan))
  if ("label" %in% names(districts)) {
    districts$label <- htmlEscape(districts$label)
  }

  w <- leaflet(height = height) |>
    fitBounds(bounds[["xmin"]], bounds[["ymin"]], bounds[["xmax"]], bounds[["ymax"]]) |>
    onRender(DRAW_DISTRICTS_JS, data = list(
      key = district_key(chamber, plan),
      districts = districts,
      hover = hover
    ))
  w$dependencies <- c(w$dependencies, list(district_dependency(chamber, plan)))
  w
}

VOTE_MAP_COLORS <- c(
  "Democrat: Yea"   = "#3F5B93",
  "Democrat: Nay"   = "#B2BDD4",
  "Republican: Yea" = "#A8433A",
  "Republican: Nay" = "#DCB4B0",
  "Absent/NV"       = "#CCCCCC"
)

#' Roll call vote map for a bill page
#' @param vote One roll call's votes joined to people (name, party, district,
#'   vote_text)
#' @param chamber Roll call chamber code ("H" / "S")
#' @param ga General Assembly
vote_map <- function(vote, chamber, ga = CURRENT_GA) {
  # Start from every district so seats with no recorded vote still get a label
  all_districts <- district_geometry(chamber_name(chamber), ga_district_plan(ga)) |>
    st_drop_geometry() |>
    select(District)

  districts <- vote |>
    mutate(District = parse_district_number(district)) |>
    select(District, name, party, vote_text) |>
    right_join(all_districts, by = "District") |>
    mutate(
      category = case_when(
        party == "D" & vote_text == "Yea" ~ "Democrat: Yea",
        party == "D" & vote_text == "Nay" ~ "Democrat: Nay",
        party == "R" & vote_text == "Yea" ~ "Republican: Yea",
        party == "R" & vote_text == "Nay" ~ "Republican: Nay",
        .default = "Absent/NV"
      ),
      fill = unname(VOTE_MAP_COLORS[category]),
      label = paste0(coalesce(name, paste("District", District)),
                     " (", coalesce(party, "?"), "-", District, "): ",
                     coalesce(vote_text, "No vote"))
    ) |>
    select(District, fill, label)

  district_map(districts, chamber, ga) |>
    addTiles() |>
    addLegend(
      position = "bottomright",
      colors = unname(VOTE_MAP_COLORS),
      labels = names(VOTE_MAP_COLORS),
      title = "Vote",
      opacity = 0.9
    )
}
