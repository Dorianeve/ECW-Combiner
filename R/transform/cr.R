# CR combiner (children reached) ----
# Replaces: load_cr_template.R (processing), 01_cr_joins.R, 02_cr_processing_previous_combiner.R,
#           03_cr_pivoting.R.
# Every function takes data frames and returns a data frame; file I/O lives in the pipeline.

# 1. Source data from the workbooks ----

#' Turn the raw children-table sheets into one tidy table
#'
#' @param raw_tables List of raw data frames ([tables_for()] with key "children").
build_cr_source <- function(raw_tables, cp) {
  cleaned <- purrr::map(raw_tables, clean_promoted) |>
    trace_step("CR source: rows in the children tables of all workbooks")
  check_first_column(cleaned, "type_of_education", "CR")

  cleaned <- purrr::map(cleaned, standardise_columns)
  check_headers_consistency(cleaned, "CR tables")

  df <- dplyr::bind_rows(cleaned) |>
    dplyr::filter(type_of_education %in% c("Formal education", "Non-formal education")) |>
    trace_step("CR source: after keeping formal / non-formal education") |>
    dplyr::filter(!is.na(grn)) |>          # rows with no GRN come from the longer templates
    trace_step("CR source: after dropping rows without a GRN") |>
    blank_to_na() |>
    dplyr::mutate(LeadGRN = lead_grn_from_grid(GRID),
                  source_of_data = paste0("ARR", cp$yy, " - CR"),
                  ExportDate = cp$export_date)
  df
}

# 2. Join with GMS and reporting windows ----

#' Join CR to GMS (by GRN) and to the latest reporting window per programme
cr_join <- function(cr, grants_db, rw, cp) {
  cr <- cr |>
    dplyr::mutate(grn = dplyr::case_when(grantee == "Mutiple Grantees" ~ LeadGRN, TRUE ~ grn)) |>
    dplyr::mutate(grn = trimws(grn))
  grants_db <- dplyr::mutate(grants_db, GMGRN = trimws(GMGRN))

  cr <- cr |>
    dplyr::left_join(grants_db, by = c("grn" = "GMGRN")) |>
    trace_step("CR join: after joining the GMS (should not add rows)") |>
    dplyr::mutate(GMGRN = grn,
                  covid_19_related_report = dplyr::if_else(stringr::str_detect(file_name, "Covid"), "Yes", "No"),
                  covid_flag = ifelse(grepl("covid", file_name, ignore.case = TRUE), "Yes", "No"))

  rw_unique <- rw |>
    dplyr::mutate(covid_flag = ifelse(grepl("covid", FileName, ignore.case = TRUE), "Yes", "No")) |>
    dplyr::select(ProgrammeID, reporting_period_up_to, report_year, m_e_review, covid_flag) |>
    dplyr::filter(reporting_period_up_to < cp$cutoff_date) |>
    dplyr::arrange(dplyr::desc(reporting_period_up_to)) |>
    dplyr::group_by(ProgrammeID, covid_flag) |>
    dplyr::slice(1) |>
    dplyr::ungroup()

  cr |>
    dplyr::left_join(rw_unique, by = c("ProgrammeID", "covid_flag")) |>
    trace_step("CR join: after joining the reporting windows (should not add rows)") |>
    dplyr::select(
      ProgrammeID, LeadGRN, GMGRN, Reportingrole, Granteeorganization, Country, Typeofinvestment,
      Startdate, Enddate, Currentenddate, type_of_education, indicator, type_of_beneficiary,
      pre_primary_targeted_female, pre_primary_targeted_male, primary_targeted_female,
      primary_targeted_male, secondary_targeted_female, secondary_targeted_male,
      unknown_level_of_education_targeted_female, unknown_level_of_education_targeted_male,
      total_female_targeted, total_male_targeted, total_beneficiaries_targeted,
      pre_primary_reached_female, pre_primary_reached_male, primary_reached_female,
      primary_reached_male, secondary_reached_female, secondary_reached_male,
      unknown_level_of_education_reached_female, unknown_level_of_education_reached_male,
      total_female_reached, total_male_reached, total_beneficiaries_reached,
      comments_and_context, reporting_stage, date_of_reporting, GRID, tab, grn_reference,
      grantee_reference, target_line_reference, reached_line_reference, comments_line_reference,
      file_name, Covid.19related, covid_19_related_report, reporting_period_up_to, report_year,
      m_e_review, dplyr::all_of(cp$old_active_year), dplyr::all_of(cp$active_year),
      ActiveStrategicPlan, Excomapprovaldate, ExportDate)
}

# 3. Previous-year combiner ----

