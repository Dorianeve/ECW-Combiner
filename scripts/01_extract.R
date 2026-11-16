# Step 1: extract all configured tables from the source workbooks (cached, parallel).
# Run from the project root:  Rscript scripts/01_extract.R [--refresh]

invisible(lapply(list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE), source))

args <- commandArgs(trailingOnly = TRUE)
cfg <- load_config()

t0 <- Sys.time()
extracted <- extract_all(cfg, refresh = "--refresh" %in% args)
elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

report <- extraction_report(extracted)
print(report, n = Inf, width = Inf)
message(sprintf("Done in %ss: %d file(s), %d from cache.",
                elapsed, nrow(report), sum(report$origin == "cache")))
