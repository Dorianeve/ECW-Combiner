# Finance combiners: Aligned Funding (AF) and DCM ----
# Replaces: load_aligned_funding_template.R, 01_af_joins.R, load_dcm_template.R, 01_dcm_joins.R.

#' Use the first data row as header (French and doubled-header templates)
first_row_as_header <- function(df) {
  hdr <- as.character(df[1, ])
  hdr[names(df) %in% META_COLS] <- names(df)[names(df) %in% META_COLS]
  names(df) <- janitor::make_clean_names(hdr)
  df <- df[-1, ]
  rownames(df) <- NULL
  df
}

# 1. Aligned funding ----

#' Turn the raw leverage-funding sheets into one tidy table
build_af_source <- function(raw_tables) {
  cleaned <- purrr::map(raw_tables, clean_promoted)
  check_first_column(cleaned, c("donor", "donateur"), "AF")

  # French template: the real header sits one row lower
  cleaned <- purrr::map(cleaned, function(df) if (names(df)[1] == "donateur") first_row_as_header(df) else df)
  # Templates repeating the header as first data row
  cleaned <- purrr::map(cleaned, function(df) {
    first_cell <- df[1, 1, drop = TRUE]
    if (!is.na(first_cell) && tolower(first_cell) %in% c("donor", "donateur")) first_row_as_header(df) else df
  })
  check_headers_consistency(cleaned, "AF tables")

  us_cuts <- "please_specify_the_total_amount_and_percentage_of_dedicated_awards_impacted_by_the_u_s_funding_cuts_for_2025_relative_to_the_overall_grant"
  cleaned <- purrr::map(cleaned, function(df) {
    df <- dplyr::select(df, -dplyr::starts_with("na"))
    if (!us_cuts %in% names(df)) df[[us_cuts]] <- NA
    grid_col <- grep("^ar_grid_", names(df), value = TRUE)
    if (length(grid_col) > 0) df <- dplyr::rename(df, grid = dplyr::all_of(grid_col))
    df
  })
  check_headers_consistency(cleaned, "AF tables")

  dplyr::bind_rows(cleaned) |>
    trace_step("AF source: rows in the leverage-funding tables") |>
    dplyr::filter(!is.na(grantee_lead_grn)) |>
    trace_step("AF source: after dropping rows without a lead grantee reference") |>
    dplyr::mutate(LeadGRN = lead_grn_from_grid(grid)) |>
    blank_to_na() |>
    dplyr::mutate(source_of_data = "Finance Aligned Funding")
}

#' Alignment score from the strategy-alignment x coordination answers
ALIGNMENT_LOOKUP <- tibble::tribble(
  ~combination,    ~aligned,
  "nono",          "Not aligned",
  "weakno",        "Not aligned",
  "noweak",        "Not aligned",
  "strongweak",    "Strongly aligned",
  "weakstrong",    "Strongly aligned",
  "strongstrong",  "Strongly aligned",
  "weakweak",      "Weakly aligned",
  "strongno",      "Weakly aligned",
  "nostrong",      "Weakly aligned")

