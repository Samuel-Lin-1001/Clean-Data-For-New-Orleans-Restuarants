# =============================================================================
# R/04_analysis.R
# Reviews joined to the study restaurants; all-reviewer vs. eligible-reviewer
# results; reviewer-normalized scores; top 10; best area; figures.
# Inputs : study_restaurants.rds, la_restaurant_reviews.rds, areas_*.rds
# =============================================================================

source("R/00_setup.R")
sf_use_s2(FALSE)

study    <- read_rds_clean("study_restaurants")
areas    <- read_rds_clean(paste0("areas_", main_geography))
nola     <- read_rds_clean("nola_boundary")
la_reviews <- read_rds_clean("la_restaurant_reviews")

area_id_col   <- paste0(main_geography, "_id")
area_name_col <- paste0(main_geography, "_name")
study <- study |>
  mutate(area_id = .data[[area_id_col]], area_name = .data[[area_name_col]])
study_tbl <- st_drop_geometry(study)

# ---- 1. Join: filter reviews to the study restaurants (one-to-many) ---------
category_reviews <- la_reviews |>
  semi_join(study_tbl, by = "business_id") |>
  mutate(review_date = as_date(ymd_hms(date, quiet = TRUE)),
         review_year = year(review_date))
rm(la_reviews); invisible(gc())

join_check <- tibble(
  study_restaurants          = nrow(study_tbl),
  restaurants_with_reviews   = n_distinct(category_reviews$business_id),
  reviews                    = nrow(category_reviews),
  reviewers                  = n_distinct(category_reviews$user_id),
  yelp_review_count_total    = sum(study_tbl$review_count),
  first_review = min(category_reviews$review_date, na.rm = TRUE),
  last_review  = max(category_reviews$review_date, na.rm = TRUE)
)
save_table(join_check, "join_check")

# ---- 2. All reviewers -------------------------------------------------------
all_reviewer_summary <- category_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_all_reviewers = n(),
    average_stars_all_reviewers     = mean(stars),
    median_stars_all_reviewers      = median(stars),
    .groups = "drop"
  )

# ---- 3. Reviewer baselines and normalized scores ----------------------------
# Baseline = the reviewer's own mean (and median) within this category group.
# Primary score uses the MEAN: Yelp stars are integers, so a median baseline
# makes most normalized scores exactly 0 and hides small differences.
reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(reviewer_mean = mean(stars), reviewer_median = median(stars),
            reviewer_review_count = n(), .groups = "drop")

category_reviews_adjusted <- category_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  mutate(normalized_mean_score   = stars - reviewer_mean,
         normalized_median_score = stars - reviewer_median)

eligible_reviewers <- reviewer_baselines |>
  filter(reviewer_review_count >= min_reviewer_reviews)
eligible_adjusted_reviews <- category_reviews_adjusted |>
  semi_join(eligible_reviewers, by = "user_id")

reviewer_retention <- tibble(
  threshold = threshold_grid,
  reviewers_kept = map_int(threshold_grid, \(t) sum(reviewer_baselines$reviewer_review_count >= t)),
  reviews_kept   = map_int(threshold_grid, \(t) sum(category_reviews_adjusted$reviewer_review_count >= t)),
  restaurants_with_5plus_eligible = map_int(threshold_grid, \(t) {
    category_reviews_adjusted |> filter(reviewer_review_count >= t) |>
      count(business_id) |> filter(n >= 5) |> nrow()
  })
) |>
  mutate(pct_reviewers = reviewers_kept / n_distinct(category_reviews$user_id),
         pct_reviews   = reviews_kept / nrow(category_reviews))
save_table(reviewer_retention, "reviewer_retention")

# ---- 4. Restaurant-level comparison -----------------------------------------
global_mean <- mean(category_reviews$stars)

