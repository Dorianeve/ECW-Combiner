# Synthetic data shaped like the extractor output and the GMS export.
# Nothing here comes from real reports.

test_cfg <- function(year = 2025, global_regional = "legacy") {
  list(reporting = list(year = year, window_cutoff_date = paste0(year + 1, "-01-01"),
                        apply_approval_filter = FALSE),
       filters = list(global_regional = global_regional))
}

test_cp <- function(...) {
  cp <- cycle_params(test_cfg(...))
  cp$export_date <- as.Date("2026-01-15")
  cp
}

#' A raw sheet table as returned by the extractor: character matrix + file_name + table_index
raw_sheet <- function(rows, file = "Results template X.xlsx", index = 1) {
  m <- do.call(rbind, rows)
  df <- as.data.frame(m, stringsAsFactors = FALSE)
  names(df) <- paste0("col_", seq_len(ncol(df)))
  df$file_name <- file
  df$table_index <- index
  df
}

#' Turn an old-style raw sheet (header row somewhere inside the data) into what the extractor
#' returns for a named Excel table: the table's own header row becomes the column names, the
#' empty first sheet column is gone, `file_name` / `table_index` are appended.
sheet_to_table <- function(raw, header_row) {
  keep <- !names(raw) %in% META_COLS
  hdr <- as.character(raw[header_row, keep])
  out <- raw[-(1:header_row), keep, drop = FALSE]
  names(out) <- hdr
  out <- out[, -1, drop = FALSE]
  out$file_name <- raw$file_name[1]
  out$table_index <- raw$table_index[1]
  rownames(out) <- NULL
  out
}

# Raw GMS export, as downloaded (before name cleaning)
synthetic_gms_raw <- function() {
  tibble::tibble(
    `Programme ID` = c("P1", "P1", "P2", "P3"),
    GMGRN = c("G-LEAD", "G-PART", "G-TWO", "G-AF"),
    `Reporting role` = c("Lead", "Partner", "Lead", "Lead"),
    `Grantee organization` = c("Org A", "Org B", "Org C", "Org D"),
    Country = c("Chad", "Chad", "Global", "Peru"),
    `Type of investment` = c("MYRP", "MYRP", "FER", "AF"),
    `Start date` = c("01/01/2023", "01/01/2023", "01/03/2020", "01/01/2022"),
    `End date` = c("31/12/2024", "31/12/2024", "31/12/2023", "31/12/2026"),
    `Current end date` = c("31/12/2025", "31/12/2024", "31/12/2023", "31/12/2026"),
    `Crisis context` = c("Protracted crisis", "New displacement of populations", NA, "Anticipatory action"),
    `Type of emergency` = c("Conflict/violence; Climate", "Public health", "Other", NA),
    `Covid-19 related` = c("No", "No", "Yes", "No"),
    `Excom approval date` = c("01/02/2022", "01/02/2022", "01/02/2020", "01/02/2022"))
}

#' Processed grants table (as the pipeline passes it around)
synthetic_grants_db <- function(cp = test_cp()) {
  gms_process(synthetic_gms_raw(), cp, "arr")
}

#' CR sheet: 2 junk rows, header row, then data rows. `grn` is col 3, `grantee` col 4.
cr_header <- c("", "Type of education", "GRN", "Grantee", "Indicator", "Type of beneficiary",
               "AR GRID 2021", "Tab", "GRN reference", "Grantee reference",
               "Target line reference", "Reached line reference", "Comments line reference",
               "Reporting stage", "Date of reporting", "Comments and context",
               paste(rep(c("Pre-primary", "Primary", "Secondary", "Unknown level of education"), each = 4),
                     rep(c("targeted", "targeted", "reached", "reached"), 4),
                     rep(c("female", "male"), 8)),
               "Total female targeted", "Total male targeted", "Total beneficiaries targeted",
               "Total female reached", "Total male reached", "Total beneficiaries reached")

cr_row <- function(type = "Formal education", grn = "G-LEAD", grantee = "Org A", beneficiary = "Refugees",
                   grid = "x | x | x | x | G-LEAD | x", values = 1) {
  c("", type, grn, grantee, "Enrolled", beneficiary, grid, "tab1", "r1", "r2", "r3", "r4", "r5",
    "Individual report", "2025-06-01", "ok", rep(as.character(values), 16), rep(as.character(values), 6))
}

synthetic_cr_sheet <- function(file = "Results template X.xlsx") {
  sheet_to_table(raw_sheet(list(
    rep("", length(cr_header)), rep("junk", length(cr_header)), cr_header,
    cr_row(values = 1),
    cr_row(type = "Non-formal education", values = 2),
    cr_row(type = "Total", values = 9),          # filtered out
    cr_row(grn = NA, values = 3),                # no GRN: filtered out
    rep("", length(cr_header))),                 # empty row: dropped
    file = file), 3)
}

