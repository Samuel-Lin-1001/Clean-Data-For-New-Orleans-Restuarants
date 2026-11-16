# =============================================================================
# R/05_animations.R  —  animated GIFs (optional; run after R/04_analysis.R)
#
#   figures/anim_city_fills_in.gif   restaurants appear in the year of their
#                                    first Yelp review, on the ink street map
#   figures/anim_reviews_growth.gif  total reviews per cuisine, drawn over time
#
# Each frame is drawn as an ordinary ggplot and the frames are stitched into a
# GIF by frames_to_gif() in R/00_theme.R, so frame order is exact.
# Needs: install.packages("gifski")   (falls back to magick if missing)
# =============================================================================

source("R/00_setup.R")
sf_use_s2(FALSE)

study    <- read_rds_clean("study_restaurants")
nola     <- read_rds_clean("nola_boundary")
water_sf <- read_rds_clean("nola_water")
roads_sf <- read_rds_clean("nola_roads")

reviews <- read_rds_clean("la_restaurant_reviews") |>
  semi_join(st_drop_geometry(study), by = "business_id") |>
  mutate(review_date = as_date(ymd_hms(date, quiet = TRUE))) |>
  filter(!is.na(review_date))

# ---- 1. The city fills in ---------------------------------------------------
# A restaurant "appears" in the year of its first review on Yelp (a proxy for
# when it joined Yelp, not necessarily when it opened).
first_seen <- reviews |>
  group_by(business_id) |>
  summarise(first_year = year(min(review_date)), .groups = "drop")

pts <- study |>
  select(business_id, cuisine_group) |>
  inner_join(first_seen, by = "business_id") |>
  mutate(cuisine_group = factor(cuisine_group, levels = names(cuisine_colors)))

years <- seq(min(pts$first_year), max(pts$first_year))
bb <- st_bbox(st_buffer(pts, 1500))
label_x <- bb[["xmin"]] + 0.04 * (bb[["xmax"]] - bb[["xmin"]])
label_y <- bb[["ymax"]] - 0.06 * (bb[["ymax"]] - bb[["ymin"]])
present <- names(cuisine_colors)[names(cuisine_colors) %in% pts$cuisine_group]

# Base map drawn once, reused by every frame
fill_base <- ggplot() +
  ink_base(nola, water_sf, roads_sf) +
  scale_colour_manual(values = cuisine_colors, limits = present, name = "Cuisine") +
  scale_shape_manual(values = cuisine_shapes_solid, limits = present, name = "Cuisine") +
  labs(title = "The city fills in",
       subtitle = "Restaurants appear in the year of their first Yelp review\nRed rings mark each year's newcomers",
       caption = data_caption) +
  theme_ink_map() +
  theme(legend.position = "bottom")

fill_frame <- function(i) {
  y <- years[i]
  old <- pts |> filter(first_year < y)
  new <- pts |> filter(first_year == y)
  fill_base +
    geom_sf(data = old, aes(colour = cuisine_group, shape = cuisine_group), size = 1.7, alpha = 0.8) +
    geom_sf(data = new, aes(colour = cuisine_group, shape = cuisine_group), size = 3.2) +
    geom_sf(data = new, shape = 21, size = 6, colour = seal_red, fill = NA, stroke = 0.7) +
    annotate("label", x = label_x, y = label_y,
             label = paste0(y, "\n", comma(nrow(old) + nrow(new)), " restaurants"),
             family = font_display, fontface = "bold", size = 9, colour = ink,
             fill = alpha(paper, 0.9), label.size = 0, label.r = unit(0, "pt"),
             lineheight = 0.9, hjust = 0, vjust = 1) +
    # zoom last: each geom_sf() above would otherwise reset the map extent
    coord_sf(xlim = as.numeric(bb[c("xmin", "xmax")]), ylim = as.numeric(bb[c("ymin", "ymax")]),
             expand = FALSE)
}

frames_to_gif(fill_frame, n = length(years), name = "anim_city_fills_in",
              width = 8, height = 8.5, fps = 2, hold = 6)

# ---- 2. Reviews grow, cuisine by cuisine ------------------------------------
monthly <- reviews |>
  left_join(st_drop_geometry(study) |> select(business_id, cuisine_group), by = "business_id") |>
  mutate(month = floor_date(review_date, "month")) |>
  count(cuisine_group, month) |>
  complete(cuisine_group, month = seq(min(month), max(month), by = "month"),
           fill = list(n = 0)) |>
  arrange(cuisine_group, month) |>
  group_by(cuisine_group) |>
  mutate(cumulative = cumsum(n)) |>
  ungroup()

all_months <- sort(unique(monthly$month))
step <- max(1, round(length(all_months) / 100))            # about 100 frames
frame_months <- unique(c(all_months[seq(1, length(all_months), by = step)], max(all_months)))
label_gap <- 0.05 * max(monthly$cumulative)                  # keeps labels from overlapping

growth_frame <- function(i) {
  lines <- monthly |> filter(month <= frame_months[i])
  heads <- lines |>
    group_by(cuisine_group) |>
    slice_max(month, n = 1) |>
    ungroup() |>
    arrange(cumulative) |>
    mutate(label_y = accumulate(cumulative, \(prev, cur) max(cur, prev + label_gap)))
  ggplot() +
    geom_line(data = lines, aes(month, cumulative, colour = cuisine_group, group = cuisine_group),
              linewidth = 1.1) +
    geom_point(data = heads, aes(month, cumulative, shape = cuisine_group, fill = cuisine_group),
               size = 3.4, colour = paper, stroke = 0.6) +
    geom_text(data = heads, aes(month, label_y, label = paste0(cuisine_group, "  ", comma(cumulative))),
              hjust = -0.12, family = font_display, fontface = "bold", size = 5, colour = ink) +
    scale_colour_manual(values = cuisine_colors, guide = "none") +
    scale_fill_manual(values = cuisine_colors, guide = "none") +
    scale_shape_manual(values = cuisine_shapes, guide = "none") +
    scale_x_date(limits = range(all_months), expand = expansion(mult = c(0.02, 0.28))) +
    scale_y_continuous(labels = comma, limits = c(0, max(monthly$cumulative) + 2 * label_gap),
                       expand = expansion(mult = c(0, 0.02))) +
    labs(title = "A city learns to review",
         subtitle = "Total Yelp reviews of New Orleans' Vietnamese, Chinese & Japanese restaurants",
         x = NULL, y = "Reviews so far", caption = data_caption) +
    theme_ink() +
    theme(panel.grid.major.x = element_blank())
}

frames_to_gif(growth_frame, n = length(frame_months), name = "anim_reviews_growth",
              width = 9, height = 6, fps = 20, hold = 30, basemap = TRUE)