summarise_eligible <- function(reviews) {
  reviews |>
    group_by(business_id) |>
    summarise(
      number_of_reviews_eligible_reviewers = n(),
      average_stars_eligible_reviewers     = mean(stars),
      average_normalized_score             = mean(normalized_mean_score),
      median_normalized_score              = median(normalized_mean_score),
      average_normalized_median_score      = mean(normalized_median_score),
      sum_normalized                       = sum(normalized_mean_score),
      .groups = "drop"
    )
}

restaurant_summary <- study_tbl |>
  select(business_id, business_name, address, cuisines, cuisine_group, is_open,
         latitude, longitude, area_id, area_name, business_stars = stars) |>
  left_join(all_reviewer_summary, by = "business_id") |>
  left_join(summarise_eligible(eligible_adjusted_reviews), by = "business_id") |>
  mutate(
    across(c(number_of_reviews_all_reviewers, number_of_reviews_eligible_reviewers),
           \(x) replace_na(x, 0L)),
    # Reliability: shrink small samples toward the group mean (raw) or 0 (adjusted)
    shrunk_stars = (average_stars_all_reviewers * number_of_reviews_all_reviewers +
                      shrink_k * global_mean) / (number_of_reviews_all_reviewers + shrink_k),
    shrunk_adjusted = replace_na(sum_normalized, 0) /
      (number_of_reviews_eligible_reviewers + shrink_k),
    rankable = is_open == 1 &
      number_of_reviews_all_reviewers >= min_reviews_to_rank &
      number_of_reviews_eligible_reviewers >= min_eligible_to_rank
  )

# "Best" = average of two percentile ranks among rankable restaurants:
#   reliability-adjusted raw stars (what diners see) and the reliability-
#   adjusted reviewer-normalized score (did reviewers like it MORE than usual?)
ranked <- restaurant_summary |>
  filter(rankable) |>
  mutate(
    pct_raw      = percent_rank(shrunk_stars),
    pct_adjusted = percent_rank(shrunk_adjusted),
    best_score   = (pct_raw + pct_adjusted) / 2,
    rank_raw      = min_rank(desc(average_stars_all_reviewers)),
    rank_adjusted = min_rank(desc(average_normalized_score)),
    rank_change   = rank_raw - rank_adjusted
  ) |>
  # ties are broken by review volume (more evidence wins)
  arrange(desc(best_score), desc(number_of_reviews_all_reviewers)) |>
  mutate(rank_best = row_number())

restaurant_summary <- restaurant_summary |>
  left_join(ranked |> select(business_id, pct_raw, pct_adjusted, best_score,
                             rank_raw, rank_adjusted, rank_change, rank_best),
            by = "business_id")
save_rds(restaurant_summary, "restaurant_summary")

# Extra detail for the interactive map's restaurant cards
star_dist <- category_reviews |>
  count(business_id, stars) |>
  mutate(stars = paste0("stars_", stars)) |>
  pivot_wider(names_from = stars, values_from = n, values_fill = 0)
for (k in paste0("stars_", 1:5)) if (!k %in% names(star_dist)) star_dist[[k]] <- 0L
review_span <- category_reviews |>
  group_by(business_id) |>
  summarise(first_review_year = min(review_year, na.rm = TRUE),
            last_review_year  = max(review_year, na.rm = TRUE), .groups = "drop")

top10 <- ranked |>
  slice_head(n = 10) |>
  left_join(star_dist, by = "business_id") |>
  left_join(review_span, by = "business_id") |>
  left_join(study_tbl |> select(business_id, postal_code), by = "business_id") |>
  transmute(rank = rank_best, restaurant = business_name, cuisine = cuisines, cuisine_group, area = area_name,
            address, postal_code, reviews = number_of_reviews_all_reviewers,
            avg_stars = round(average_stars_all_reviewers, 2),
            eligible_reviews = number_of_reviews_eligible_reviewers,
            avg_normalized = round(average_normalized_score, 2),
            best_score = round(best_score, 3),
            rank_raw, rank_adjusted, restaurants_ranked = nrow(ranked),
            is_open, first_review_year, last_review_year,
            stars_1, stars_2, stars_3, stars_4, stars_5,
            latitude, longitude)
