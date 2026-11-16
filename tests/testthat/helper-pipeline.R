# End-to-end fixture: real .xlsx workbooks with Excel tables, a saved GMS export, previous
# combiners and reference tables, all synthetic.

repo_root <- function() {
  if (file.exists("R/pipeline/run_pipeline.R")) normalizePath(getwd()) else normalizePath(file.path("..", ".."))
}

write_tables_book <- function(path, tables) {
  wb <- openxlsx2::wb_workbook()
  for (nm in names(tables)) {
    df <- tables[[nm]]
    df <- df[setdiff(names(df), c("file_name", "table_index"))]   # added by the extractor
    wb$add_worksheet(nm)
    wb$add_data_table(nm, x = df, table_name = nm)
  }
  wb$save(path)
}

#' Reporting-windows table: the Excel table's own header row holds the column names
synthetic_rw_sheet <- function() {
  data.frame(
    `Report Year` = c("Window 1", "Window 2"), `Type of reporting` = "Annual",
    `Reporting period up to` = c("2024-12-31", "2025-12-31"), `Submission deadline` = "2025-03-01",
    `M&E review` = "Approved", `Education team review` = "Done",
    `AR GRID 2021` = GRID_LEAD, GRID = NA_character_, check.names = FALSE, stringsAsFactors = FALSE)
}

make_pipeline_fixture <- function(workers = 1) {
  base <- tempfile("pipe_")
  src <- file.path(base, "source"); dir.create(src, recursive = TRUE)

  write_tables_book(file.path(src, "Results template X.xlsx"),
                    list(tbl_children = synthetic_cr_sheet(), tbl_si = synthetic_si_sheet(),
                         tbl_rw = synthetic_rw_sheet()))
  write_tables_book(file.path(src, "Results template Y.xlsx"), list(tbl_results = synthetic_rt_sheet()))
  write_tables_book(file.path(src, "Programme template X.xlsx"), list(tbl_results = synthetic_pt_sheet()))
  write_tables_book(file.path(src, "Programme template Z.xlsx"), list(tbl_af = synthetic_af_sheet()))
  write_tables_book(file.path(src, "Finance template Q.xlsx"), list(tbl_dcm = synthetic_dcm_sheet()))

  gms_file <- file.path(base, "gms_export.csv")
  gms <- synthetic_gms_raw()
  extra <- gms[1, ]                       # the grant the DCM sheet refers to
  extra$`Programme ID` <- "P9"; extra$GMGRN <- "24-ABC-LD1-RT2-ZZ9"
  readr::write_csv(rbind(gms, extra), gms_file)

  prev <- file.path(base, "previous"); dir.create(prev)
  utils::write.csv(synthetic_old_cr(), file.path(prev, "cr.csv"), row.names = FALSE)
  utils::write.csv(synthetic_old_pr(), file.path(prev, "pr.csv"), row.names = FALSE)

  ref <- file.path(base, "reference"); dir.create(ref)
  r <- synthetic_pr_reference()
  utils::write.csv(r$columns, file.path(ref, "pr_columns.csv"), row.names = FALSE)
  utils::write.csv(r$order, file.path(ref, "pr_columns_order.csv"), row.names = FALSE)
  utils::write.csv(r$names, file.path(ref, "pr_old_new_names.csv"), row.names = FALSE)

  list(
    paths = list(source_dir = src, cache_dir = file.path(base, "cache"), output_dir = file.path(base, "output"),
                 reference_dir = ref),
    source = list(backend = "local",
                  file_patterns = list(results = "Results template.*\\.xlsx$", programme = "Programme template.*\\.xlsx$",
                                       finance = "Finance template.*\\.xlsx$", aligned = "Aligned funding template.*\\.xlsx$")),
    tables = list(children = "tbl_children", results_framework = "tbl_results", standard_indicators = "tbl_si",
                  reporting_windows = "tbl_rw", leverage_funding = "tbl_af", finance_dcm = "tbl_dcm"),
    parallel = list(enabled = workers > 1, workers = workers),
    gms = list(from_file = gms_file),
    reporting = list(year = 2025, window_cutoff_date = "2026-01-01", apply_approval_filter = FALSE),
    filters = list(global_regional = "legacy"),
    inputs = list(previous_cr_combiner = file.path(prev, "cr.csv"), previous_pr_combiner = file.path(prev, "pr.csv")),
    outputs = list(share_dir = NULL))
}