#' Join AF to GMS, add the alignment score and total funding
af_join <- function(af, grants_db) {
  grants_sel <- dplyr::select(grants_db, GMGRN, Typeofinvestment, Country, Granteeorganization,
                              ProgrammeID, Startdate, Currentenddate, Covid.19related)

  new_col  <- "for_new_programmes_only_how_much_of_the_funding_amount_in_usd_is_targeting_the_same_type_of_beneficiaries_as_the_myrp"
  pre_col  <- "for_pre_existing_programmes_only_how_much_of_the_unspent_funding_amount_in_usd_is_targeting_the_same_type_of_beneficiaries_as_the_myrp"
  type_col <- "new_pre_existing_programme_in_relation_to_myrp_start_year"

  df <- af |>
    dplyr::left_join(grants_sel, by = c("LeadGRN" = "GMGRN")) |>
    trace_step("AF join: after joining the GMS (should not add rows)") |>
    dplyr::mutate(combination = paste0(
      tolower(trimws(to_what_extent_is_the_programme_aligned_with_the_myrp_strategy)),
      tolower(trimws(to_what_extent_has_there_been_coordination_between_the_myrp_and_the_programme)))) |>
    dplyr::left_join(ALIGNMENT_LOOKUP, by = "combination") |>
    dplyr::mutate(alignment_score = aligned) |>
    dplyr::select(-c(aligned, combination)) |>
    dplyr::mutate(sum_total_funding = dplyr::case_when(
      .data[[type_col]] == "New" ~ as.numeric(.data[[new_col]]),
      .data[[type_col]] == "Pre-existing" ~ as.numeric(.data[[pre_col]]),
      TRUE ~ rowSums(dplyr::across(dplyr::all_of(c(new_col, pre_col)), ~ as.numeric(.x)), na.rm = TRUE)))

  preferred_order <- c(
    "Typeofinvestment", "Country", "Granteeorganization", "ProgrammeID", "LeadGRN", "Startdate",
    "Currentenddate", "Covid.19related", "donor", "recipient_agency", "programme_name",
    "programme_start_year", "programme_end_year", "programme_total_funding_in_original_currency",
    "original_currency", "programme_total_funding_in_usd",
    "new_pre_existing_programme_in_relation_to_myrp_start_year", new_col, pre_col,
    "target_group_alignment", "to_what_extent_is_the_programme_aligned_with_the_myrp_strategy",
    "strategic_alignment_comments",
    "to_what_extent_has_there_been_coordination_between_the_myrp_and_the_programme",
    "coordination_engagement_comments", "alignment_score",
    "for_new_programmes_only_to_what_extent_has_the_myrp_contributed_to_leverage_the_new_programme",
    "contribution_to_leveraging_comments", "source_of_information", "file_name", "sum_total_funding")
  dplyr::select(df, dplyr::any_of(preferred_order), dplyr::everything())
}

#' Run the AF flow in memory
run_af <- function(raw_tables, grants_db_finance) {
  af_join(csv_roundtrip(build_af_source(raw_tables)), grants_db_finance)
}

# 2. DCM ----
# DCM workbooks come in three template generations, distinguished by their first column
# (already correctly named by extraction): "grantee", "consortium_partner(s)", or the
# sub-grantee name column.

DCM_WOMEN_RENAMES <- list(c("woman_organization", "women_led_organization"),
                          c("women_organization", "women_led_organization"))

#' Rename helper shared by the three DCM groups
#'
#' @param renames List of c(pattern, replacement) pairs applied to the column names.
dcm_group_clean <- function(df, renames = DCM_WOMEN_RENAMES, required_cols = NULL, grid_rename = FALSE) {
  for (r in renames) names(df) <- stringr::str_replace_all(names(df), r[1], r[2])
  if (grid_rename) df <- dplyr::rename(df, grid = dplyr::matches("grid"))
  for (col in required_cols) if (!col %in% names(df)) df[[col]] <- NA
  dplyr::select(df, -dplyr::matches("^na"))
}

#' Turn the raw finance-DCM sheets into one tidy table
build_dcm_source <- function(raw_tables) {
  cleaned <- purrr::map(raw_tables, clean_promoted)

  first <- vapply(cleaned, function(d) names(d)[1], character(1))
  sub_name <- "sub_grantee_ip_name_please_list_only_direct_sub_grantees"
  known <- c("grantee", "consortium_partner", "consortium_partners", sub_name)
  check_first_column(cleaned, known, "DCM")

  grantee    <- cleaned[first == "grantee"]
  consortium <- cleaned[first %in% c("consortium_partner", "consortium_partners")]
  subgrantee <- cleaned[first == sub_name]

  consortium <- purrr::map(consortium, dcm_group_clean, renames = list(
    c("woman_organization", "women_led_organization"),
    c("consortium_parnter_type", "consortium_partner_type"),
    c("consortium_partners", "consortium_partner")))
  grantee <- purrr::map(grantee, dcm_group_clean)
  subgrantee <- purrr::map(subgrantee, dcm_group_clean, grid_rename = TRUE, required_cols = c(
    "organization_of_persons_with_disabilities", "refugee_led_organization", "women_led_organization"))

  check_headers_consistency(consortium, "DCM consortium")
  check_headers_consistency(grantee, "DCM grantee")
  check_headers_consistency(subgrantee, "DCM sub-grantee")

  tag <- function(tables, label) {
    if (length(tables) == 0) return(NULL)      # this kind of table is absent this year
    dplyr::bind_rows(tables) |>
      dplyr::filter(!is.na(grid)) |>
      trace_step(paste0("DCM source: ", label)) |>
      dplyr::mutate(source_of_data = label)
  }
  dplyr::bind_rows(
    tag(subgrantee, "Finance | DCM | subgrantees"),
    tag(grantee, "Finance | DCM | grantees"),
    tag(consortium, "Finance | DCM | consortium partners"))
}