synthetic_rw <- function() {
  data.frame(
    ProgrammeID = c("P1", "P1", "P2"),
    GMGRN = c("G-LEAD", "G-LEAD", "G-TWO"),
    report_year = c("Window 1", "Window 2", "Window 1"),
    type_of_reporting = "Annual",
    reporting_period_up_to = c("2024-12-31", "2025-12-31", "2023-12-31"),
    Currentenddate = c("2025-12-31", "2025-12-31", "2023-12-31"),
    submission_deadline = NA, m_e_review = c("Approved", "Approved", "Pending"),
    education_team_review = NA, GRID = "g", FileName = "Results template X.xlsx",
    stringsAsFactors = FALSE)
}

synthetic_old_cr <- function() {
  data.frame(
    LeadGRN = c("G-LEAD", "G-TWO", "G-TWO"),
    GMGRN = c("G-LEAD", "G-TWO", "Mutiple Grantees"),
    ProgrammeID = c("P1", "P2", "P2"),
    Exercise = c("ARR24 Cumulative", "ARR24 Cumulative", "ARR24 Annual"),
    Covid19relateddata = "Non-Covid-19 related data",
    Number = c("1,000", "20", "5"),
    ActiveStrategicPlan = "Yes", Reportingrole = "Lead",
    Activein2023 = "Yes", Activein2024 = "Yes",
    stringsAsFactors = FALSE)
}

# PR templates ----
pr_value_headers <- function() {
  c("Total RW1", "Female RW1", "Male RW1", "Year of data RW1", "Report end date RW1", "Comments RW1",
    "Children with disabilities RW1", "Adapted accessible RW1", "Other levels of disaggregation RW1",
    "Total baseline", "Total target")
}
pr_values <- function(total = "10") {
  c(total, "4", "6", "2024", "2024-12-31", "c1", "yes", "no", "x", "1", "20")
}
GRID_LEAD <- "g | g | g | g | G-LEAD | g"

#' Programme template: header on sheet row 5
synthetic_pt_sheet <- function() {
  hdr <- c("", "Outcome / output numbering", "Level", "Result statement", "Indicator text",
           "Grantees own program specific indicator", "Analysis code", "Unit of measurement",
           "Indicator data status", "Level outcome output", "Disaggregated by sex",
           "Date indicator is proposed", "GRID", pr_value_headers())
  row <- c("", "1.1", "Outcome", "R1", "Ind A", NA, "A1", "number", "Reported", "Outcome", "Yes",
           "45000", GRID_LEAD, pr_values())
  sheet_to_table(raw_sheet(list(rep("", length(hdr)), rep("j", length(hdr)), rep("j", length(hdr)), rep("j", length(hdr)),
                 hdr, row), file = "Programme template X.xlsx"), 5)
}

#' Standard indicators template: header on sheet row 8; one row with values, one empty
synthetic_si_sheet <- function() {
  hdr <- c("", "Level", "Result statement", "Indicator", "Analysis code", "Indicator data status",
           "Unit of measurement", "AR GRID 2021", pr_value_headers())
  junk <- rep(list(rep("j", length(hdr))), 7)
  full <- c("", "SI", "R-SI", "Ind S1", "S1", "Reported", "number", GRID_LEAD, pr_values("7"))
  empty <- c("", "SI", "R-SI", "Ind S2", "S2", "Reported", "number", GRID_LEAD, rep(NA, 11))
  sheet_to_table(raw_sheet(c(junk, list(hdr, full, empty)), file = "Results template X.xlsx"), 8)
}

#' Results template: header row = 2nd occurrence of the anchor text
synthetic_rt_sheet <- function() {
  cm <- unlist(lapply(1:6, function(k) c(paste0("Comments RW", k), paste0("Comments RW", k, " 2"))))
  hdr <- c("", "Outcome / output numbering", "Level outcome output", "Result statement", "Indicator",
           "Grantees own program specific indicator", "Analysis code", "ECW anaysis code",
           "Unit of measurement", "Source of verification", "Means of verification",
           "Indicator data status", "AR GRID 2021",
           pr_value_headers()[pr_value_headers() != "Comments RW1"], cm,
           "Comments baseline", "Baseline comments", "Comments target", "Target comments")
  n <- length(hdr)
  row <- rep(NA_character_, n)
  names(row) <- hdr; row <- unname(row)
  set <- function(h, v, nth = 1) { row[which(hdr == h)[nth]] <<- v }
  set("Outcome / output numbering", "2.1"); set("Level outcome output", "Output")
  set("Result statement", "R2"); set("Indicator", "Ind R"); set("ECW anaysis code", "R1code")
  set("Analysis code", "old"); set("Unit of measurement", "Percentage")
  set("Indicator data status", "Reported"); set("AR GRID 2021", GRID_LEAD)
  set("Source of verification", "survey"); set("Means of verification", "visit")
  set("Total RW1", "55"); set("Female RW1", "25"); set("Male RW1", "30")
  set("Total baseline", "5"); set("Total target", "80")
  sheet_to_table(raw_sheet(list(rep("t", n), hdr, rep("j", n), hdr, row), file = "Results template Y.xlsx"), 4)
}

