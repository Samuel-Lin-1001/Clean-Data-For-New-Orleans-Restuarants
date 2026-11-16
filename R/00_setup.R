# =============================================================================
# R/00_setup.R
# Packages, paths, and analysis settings shared by every script.
# Every other script starts with source("R/00_setup.R").
# =============================================================================

# Install once (or use renv::restore() after renv.lock exists):
# install.packages(c("tidyverse", "jsonlite", "lubridate", "sf", "tigris",
#                    "scales", "viridis", "ggrepel", "knitr", "renv",
#                    "ragg", "systemfonts", "gifski"))

suppressPackageStartupMessages({
  library(tidyverse)
  library(jsonlite)
  library(lubridate)
  library(sf)
  library(tigris)
  library(scales)
  library(viridis)
  library(ggrepel)
})

options(tigris_use_cache = TRUE, timeout = 600)

# ---- Paths ------------------------------------------------------------------
raw_dir      <- "data/raw"            # giant Yelp JSON files (git-ignored)
clean_dir    <- "data/new_orleans"    # filtered, compressed .rds outputs
boundary_dir <- "data/boundaries"     # downloaded boundary files
fig_dir      <- "figures"
table_dir    <- "output/tables"

for (d in c(clean_dir, boundary_dir, fig_dir, table_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# ---- Analysis settings (change here, re-run, and document what changed) -----

# Core cuisines (the three related categories) plus sub-cuisine labels that
# Yelp sometimes uses WITHOUT the parent label (e.g., a sushi bar tagged only
# "Sushi Bars"). Each sub-cuisine is mapped back to its parent cuisine.
cuisine_map <- tribble(
  ~category,      ~cuisine,
  "vietnamese",   "Vietnamese",
  "chinese",      "Chinese",
  "japanese",     "Japanese",
  "sushi bars",   "Japanese",
  "ramen",        "Japanese",
  "izakaya",      "Japanese",
  "teppanyaki",   "Japanese",
  "dim sum",      "Chinese",
  "szechuan",     "Chinese",
  "cantonese",    "Chinese",
  "shanghainese", "Chinese",
  "hong kong style cafe", "Chinese"
)

min_reviewer_reviews   <- 5   # reviewer must have >= this many reviews in the category group
threshold_grid         <- c(2, 3, 5, 10)  # sensitivity check
min_reviews_to_rank    <- 20  # restaurant needs >= this many total reviews for top-10
min_eligible_to_rank   <- 3   # ... and >= this many reviews from eligible reviewers
shrink_k               <- 10  # pseudo-reviews used to shrink small samples toward the mean
min_restaurants_area   <- 3   # areas with fewer restaurants are shown but not ranked

# Main geography chosen AFTER reviewing the comparison table in R/03_geography.R.
# One of: "nsa", "zcta", "tract"
main_geography <- "nsa"

# Projected CRS for spatial work (UTM zone 15N, metres) and lon/lat for storage
crs_projected <- 26915
crs_lonlat    <- 4326

save_rds <- function(x, name) {
  saveRDS(x, file.path(clean_dir, paste0(name, ".rds")), compress = "xz")
}
read_rds_clean <- function(name) readRDS(file.path(clean_dir, paste0(name, ".rds")))
save_table <- function(x, name) write_csv(x, file.path(table_dir, paste0(name, ".csv")))

# Visual identity: colors, fonts, ggplot themes, save_fig()
source("R/00_theme.R")
