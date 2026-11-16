# Shared helpers ----
# These replace code that was copy-pasted into every loader script.

# Cells and header detection ----

#' Normalise cell text for matching (character, optional whitespace collapse, trim, lower)
norm_cell <- function(x, collapse_ws = FALSE) {
  x <- as.character(x)
  if (collapse_ws) {
    x <- stringr::str_replace_all(x, "[\r\n\t]", " ")
    x <- stringr::str_replace_all(x, "\\s+", " ")
  }
  tolower(trimws(x))
}

#' Row numbers of a raw sheet table whose cell in column `col` matches
#'
#' @param equals Exact (normalised) strings to match, or
#' @param regex  a case-insensitive regex.
find_header_rows <- function(df, col, equals = NULL, regex = NULL, collapse_ws = FALSE) {
  txt <- norm_cell(df[[col]], collapse_ws)
  hit <- if (!is.null(equals)) txt %in% equals else
    stringr::str_detect(txt, stringr::regex(regex, ignore_case = TRUE))
  which(hit)
}

META_COLS <- c("file_name", "table_index")

#' Convert a column to text without scientific notation
#'
#' `as.character(500000)` is "5e+05" and `as.character(1e6)` is "1e+06". Text like that breaks
#' later cleaning that strips non-digits ("5e+05" -> "505"). Numbers are written with up to
#' 15 significant digits instead; other types use `as.character()`.
as_plain_text <- function(x) {
  # plain numbers only: dates, times and other classed numbers keep their normal text form
  if (!is.double(x) || !is.null(attr(x, "class"))) return(as.character(x))
  out <- sprintf("%.15g", x)
  out[!is.finite(x)] <- as.character(x[!is.finite(x)])
  out
}

#' Trim whitespace and drop fully empty rows of an all-character table
tidy_body <- function(df) {
  df |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ trimws(as_plain_text(.x)))) |>
    dplyr::filter(!dplyr::if_all(dplyr::everything(), ~ .x == "" | is.na(.x)))
}

#' Normalise names and tidy rows of a table whose header is already correct
#'
#' The extractor (`wb_to_df` on a named Excel table) always returns the table's own
#' header row as column names already; there is no header row to locate or promote
#' from inside the data.
clean_promoted <- function(df) {
  names(df) <- janitor::make_clean_names(names(df))
  tidy_body(df)
}

#' Use row `header_row` of a raw sheet table as header and drop everything above it
#'
#' The extractor appends `file_name` and `table_index` columns; their header cells hold
#' the file name / index, so they are forced to the names "file_name"/"table_index"
#' here (this is independent of how workbooks are named).
#'
#' @param drop_first_col Drop the (empty) first sheet column.
#' @param trim_names Trim header text before snake-casing.
promote_header <- function(df, header_row, drop_first_col = TRUE, trim_names = TRUE) {
  hdr <- as.character(df[header_row, ])
  hdr[names(df) %in% META_COLS] <- names(df)[names(df) %in% META_COLS]
  body <- df[-(1:header_row), , drop = FALSE]
  if (drop_first_col) {
    hdr <- hdr[-1]
    body <- body[, -1, drop = FALSE]
  }
  if (trim_names) hdr <- trimws(hdr)
  names(body) <- janitor::make_clean_names(hdr)
  tidy_body(body)
}

#' Standard header repairs shared by all result-type templates
#'
#' Drops `na_*` columns, maps the grid column(s) to `GRID` and repairs analysis-code typos.
standardise_columns <- function(df, grid_from = c("ar_grid_2021", "grid")) {
  df <- dplyr::select(df, -dplyr::starts_with("na_"))
  for (g in grid_from) {
    if (g %in% names(df) && !"GRID" %in% names(df)) df <- dplyr::rename(df, GRID = dplyr::all_of(g))
  }
  typos <- intersect(names(df), c("analysis_code", "aysis_code", "ecw_anays_code",
                                  "anaysis_code", "anays_code"))
  if (length(typos) == 1 && typos != "analysis_code") {
    df <- dplyr::rename(df, analysis_code = dplyr::all_of(typos))
  }
  df
}

#' Report whether all tables share the same header set
check_headers_consistency <- function(df_list, group_name = "Group") {
  colnames_list <- purrr::map(df_list, ~ sort(names(.x)))
  unique_colnames <- unique(colnames_list)
  if (length(unique_colnames) <= 1) {
    message("OK ", group_name, ": all tables have consistent headers.")
    return(invisible(TRUE))
  }
  message("WARNING ", group_name, ": inconsistent headers, ", length(unique_colnames), " distinct sets.")
  ref <- unique_colnames[[1]]
  purrr::iwalk(colnames_list, function(cols, idx) {
    if (!identical(cols, ref)) {
      message("  table ", idx, " differs.")
      missing <- setdiff(ref, cols); extra <- setdiff(cols, ref)
      if (length(missing)) message("    missing: ", paste(missing, collapse = ", "))
      if (length(extra))   message("    extra:   ", paste(extra, collapse = ", "))
    }
  })
  invisible(FALSE)
}

