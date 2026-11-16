# Reference tables and output files ----

#' Read a lookup table from reference/ (same reader call as the legacy code, for parity)
read_reference <- function(name, dir = "reference") {
  utils::read.csv(file.path(dir, paste0(name, ".csv")), encoding = "UTF-8")
}

#' The three PR column lookup tables
load_pr_reference <- function(dir = "reference") {
  list(columns = read_reference("pr_columns", dir),
       order = read_reference("pr_columns_order", dir),
       names = read_reference("pr_old_new_names", dir))
}

#' Read a previous-year combiner (path from `inputs` in the config)
read_previous_combiner <- function(cfg, which = c("cr", "pr")) {
  which <- match.arg(which)
  path <- cfg$inputs[[paste0("previous_", which, "_combiner")]]
  if (is.null(path) || !file.exists(path)) {
    stop("Previous ", toupper(which), " combiner not found: ", path %||% "<not set>",
         "\nSet inputs$previous_", which, "_combiner in the config.", call. = FALSE)
  }
  utils::read.csv(path, encoding = "UTF-8")
}

#' The folder of the AnnualResultsReport repository that receives the hand-over files
#'
#' The two repositories are downloaded side by side and talk to each other: the files the ARR flow
#' reads (`cr_clean.xlsx`, `pr_clean.xlsx`, `grants_db.csv`) are copied to its `data/input/` folder.
#' Set `outputs: arr_input_dir` in the config (default `../AnnualResultsReport/data/input`).
#' @return The folder, or NULL when it is not configured or cannot be used (a warning says why).
arr_handoff_dir <- function(cfg) {
  dir <- cfg$outputs$arr_input_dir
  if (is.null(dir) || !nzchar(dir)) return(NULL)
  assert_outside_source(dir, cfg, "the hand-over to AnnualResultsReport")
  if (!dir.exists(dir)) {
    if (!dir.exists(dirname(dir))) {
      warning("AnnualResultsReport was not found, so the hand-over files were not copied to it. ",
              "Expected the folder: ", dir, ". Download both repositories into the same parent folder, ",
              "or set `outputs: arr_input_dir` in the config.", call. = FALSE)
      return(NULL)
    }
    dir.create(dir, showWarnings = FALSE)
  }
  dir
}

#' Save the processed GMS grants table that the ARR flow reads (`grants_db.csv`)
#'
#' Written to `<output_dir>/gms/grants_db.csv` and copied to the AnnualResultsReport input folder.
#' @param grants Output of [gms_process()] with profile "arr".
#' @return The written paths (invisibly).
write_grants_db <- function(grants, cfg) {
  if (is.null(grants)) return(invisible(NULL))
  dir <- file.path(cfg$paths$output_dir, "gms")
  assert_outside_source(dir, cfg, "outputs")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  old <- options(scipen = 999)
  on.exit(options(old), add = TRUE)
  path <- file.path(dir, "grants_db.csv")
  utils::write.csv(grants, path, row.names = FALSE, fileEncoding = "UTF-8")

  arr <- arr_handoff_dir(cfg)
  if (!is.null(arr)) {
    file.copy(path, file.path(arr, "grants_db.csv"), overwrite = TRUE)
    path <- c(path, file.path(arr, "grants_db.csv"))
  }
  invisible(path)
}

#' Save a combiner as dated CSV plus a stable-named XLSX
#'
#' @param name e.g. "cr" -> `<output_dir>/cr/<date>_cr cleaned.csv` and `.../cr_clean.xlsx`
#' @param csv_df What goes into the dated CSV. Defaults to `df`. For PR the legacy CSV was the
#'   combiner *before* the final tidy-up while the XLSX held the tidied one, so the pipeline
#'   passes the pre-tidy table here. In that case the tidied table is also saved as
#'   `<name>_clean.csv`.
#' @return The written paths (invisibly). If `outputs$share_dir` is set, the XLSX is also
#'   copied there (legacy "ARR checks workflow" hand-over).
write_combiner <- function(df, name, cfg, date = Sys.Date(), csv_df = df) {
  dir <- file.path(cfg$paths$output_dir, name)
  assert_outside_source(dir, cfg, "outputs")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  old <- options(scipen = 999)   # plain notation for large amounts in the CSV
  on.exit(options(old), add = TRUE)

  csv_path <- file.path(dir, paste0(date, "_", name, " cleaned.csv"))
  xlsx_path <- file.path(dir, paste0(name, "_clean.xlsx"))
  utils::write.csv(csv_df, csv_path, row.names = FALSE, fileEncoding = "UTF-8")
  openxlsx2::write_xlsx(df, xlsx_path)
  paths <- c(csv_path, xlsx_path)
  if (!identical(csv_df, df)) {
    final_csv <- file.path(dir, paste0(name, "_clean.csv"))
    utils::write.csv(df, final_csv, row.names = FALSE, fileEncoding = "UTF-8")
    paths <- c(paths, final_csv)
  }

  share <- cfg$outputs$share_dir
  if (!is.null(share) && nzchar(share)) {
    assert_outside_source(share, cfg, "the shared output copy")
    dir.create(share, recursive = TRUE, showWarnings = FALSE)
    file.copy(xlsx_path, file.path(share, basename(xlsx_path)), overwrite = TRUE)
  }

  # hand-over to the AnnualResultsReport repository (CR and PR only)
  arr <- if (name %in% c("cr", "pr")) arr_handoff_dir(cfg)
  if (!is.null(arr)) {
    file.copy(xlsx_path, file.path(arr, basename(xlsx_path)), overwrite = TRUE)
    paths <- c(paths, file.path(arr, basename(xlsx_path)))
  }
  invisible(paths)
}
