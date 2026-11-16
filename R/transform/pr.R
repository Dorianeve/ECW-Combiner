# PR combiner (programme results) ----
# Replaces: pr_processing_previous_combiner.R, pr_merge.R, pr_pivoting.R,
#           pr_cleaning_outputting.R (and the PR template merge logic).

# 1. Previous-year combiner ----

#' Prepare last year's PR combiner: refresh GMS fields and carry inactive grants forward
pr_prepare_previous <- function(old, grants_db, cp) {
  db <- dplyr::select(grants_db, GMGRN, ProgrammeID, dplyr::all_of(cp$active_year),
                      ActiveStrategicPlan, Reportingrole)

  # active flags are rebuilt from GMS: drop every ActiveinYYYY except the current one
  drop_active <- grep("^Activein\\d{4}$", names(old), value = TRUE)
  drop_active <- setdiff(drop_active, cp$active_year)

  old <- old |>
    dplyr::select(-dplyr::any_of(c("ActiveStrategicPlan", "Reportingrole")), -dplyr::all_of(drop_active)) |>
    dplyr::mutate(GMGRN = ifelse(GMGRN == "Mutiple Grantees", LeadGRN, GMGRN),
                  LeadGRN = trimws(LeadGRN)) |>
    dplyr::left_join(db, by = c("LeadGRN" = "GMGRN", "ProgrammeID" = "ProgrammeID")) |>
    dplyr::mutate(!!cp$active_year := ifelse(is.na(.data[[cp$active_year]]), "No", .data[[cp$active_year]]))

  # unlike CR's Covid19relateddata, PR's Covid19related is the raw GMS flag (No/Round 1/Round 2/NA
  # in current combiners; some older combiners instead stored CR-style recoded text here)
  if (!"Covid19related" %in% names(old)) old$Covid19related <- NA_character_
  carried <- old |>
    dplyr::filter(Exercise == cp$old_exercise_cumulative) |>
    dplyr::filter(.data[[cp$active_year]] == "No" |
                    (.data[[cp$active_year]] == "Yes" &
                       !is.na(Covid19related) &
                       !Covid19related %in% c("No", "Non-Covid-19 related data"))) |>
    dplyr::mutate(Exercise = cp$exercise_cumulative)

  df <- if (cp$carry_over_inactive) rbind(old, carried) else old
  df <- trace_step(df, "PR previous: last cycle's rows + carried-over inactive grants")
  df$Value <- as.numeric(gsub(",", "", df$Value))
  trim_active_columns(df)
}

# 2. Merge the three templates ----

#' Column rename map (new name -> old name) from the correspondence table
pr_rename_map <- function(cols, from, to) {
  cols |>
    dplyr::filter(!is.na(.data[[to]])) |>
    dplyr::select(dplyr::all_of(c(from, to))) |>
    tibble::deframe() |>
    (\(x) stats::setNames(names(x), x))()
}

