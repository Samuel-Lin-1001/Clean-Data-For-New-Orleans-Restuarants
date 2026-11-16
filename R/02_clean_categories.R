# =============================================================================
# R/02_clean_categories.R
# Clean New Orleans restaurants, split categories, count and co-occur them,
# and apply the Vietnamese / Chinese / Japanese inclusion rule.
# Inputs : data/new_orleans/la_restaurants.rds
# Outputs: restaurant_categories.rds, asian_restaurants_text.rds, tables
# =============================================================================

source("R/00_setup.R")

la_restaurants <- read_rds_clean("la_restaurants")

# ---- 1. Clean fields --------------------------------------------------------
la_restaurants <- la_restaurants |>
  mutate(
    postal_code   = na_if(str_squish(postal_code), ""),
    categories    = str_squish(categories),
    business_name = str_squish(name),
    city_clean    = str_to_title(str_squish(city)),
    yelp_says_new_orleans = str_detect(str_to_lower(city_clean), "^new orleans|^nola$")
  )

# How is "New Orleans" spelled in the city field? (typos, "Nola", trailing text)
city_labels <- la_restaurants |>
  count(city_clean, yelp_says_new_orleans, sort = TRUE)
save_table(city_labels, "city_labels")

missing_check <- la_restaurants |>
  summarise(
    restaurants       = n(),
    missing_latitude  = sum(is.na(latitude)),
    missing_longitude = sum(is.na(longitude)),
    missing_postal    = sum(is.na(postal_code)),
    closed            = sum(is_open == 0)
  )
save_table(missing_check, "missing_check")

# ---- 2. One row per business-category ---------------------------------------
restaurant_categories <- la_restaurants |>
  select(business_id, categories) |>
  separate_rows(categories, sep = ",") |>
  mutate(category = str_to_lower(str_squish(categories))) |>
  filter(category != "") |>
  distinct(business_id, category)

save_rds(restaurant_categories, "restaurant_categories")

nola_ids <- la_restaurants |> filter(yelp_says_new_orleans) |> pull(business_id)
nola_categories <- restaurant_categories |> filter(business_id %in% nola_ids)

# Generic labels that say nothing about cuisine
generic <- c("restaurants", "food", "nightlife", "bars", "event planning & services")

category_counts <- nola_categories |>
  filter(!category %in% generic) |>
  count(category, name = "restaurants", sort = TRUE)
save_table(category_counts, "category_counts_all")

# Every Asian-cuisine label that appears, so the choice is visible, not assumed
asian_pattern <- regex(
  "viet|chinese|japan|sushi|ramen|izakaya|teppan|dim sum|szechuan|cantonese|shanghai|hong kong|taiwan|korean|thai|asian|noodle|poke|hot pot|bubble tea",
  ignore_case = TRUE
)
asian_candidate_counts <- category_counts |>
  filter(str_detect(category, asian_pattern)) |>
  left_join(cuisine_map, by = "category") |>
  mutate(selected = !is.na(cuisine))
save_table(asian_candidate_counts, "asian_candidate_counts")

# ---- 3. Co-occurrence -------------------------------------------------------
# (a) Pairs among the candidate Asian labels
candidates <- asian_candidate_counts$category
cand_long <- nola_categories |> filter(category %in% candidates)

pair_counts <- cand_long |>
  inner_join(cand_long, by = "business_id", relationship = "many-to-many") |>
  filter(category.x < category.y) |>
  count(category_1 = category.x, category_2 = category.y,
        name = "restaurants_with_both", sort = TRUE)
save_table(pair_counts, "asian_category_pairs")

# Full matrix (including the diagonal) for a heat map
pair_matrix <- cand_long |>
  inner_join(cand_long, by = "business_id", relationship = "many-to-many") |>
  count(category.x, category.y, name = "restaurants")
save_rds(pair_matrix, "asian_pair_matrix")

# (b) What else are the selected restaurants tagged with? (shows the group is
#     coherent: shared labels such as noodles, asian fusion, seafood)
selected_ids_tmp <- nola_categories |>
  filter(category %in% cuisine_map$category) |>
  distinct(business_id)
companion_categories <- nola_categories |>
  semi_join(selected_ids_tmp, by = "business_id") |>
  filter(!category %in% c(generic, cuisine_map$category)) |>
  count(category, name = "selected_restaurants_with_label", sort = TRUE) |>
  slice_head(n = 20)
save_table(companion_categories, "companion_categories")

# (c) How often does a sub-cuisine label appear WITHOUT its parent label?
#     This justifies mapping e.g. "sushi bars" back to "Japanese".
sub_without_parent <- cuisine_map |>
  filter(!category %in% c("vietnamese", "chinese", "japanese")) |>
  rowwise() |>
  mutate(
    with_label = n_distinct(nola_categories$business_id[nola_categories$category == category]),
    parent     = str_to_lower(cuisine),
    without_parent = {
      ids <- nola_categories$business_id[nola_categories$category == category]
      par <- nola_categories$business_id[nola_categories$category == parent]
      length(setdiff(ids, par))
    }
  ) |>
  ungroup() |>
  filter(with_label > 0)
save_table(sub_without_parent, "subcuisine_without_parent")

# ---- 4. Inclusion rule ------------------------------------------------------
# A restaurant is included if it carries AT LEAST ONE label in cuisine_map.
# "Asian Fusion" alone is NOT enough (it does not tell us the cuisine).
restaurant_cuisine <- restaurant_categories |>
  inner_join(cuisine_map, by = "category") |>
  group_by(business_id) |>
  summarise(
    cuisines     = paste(sort(unique(cuisine)), collapse = " + "),
    n_cuisines   = n_distinct(cuisine),
    cuisine_group = if_else(n_cuisines > 1, "Multiple", first(cuisine)),
    .groups = "drop"
  )

asian_restaurants_text <- la_restaurants |>
  inner_join(restaurant_cuisine, by = "business_id")

save_rds(asian_restaurants_text, "asian_restaurants_la")

inclusion_summary <- asian_restaurants_text |>
  mutate(label = if_else(yelp_says_new_orleans, "Yelp city = New Orleans", "Other LA city label")) |>
  count(label, cuisine_group) |>
  pivot_wider(names_from = label, values_from = n, values_fill = 0)
save_table(inclusion_summary, "inclusion_summary")
inclusion_summary