#' Prepare last year's combiner: refresh GMS fields and carry inactive grants forward
#'
#' Grants no longer active (or active with Covid data, reported in another template) keep
#' their cumulative data, which is duplicated as the current-year cumulative exercise.
cr_prepare_previous <- function(old, grants_db, cp) {
  db <- dplyr::select(grants_db, GMGRN, ProgrammeID, dplyr::all_of(cp$active_year),
                      ActiveStrategicPlan, Reportingrole)

  # older combiners stored this file-name-derived column as "Covid19related"
  if (!"Covid19relateddata" %in% names(old)) {
    old <- dplyr::rename(old, dplyr::any_of(c(Covid19relateddata = "Covid19related")))
  }

  old <- old |>
    dplyr::mutate(GMGRN = ifelse(GMGRN == "Mutiple Grantees", LeadGRN, GMGRN)) |>
    dplyr::mutate(GMGRN = ifelse(GMGRN == "N/A", LeadGRN, GMGRN)) |>
    dplyr::select(-dplyr::any_of(c("ActiveStrategicPlan", "Reportingrole"))) |>
    dplyr::left_join(db, by = c("ProgrammeID", "GMGRN")) |>
    dplyr::mutate(!!cp$active_year := ifelse(is.na(.data[[cp$active_year]]), "No", .data[[cp$active_year]]))

  carried <- old |>
    dplyr::filter(Exercise == cp$old_exercise_cumulative) |>
    dplyr::filter(.data[[cp$active_year]] == "No" |
                    (.data[[cp$active_year]] == "Yes" & Covid19relateddata == "Covid-19 related data")) |>
    dplyr::mutate(Exercise = cp$exercise_cumulative)

  df <- if (cp$carry_over_inactive) rbind(old, carried) else old
  df <- trace_step(df, "CR previous: last cycle's rows + carried-over inactive grants")
  df$Number <- as.numeric(gsub(",", "", df$Number))

  df |>
    dplyr::filter(Covid19relateddata == "Non-Covid-19 related data" |
                    (Covid19relateddata == "Covid-19 related data" &
                       grepl("cumulative", Exercise, ignore.case = TRUE))) |>
    trace_step("CR previous: after dropping Covid-19 rows that are not cumulative") |>
    trim_active_columns()
}

# 4. Pivot to long format ----

CR_VALUE_COLS <- c(
  "pre_primary_targeted_female", "pre_primary_targeted_male", "pre_primary_targeted_total",
  "primary_targeted_female", "primary_targeted_male", "primary_targeted_total",
  "secondary_targeted_female", "secondary_targeted_male", "secondary_targeted_total",
  "unknown_level_of_education_targeted_female", "unknown_level_of_education_targeted_male",
  "unknown_level_of_education_targeted_total",
  "total_female_targeted", "total_male_targeted", "total_beneficiaries_targeted",
  "pre_primary_reached_female", "pre_primary_reached_male", "pre_primary_reached_total",
  "primary_reached_female", "primary_reached_male", "primary_reached_total",
  "secondary_reached_female", "secondary_reached_male", "secondary_reached_total",
  "unknown_level_of_education_reached_female", "unknown_level_of_education_reached_male",
  "unknown_level_of_education_reached_total",
  "total_female_reached", "total_male_reached", "total_beneficiaries_reached")

#' Pivot the wide CR table to one row per indicator x gender x status x education level
cr_pivot_long <- function(df) {
  levels <- c("pre_primary", "primary", "secondary", "unknown_level_of_education")
  parts <- c("targeted", "reached")
  sex_cols <- unlist(lapply(levels, function(l) unlist(lapply(parts, function(p)
    paste0(l, "_", p, c("_female", "_male"))))))

  # A dash means "nothing to report": it becomes empty. Any other text would give a warning.
  dash_to_na <- function(x) { x <- as.character(x); x[!is.na(x) & trimws(x) %in% c("-", "\u2013", "\u2014")] <- NA; as.numeric(x) }
  df <- df |>
    dplyr::mutate(dplyr::across(dplyr::all_of(sex_cols), dash_to_na))
  for (l in levels) for (p in parts) {
    df[[paste0(l, "_", p, "_total")]] <- df[[paste0(l, "_", p, "_female")]] + df[[paste0(l, "_", p, "_male")]]
  }

  df |>
    dplyr::mutate(dplyr::across(dplyr::all_of(CR_VALUE_COLS), ~ suppressWarnings(as.numeric(.x)))) |>
    tidyr::pivot_longer(cols = dplyr::all_of(CR_VALUE_COLS), names_to = "Attribute", values_to = "Number") |>
    trace_step("CR pivot: rows after pivoting to long format") |>
    dplyr::mutate(
      Gender = dplyr::case_when(
        stringr::str_detect(Attribute, "female") ~ "Female",
        stringr::str_detect(Attribute, "male") ~ "Male",
        stringr::str_detect(Attribute, "total") ~ "Total",
        TRUE ~ "Error"),
      Status = dplyr::case_when(
        stringr::str_detect(Attribute, "targeted") ~ "Targeted",
        stringr::str_detect(Attribute, "reached") ~ "Reached",
        TRUE ~ "Error"),
      level_of_education = dplyr::case_when(
        stringr::str_detect(Attribute, "pre_primary") ~ "Pre-primary",
        stringr::str_detect(Attribute, "primary") ~ "Primary",
        stringr::str_detect(Attribute, "secondary") ~ "Secondary",
        stringr::str_detect(Attribute, "unknown_level_of_education") ~ "Unknown level of education",
        stringr::str_detect(Attribute, "total") ~ "Total",
        TRUE ~ "Error"))
}