#' Merge programme, results and standard-indicator tables and add GMS and reporting windows
#'
#' @param cols Correspondence table (reference/pr_columns.csv).
#' @param order_tbl Column order table (reference/pr_columns_order.csv).
pr_merge_templates <- function(rt, pr, si, cols, order_tbl, grants_db, rw, cp) {
  cols <- cols |>
    dplyr::mutate(RevisedResults = ifelse(RevisedResults == "", NA, RevisedResults),
                  RevisedIndicators = ifelse(RevisedIndicators == "", NA, RevisedIndicators),
                  RevisedProgramme = ifelse(RevisedProgramme == "", NA, RevisedProgramme))
  cols[] <- lapply(cols, function(x) if (is.character(x)) trimws(x) else x)

  safe_rename <- function(df, mapping) if (length(mapping) > 0) dplyr::rename(df, dplyr::any_of(mapping)) else df
  pr <- safe_rename(pr, pr_rename_map(cols, "Programme", "RevisedProgramme"))
  rt <- safe_rename(rt, pr_rename_map(cols, "Results", "RevisedResults"))
  si <- safe_rename(si, pr_rename_map(cols, "Indicators", "RevisedIndicators"))

  # align columns, everything as character, tag the template of origin
  df_list <- list(Programme = pr, Results = rt, SI = si)
  all_columns <- Reduce(union, lapply(df_list, names))
  aligned <- Map(function(df, source) {
    df <- add_missing_columns(df, all_columns)
    df[] <- lapply(df, as.character)
    df$source <- source
    df
  }, df_list, names(df_list))

  df <- dplyr::bind_rows(aligned) |>
    trace_step("PR merge: rows of the programme, results and standard-indicator templates stacked")
  df[df == "NA"] <- NA

  # column order (legacy reads the order table's `Results` column)
  wanted <- order_tbl$Results
  existing_order <- wanted[wanted %in% names(df)]
  df <- dplyr::select(df, dplyr::all_of(c(existing_order, setdiff(names(df), existing_order))))

  # GMS
  grants_sel <- grants_db |>
    dplyr::select(GMGRN, Granteeorganization, Country, ProgrammeID, Typeofinvestment, Reportingrole,
                  Startdate, Currentenddate, dplyr::all_of(cp$old_active_year),
                  dplyr::all_of(cp$active_year), ActiveStrategicPlan, Covid.19related) |>
    dplyr::mutate(GMGRN = trimws(GMGRN))

  df <- df |>
    dplyr::mutate(LeadGRN = trimws(LeadGRN)) |>
    dplyr::left_join(grants_sel, by = c("LeadGRN" = "GMGRN")) |>
    trace_step("PR merge: after joining the GMS (should not add rows)") |>
    dplyr::mutate(covid_19_related_report = dplyr::if_else(stringr::str_detect(file_name, "Covid"), "Yes", "No"))

  # latest reporting window per programme (a programme can have Covid and non-Covid reports)
  rw_unique <- rw |>
    dplyr::mutate(covid_flag = ifelse(grepl("covid", FileName, ignore.case = TRUE), "Yes", "No")) |>
    dplyr::select(ProgrammeID, reporting_period_up_to, report_year, m_e_review, covid_flag) |>
    dplyr::filter(reporting_period_up_to < cp$cutoff_date) |>
    dplyr::arrange(dplyr::desc(reporting_period_up_to)) |>
    dplyr::group_by(ProgrammeID, covid_flag) |>
    dplyr::slice(1) |>
    dplyr::ungroup()

  df |>
    dplyr::mutate(covid_flag = ifelse(grepl("covid", file_name, ignore.case = TRUE), "Yes", "No")) |>
    dplyr::left_join(rw_unique, by = c("ProgrammeID", "covid_flag")) |>
    trace_step("PR merge: after joining the reporting windows (should not add rows)") |>
    dplyr::rename(MnEReview = m_e_review) |>
    dplyr::filter(!(grepl("additional results", result_statement, ignore.case = TRUE) |
                      grepl("additional indicators", result_statement, ignore.case = TRUE))) |>
    trace_step("PR merge: after dropping 'additional results/indicators' rows")
}

# 3. Pivot to long format ----

PR_ID_KEYS <- c("LeadGRN", "result_statement", "outcome_output_numbering", "analysis_code",
                "source_of_data", "indicator", "grantees_own_program_specific_indicator")

