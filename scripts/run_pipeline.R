# Run the whole pipeline.
#   Rscript scripts/run_pipeline.R                 # all flows
#   Rscript scripts/run_pipeline.R cr pr           # only some flows
#   Rscript scripts/run_pipeline.R --refresh       # ignore the extraction cache
#   Rscript scripts/run_pipeline.R --cache-only    # no workbook opened, source folder not read, no GMS login

source("R/pipeline/run_pipeline.R")
source_project()

args <- commandArgs(trailingOnly = TRUE)
flows <- setdiff(args, c("--refresh", "--cache-only"))
if (length(flows) == 0) flows <- ALL_FLOWS

cache_only <- "--cache-only" %in% args
cfg <- load_config(check_source_dir = !cache_only)   # cache-only does not need the source folder
out <- run_pipeline(cfg, flows = flows, refresh = "--refresh" %in% args, cache_only = cache_only)

print(out$log)
message("Outputs written under ", cfg$paths$output_dir)
