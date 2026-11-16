# =============================================================================
# R/01_import.R  —  run ONCE. Needs the raw Yelp JSON files in data/raw/.
#
# Large-data strategy:
#   * business file (~100 MB): small enough to read whole with stream_in().
#   * review file (~5 GB, ~7 million lines): NEVER loaded whole. stream_in()
#     reads it in pages of 100,000 lines; a handler keeps only reviews for
#     Louisiana restaurants and drops the long `text` column.
#   * results are saved as xz-compressed .rds files; after this script finishes
#     the raw JSON can be deleted.
# =============================================================================

source("R/00_setup.R")

business_file <- file.path(raw_dir, "yelp_academic_dataset_business.json")
review_file   <- file.path(raw_dir, "yelp_academic_dataset_review.json")
stopifnot(
  "Put yelp_academic_dataset_business.json in data/raw/" = file.exists(business_file),
  "Put yelp_academic_dataset_review.json in data/raw/"   = file.exists(review_file)
)

import_log <- tibble(step = character(), seconds = numeric(), rows = numeric(),
                     note = character())
log_step <- function(step, t0, rows, note = "") {
  import_log <<- add_row(import_log, step = step,
                         seconds = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
                         rows = rows, note = note)
  message(step, ": ", rows, " rows")
}

# ---- 1. Business table ------------------------------------------------------
t0 <- Sys.time()
business_raw <- stream_in(file(business_file), verbose = FALSE)
log_step("read business JSON", t0, nrow(business_raw),
         paste0(round(file.size(business_file) / 1e6, 1), " MB on disk"))

business <- business_raw |>
  select(business_id, name, address, city, state, postal_code,
         latitude, longitude, stars, review_count, is_open, categories)
rm(business_raw); invisible(gc())

dim(business)
glimpse(business)

# Keep every Louisiana restaurant (not just city == "New Orleans") so the
# spatial join can find restaurants whose text label and location disagree.
la_restaurants <- business |>
  filter(state == "LA",
         !is.na(categories),
         str_detect(categories, regex("\\bRestaurants\\b", ignore_case = TRUE))) |>
  distinct(business_id, .keep_all = TRUE)

save_rds(la_restaurants, "la_restaurants")
log_step("Louisiana restaurants kept", t0, nrow(la_restaurants))

# Context numbers for the report
business_overview <- tibble(
  all_businesses        = nrow(business),
  louisiana_businesses  = sum(business$state == "LA", na.rm = TRUE),
  louisiana_restaurants = nrow(la_restaurants)
)
save_table(business_overview, "business_overview")
rm(business); invisible(gc())

# ---- 2. Review table, streamed in chunks ------------------------------------
keep_ids <- la_restaurants$business_id
review_cols <- c("review_id", "user_id", "business_id", "stars", "date",
                 "useful", "funny", "cool")

chunks <- list()
k <- 0
lines_read <- 0

t0 <- Sys.time()
stream_in(
  file(review_file),
  handler = function(df) {
    lines_read <<- lines_read + nrow(df)
    keep <- df[df$business_id %in% keep_ids, review_cols, drop = FALSE]
    if (nrow(keep) > 0) {
      k <<- k + 1
      chunks[[k]] <<- keep
    }
    if (lines_read %% 1e6 == 0) message(format(lines_read, big.mark = ",", scientific = FALSE), " reviews scanned")
  },
  pagesize = 100000,
  verbose = FALSE
)
la_reviews <- bind_rows(chunks)
rm(chunks); invisible(gc())
log_step("stream review JSON, keep LA restaurant reviews", t0, nrow(la_reviews),
         paste0(format(lines_read, big.mark = ",", scientific = FALSE), " reviews scanned; ",
                round(file.size(review_file) / 1e9, 1), " GB on disk"))

dim(la_reviews)
glimpse(la_reviews)

save_rds(la_reviews, "la_restaurant_reviews")
log_step("saved compressed .rds", t0, nrow(la_reviews),
         paste0(round(file.size(file.path(clean_dir, "la_restaurant_reviews.rds")) / 1e6, 1),
                " MB after xz compression"))

save_table(import_log, "import_log")
import_log