#' Pivot the baseline/target/reporting-window columns to long format
pr_pivot_long <- function(df, cp) {
  df[] <- lapply(df, as.character)
  pivot_cols <- names(df)[stringr::str_detect(names(df), "_(baseline|target|revised_target|rw[1-9])$")]

  # Time-formatted cells: depending on the platform / package version they arrive as "03:01:00"
  # or as the Excel number (fraction of a day). Always use the number, as the legacy output does.
  value_cols <- pivot_cols[!stringr::str_detect(pivot_cols, "comments")]
  df[value_cols] <- lapply(df[value_cols], excel_time_to_fraction)

  df <- df |>
    dplyr::mutate(unit_of_measurement = trimws(unit_of_measurement)) |>
    dplyr::mutate(unit_of_measurement = stringr::str_to_title(unit_of_measurement)) |>
    dplyr::mutate(unit_of_measurement = dplyr::case_when(
      grepl("Us\\$", unit_of_measurement, ignore.case = TRUE) ~ "US$",
      grepl("Number", unit_of_measurement, ignore.case = TRUE) ~ "Number #",
      grepl("Percentage", unit_of_measurement, ignore.case = TRUE) ~ "Percentage %",
      grepl("Ratio", unit_of_measurement, ignore.case = TRUE) ~ "Ratio",
      grepl("Scale", unit_of_measurement, ignore.case = TRUE) ~ "Scale",
      grepl("Yes", unit_of_measurement, ignore.case = TRUE) ~ "Yes/No",
      TRUE ~ unit_of_measurement))

  df_long <- tidyr::pivot_longer(df, cols = dplyr::all_of(pivot_cols), names_to = "Attribute", values_to = "Value") |>
    trace_step("PR pivot: rows after pivoting to long format")

  # split "<core>_<suffix>" (suffix = baseline / target / rwN ...), longest suffix first
  suffixes <- c("revised_target", "revised", "baseline", "target", paste0("rw", 1:9))
  suffix_pattern <- paste0("(", paste0(suffixes, collapse = "|"), ")$")

  df_split <- df_long |>
    dplyr::mutate(
      Attribute_2 = stringr::str_extract(Attribute, suffix_pattern),
      Attribute_1 = ifelse(!is.na(Attribute_2),
                           stringr::str_remove(Attribute, paste0("_", Attribute_2, "$")),
                           Attribute)) |>
    dplyr::mutate(Attribute_1 = dplyr::case_when(
      grepl("year_of", Attribute_1, ignore.case = TRUE) ~ "Year",
      grepl("total", Attribute_1, ignore.case = TRUE) ~ "Total",
      grepl("female", Attribute_1, ignore.case = TRUE) ~ "Female",
      grepl("male", Attribute_1, ignore.case = TRUE) ~ "Male",
      grepl("other_levels_of_disaggregation", Attribute_1, ignore.case = TRUE) ~ "OtherLevelsOfDisaggregation",
      grepl("children_with_disabilities", Attribute_1, ignore.case = TRUE) ~ "ChildrenWithDisabilities",
      grepl("adapted_accessible", Attribute_1, ignore.case = TRUE) ~ "AdaptedAccessible",
      grepl("comments", Attribute_1, ignore.case = TRUE) ~ "Comments",
      grepl("report_end_date", Attribute_1, ignore.case = TRUE) ~ "ReportEndDate",
      TRUE ~ NA_character_)) |>
    dplyr::mutate(Attribute_2 = stringr::str_to_sentence(Attribute_2))

  keys_rw <- c(PR_ID_KEYS[1:3], "ReportingWindow", PR_ID_KEYS[4:7])
  join_by <- c("LeadGRN", "result_statement", "outcome_output_numbering", "ReportingWindow",
               "analysis_code", "source_of_data", "indicator", "grantees_own_program_specific_indicator")
  key_cols <- c("LeadGRN", "Attribute_2", "Attribute_1", "analysis_code", "result_statement",
                "outcome_output_numbering", "indicator", "grantees_own_program_specific_indicator",
                "Value", "source_of_data")

  df_gender <- df_split |>
    dplyr::filter(Attribute_1 %in% c("Total", "Female", "Male")) |>
    dplyr::rename(Gender = Attribute_1, ReportingWindow = Attribute_2) |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c(PR_ID_KEYS[1:3], "ReportingWindow", "Gender", PR_ID_KEYS[4:7]))),
                    .keep_all = TRUE)

  one_attribute <- function(attribute, new_name) {
    out <- df_split |>
      dplyr::select(dplyr::all_of(key_cols)) |>
      dplyr::filter(Attribute_1 %in% attribute) |>
      dplyr::rename(!!new_name := Value, ReportingWindow = Attribute_2)
    if (new_name != "ReportEndDate") out <- dplyr::select(out, -Attribute_1)
    dplyr::distinct(out, dplyr::across(dplyr::all_of(c(PR_ID_KEYS[1:3], "ReportingWindow", new_name, PR_ID_KEYS[4:7]))),
                    .keep_all = TRUE)
  }
  df_dates <- one_attribute("ReportEndDate", "ReportEndDate")
  df_comments <- one_attribute("Comments", "Comments")
  df_year <- one_attribute("Year", "Year")

  df_disagg <- df_split |>
    dplyr::select(dplyr::all_of(key_cols)) |>
    dplyr::filter(Attribute_1 %in% c("ChildrenWithDisabilities", "AdaptedAccessible", "OtherLevelsOfDisaggregation")) |>
    tidyr::pivot_wider(names_from = Attribute_1, values_from = Value,
                       values_fn = ~ dplyr::first(stats::na.omit(.))) |>
    dplyr::rename(ReportingWindow = Attribute_2) |>
    dplyr::mutate(
      ChildrenWithDisabilities = stringr::str_trim(stringr::str_to_lower(as.character(ChildrenWithDisabilities))),
      AdaptedAccessible = stringr::str_trim(stringr::str_to_lower(as.character(AdaptedAccessible)))) |>
    dplyr::mutate(ChildrenWithDisabilities = dplyr::if_else(
      is.na(ChildrenWithDisabilities) | ChildrenWithDisabilities %in% c("n/a", "no data", "", "na"),
      AdaptedAccessible, ChildrenWithDisabilities)) |>
    dplyr::select(LeadGRN, ReportingWindow, OtherLevelsOfDisaggregation, ChildrenWithDisabilities,
                  result_statement, outcome_output_numbering, analysis_code, indicator,
                  grantees_own_program_specific_indicator, source_of_data) |>
    dplyr::distinct(dplyr::across(dplyr::all_of(c(PR_ID_KEYS[1:3], "ReportingWindow", PR_ID_KEYS[4:7]))),
                    .keep_all = TRUE)

  df_final <- df_gender |>
    dplyr::left_join(df_disagg, by = join_by) |>
    dplyr::left_join(df_dates, by = join_by) |>
    dplyr::left_join(df_comments, by = join_by) |>
    dplyr::left_join(df_year, by = join_by) |>
    trace_step("PR pivot: gender rows with disaggregation, dates, comments and year joined")

  df_final <- df_final |>
    dplyr::mutate(Value = ifelse(Value == "NULL", NA, Value)) |>
    dplyr::filter(!is.na(analysis_code) | !is.na(Value) |
                    !is.na(ChildrenWithDisabilities) | !is.na(OtherLevelsOfDisaggregation)) |>
    trace_step("PR pivot: after dropping rows with no code, value or disaggregation") |>
    dplyr::mutate(level = ifelse(is.na(level), level_outcome_output, level)) |>
    dplyr::select(-level_outcome_output) |>
    dplyr::filter(!grepl("Data in this row is not needed", indicator_data_status, ignore.case = TRUE)) |>
    trace_step("PR pivot: after dropping rows marked 'data not needed'")

  # standard indicators: drop groups where every value is empty
  df_final <- df_final |>
    dplyr::group_by(LeadGRN, analysis_code, source) |>
    dplyr::filter(!(all(source == "SI") & all(is.na(Value)))) |>
    dplyr::ungroup() |>
    trace_step("PR pivot: after dropping standard-indicator groups without values")

  pr_rename_and_order(df_final, cp)
}

