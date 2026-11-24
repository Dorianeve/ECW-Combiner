# Step 0, Google Drive only: pull every matching workbook out of Drive into a local folder,
# converting Google Sheets to real .xlsx files on the way. Run this first if you switched to
# Google Drive and some source files are Google Sheets, not already real .xlsx files.
# (If every source file is already a real .xlsx, you do not need this script -- see
# docs/google-drive.md.)
#
#   Rscript scripts/00_drive_export.R [--refresh]
#
# Needs: install.packages("googledrive"), and `drive_export: folder_id:` set in config.yml.
# First run opens a browser to sign in to Google; the token is then cached. For an unattended
# run, set GDRIVE_SERVICE_ACCOUNT_JSON to the path of a service account key instead.

invisible(lapply(list.files("R", pattern = "\\.R$", recursive = TRUE, full.names = TRUE), source))

args <- commandArgs(trailingOnly = TRUE)
cfg <- load_config(check_source_dir = FALSE)

manifest <- drive_export_all(cfg, refresh = "--refresh" %in% args)
print(drive_export_report(manifest))

dest_dir <- cfg$drive_export$dest_dir %||% "cache/drive_export"
message("Done. ", nrow(manifest), " file(s) in ", dest_dir, ". Point paths: source_dir at this ",
        "folder (or let Drive for Desktop mirror it), then run the pipeline as usual.")
