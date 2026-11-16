# Reporting-cycle parameters ----
# Everything that used to be edited by hand each year (Activein2025, "ARR25 Annual", ...)
# is derived from `reporting.year` in the config.

#' Fill year placeholders in a text template
#'
#' `{year}` is the year (2025), `{yy}` its last two digits (25). Both accept an offset:
#' `{year-1}`, `{year+1}`, `{yy-1}`. Example: `fill_year_template("ARR{yy-1} Cumulative", 2025)`
#' gives "ARR24 Cumulative".
fill_year_template <- function(x, year) {
  pattern <- "\\{(year|yy)([+-][0-9]+)?\\}"
  stringr::str_replace_all(x, pattern, function(m) {
    parts <- stringr::str_match(m, pattern)
    y <- year + ifelse(is.na(parts[, 3]), 0L, as.integer(parts[, 3]))
    ifelse(parts[, 2] == "yy", sprintf("%02d", y %% 100), as.character(y))
  })
}

#' Derive all cycle-dependent names and settings from the config
#'
#' Defaults reproduce the earlier scripts. See `reporting:` in config.example.yml for how
#' `active_in`, `strategic_plan` and `exercises` can be changed.
cycle_params <- function(cfg) {
  y <- as.integer(cfg$reporting$year)
  if (is.na(y)) stop("reporting$year must be a year, e.g. 2025.", call. = FALSE)
  yy <- sprintf("%02d", y %% 100)
  active_years <- as.integer(unlist(cfg$reporting$active_years %||% (y - 2):y))

  # ActiveinYYYY: a grant is "Yes" when its dates overlap the period of that year
  ai <- cfg$reporting$active_in
  active_in <- list(start = ai$start %||% "{year}-01-01",
                    end = ai$end %||% "{year}-12-31",
                    lead_rule = !isFALSE(ai$lead_rule))
  for (yr in active_years) for (part in c("start", "end")) {
    d <- tryCatch(as.Date(fill_year_template(active_in[[part]], yr)), error = function(e) NA)
    if (is.na(d)) stop("reporting$active_in$", part, " does not give a date for ", yr,
                       ": ", active_in[[part]], call. = FALSE)
  }

  # ActiveStrategicPlan
  plan <- cfg$reporting$strategic_plan %||% list(start = paste0(y - 2, "-01-01"),
                                                 end = paste0(y, "-12-31"))
  strategic_plan <- list(start = plan$start, end = plan$end,
                         include_boundary_end = isTRUE(plan$include_boundary_end))
  to_date <- function(x) tryCatch(as.Date(x), error = function(e) NA)
  if (anyNA(c(to_date(strategic_plan$start), to_date(strategic_plan$end)))) {
    stop("reporting$strategic_plan needs a start and an end date (YYYY-MM-DD).", call. = FALSE)
  }

  # Exercises: Annual / Cumulative rows of the current cycle
  ex <- cfg$reporting$exercises
  create <- tolower(unlist(ex$create %||% c("cumulative", "annual")))
  if (length(create) == 0 || !all(create %in% c("annual", "cumulative"))) {
    stop("reporting$exercises$create must contain 'annual' and/or 'cumulative'.", call. = FALSE)
  }
  exercise_keys <- c("cumulative", "annual")[c("cumulative", "annual") %in% create]
  exercise_cols <- paste0("ARR", yy, c(cumulative = "Cumulative", annual = "Annual")[exercise_keys])

  # Optional rule per exercise: a row belongs to it when the end of the programme's latest
  # reporting window falls in from..to. Without a rule every row belongs to it (earlier behaviour).
  parse_rule <- function(rule, key) {
    if (is.null(rule) || (is.null(rule$from) && is.null(rule$to))) return(NULL)
    one <- function(x) {
      if (is.null(x)) return(as.Date(NA))
      d <- tryCatch(as.Date(fill_year_template(x, y)), error = function(e) as.Date(NA))
      if (is.na(d)) stop("reporting$exercises$", key, "_rule: not a date: ", x, call. = FALSE)
      d
    }
    list(from = one(rule$from), to = one(rule$to))
  }

  list(
    year = y,
    yy = yy,
    active_year = paste0("Activein", y),
    old_active_year = paste0("Activein", y - 1),
    active_years = active_years,
    active_in = active_in,
    strategic_plan = strategic_plan,
    exercise_annual = fill_year_template(ex$annual_label %||% "ARR{yy} Annual", y),
    exercise_cumulative = fill_year_template(ex$cumulative_label %||% "ARR{yy} Cumulative", y),
    old_exercise_cumulative = fill_year_template(ex$previous_cumulative_label %||% "ARR{yy-1} Cumulative", y),
    exercise_cols = exercise_cols,
    exercise_keys = exercise_keys,
    annual_rule = parse_rule(ex$annual_rule, "annual"),
    cumulative_rule = parse_rule(ex$cumulative_rule, "cumulative"),
    carry_over_inactive = !isFALSE(ex$carry_over_inactive),
    cutoff_date = as.character(cfg$reporting$window_cutoff_date),
    apply_mne_filter = isTRUE(cfg$reporting$apply_approval_filter),
    global_regional = cfg$filters$global_regional %||% "legacy",
    export_date = Sys.Date()
  )
}

#' Excel table name for a logical table key (e.g. "children")
table_name <- function(cfg, key) {
  nm <- cfg$tables[[key]]
  if (is.null(nm)) stop("No table configured for '", key, "'.", call. = FALSE)
  nm
}

#' Regex matching any of the configured file families (e.g. c("results", "programme"))
family_pattern <- function(cfg, families) {
  pats <- unlist(cfg$source$file_patterns[families])
  if (length(pats) != length(families)) {
    stop("Missing source$file_patterns entry among: ", paste(families, collapse = ", "), call. = FALSE)
  }
  paste0("(", paste(pats, collapse = "|"), ")")
}

#' Collect the tables of one kind from the files of the given families
tables_for <- function(extracted, cfg, key, families) {
  collect_tables(extracted, table_name(cfg, key), file_pattern = family_pattern(cfg, families))
}