synthetic_pr_reference <- function() {
  list(
    columns = data.frame(
      Programme = c("indicator_text", ""), RevisedProgramme = c("indicator", ""),
      Indicators = c("", ""), RevisedIndicators = c("", ""),
      Results = c("ecw_analysis_code", ""), RevisedResults = c("analysis_code", ""),
      stringsAsFactors = FALSE),
    order = data.frame(Results = c("LeadGRN", "outcome_output_numbering", "level"), stringsAsFactors = FALSE),
    names = data.frame(clean = c("Indicator", "Covid19related"),
                       old_combiner = c("OldIndicator", "Covid19related"), stringsAsFactors = FALSE))
}

synthetic_old_pr <- function() {
  data.frame(
    LeadGRN = c("G-LEAD", "G-TWO"), GMGRN = c("G-LEAD", "G-TWO"), ProgrammeID = c("P1", "P2"),
    Exercise = c("ARR24 Cumulative", "ARR24 Cumulative"), Covid19related = "Non-Covid-19 related data",
    Value = c("1,500", "300"), OldIndicator = c("old ind 1", "old ind 2"),
    ActiveStrategicPlan = "Yes", Reportingrole = "Lead", Activein2023 = "Yes", Activein2024 = "Yes",
    stringsAsFactors = FALSE)
}

# Finance ----
synthetic_grants_finance <- function() {
  data.frame(GMGRN = c("G-LEAD", "24-ABC-LD1-RT2-ZZ9"), Typeofinvestment = "MYRP", Country = "Chad",
             Granteeorganization = "Org A", ProgrammeID = c("P1", "P9"), Startdate = "2023-01-01",
             Currentenddate = "2025-12-31", Covid.19related = "No", stringsAsFactors = FALSE)
}

synthetic_af_sheet <- function() {
  new_col <- "for_new_programmes_only_how_much_of_the_funding_amount_in_usd_is_targeting_the_same_type_of_beneficiaries_as_the_myrp"
  pre_col <- "for_pre_existing_programmes_only_how_much_of_the_unspent_funding_amount_in_usd_is_targeting_the_same_type_of_beneficiaries_as_the_myrp"
  hdr <- c("", "Donor", "grantee_lead_grn", "grid", "to_what_extent_is_the_programme_aligned_with_the_myrp_strategy",
           "to_what_extent_has_there_been_coordination_between_the_myrp_and_the_programme",
           "new_pre_existing_programme_in_relation_to_myrp_start_year", new_col, pre_col)
  rows <- list(
    c("", "D1", "G-LEAD", GRID_LEAD, "Strong", "Weak", "New", "100", "50"),
    c("", "D2", "G-LEAD", GRID_LEAD, "No", "No", "Pre-existing", "100", "50"),
    c("", "D3", "G-LEAD", GRID_LEAD, "Weak", "Weak", NA, "100", "50"),
    c("", "D4", NA, GRID_LEAD, "Weak", "Weak", "New", "1", "1"))
  sheet_to_table(raw_sheet(c(list(rep("j", length(hdr)), hdr), rows), file = "Programme template Z.xlsx"), 2)
}

synthetic_dcm_sheet <- function() {
  hdr <- c("", "Sub-grantee/IP name (please list only direct sub-grantees)", "sub_grantee_ip_type",
           "consortium_partner", "consortium_partner_type",
           "total_amount_allocated_to_be_disbursed_to_consortium_partner",
           "cumulative_expenditure_by_consortium_partner",
           "cumulative_ecw_funds_transferred_to_partner_in_us_since_inception", "date_last_updated",
           "women_led_organization", "refugee_led_organization", "organization_of_persons_with_disabilities",
           "comments_remarks", "working_with_implementing_partners", "grid")
  row <- c("", "Sub A", "NGO", "Partner 1", "National NGO", "$1,234.567", "10", "20", "2025-01-01", "Yes", "No", "No",
           "note", "yes", "x | 24-ABC-LD1-RT2-ZZ9 | y")
  sheet_to_table(raw_sheet(list(rep("j", length(hdr)), hdr, row), file = "Finance template Q.xlsx"), 2)
}

#' Cycle parameters with some `reporting:` settings overridden, e.g. cp_with(list(active_in = list(...)))
cp_with <- function(reporting_changes = list(), year = 2025) {
  cfg <- test_cfg(year)
  cfg$reporting <- utils::modifyList(cfg$reporting, reporting_changes)
  cp <- cycle_params(cfg)
  cp$export_date <- as.Date("2026-01-15")
  cp
}