save_table(top10, "top10_restaurants")

big_movers <- ranked |>
  filter(abs(rank_change) >= quantile(abs(rank_change), 0.9)) |>
  transmute(restaurant = business_name, area = area_name,
            reviews = number_of_reviews_all_reviewers,
            eligible_reviews = number_of_reviews_eligible_reviewers,
            avg_stars = round(average_stars_all_reviewers, 2),
            avg_normalized = round(average_normalized_score, 2),
            rank_raw, rank_adjusted, rank_change) |>
  arrange(desc(abs(rank_change)))
save_table(big_movers, "rank_changes")

# Threshold sensitivity: how many of today's top 10 survive other thresholds?
top10_at <- function(t) {
  elig <- category_reviews_adjusted |> filter(reviewer_review_count >= t)
  restaurant_summary |>
    select(business_id, is_open, number_of_reviews_all_reviewers, shrunk_stars) |>
    left_join(summarise_eligible(elig), by = "business_id") |>
    mutate(n_e = replace_na(number_of_reviews_eligible_reviewers, 0L),
           adj = replace_na(sum_normalized, 0) / (n_e + shrink_k)) |>
    filter(is_open == 1, number_of_reviews_all_reviewers >= min_reviews_to_rank,
           n_e >= min_eligible_to_rank) |>
    mutate(score = (percent_rank(shrunk_stars) + percent_rank(adj)) / 2) |>
    slice_max(score, n = 10, with_ties = FALSE) |>
    pull(business_id)
}
main_top <- top10_at(min_reviewer_reviews)
threshold_sensitivity <- tibble(threshold = threshold_grid) |>
  mutate(overlap_with_main_top10 = map_int(threshold, \(t) length(intersect(top10_at(t), main_top))))
save_table(threshold_sensitivity, "threshold_sensitivity")

# ---- 5. Which area is best? -------------------------------------------------
# An area is good for finding these restaurants if it has MANY top-quartile
# restaurants (choice), not just one lucky high average.
area_summary <- restaurant_summary |>
  filter(!is.na(area_id)) |>
  group_by(area_id, area_name) |>
  summarise(
    restaurants          = n(),
    open_restaurants     = sum(is_open == 1),
    reviews              = sum(number_of_reviews_all_reviewers),
    review_weighted_stars = weighted.mean(average_stars_all_reviewers,
                                          number_of_reviews_all_reviewers, na.rm = TRUE),
    mean_normalized      = weighted.mean(average_normalized_score,
                                         number_of_reviews_eligible_reviewers, na.rm = TRUE),
    top_quartile_restaurants = sum(best_score >= 0.75, na.rm = TRUE),
    top10_restaurants    = sum(rank_best <= 10, na.rm = TRUE),
    cuisines_present     = n_distinct(cuisine_group),
    .groups = "drop"
  ) |>
  mutate(rankable_area = restaurants >= min_restaurants_area,
         share_top_quartile = top_quartile_restaurants / restaurants) |>
  arrange(desc(rankable_area), desc(top_quartile_restaurants), desc(review_weighted_stars))
save_table(area_summary, paste0("area_summary_", main_geography))

# Same summary under every system (does the answer depend on the boundaries?)
area_answer_by_system <- map(c("nsa", "zcta", "tract"), \(g) {
  restaurant_summary |>
    select(business_id, best_score) |>
    left_join(study_tbl |> select(business_id, area = all_of(paste0(g, "_name"))), by = "business_id") |>
    filter(!is.na(area)) |>
    group_by(area) |>
    summarise(restaurants = n(), top_quartile = sum(best_score >= 0.75, na.rm = TRUE), .groups = "drop") |>
    filter(restaurants >= min_restaurants_area) |>
    slice_max(top_quartile, n = 3, with_ties = FALSE) |>
    mutate(system = g)
}) |> list_rbind()
save_table(area_answer_by_system, "area_answer_by_system")

