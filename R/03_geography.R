# =============================================================================
# R/03_geography.R
# Spatial joins: (1) Census place boundary to check Yelp's city label,
# (2) three candidate geographic systems compared side by side.
# Inputs : asian_restaurants_la.rds, la_restaurants.rds
# Outputs: study_restaurants.rds, areas_<system>.rds, comparison tables + maps
# Needs internet the first time (tigris + data.nola.gov downloads).
# =============================================================================

source("R/00_setup.R")
sf_use_s2(FALSE)   # everything is projected to UTM metres below

asian_la <- read_rds_clean("asian_restaurants_la")

to_points <- function(df) {
  df |>
    filter(!is.na(longitude), !is.na(latitude)) |>
    st_as_sf(coords = c("longitude", "latitude"), crs = crs_lonlat, remove = FALSE) |>
    st_transform(crs_projected)
}

# ---- 1. Official city boundary (Census TIGER place) -------------------------
la_places <- tigris::places(state = "LA", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(crs_projected) |>
  st_make_valid()
nola_boundary <- la_places |> filter(NAME == "New Orleans") |> select(GEOID, NAME)
save_rds(nola_boundary, "nola_boundary")

asian_pts <- to_points(asian_la) |>
  st_join(la_places |> select(place_geoid = GEOID, place_name = NAME),
          join = st_within, left = TRUE) |>
  mutate(
    place_name = replace_na(place_name, "(outside any Census place)"),
    inside_official_nola = place_name == "New Orleans",
    metres_to_nola_boundary = as.numeric(st_distance(geometry, st_boundary(nola_boundary)))
  )

# Yelp text label versus official polygon
city_vs_place <- asian_pts |>
  st_drop_geometry() |>
  count(yelp_city = city_clean, census_place = place_name, sort = TRUE)
save_table(city_vs_place, "city_vs_place")

label_agreement <- asian_pts |>
  st_drop_geometry() |>
  count(yelp_says_new_orleans, inside_official_nola) |>
  mutate(meaning = case_when(
    yelp_says_new_orleans & inside_official_nola   ~ "Agree: New Orleans",
    yelp_says_new_orleans & !inside_official_nola  ~ "Yelp says New Orleans, point is outside the city",
    !yelp_says_new_orleans & inside_official_nola  ~ "Point is inside the city, Yelp uses another label",
    TRUE ~ "Agree: not New Orleans"
  ))
save_table(label_agreement, "label_agreement")

mismatches <- asian_pts |>
  st_drop_geometry() |>
  filter(yelp_says_new_orleans != inside_official_nola) |>
  select(business_name, address, city_clean, postal_code, place_name,
         metres_to_nola_boundary, review_count) |>
  arrange(metres_to_nola_boundary)
save_table(mismatches, "label_mismatches")

# STUDY DEFINITION: a "New Orleans" restaurant is one whose coordinates fall
# inside the official City of New Orleans (= Orleans Parish) boundary.
# This matches the area covered by every geographic system below.
study_pts <- asian_pts |> filter(inside_official_nola)

# ---- 2. Candidate geographic systems ----------------------------------------
# All systems are clipped to the city boundary so they cover the same land.
prep_areas <- function(x, id_col, name_col, system) {
  x <- x |>
    st_transform(crs_projected) |>
    st_make_valid() |>
    transmute(area_id   = as.character(.data[[id_col]]),
              area_name = as.character(.data[[name_col]]))
  x <- suppressWarnings(st_intersection(x, st_geometry(nola_boundary)))
  x <- x[as.numeric(st_area(x)) > 2e5, ]          # drop slivers < 0.2 km²
  x |>
    group_by(area_id, area_name) |>
    summarise(.groups = "drop") |>
    mutate(system = system,
           area_km2 = round(as.numeric(st_area(geometry)) / 1e6, 2))
}

# (a) Neighborhood Statistical Areas (City of New Orleans / GNOCDC)
nsa_file <- file.path(boundary_dir, "neighborhood_statistical_areas.geojson")
if (!file.exists(nsa_file)) {
  urls <- c(
    "https://data.nola.gov/api/geospatial/exvn-jeh2?method=export&format=GeoJSON",
    "https://data.nola.gov/api/v3/views/exvn-jeh2/query.geojson?accessType=DOWNLOAD"
  )
  for (u in urls) {
    ok <- tryCatch({ download.file(u, nsa_file, mode = "wb", quiet = TRUE); TRUE },
                   error = function(e) FALSE)
    if (ok && file.size(nsa_file) > 1000) break
  }
}
if (!file.exists(nsa_file) || file.size(nsa_file) < 1000) {
  stop("Download the Neighborhood Statistical Area layer manually from ",
       "https://data.nola.gov/d/exvn-jeh2 (Export -> GeoJSON) and save it as ", nsa_file)
}
nsa_raw <- st_read(nsa_file, quiet = TRUE)
nsa_name_col <- names(nsa_raw)[match(c("gnocdc_lab", "lup_lab", "nbhd_name", "name"),
                                     str_to_lower(names(nsa_raw)))]
nsa_name_col <- nsa_name_col[!is.na(nsa_name_col)][1]
stopifnot("Could not find the neighborhood name column; check names(nsa_raw)" = !is.na(nsa_name_col))
nsa_raw$nsa_label <- str_to_title(nsa_raw[[nsa_name_col]])
areas_nsa <- prep_areas(nsa_raw, "nsa_label", "nsa_label", "Neighborhood Statistical Area")

# (b) ZIP Code Tabulation Areas (Census, 2020)
zcta_raw <- tigris::zctas(year = 2020, cb = TRUE, starts_with = c("700", "701"), class = "sf")
zcta_id <- intersect(c("ZCTA5CE20", "GEOID20", "ZCTA5CE10"), names(zcta_raw))[1]
areas_zcta <- prep_areas(zcta_raw, zcta_id, zcta_id, "ZIP/ZCTA") |>
  mutate(area_name = paste("ZIP", area_name))

# (c) Census tracts (Orleans Parish, 2024)
tract_raw <- tigris::tracts(state = "LA", county = "Orleans", year = 2024, cb = TRUE, class = "sf")
areas_tract <- prep_areas(tract_raw, "GEOID", "NAME", "Census tract") |>
  mutate(area_name = paste("Tract", area_name))

area_systems <- list(nsa = areas_nsa, zcta = areas_zcta, tract = areas_tract)
iwalk(area_systems, \(a, nm) save_rds(a, paste0("areas_", nm)))

# ---- 3. Spatial join for each system ----------------------------------------
# st_within first; points that fall in a gap (exactly on a line, or in a
# clipped sliver) get the nearest area if it is within 100 m, and are flagged.
assign_area <- function(points, areas) {
  joined <- st_join(points, areas |> select(area_id, area_name), join = st_within, left = TRUE) |>
    distinct(business_id, .keep_all = TRUE)
  gap <- is.na(joined$area_id)
  if (any(gap)) {
    nearest <- st_nearest_feature(joined[gap, ], areas)
    dist <- as.numeric(st_distance(joined[gap, ], areas[nearest, ], by_element = TRUE))
    fix <- dist <= 100
    joined$area_id[which(gap)[fix]]   <- areas$area_id[nearest[fix]]
    joined$area_name[which(gap)[fix]] <- areas$area_name[nearest[fix]]
  }
  joined$matched_by <- case_when(!gap ~ "within", !is.na(joined$area_id) ~ "nearest <= 100 m",
                                 TRUE ~ "unmatched")
  joined
}

assigned <- map(area_systems, \(a) assign_area(study_pts, a))

compare_system <- function(pts, areas) {
  per_area <- areas |>
    st_drop_geometry() |>
    left_join(pts |> st_drop_geometry() |> filter(!is.na(area_id)) |>
                group_by(area_id) |>
                summarise(restaurants = n(), mean_stars = mean(stars), .groups = "drop"),
              by = "area_id") |>
    mutate(restaurants = replace_na(restaurants, 0L))
  occupied <- per_area |> filter(restaurants > 0)
  rankable <- occupied |> filter(restaurants >= min_restaurants_area)
  tibble(
    geographic_system      = areas$system[1],
    number_of_areas        = nrow(areas),
    areas_with_restaurants = nrow(occupied),
    restaurants_assigned   = sum(!is.na(pts$area_id)),
    assigned_by_nearest    = sum(pts$matched_by == "nearest <= 100 m"),
    unmatched_restaurants  = sum(is.na(pts$area_id)),
    smallest_area_count    = min(occupied$restaurants),
    median_area_count      = median(occupied$restaurants),
    largest_area_count     = max(occupied$restaurants),
    areas_rankable         = nrow(rankable),
    median_area_km2        = median(areas$area_km2),
    spread_of_area_mean_stars = round(sd(rankable$mean_stars), 2)
  )
}

geo_comparison <- map2(assigned, area_systems, compare_system) |> list_rbind()
save_table(geo_comparison, "geography_comparison")
geo_comparison

# Requirement check: >= 10 restaurants in >= 7 areas
requirement_check <- geo_comparison |>
  transmute(geographic_system, restaurants_assigned, areas_with_restaurants,
            meets_requirement = restaurants_assigned >= 10 & areas_with_restaurants >= 7)
save_table(requirement_check, "requirement_check")

# Keep each system's assignment as a column on one study table
study_restaurants <- study_pts |>
  left_join(assigned$nsa   |> st_drop_geometry() |> select(business_id, nsa_id = area_id, nsa_name = area_name),
            by = "business_id") |>
  left_join(assigned$zcta  |> st_drop_geometry() |> select(business_id, zcta_id = area_id, zcta_name = area_name),
            by = "business_id") |>
  left_join(assigned$tract |> st_drop_geometry() |> select(business_id, tract_id = area_id, tract_name = area_name),
            by = "business_id")
save_rds(study_restaurants, "study_restaurants")

# ---- 4. Base layers for artistic maps: the river and major roads -----------
# The Mississippi's crescent is what gives the "Crescent City" its name, so it
# anchors every map. Roads are drawn as faint ink strokes for orientation.
map_frame <- st_buffer(nola_boundary, 6000)
nola_water <- tryCatch({
  w <- tigris::area_water(state = "LA",
                          county = c("Orleans", "Jefferson", "St. Bernard", "St. Tammany", "Plaquemines"),
                          year = 2024, class = "sf") |>
    st_transform(crs_projected) |> st_make_valid()
  w <- suppressWarnings(st_intersection(w, st_geometry(map_frame)))
  w[as.numeric(st_area(w)) > 3e5, ]
}, error = function(e) { message("Water layer skipped: ", conditionMessage(e)); NULL })
# Every street (TIGER/Line "All Roads") in Orleans and its neighboring
# parishes, so the street grid continues past the city line like a real map.
# MTFCC codes: S1100 = interstate, S1200 = major road, S1400 = local street.
street_frame <- st_buffer(nola_boundary, 4000)
nola_roads <- tryCatch({
  map(c("Orleans", "Jefferson", "St. Bernard", "Plaquemines"),
      \(cty) tigris::roads(state = "LA", county = cty, year = 2024, class = "sf")) |>
    list_rbind() |> st_as_sf() |>
    st_transform(crs_projected) |>
    select(FULLNAME, MTFCC) |>
    st_filter(street_frame) |>
    mutate(road_class = case_when(MTFCC == "S1100" ~ "interstate",
                                  MTFCC %in% c("S1200", "S1630") ~ "major",
                                  TRUE ~ "local"))
}, error = function(e) {
  message("Full street layer failed (", conditionMessage(e), "); using major roads only")
  tryCatch(tigris::primary_secondary_roads(state = "LA", year = 2024, class = "sf") |>
             st_transform(crs_projected) |> st_filter(street_frame) |>
             mutate(road_class = if_else(MTFCC == "S1100", "interstate", "major")),
           error = function(e) NULL)
})
save_rds(nola_water, "nola_water")
save_rds(nola_roads, "nola_roads")

# ---- 5. One map per system --------------------------------------------------
map_system <- function(pts, areas) {
  counts <- areas |>
    left_join(pts |> st_drop_geometry() |> count(area_id, name = "restaurants"), by = "area_id") |>
    mutate(restaurants = replace_na(restaurants, 0L))
  ggplot() +
    ink_base(nola_boundary, nola_water, nola_roads,
             geom_sf(data = counts, aes(fill = restaurants), colour = paper, linewidth = 0.35)) +
    geom_sf(data = pts, aes(colour = cuisine_group, shape = cuisine_group), size = 1.7, alpha = 0.9) +
    scale_fill_stepsn(colours = ink_wash[1:5], name = "Restaurants\nper area", n.breaks = 5) +
    scale_colour_manual(values = cuisine_colors, name = "Cuisine") +
    scale_shape_manual(values = cuisine_shapes_solid, name = "Cuisine") +
    labs(title = areas$system[1],
         subtitle = paste0(nrow(areas), " areas, ", sum(counts$restaurants == 0),
                           " with no Vietnamese, Chinese or Japanese restaurant"),
         caption = data_caption) +
    theme_ink_map(11)
}
iwalk(names(area_systems), \(nm, i) save_fig(map_system(assigned[[nm]], area_systems[[nm]]),
                                             paste0("map_counts_", nm), width = 8, height = 7,
                                             basemap = FALSE))

# Label check map: where does Yelp's "New Orleans" disagree with the boundary?
label_pts <- asian_pts |>
  filter(yelp_says_new_orleans | inside_official_nola) |>
  mutate(where = if_else(inside_official_nola, "Inside the city boundary", "Outside the city boundary"))
p_labels <- ggplot() +
  ink_base(nola_boundary, nola_water, nola_roads) +
  geom_sf(data = label_pts, aes(colour = where, shape = where), size = 1.8, alpha = 0.85) +
  scale_colour_manual(values = c("Inside the city boundary" = cuisine_colors[["Vietnamese"]],
                                 "Outside the city boundary" = seal_red), name = NULL) +
  scale_shape_manual(values = c("Inside the city boundary" = 16,
                                "Outside the city boundary" = 4), name = NULL) +
  labs(title = "Where Yelp's “New Orleans” really is",
       subtitle = "Restaurants labeled New Orleans by Yelp, checked against the official city line",
       caption = data_caption) +
  theme_ink_map(11) + theme(legend.position = "bottom")
save_fig(p_labels, "map_label_check", width = 8, height = 7, basemap = FALSE)