#' Friendly column names and column order of the long PR table
pr_rename_and_order <- function(df, cp) {
  rename_map <- c(
    OutcomeOutputNumbering = "outcome_output_numbering", ReportingWindow = "Attribute_2",
    Level = "level", ResultStatement = "result_statement", Indicator = "indicator",
    GeneralComments = "comments", CurrentEndDate = "Currentenddate",
    DetailedComments = "notes_on_result_indicator",
    AlignmentWithHRPIndicators = "alignment_with_hrp_rrp_tep_esp_indicators",
    ProgramSpecificIndicator = "grantees_own_program_specific_indicator",
    DateIndicatorProposed = "date_indicator_is_proposed", ECWComments = "ecw_m_e_comments",
    GranteeResponseToMEComment = "grantee_response_to_m_e_comment",
    ContributingAgencies = "contributing_agencies", UnitOfMeasurement = "unit_of_measurement",
    SourceOfVerification = "source_of_verification", DataAvailability = "data_availability",
    DuplicatedIndicator = "duplicated_indicator", IndicatorAdmin = "indicator_admin",
    IndicatorApplicability = "indicator_applicability", DisaggregatedBySex = "disaggregated_by_sex",
    IndicatorType = "indicator_type", AnalysisCode = "analysis_code", GRID = "GRID",
    FileName = "file_name", LevelOutcomeOutput = "level_outcome_output",
    SourceOfData = "source_of_data", ReportingRole = "ReportingRole", Covid19related = "Covid.19related")
  df <- dplyr::rename(df, !!!rename_map[rename_map %in% names(df)])

  ordered_columns <- c(
    "ProgrammeID", "LeadGRN", "GMGRN", "ReportingRole", "Typeofinvestment", "Country",
    "Granteeorganization", "StartDate", "CurrentEndDate", "Covid.19Related", "GeneralComments",
    "OutcomeOutputNumbering", "Level", "ResultStatement", "Indicator", "ProgramSpecificIndicator",
    "IndicatorAndPSIMerged", "ECWComments", "GranteeResponseToMEComment", "AlignmentWithHRPIndicators",
    "ContributingAgencies", "DateIndicatorProposed", "UnitOfMeasurement", "SourceOfVerification",
    "ReportingWindow", "Year", "ReportEndDate", "Gender", "Value", "ChildrenWithDisabilities",
    "OtherLevelsOfDisaggregation", "Comments", "AnalysisCode", "Attribute",
    "ecw_standard_indicator_select_from_dropdown_or_select_other_program_specific_indicator_and_add_it",
    "IndicatorApplicability", "DisaggregatedBySex", "IndicatorAdmin", "DuplicatedIndicator",
    "DataAvailability", "LinkageToECWResult", "Exercise", "SourceOfData",
    cp$old_active_year, cp$active_year, "OmitForBeneficiaryAnalysis", "OmitForEducationLevelAnalysis",
    "MnEReview", "GRID", "FileName", "ExportDate")
  matched <- ordered_columns[ordered_columns %in% names(df)]
  df[, c(matched, setdiff(names(df), matched))]
}

