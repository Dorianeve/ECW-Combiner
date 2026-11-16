# Grants management system (GMS) data ----
# Replaces load_grants_db.R (ARR flows) and load_grants_db_finance.R (finance flows),
# which were near-duplicates with hardcoded years.

#' Download one GMS export
#'
#' @param endpoint Key of `cfg$gms$endpoints` ("grants", "allocations", "expenditures").
#' @return The parsed CSV export as a tibble.
gms_fetch <- function(cfg, endpoint = "grants") {
  user <- cfg$gms$user; pass <- cfg$gms$password
  if (is.na(user) || is.na(pass) || !nzchar(user) || !nzchar(pass)) {
    stop("GMS credentials missing: set GMS_USER and GMS_PASSWORD in .Renviron.", call. = FALSE)
  }
  path <- cfg$gms$endpoints[[endpoint]]
  if (is.null(path)) stop("Unknown GMS endpoint: ", endpoint, call. = FALSE)
  url <- paste0(sub("/+$", "", cfg$gms$base_url), "/", path)
  resp <- httr::GET(url, httr::authenticate(user = user, password = pass))
  httr::stop_for_status(resp, task = paste("download GMS export", endpoint))
  suppressMessages(httr::content(resp, as = "parsed"))
}

#' Add the `ActiveinYYYY` Yes/No flags
#'
#' A grant is "Yes" for year YYYY when its [Startdate, Currentenddate] overlaps the period
#' `active_in$start` .. `active_in$end` (by default the calendar year; see [fill_year_template()]).
add_active_flags <- function(df, cp) {
  for (y in cp$active_years) {
    start <- as.Date(fill_year_template(cp$active_in$start, y))
    end <- as.Date(fill_year_template(cp$active_in$end, y))
    df[[paste0("Activein", y)]] <- ifelse(df$Startdate <= end & df$Currentenddate >= start, "Yes", "No")
  }
  df
}

#' Yes/No flags derived from the free-text crisis context and type of emergency
add_crisis_flags <- function(df) {
  flag <- function(x, pattern) ifelse(grepl(pattern, x, ignore.case = TRUE), "Yes", "No")
  dplyr::mutate(df,
    Crisis_Protracted          = flag(Crisiscontext, "Protracted crisis"),
    Crisis_New_sudden_onset    = flag(Crisiscontext, "New or sudden on-set emergency"),
    Crisis_Escalation          = flag(Crisiscontext, "Escalation of an existing crisis"),
    Crisis_New_displacement    = flag(Crisiscontext, "New displacement of populations"),
    Crisis_Anticipatory_action = flag(Crisiscontext, "Anticipatory action"),
    Emergency_Conflict         = flag(Typeofemergency, "Conflict/violence"),
    Emergency_Natural_disaster = flag(Typeofemergency, "Natural/environmental disaster"),
    Emergency_Climate          = flag(Typeofemergency, "Climate"),
    Emergency_Public_health    = flag(Typeofemergency, "Public health"),
    Emergency_Economic         = flag(Typeofemergency, "Economic"),
    Emergency_Other            = flag(Typeofemergency, "Other"))
}

#' Process a raw GMS grants export
#'
#' @param profile `"arr"` adds the strategic-plan flag, copies the lead grantee's active
#'   flags to every grantee of a programme, and applies the investment/country filters.
#'   `"finance"` only adds the active and crisis flags.
#' @return Data frame with the same types the legacy CSV hand-off produced
#'   (dates as text, syntactic names).
gms_process <- function(raw, cp, profile = c("arr", "finance"), legacy_types = TRUE) {
  profile <- match.arg(profile)

  df <- raw |>
    dplyr::mutate(dplyr::across(dplyr::contains("date"), ~ lubridate::dmy(.x, quiet = TRUE)))
  names(df) <- trimws(gsub("\\.", "", names(df)))
  names(df) <- gsub("\\s+", "", names(df))

  df <- trace_step(df, "GMS: grants in the export")
  df <- add_active_flags(df, cp)

  if (profile == "arr") {
    # The earlier scripts used a strict ">" for the plan's start (a grant ending exactly on the
    # start date was not active); `include_boundary_end: true` makes it ">=".
    plan <- cp$strategic_plan
    ends_after_start <- if (plan$include_boundary_end) df$Currentenddate >= as.Date(plan$start) else
      df$Currentenddate > as.Date(plan$start)
    df$ActiveStrategicPlan <- ifelse(df$Startdate <= as.Date(plan$end) & ends_after_start, "Yes", "No")

    # A programme counts as active when its lead grantee is (switch off with active_in$lead_rule)
    if (cp$active_in$lead_rule) {
      active_cols <- paste0("Activein", cp$active_years)
      df <- df |>
        dplyr::group_by(ProgrammeID) |>
        dplyr::mutate(dplyr::across(dplyr::all_of(active_cols),
                                    ~ dplyr::coalesce(.x[Reportingrole %in% "Lead"][1], .x))) |>
        dplyr::ungroup()
    }
  }

  df <- add_crisis_flags(df)

  if (profile == "arr") {
    df <- df |>
      dplyr::filter(Typeofinvestment != "AF") |>
      trace_step("GMS: after dropping investment type AF") |>
      filter_global_regional(cp$global_regional) |>
      trace_step("GMS: after the Global/Regional filter")
  }

  if (legacy_types) csv_roundtrip(df) else df
}
