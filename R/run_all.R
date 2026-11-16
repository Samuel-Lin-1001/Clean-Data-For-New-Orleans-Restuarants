# Run the whole pipeline in order. 01_import.R only needs to run once;
# after that you can comment it out (and delete the raw JSON).
source("R/01_import.R")
source("R/02_clean_categories.R")
source("R/03_geography.R")
source("R/04_analysis.R")
source("R/05_animations.R")   # optional: animated GIFs (needs gifski)