#' Amount text -> number, rounded to 2 decimals
#'
#' Currency symbols, spaces and thousands separators are removed (as in the earlier scripts, which
#' also dropped minus signs). Text in scientific notation ("5e+05") is read as a number instead of
#' being stripped to digits ("505").
parse_amount <- function(x) {
  x <- as.character(x)
  sci <- grepl("^[[:space:]]*[0-9.]+[eE][+-]?[0-9]+[[:space:]]*$", x)
  round(suppressWarnings(as.numeric(ifelse(sci, trimws(x), gsub("[^0-9.]", "", x)))), 2)
}

#' Join DCM to GMS and tidy names and numbers
dcm_join <- function(dcm, grants_db) {
  grants_sel <- dplyr::select(grants_db, GMGRN, Typeofinvestment, Country, Granteeorganization,
                              ProgrammeID, Startdate, Currentenddate, Covid.19related)

  dcm |>
    dplyr::mutate(GMGRN = stringr::str_extract(grid, "\\b\\d{2}-[A-Z]{3}(?:-[A-Z0-9]{2,5}){3,}\\b")) |>
    dplyr::left_join(grants_sel, by = "GMGRN") |>
    trace_step("DCM join: after joining the GMS (should not add rows)") |>
    dplyr::mutate(LocalTransfer = ifelse(
      consortium_partner_type %in% c("National NGO", "Government", "Local NGO", "In-country Organizations"),
      "Yes", "No")) |>
    dplyr::select(
      Typeofinvestment, Country, Granteeorganization, ProgrammeID, GMGRN, Startdate, Currentenddate,
      Covid.19related, consortium_partner, consortium_partner_type,
      total_amount_allocated_to_be_disbursed_to_consortium_partner,
      cumulative_expenditure_by_consortium_partner,
      cumulative_ecw_funds_transferred_to_partner_in_us_since_inception, date_last_updated,
      LocalTransfer, women_led_organization, refugee_led_organization,
      organization_of_persons_with_disabilities, comments_remarks, working_with_implementing_partners,
      sub_grantee_ip_name_please_list_only_direct_sub_grantees, sub_grantee_ip_type,
      source_of_data, grid, file_name) |>
    dplyr::rename(
      Covid19Related = Covid.19related, ConsortiumPartner = consortium_partner,
      ConsortiumPartnerType = consortium_partner_type,
      TotalAmountAllocatedToBeDiscursedToConsortiumPartner = total_amount_allocated_to_be_disbursed_to_consortium_partner,
      CumulativeExpenditureByConsortiumPartner = cumulative_expenditure_by_consortium_partner,
      CumulativeECWFundsTransferredToPartnerinUSSinceInception = cumulative_ecw_funds_transferred_to_partner_in_us_since_inception,
      DateLastUpdated = date_last_updated, WomenLedOrganization = women_led_organization,
      RefugeeLedOrganization = refugee_led_organization,
      OrganizationOfPWD = organization_of_persons_with_disabilities,
      CommentsRemarks = comments_remarks, WorkingWithImplementingPartners = working_with_implementing_partners,
      SubgranteeIPName = sub_grantee_ip_name_please_list_only_direct_sub_grantees,
      SubgranteeIPType = sub_grantee_ip_type, Source = source_of_data, GRID = grid, FileName = file_name) |>
    dplyr::mutate(dplyr::across(
      dplyr::all_of(c("TotalAmountAllocatedToBeDiscursedToConsortiumPartner",
                      "CumulativeExpenditureByConsortiumPartner",
                      "CumulativeECWFundsTransferredToPartnerinUSSinceInception")),
      parse_amount))
}

#' Run the DCM flow in memory
run_dcm <- function(raw_tables, grants_db_finance) {
  dcm_join(csv_roundtrip(build_dcm_source(raw_tables)), grants_db_finance)
}
