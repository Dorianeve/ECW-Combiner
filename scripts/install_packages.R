# One-off setup: install the packages the pipeline needs.
# (Pipeline scripts never call install.packages(); run this once, or use renv::restore().)
pkgs <- c(
  "openxlsx2", "tidyverse", "readr", "tibble", "janitor", "lubridate", "stringr", "purrr", "dplyr",
  "tidyr", "fs", "httr", "yaml", "digest", "future", "furrr", "progressr", "testthat"
)
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing)