# 4. Current-year combiner and history ----

#' Filter the long table, add the Annual and Cumulative exercises
pr_current_year <- function(clean, cp) {
  clean <- clean |>
    dplyr::filter(.data[[cp$active_year]] == "Yes") |>
    trace_step(paste0("PR current: after keeping grants with ", cp$active_year, " = Yes")) |>
    dplyr::filter(Typeofinvestment != "AF") |>
    trace_step("PR current: after dropping investment type AF") |>
    filter_global_regional(cp$global_regional) |>
    trace_step("PR current: after the Global/Regional filter") |>
    dplyr::filter(if (cp$apply_mne_filter) MnEReview == "Approved" else TRUE) |>
    trace_step("PR current: after the approval filter")

  clean <- add_exercise_flags(clean, clean$reporting_period_up_to, cp)
  clean |>
    tidyr::pivot_longer(cols = dplyr::all_of(cp$exercise_cols), names_to = "Exercise", values_to = "ValueExer") |>
    dplyr::filter(ValueExer == "Yes") |>
    dplyr::mutate(Exercise = dplyr::case_when(
      grepl("cumulative", Exercise, ignore.case = TRUE) ~ cp$exercise_cumulative,
      grepl("annual", Exercise, ignore.case = TRUE) ~ cp$exercise_annual,
      TRUE ~ Exercise)) |>
    dplyr::select(-c(ValueExer, Attribute)) |>
    unique() |>
    trace_step("PR current: current-cycle rows x exercises (duplicates removed)")
}

#' Append last year's combiner after harmonising its column names
#'
#' @param names_tbl Old/new column name table (reference/pr_old_new_names.csv).
pr_bind_history <- function(clean, old_combiner, names_tbl) {
  rename_vector <- stats::setNames(names_tbl$clean, names_tbl$old_combiner)
  names(old_combiner) <- ifelse(names(old_combiner) %in% names(rename_vector),
                                rename_vector[names(old_combiner)], names(old_combiner))

  old_combiner[setdiff(names(clean), names(old_combiner))] <- NA
  clean[setdiff(names(old_combiner), names(clean))] <- NA
  old_combiner <- old_combiner[, names(clean)]

  dplyr::bind_rows(dplyr::mutate(clean, dplyr::across(dplyr::everything(), as.character)),
                   dplyr::mutate(old_combiner, dplyr::across(dplyr::everything(), as.character))) |>
    trace_step("PR final: after appending the history")
}

# 5. Final clean-up (dates, codes, units) ----