# ---- 6. Figures (Ink & Lacquer style, see R/00_theme.R) ---------------------
water_sf <- read_rds_clean("nola_water")
roads_sf <- read_rds_clean("nola_roads")

# 6a. Candidate category counts
cand <- read_csv(file.path(table_dir, "asian_candidate_counts.csv"), show_col_types = FALSE)
p_cats <- cand |>
  slice_max(restaurants, n = 18) |>
  mutate(category = fct_reorder(str_to_title(category), restaurants),
         status = if_else(selected, "Included", "Not included")) |>
  ggplot(aes(restaurants, category, fill = status)) +
  geom_col(width = 0.62) +
  geom_text(aes(label = restaurants), hjust = -0.3, size = 3.2, colour = ink_soft, family = font_body) +
  scale_fill_manual(values = c(Included = ink, `Not included` = ink_wash[3]), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "The Asian table in New Orleans",
       subtitle = "Yelp category labels among New Orleans restaurants; dark bars form the study group",
       x = "Restaurants carrying the label", y = NULL, caption = data_caption) +
  theme_ink() +
  theme(legend.position = "top", legend.justification = "left", panel.grid.major.y = element_blank())
save_fig(p_cats, "category_counts", width = 9, height = 7)

# 6b. Co-occurrence: an ink-wash grid
pm <- read_rds_clean("asian_pair_matrix") |>
  filter(category.x %in% cand$category[cand$selected | cand$restaurants >= 10],
         category.y %in% cand$category[cand$selected | cand$restaurants >= 10]) |>
  mutate(across(c(category.x, category.y), str_to_title))
p_pairs <- ggplot(pm, aes(category.x, category.y, fill = restaurants)) +
  geom_tile(colour = paper, linewidth = 1.2) +
  geom_text(aes(label = restaurants, colour = restaurants > 0.65 * max(restaurants)),
            size = 3.2, family = font_body, show.legend = FALSE) +
  scale_fill_gradientn(colours = ink_wash, trans = "sqrt", name = "Restaurants") +
  scale_colour_manual(values = c(`TRUE` = paper, `FALSE` = ink)) +
  coord_fixed() +
  labs(title = "Labels that travel together",
       subtitle = "Restaurants carrying both labels; the diagonal counts each label alone",
       x = NULL, y = NULL, caption = data_caption) +
  theme_ink() +
  theme(axis.text.x = element_text(angle = 40, hjust = 1),
        panel.grid = element_blank(), panel.grid.major = element_blank())
save_fig(p_pairs, "category_cooccurrence", width = 9, height = 8)

# 6c. Raw vs adjusted
scatter_data <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= min_eligible_to_rank)
p_scatter <- ggplot(scatter_data, aes(average_stars_all_reviewers, average_normalized_score)) +
  geom_hline(yintercept = 0, colour = ink_soft, linewidth = 0.4, linetype = "22") +
  annotate("text", x = min(scatter_data$average_stars_all_reviewers, na.rm = TRUE), y = 0,
           label = "rated exactly as these reviewers usually rate", vjust = -0.6, hjust = 0,
           family = font_body, fontface = "italic", size = 3, colour = ink_soft) +
  geom_point(aes(size = number_of_reviews_all_reviewers, fill = cuisine_group, shape = cuisine_group),
             colour = paper, stroke = 0.5, alpha = 0.9) +
  geom_text_repel(data = \(d) d |> filter(rank_best <= 10),
                  aes(label = business_name), family = font_display, fontface = "bold",
                  size = 3.6, colour = ink, max.overlaps = 30, seed = 42,
                  segment.colour = ink_soft, segment.size = 0.3) +
  scale_fill_manual(values = cuisine_colors, name = "Cuisine") +
  scale_shape_manual(values = cuisine_shapes, name = "Cuisine") +
  scale_size_area(max_size = 9, name = "Reviews", labels = label_comma()) +
  guides(fill  = guide_legend(override.aes = list(size = 4)),
         size  = guide_legend(override.aes = list(shape = 21, fill = ink_soft))) +
  labs(title = "Praise from the regulars",
       subtitle = "Above the line, experienced reviewers liked a restaurant more than they usually like these cuisines",
       x = "Average stars, all reviewers", y = "Reviewer-adjusted score", caption = data_caption) +
  theme_ink()