#' Warn about tables whose first column is not one of the expected names
check_first_column <- function(df_list, expected, group_name = "Group") {
  first <- vapply(df_list, function(d) names(d)[1], character(1))
  bad <- first[!first %in% expected]
  if (length(bad)) {
    warning(group_name, ": ", length(bad), " table(s) have an unexpected first column: ",
            paste(unique(bad), collapse = ", "), call. = FALSE)
  }
  invisible(first)
}

#' Add the columns missing from `df` (as NA) and order by `all_columns`
add_missing_columns <- function(df, all_columns) {
  missing_cols <- setdiff(all_columns, names(df))
  df[missing_cols] <- NA
  dplyr::select(df, dplyr::all_of(all_columns))
}

# Values ----

#' Replace empty / whitespace-only strings with NA across all columns
blank_to_na <- function(df) {
  before <- sum(is.na(df))
  out <- dplyr::mutate(df, dplyr::across(dplyr::everything(),
                                         ~ ifelse(stringr::str_trim(.x) == "", NA, .x)))
  message("Blank values replaced with NA: ", sum(is.na(out)) - before)
  out
}

#' Set the `ARRyyAnnual` / `ARRyyCumulative` Yes/No columns of the current cycle
#'
#' Every row gets "Yes" unless the exercise has a rule (`reporting.exercises.annual_rule` /
#' `cumulative_rule`): then "Yes" needs `period_end` (end date of the programme's latest
#' reporting window) to lie in the rule's `from`..`to`; a missing date gives "No".
add_exercise_flags <- function(df, period_end, cp) {
  for (i in seq_along(cp$exercise_cols)) {
    rule <- cp[[paste0(cp$exercise_keys[i], "_rule")]]
    yes <- rep(TRUE, nrow(df))
    if (!is.null(rule)) {
      d <- as.Date(period_end)
      yes <- !is.na(d) & (is.na(rule$from) | d >= rule$from) & (is.na(rule$to) | d <= rule$to)
    }
    df[[cp$exercise_cols[i]]] <- ifelse(yes, "Yes", "No")
  }
  df
}

#' Convert clock-time text ("03:01:00", "3:01") to Excel's day fraction; other values unchanged
#'
#' Excel stores a time as a fraction of a day (03:01:00 = 0.1256944...). Some platforms or
#' package versions return such a cell as text, others as the number; this makes both agree.
excel_time_to_fraction <- function(x) {
  x <- as.character(x)
  m <- stringr::str_match(x, "^\\s*(\\d{1,2}):(\\d{2})(?::(\\d{2}))?\\s*$")
  hit <- !is.na(m[, 1])
  sec <- ifelse(is.na(m[, 4]), 0, as.numeric(m[, 4]))
  frac <- (as.numeric(m[, 2]) * 3600 + as.numeric(m[, 3]) * 60 + sec) / 86400
  x[hit] <- as.character(frac[hit])
  x
}

#' Lead grantee reference number: 5th "|"-separated element of the grid string
lead_grn_from_grid <- function(grid) {
  stringr::str_split(grid, "\\|") |> purrr::map_chr(~ stringr::str_trim(.x[5]))
}

#' Filter on the Country column (setting `filters: global_regional`)
#'
#' Used in three places: the GMS grants list, the CR clean-up and the PR clean-up.
#'
#' What each mode does to the rows:
#'   * `legacy`  (default, the behaviour of the old scripts): "Global" and "Regional" grants are
#'               KEPT. Only rows whose Country is empty (NA) are dropped. The old code wrote
#'               `Country != "Global" | Country != "Regional"`. A country cannot be both, so
#'               this is TRUE for every country, and the filter never removed Global or Regional.
#'   * `exclude` : "Global" and "Regional" grants are REMOVED. Rows with an empty Country are
#'               kept. This changes the numbers compared with `legacy`.
#'   * `keep`    : no filter at all: nothing is removed, also not the rows with an empty Country.
filter_global_regional <- function(df, mode = "legacy") {
  switch(mode,
    legacy  = dplyr::filter(df, Country != "Global" | Country != "Regional"),
    exclude = dplyr::filter(df, !Country %in% c("Global", "Regional")),
    keep    = df,
    stop("filters$global_regional must be legacy, exclude or keep.", call. = FALSE)
  )
}

#' Drop ActiveinYYYY columns older than (latest year - 1)
trim_active_columns <- function(df) {
  active_cols <- grep("^Activein\\d{4}$", names(df), value = TRUE)
  if (length(active_cols) == 0) return(df)
  latest <- max(as.numeric(stringr::str_extract(active_cols, "\\d{4}")), na.rm = TRUE)
  drop <- active_cols[as.numeric(stringr::str_extract(active_cols, "\\d{4}")) < latest - 1]
  dplyr::select(df, -dplyr::all_of(drop))
}