pr_final_clean <- function(df) {
  excel_or_iso <- function(x, us_style = FALSE) {
    x <- as.character(x)
    out <- as.Date(rep(NA_character_, length(x)))
    serial <- grepl("^[0-9]+$", x)
    out[serial & !is.na(x)] <- as.Date(as.numeric(x[serial & !is.na(x)]), origin = "1899-12-30")
    if (us_style) {
      us <- grepl("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$", x)
      out[us & !is.na(x)] <- lubridate::mdy(x[us & !is.na(x)])
      rest <- !serial & !us
    } else rest <- !serial
    out[rest & !is.na(x)] <- as.Date(x[rest & !is.na(x)])
    # Excel's "zero date" (an empty date cell shown as 0) is 1899-12-30; some platforms and
    # package versions give 1899-12-31. Both mean "no date", so the cell is left empty.
    out[!is.na(out) & out %in% as.Date(c("1899-12-30", "1899-12-31"))] <- NA
    out
  }

  df <- df |>
    dplyr::mutate(DateIndicatorProposed = excel_or_iso(DateIndicatorProposed, us_style = TRUE),
                  ReportEndDate = excel_or_iso(ReportEndDate, us_style = TRUE),
                  Value = as.numeric(Value))

  df <- df |>
    dplyr::mutate(
      AnalysisCode = tolower(dplyr::na_if(trimws(AnalysisCode), "")),
      AnalysisCode = dplyr::recode(AnalysisCode,
        "do not count" = "do_not_count", "do not cout" = "do_not_count", "do_not count" = "do_not_count",
        "enter code" = "enter_code", "no indicator" = "no_indicator",
        "e46 drr" = "e46_drr", "e46 gender" = "e46_gender", "e46 learning" = "e46_learning",
        "e46 mhpss" = "e46_mhpss", "e46 wash" = "e46_wash", "e46 climate" = "e46_climate",
        "z4 climate" = "z4_climate"),
      AnalysisCode = ifelse(stringr::str_starts(AnalysisCode, "outlier"), "outlier_incorrect", AnalysisCode))

  df <- df |>
    dplyr::mutate(
      DisaggregatedBySex = dplyr::na_if(tolower(trimws(DisaggregatedBySex)), ""),
      DisaggregatedBySex = dplyr::case_when(
        DisaggregatedBySex %in% c("yes", "y", "yesd", "yes ", "yesy", "yess") ~ "yes",
        DisaggregatedBySex %in% c("no", "no indicator", "n", "yno") ~ "no",
        TRUE ~ DisaggregatedBySex))

  df <- df |>
    dplyr::mutate(
      UnitOfMeasurement = dplyr::na_if(dplyr::na_if(trimws(UnitOfMeasurement), ""), "N/A"),
      UnitOfMeasurement = dplyr::case_when(
        UnitOfMeasurement %in% c("yes/nos", "yes/no", "Yes (1), No (0)", "Yes/No") ~ "Yes/No",
        UnitOfMeasurement %in% c("number", "Number", "Number #") ~ "# Number",
        grepl("^us\\$?$", tolower(UnitOfMeasurement)) ~ "US$",
        UnitOfMeasurement %in% c("%", "percentage", "Percentage %", "% Percentage") ~ "% Percentage",
        TRUE ~ UnitOfMeasurement))

  dplyr::mutate(df,
    Covid19related = ifelse(is.na(Covid19related), "No", Covid19related),
    covid_flag = ifelse(is.na(covid_flag), "No", covid_flag),
    covid_19_related_report = ifelse(is.na(covid_19_related_report), "No", covid_19_related_report))
}

# 6. Whole PR flow ----

#' Run the complete PR flow in memory (see [run_cr()] for the roundtrip convention)
#'
#' @param raw List with `results`, `programme`, `standard_indicators` raw tables.
#' @param ref List with the reference tables `columns`, `order`, `names`.
#' @return list(source = merged source table, combiner = final cleaned PR combiner,
#'   combined_raw = the combiner before the final tidy-up step: this is what the legacy flow
#'   saved as `<date>_pr cleaned.csv`, while `pr_clean.xlsx` held the tidied version).
run_pr <- function(raw, grants_db, rw, old, ref, cp) {
  rt <- csv_roundtrip(build_pr_results(raw$results, cp))
  pr <- csv_roundtrip(build_pr_programme(raw$programme, cp))
  si <- csv_roundtrip(build_pr_standard_indicators(raw$standard_indicators, cp))

  source_data <- csv_roundtrip(pr_merge_templates(rt, pr, si, ref$columns, ref$order, grants_db, rw, cp))
  historical <- csv_roundtrip(pr_prepare_previous(old, grants_db, cp))

  current <- pr_current_year(pr_pivot_long(source_data, cp), cp)
  combined <- pr_bind_history(current, historical, ref$names)
  list(source = source_data, combiner = pr_final_clean(csv_roundtrip(combined)), combined_raw = combined)
}
