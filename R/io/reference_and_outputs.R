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

# Last year's file may be the CSV that the ARR project cleaned for analysis. That cleaning renames a few
# Combiner columns and adds columns of its own. The names below (old name = Combiner name) and the added
# columns are put back to what the Combiner makes, so the new combiner is the same whatever the old file holds.
ARR_RENAMED <- list(
  cr = c(Grantee = "Granteeorganization", Covid19related = "Covid19relateddata"),
  pr = c(Grantee = "Granteeorganization", unit = "UnitOfMeasurement", Reportingwindow = "ReportingWindow",
         code = "AnalysisCode", indicatoradmin = "IndicatorAdmin", Sourceofdata = "SourceOfData"))
ARR_ADDED <- list(
  cr = c("date", "yearstart", "yearend", "exercice"),
  pr = c("exercice", "c19", "Total", "revised_unit", "unit2", "yearend", "yearstart", "monthstart", "monthend",
         "daystart", "dayend", "concat", "Priority", "level_code", "RW_number"))

#' Give last year's combiner the Combiner's own column names
#'
#' Renames the columns that ARR renamed back to the Combiner name, and drops the columns that ARR adds
#' (the ARR cleaning creates them again). A file that is already a plain Combiner file is not changed.
#' @param old Last year's combiner (data frame).
#' @param which "cr" or "pr".
restore_combiner_names <- function(old, which = c("cr", "pr")) {
  which <- match.arg(which)
  ren <- ARR_RENAMED[[which]]
  todo <- ren[names(ren) %in% names(old) & !ren %in% names(old)]   # only when the Combiner name is free
  if (length(todo)) names(old)[match(names(todo), names(old))] <- unname(todo)
  drop <- intersect(ARR_ADDED[[which]], names(old))
  old <- old[, !names(old) %in% drop, drop = FALSE]
  if (length(todo) || length(drop)) {
    message("Previous ", toupper(which), " combiner: ",
            if (length(todo)) paste0("renamed to the Combiner names: ", paste(names(todo), collapse = ", "), ". "),
            if (length(drop)) paste0("dropped (the ARR cleaning adds them again): ", paste(drop, collapse = ", "), "."))
  }
  old
}

#' Dates written as `month/day/year` (or `day/month/year`) in last year's CSV become `YYYY-MM-DD`
#'
#' A CSV that was opened and saved in Excel has its dates rewritten in the local format, for example
#' `12/26/2023`. The Combiner writes `2023-12-26`, so the two formats would be mixed in the new
#' combiner. The order of day and month is decided from the data: a first number above 12 can only be
#' a day, a second number above 12 can only be a day too. If the data does not decide (or says both),
#' nothing is changed and a warning says so. Values that are already `YYYY-MM-DD` are not touched.
#' @param old Last year's combiner (data frame).
normalise_previous_dates <- function(old) {
  slash <- "^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$"
  is_slash <- lapply(old, function(x) is.character(x) & !is.na(x) & grepl(slash, trimws(x)))
  cols <- names(old)[vapply(is_slash, any, logical(1))]
  if (length(cols) == 0) return(old)

  parts <- do.call(rbind, lapply(cols, function(cn) do.call(rbind, strsplit(trimws(old[[cn]][is_slash[[cn]]]), "/", fixed = TRUE))))
  first <- as.integer(parts[, 1]); second <- as.integer(parts[, 2])
  day_first <- any(first > 12); month_first <- any(second > 12)
  if (day_first == month_first) {
    warning("Dates like 12/26/2023 were found in the previous combiner (columns: ", paste(cols, collapse = ", "),
            "), but the order of day and month cannot be decided from the data, so they were not changed.", call. = FALSE)
    return(old)
  }
  fmt <- if (month_first) "%m/%d/%Y" else "%d/%m/%Y"
  for (cn in cols) {
    old[[cn]][is_slash[[cn]]] <- format(as.Date(trimws(old[[cn]][is_slash[[cn]]]), fmt), "%Y-%m-%d")
  }
  message("Previous combiner: dates written as ", if (month_first) "month/day/year" else "day/month/year",
          " were changed to YYYY-MM-DD in: ", paste(cols, collapse = ", "), ".")
  old
}

#' Read a previous-year combiner (path from `inputs` in the config)
read_previous_combiner <- function(cfg, which = c("cr", "pr")) {
  which <- match.arg(which)
  path <- cfg$inputs[[paste0("previous_", which, "_combiner")]]
  if (is.null(path) || !file.exists(path)) {
    stop("Previous ", toupper(which), " combiner not found: ", path %||% "<not set>",
         "\nSet inputs$previous_", which, "_combiner in the config.", call. = FALSE)
  }
  normalise_previous_dates(restore_combiner_names(utils::read.csv(path, encoding = "UTF-8"), which))
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
