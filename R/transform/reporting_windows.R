# Reporting windows ----
# Replaces load_reporting_windows.R (table processing part; extraction is generic now).

#' Build the reporting-window table
#'
#' @param raw_tables List of raw data frames from [tables_for()] (one per workbook; only
#'   the first table instance of each workbook is used, as in the legacy code).
#' @param grants_db Processed GMS export (from [gms_process()]).
build_reporting_windows <- function(raw_tables, grants_db) {
  # first table of each workbook, dropping empty ones
  tbls <- raw_tables |>
    purrr::keep(~ .x$table_index[1] == 1) |>
    purrr::map(~ dplyr::select(.x, -dplyr::any_of("table_index"))) |>
    purrr::keep(~ !(is.null(.x) || nrow(.x) == 0 || all(is.na(.x))))

  # Table variants differ (e.g. `grid` vs `ar_grid_2021`); bind_rows NA-fills.
  cleaned <- purrr::map_dfr(tbls, clean_promoted)

  # FileName = workbook the row came from (legacy derived it from a header-named column)
  df <- dplyr::mutate(cleaned, FileName = file_name)

  df <- df |>
    dplyr::filter(grepl("window", report_year, ignore.case = TRUE)) |>
    dplyr::filter(!is.na(reporting_period_up_to)) |>
    dplyr::filter(type_of_reporting != "Progress") |>
    dplyr::mutate(GRID = ifelse(is.na(ar_grid_2021), grid, ar_grid_2021)) |>
    dplyr::mutate(
      LeadGranteeGRN = stringr::str_split_fixed(GRID, " \\| ", 8)[, 5] |> stringr::str_trim(),
      LeadGranteeGRN = trimws(LeadGranteeGRN)) |>
    dplyr::left_join(grants_db, by = c("LeadGranteeGRN" = "GMGRN")) |>
    dplyr::rename(GMGRN = LeadGranteeGRN) |>
    dplyr::select(ProgrammeID, GMGRN, report_year, type_of_reporting, reporting_period_up_to,
                  Currentenddate, submission_deadline, m_e_review, education_team_review,
                  GRID, FileName) |>
    dplyr::mutate(
      reporting_period_up_to = as.Date(reporting_period_up_to, format = "%Y-%m-%d"),
      Currentenddate = as.Date(Currentenddate, format = "%Y-%m-%d")) |>
    dplyr::mutate(CheckDays = as.numeric(reporting_period_up_to - Currentenddate))

  csv_roundtrip(df)
}
