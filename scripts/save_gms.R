# Download the GMS grants export once and keep it in the cache (<cache_dir>/gms/).
#   Rscript scripts/save_gms.R
# No workbook is opened and the source folder is not read. Afterwards
#   Rscript scripts/run_pipeline.R --cache-only
# runs without logging in to the GMS again. Needs GMS_USER / GMS_PASSWORD.

source("R/pipeline/run_pipeline.R")
source_project()

cfg <- load_config(check_source_dir = FALSE)
raw <- gms_load(cfg)
message("Saved ", nrow(raw), " GMS rows to ", file.path(cfg$paths$cache_dir, "gms"))