#' Rename, recode and filter the long CR table (current-year "root" combiner)
cr_clean_root <- function(long, cp) {
  clean <- long |>
    dplyr::rename(Covid19relateddata = covid_19_related_report, Typeofreporting = reporting_stage) |>
    dplyr::mutate(
      Covid19relateddata = ifelse(Covid19relateddata == "No", "Non-Covid-19 related data", "Covid-19 related data"),
      Sourceofdata = paste0("ARR", cp$yy, " CR"),
      type_of_beneficiary = dplyr::case_when(
        grepl("other", type_of_beneficiary, ignore.case = TRUE) ~ "Other affected populations",
        grepl("total", type_of_beneficiary, ignore.case = TRUE) ~ "Total",
        grepl("unknown", type_of_beneficiary, ignore.case = TRUE) ~ "Type of beneficiary unknown",
        TRUE ~ type_of_beneficiary),
      Typeofreporting = dplyr::case_when(
        grepl("individual", Typeofreporting, ignore.case = TRUE) ~ "Individual",
        grepl("joint", Typeofreporting, ignore.case = TRUE) ~ "Joint",
        TRUE ~ NA)) |>
    dplyr::rename(Typeofeducation = type_of_education, Indicator = indicator,
                  Levelofeducation = level_of_education, Typeofbeneficiary = type_of_beneficiary,
                  Commentsandcontext = comments_and_context, Dateofreporting = date_of_reporting,
                  ReportingWindow = report_year, ReportingPeriodUpTo = reporting_period_up_to,
                  MnEReview = m_e_review, Covid19relatedgrant = Covid.19related,
                  Filename = file_name) |>
    dplyr::select(
      ProgrammeID, LeadGRN, GMGRN, Reportingrole, Granteeorganization, Country, Typeofinvestment,
      Startdate, Currentenddate, Excomapprovaldate, Covid19relatedgrant, Covid19relateddata,
      Typeofreporting, Typeofeducation, Indicator, Status, Typeofbeneficiary, Levelofeducation,
      Gender, Number, Commentsandcontext, Dateofreporting, Sourceofdata, GRID, Filename,
      MnEReview, ReportingWindow, ReportingPeriodUpTo, dplyr::all_of(cp$old_active_year),
      dplyr::all_of(cp$active_year), ActiveStrategicPlan, ExportDate)

  clean |>
    dplyr::filter(.data[[cp$active_year]] == "Yes") |>
    trace_step(paste0("CR clean: after keeping grants with ", cp$active_year, " = Yes")) |>
    dplyr::filter(Typeofinvestment != "AF") |>
    trace_step("CR clean: after dropping investment type AF") |>
    filter_global_regional(cp$global_regional) |>
    trace_step("CR clean: after the Global/Regional filter")
}

#' Duplicate the current-year table as Annual and Cumulative exercises and append history
#'
#' @param historical Output of [cr_prepare_previous()].
cr_finalise <- function(root, historical, cp) {
  out <- root |>
    dplyr::filter(if (cp$apply_mne_filter) MnEReview == "Approved" else TRUE) |>
    trace_step("CR final: after the approval filter")
  out <- add_exercise_flags(out, out$ReportingPeriodUpTo, cp)

  out <- out |>
    tidyr::pivot_longer(cols = dplyr::all_of(cp$exercise_cols), names_to = "Exercise", values_to = "Value") |>
    dplyr::filter(Value == "Yes") |>
    dplyr::mutate(Exercise = dplyr::case_when(
      grepl("cumulative", Exercise, ignore.case = TRUE) ~ cp$exercise_cumulative,
      grepl("annual", Exercise, ignore.case = TRUE) ~ cp$exercise_annual,
      TRUE ~ Exercise)) |>
    dplyr::select(-Value) |>
    trace_step("CR final: current-cycle rows x exercises")

  dplyr::bind_rows(out, historical) |>
    trace_step("CR final: after appending the history")
}

# 5. Whole CR flow ----

#' Run the complete CR flow in memory
#'
#' `csv_roundtrip()` calls sit exactly where the legacy scripts read a CSV (parity scaffold).
#'
#' @param raw_children Raw children tables ([tables_for()] with key "children").
#' @param grants_db Output of [gms_process()] (profile "arr").
#' @param rw Output of [build_reporting_windows()].
#' @param old Last year's CR combiner (data frame read from the previous output).
#' @return list(root = current-year long table, combiner = final CR combiner).
run_cr <- function(raw_children, grants_db, rw, old, cp) {
  source_data <- csv_roundtrip(build_cr_source(raw_children, cp))
  joined <- csv_roundtrip(cr_join(source_data, grants_db, rw, cp))
  root <- cr_clean_root(cr_pivot_long(joined), cp)
  historical <- csv_roundtrip(cr_prepare_previous(old, grants_db, cp))
  list(root = root, combiner = cr_finalise(root, historical, cp))
}