save_fig(p_scatter, "raw_vs_adjusted", width = 10, height = 7)

# 6d. Threshold sensitivity
p_thresh <- reviewer_retention |>
  select(threshold, `Reviewers kept` = pct_reviewers, `Reviews kept` = pct_reviews) |>
  pivot_longer(-threshold) |>
  ggplot(aes(factor(threshold), value, fill = name)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.66, colour = paper, linewidth = 0.6) +
  geom_text(aes(label = percent(value, 1)), position = position_dodge(width = 0.72),
            vjust = -0.5, size = 3.2, family = font_body, colour = ink_soft) +
  scale_y_continuous(labels = percent, expand = expansion(mult = c(0, 0.1))) +
  scale_fill_manual(values = c(`Reviewers kept` = ink_wash[3], `Reviews kept` = ink), name = NULL) +
  labs(title = "How strict should we be?",
       subtitle = "Share of reviewers and reviews kept at each activity threshold",
       x = "Minimum reviews per reviewer within this cuisine group", y = NULL, caption = data_caption) +
  theme_ink() +
  theme(legend.position = "top", legend.justification = "left", panel.grid.major.x = element_blank())
save_fig(p_thresh, "threshold_retention", width = 9, height = 6)

# 6e. Best areas: top-quartile restaurants, stacked by cuisine
best_area_ids <- area_summary |>
  filter(rankable_area) |>
  slice_max(top_quartile_restaurants, n = 12, with_ties = FALSE)
p_area <- restaurant_summary |>
  filter(area_id %in% best_area_ids$area_id, best_score >= 0.75) |>
  count(area_name, cuisine_group) |>
  mutate(area_name = fct_reorder(area_name, n, sum)) |>
  ggplot(aes(n, area_name, fill = cuisine_group)) +
  geom_col(width = 0.62, colour = paper, linewidth = 0.6) +
  scale_fill_manual(values = cuisine_colors, name = "Cuisine") +
  scale_x_continuous(breaks = pretty_breaks(), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Where to go looking",
       subtitle = paste0("Top-quartile restaurants per area (areas with at least ",
                         min_restaurants_area, " restaurants)"),
       x = "Top-quartile restaurants", y = NULL, caption = data_caption) +
  theme_ink() +
  theme(legend.position = "top", legend.justification = "left", panel.grid.major.y = element_blank())
save_fig(p_area, "best_areas", width = 9, height = 6.5)

# 6f. FINAL MAP: top 10 as red seal stamps on an ink-wash city
top10_sf <- top10 |>
  st_as_sf(coords = c("longitude", "latitude"), crs = crs_lonlat) |>
  st_transform(crs_projected)
area_fill <- areas |>
  left_join(area_summary |> select(area_id, top_quartile_restaurants), by = "area_id") |>
  mutate(top_quartile_restaurants = replace_na(top_quartile_restaurants, 0L))
bb <- st_bbox(st_buffer(top10_sf, 2500))
# Crop every layer to the view: smaller files and faster drawing
crop_to <- function(x) if (is.null(x)) NULL else suppressWarnings(st_crop(x, bb))
area_fill <- crop_to(area_fill)
final_water <- crop_to(water_sf)
final_roads <- crop_to(roads_sf)
legend_text <- paste0(top10$rank, "  ", top10$restaurant, collapse = "\n")

