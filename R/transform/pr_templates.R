# PR source tables from the three reporting templates ----
# Replaces the processing part of load_pr_standard_indicators_template.R,
# load_pr_programme_template.R and load_pr_results_template.R. The extraction itself is
# generic now (see R/extract). Each builder returns one tidy table.

#' Common ending of every template builder: bind, tag and stamp
finish_pr_template <- function(df, tag, cp) {
  df |>
    dplyr::select(-dplyr::any_of("table_index")) |>   # extraction bookkeeping, not data
    dplyr::mutate(LeadGRN = lead_grn_from_grid(GRID)) |>
    blank_to_na() |>
    dplyr::mutate(source_of_data = paste0("ARR", cp$yy, " - ", tag),
                  ExportDate = cp$export_date) |>
    trace_step(paste0("PR template ", tag, ": rows after cleaning"))
}

#' Standard indicators
build_pr_standard_indicators <- function(raw_tables, cp) {
  cleaned <- purrr::map(raw_tables, clean_promoted)
  check_first_column(cleaned, "level", "PR standard indicators")
  cleaned <- purrr::map(cleaned, standardise_columns, grid_from = "ar_grid_2021")
  check_headers_consistency(cleaned, "PR standard indicators")
  finish_pr_template(dplyr::bind_rows(cleaned), "SI", cp)
}

#' Programme results template
build_pr_programme <- function(raw_tables, cp) {
  cleaned <- purrr::map(raw_tables, clean_promoted)
  check_first_column(cleaned, "outcome_output_numbering", "PR programme")
  cleaned <- purrr::map(cleaned, standardise_columns, grid_from = c("ar_grid_2021", "grid"))
  check_headers_consistency(cleaned, "PR programme")
  finish_pr_template(dplyr::bind_rows(cleaned), "PT", cp)
}

#' Results template
#'
#' This template repeats some column labels (e.g. the RW "Comments" fields appear both as
#' the metric's own comment and next to the disability breakdown); `make_clean_names()`
#' disambiguates the second occurrence with a `_2` suffix, which the repairs below rely on.
build_pr_results <- function(raw_tables, cp) {
  cleaned <- purrr::map(raw_tables, clean_promoted)
  check_first_column(cleaned, "outcome_output_numbering", "PR results")

  cleaned <- purrr::map(cleaned, standardise_columns, grid_from = "ar_grid_2021")
  check_headers_consistency(cleaned, "PR results")

  # the template is messy: give every table the union of all columns
  all_columns <- sort(unique(unlist(purrr::map(cleaned, names))))
  patched <- purrr::map(cleaned, add_missing_columns, all_columns = all_columns)
  df <- dplyr::bind_rows(patched)

  df <- df |>
    dplyr::mutate(source_of_verification = ifelse(!is.na(source_of_verification),
                                                  paste0(source_of_verification, "|", means_of_verification),
                                                  means_of_verification)) |>
    dplyr::select(-means_of_verification) |>
    dplyr::rename(ecw_analysis_code = ecw_anaysis_code) |>
    dplyr::select(-analysis_code) |>
    dplyr::mutate(
      comments_rw1 = paste0(comments_rw1, " | ", comments_rw1_2),
      comments_rw2 = paste0(comments_rw2, " | ", comments_rw2_2),
      comments_rw3 = paste0(comments_rw3, " | ", comments_rw3_2),
      comments_rw4 = paste0(comments_rw4, " | ", comments_rw4_2),
      comments_rw5 = paste0(comments_rw5, " | ", comments_rw5_2),
      comments_rw6 = paste0(comments_rw6, " | ", comments_rw6_2),
      comments_baseline = paste0(comments_baseline, " | ", baseline_comments),
      comments_target = paste0(comments_target, " | ", target_comments)) |>
    dplyr::select(-c(comments_rw1_2, comments_rw2_2, comments_rw3_2, comments_rw4_2,
                     comments_rw5_2, comments_rw6_2, baseline_comments, target_comments))

  finish_pr_template(df, "RT", cp)
}