p_final <- ggplot() +
  ink_base(nola, final_water, final_roads,
           geom_sf(data = area_fill, aes(fill = top_quartile_restaurants),
                   colour = paper, linewidth = 0.4)) +
  geom_sf(data = top10_sf, aes(shape = cuisine_group),
          fill = cuisine_colors[top10_sf$cuisine_group], size = 4, colour = paper, stroke = 0.7) +
  geom_seal(data = top10_sf, aes(label = rank, geometry = geometry), stat = "sf_coordinates") +
  scale_fill_stepsn(colours = ink_wash[1:4], name = "Top-quartile\nrestaurants", n.breaks = 4,
                    aesthetics = "fill") +
  scale_shape_manual(values = cuisine_shapes, name = "Cuisine") +
  guides(shape = guide_legend(override.aes = list(fill = cuisine_colors[sort(unique(top10$cuisine_group))]))) +
  annotate("label", x = Inf, y = Inf, label = legend_text, hjust = 1, vjust = 1,
           family = font_display, size = 3.6, lineheight = 1.05, fill = paper,
           colour = ink, label.size = 0, label.r = unit(0, "pt")) +
  coord_sf(xlim = as.numeric(bb[c("xmin", "xmax")]), ylim = as.numeric(bb[c("ymin", "ymax")]),
           expand = FALSE) +
  labs(title = "Ten tables worth the trip",
       subtitle = "The best Vietnamese, Chinese & Japanese restaurants in New Orleans. Red seals mark the rank.",
       caption = data_caption) +
  theme_ink_map() +
  theme(legend.position = "bottom", legend.box = "horizontal")
save_fig(p_final, "final_top10_map", width = 10, height = 9, basemap = FALSE)

# Where each restaurant lands in that image (percent from the left / top),
# so the report can place clickable spots exactly on top of the markers.
xy <- st_coordinates(top10_sf)
hotspots <- panel_positions(p_final, width = 10, height = 9, x = xy[, 1], y = xy[, 2])
top10 <- top10 |> mutate(map_left_pct = hotspots$left_pct, map_top_pct = hotspots$top_pct)
save_table(top10, "top10_restaurants")

# 6g. Cover poster: three panels, one per cuisine, like three hanging scrolls
poster_pts <- restaurant_summary |>
  select(business_id, cuisines, longitude, latitude, reviews = number_of_reviews_all_reviewers) |>
  separate_rows(cuisines, sep = " \\+ ") |>
  rename(cuisine = cuisines) |>
  mutate(cuisine = factor(cuisine, levels = c("Vietnamese", "Chinese", "Japanese"))) |>
  st_as_sf(coords = c("longitude", "latitude"), crs = crs_lonlat) |>
  st_transform(crs_projected)
pbb <- st_bbox(st_buffer(poster_pts, 1500))
p_poster <- ggplot() +
  ink_base(nola, water_sf, roads_sf) +
  geom_sf(data = poster_pts, aes(colour = cuisine, size = reviews), alpha = 0.75) +
  scale_colour_manual(values = cuisine_colors, guide = "none") +
  scale_size_area(max_size = 4.5, guide = "none") +
  facet_wrap(~cuisine, nrow = 1) +
  coord_sf(xlim = as.numeric(pbb[c("xmin", "xmax")]), ylim = as.numeric(pbb[c("ymin", "ymax")])) +
  labs(title = "Pho, Dim Sum & Sushi in the Crescent City",
       subtitle = "Every Vietnamese, Chinese and Japanese restaurant on Yelp in New Orleans; larger dots have more reviews",
       caption = data_caption) +
  theme_ink_map(13) +
  theme(panel.spacing = unit(1.2, "lines"),
        panel.background = element_rect(fill = paper_deep, colour = NA),
        strip.text = element_text(size = rel(1.6), margin = margin(b = 6)))
save_fig(p_poster, "cover_poster", width = 14, height = 6.5, basemap = FALSE)

message("Done. Tables in ", table_dir, ", figures in ", fig_dir)
