# Pipeline orchestration ----
# Plain R + `future` (no extra framework). Order of work:
#   1. extract all needed Excel tables once (parallel over workbooks, cached per file)
#   2. load the GMS export(s) and build the reporting windows
#   3. run the CR, PR, AF and DCM flows in parallel (they are independent)
#   4. write the outputs, a run log and the diagnostics report
#
# A flow that fails does not stop the others: its error is recorded, the other flows are written,
# and the run ends with an error once the diagnostics report has been written. A failure before
# the flows (workbooks, GMS, reporting windows) also writes a report, with what is known so far.

ALL_FLOWS <- c("cr", "pr", "af", "dcm")

FLOW_TABLES <- list(
  cr = "children", pr = c("results_framework", "standard_indicators"),
  af = "leverage_funding", dcm = "finance_dcm")

# Which kinds of workbook (names under `source$file_patterns`) each flow reads. A run of only
# some flows opens only these workbooks.
FLOW_FAMILIES <- list(
  cr = c("results", "programme"), pr = c("results", "programme"),
  af = c("programme", "aligned"), dcm = c("finance", "programme"))

#' Load the project functions (also used inside parallel workers)
#'
#' Also remembers the names of the functions the project defines (`.project_fns`), so that an
#' error can be reported as a short list of project functions instead of a long R call stack.
source_project <- function(root = getwd()) {
  files <- list.files(file.path(root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)
  for (f in files) sys.source(f, envir = globalenv())
  defined <- unlist(lapply(files, function(f) {
    vapply(parse(f, keep.source = FALSE), function(e) {
      if (is.call(e) && (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
          is.symbol(e[[2]]) && is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))) {
        as.character(e[[2]])
      } else NA_character_
    }, "")
  }))
  assign(".project_fns", unique(defined[!is.na(defined)]), envir = globalenv())
  invisible(files)
}

#' Error text on one line (R and dplyr add line breaks and bullets)
one_line <- function(x) trimws(gsub("[[:space:]]+", " ", x))

#' The project functions in an error's call stack, outermost first
project_calls <- function(calls) {
  proj <- if (exists(".project_fns", envir = globalenv())) get(".project_fns", envir = globalenv()) else character()
  nm <- vapply(calls, function(cl) if (is.symbol(cl[[1]])) as.character(cl[[1]]) else "", "")
  setdiff(unique(nm[nm %in% proj]), c("run_flow_job", "run_pipeline", "run_pipeline_core"))
}

#' GMS export
#'
#' From a saved export (`gms$from_file`), else from the API. Every API download is also saved
#' in `<cache_dir>/gms/` (`<endpoint>_latest.csv` and a dated copy), so that a later run with
#' `cache_only = TRUE` can reuse it without logging in again.
gms_load <- function(cfg, endpoint = "grants", cache_only = FALSE) {
  file <- cfg$gms$from_file
  if (!is.null(file) && nzchar(file)) {
    return(readr::read_csv(file, show_col_types = FALSE))
  }
  latest <- file.path(cfg$paths$cache_dir, "gms", paste0(endpoint, "_latest.csv"))
  if (cache_only) {
    if (!file.exists(latest)) {
      stop("No saved GMS export in the cache (", latest, "). Run once without --cache-only, ",
           "or set gms$from_file.", call. = FALSE)
    }
    message("Using the saved GMS export from ", format(file.mtime(latest), "%Y-%m-%d %H:%M"), ".")
    return(readr::read_csv(latest, show_col_types = FALSE))
  }
  raw <- gms_fetch(cfg, endpoint)
  assert_outside_source(latest, cfg, "the GMS export")
  dir.create(dirname(latest), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(raw, latest)
  file.copy(latest, file.path(dirname(latest), paste0(endpoint, "_", Sys.Date(), ".csv")), overwrite = TRUE)
  raw
}

#' Run one flow from a plain list of inputs (executed locally or in a worker)
#'
#' Never throws: a failure comes back as `list(failed = TRUE, error, calls, trace, seconds)`, so that
#' the other flows are not lost. `trace` holds the row counts recorded by [trace_step()].
run_flow_job <- function(job, root) {
  source_project(root)
  trace_reset()
  t0 <- Sys.time()
  calls <- character()
  res <- tryCatch(
    withCallingHandlers(
      switch(job$flow,
        cr  = run_cr(job$raw, job$gms_arr, job$rw, job$old, job$cp),
        pr  = run_pr(job$raw, job$gms_arr, job$rw, job$old, job$ref, job$cp),
        af  = list(combiner = run_af(job$raw, job$gms_fin)),
        dcm = list(combiner = run_dcm(job$raw, job$gms_fin))),
      error = function(e) calls <<- project_calls(sys.calls())),
    error = function(e) list(failed = TRUE, error = one_line(conditionMessage(e)), calls = calls))
  res$trace <- trace_get()
  res$seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  res
}

#' The pipeline itself, without the diagnostics report
#'
#' @param state Environment in which the current stage and the results found so far are kept, so
#'   that a report can still be written when the run stops ([run_pipeline()] passes one).
#' @return list(results = results of the flows that worked, failures = flows that failed, traces
#'   = row traces per flow, log, paths, issues, extracted, cp, cache_only, gms_trace).
run_pipeline_core <- function(cfg, flows = ALL_FLOWS, refresh = FALSE, write = TRUE,
                              root = normalizePath(getwd()), cache_only = FALSE,
                              state = new.env()) {
  flows <- match.arg(flows, ALL_FLOWS, several.ok = TRUE)
  state$stage <- "checking the configuration"
  assert_config_paths_safe(cfg)                       # never write below the source folder
  verify <- !isFALSE(cfg$safety$verify_source) && !cache_only   # nothing is read in cache-only mode
  fingerprint <- if (verify) source_fingerprint(cfg)  # compared again at the end
  cp <- cycle_params(cfg)
  state$cp <- cp
  log <- list()
  timed <- function(step, expr) {
    t0 <- Sys.time(); on.exit(log[[step]] <<- as.numeric(difftime(Sys.time(), t0, units = "secs")))
    force(expr)
  }

  # 1. extraction
  state$stage <- if (cache_only) "reading the cached workbook tables" else "reading the workbooks"
  needed <- unique(c(unlist(FLOW_TABLES[flows]), if (any(flows %in% c("cr", "pr"))) "reporting_windows"))
  families <- unique(unlist(FLOW_FAMILIES[flows]))
  extracted <- timed("extract", extract_all(cfg, tables = vapply(needed, table_name, "", cfg = cfg),
                                            refresh = refresh, cache_only = cache_only,
                                            families = families))
  state$extracted <- extracted

  # 2. GMS and reporting windows
  state$stage <- "loading the GMS export"
  need_arr <- any(flows %in% c("cr", "pr")); need_fin <- any(flows %in% c("af", "dcm"))
  gms_raw <- timed("gms", gms_load(cfg, cache_only = cache_only))
  state$stage <- "processing the GMS export"
  trace_reset()
  gms_arr <- if (need_arr) gms_process(gms_raw, cp, "arr")
  gms_trace <- trace_get()
  state$gms_trace <- gms_trace
  gms_fin <- if (need_fin) gms_process(gms_raw, cp, "finance")
  state$stage <- "building the reporting windows"
  rw <- if (need_arr) timed("reporting_windows", build_reporting_windows(
    tables_for(extracted, cfg, "reporting_windows", c("results", "programme")), gms_arr))

  # 3. flows
  state$stage <- "preparing the flows (previous combiners, lookup tables)"
  ref <- if ("pr" %in% flows) load_pr_reference(cfg$paths$reference_dir %||% "reference")
  jobs <- list(
    cr = if ("cr" %in% flows) list(flow = "cr", cp = cp, gms_arr = gms_arr, rw = rw,
                                   old = read_previous_combiner(cfg, "cr"),
                                   raw = tables_for(extracted, cfg, "children", c("results", "programme"))),
    pr = if ("pr" %in% flows) list(flow = "pr", cp = cp, gms_arr = gms_arr, rw = rw, ref = ref,
                                   old = read_previous_combiner(cfg, "pr"),
                                   raw = list(results = tables_for(extracted, cfg, "results_framework", "results"),
                                              programme = tables_for(extracted, cfg, "results_framework", "programme"),
                                              standard_indicators = tables_for(extracted, cfg, "standard_indicators",
                                                                               c("results", "programme")))),
    af = if ("af" %in% flows) list(flow = "af", gms_fin = gms_fin,
                                   raw = tables_for(extracted, cfg, "leverage_funding", c("programme", "aligned"))),
    dcm = if ("dcm" %in% flows) list(flow = "dcm", gms_fin = gms_fin,
                                     raw = tables_for(extracted, cfg, "finance_dcm", c("finance", "programme"))))
  jobs <- Filter(Negate(is.null), jobs)

  state$stage <- "running the flows"
  workers <- min(resolve_workers(cfg), length(jobs))
  t0 <- Sys.time()
  if (workers > 1) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
    outcomes <- furrr::future_map(jobs, run_flow_job, root = root,
                                  .options = furrr::furrr_options(seed = TRUE))
  } else {
    outcomes <- purrr::map(jobs, run_flow_job, root = root)
  }
  log[["flows_wall"]] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  failed <- vapply(outcomes, function(r) isTRUE(r$failed), logical(1))
  failures <- outcomes[failed]
  results <- outcomes[!failed]
  traces <- lapply(outcomes, function(r) r$trace)
  for (fl in names(failures)) {
    warning("The ", toupper(fl), " flow failed: ", failures[[fl]]$error, call. = FALSE)
  }

  # 4. data-collection checks and outputs
  state$stage <- "writing the outputs"
  checks <- collect_data_issues(extracted, results, cp, cfg)
  n_files <- length(unique(checks$issues$file))
  message(if (n_files == 0) "Data-collection checks: no problems found." else
    paste0("Data-collection checks: ", nrow(checks$issues), " issue(s) in ", n_files,
           " workbook(s), see output/checks/data_collection_issues.csv."),
    if (checks$unchecked > 0) paste0(" (", checks$unchecked, " cached workbook(s) were not checked for ",
                                     "rows below tables: run with --refresh once to check them.)"))
  paths <- NULL
  if (write) {
    paths <- purrr::imap(results, function(r, flow) {
      write_combiner(r$combiner, flow, cfg, csv_df = r$combined_raw %||% r$combiner)
    })
    # the processed GMS table is the third file the AnnualResultsReport flow reads
    if (need_arr) write_grants_db(gms_arr, cfg)
  }

  run_log <- tibble::tibble(
    step = c(names(log), if (length(results)) paste0("flow_", names(results)),
             if (length(failures)) paste0("flow_", names(failures), "_FAILED")),
    seconds = round(c(unlist(log), vapply(results, function(r) r$seconds, numeric(1)),
                      vapply(failures, function(r) r$seconds, numeric(1))), 2),
    rows = c(rep(NA_integer_, length(log)), vapply(results, function(r) nrow(r$combiner), integer(1)),
             rep(NA_integer_, length(failures))))
  if (verify) {
    changes <- verify_source_untouched(fingerprint, cfg)
    run_log <- dplyr::bind_rows(run_log, tibble::tibble(
      step = "source_folder_untouched", seconds = NA_real_, rows = as.integer(changes$untouched)))
  }
  if (write) {
    check_dir <- file.path(cfg$paths$output_dir, "checks")
    assert_outside_source(check_dir, cfg, "the data-collection checks")
    dir.create(check_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(checks$issues, file.path(check_dir, "data_collection_issues.csv"), row.names = FALSE)
    assert_outside_source(cfg$paths$output_dir, cfg, "the run log")
    dir.create(cfg$paths$output_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(run_log, file.path(cfg$paths$output_dir, "run_log.csv"), row.names = FALSE)
  }
  state$stage <- "finished"
  list(results = results, failures = failures, traces = traces, gms_trace = gms_trace, log = run_log,
       paths = paths, issues = checks$issues, extracted = extracted, cp = cp, cache_only = cache_only)
}

#' Run the whole pipeline and write a diagnostics report
#'
#' Same arguments as the core run. Every message and warning of the run is captured. Unless
#' `write = FALSE` or `diagnostics$enabled: false`, a report is written to
#' `<output_dir>/diagnostics/<timestamp>/` (see [build_diagnostics()]), also when the run fails:
#' then it says at which stage, with which error, in which functions, and shows the row trace of
#' the flows up to that point. After the report, a failed run ends with an error.
run_pipeline <- function(cfg, flows = ALL_FLOWS, refresh = FALSE, write = TRUE,
                         root = normalizePath(getwd()), cache_only = FALSE) {
  state <- new.env()
  state$stage <- "starting"
  log_lines <- character()
  err_calls <- character()
  report <- write && !isFALSE(cfg$diagnostics$enabled)
  run_id <- format(Sys.time(), "%Y-%m-%d_%H%M%S")

  res <- tryCatch(
    withCallingHandlers(
      run_pipeline_core(cfg, flows = flows, refresh = refresh, write = write, root = root,
                        cache_only = cache_only, state = state),
      message = function(m) log_lines <<- c(log_lines, sub("\\s+$", "", conditionMessage(m))),
      warning = function(w) log_lines <<- c(log_lines, paste0("WARNING: ", conditionMessage(w))),
      error = function(e) err_calls <<- project_calls(sys.calls())),
    error = function(e) structure(list(message = one_line(conditionMessage(e))), class = "pipeline_error"))

  if (inherits(res, "pipeline_error")) {
    log_lines <- c(log_lines, paste0("ERROR: ", res$message))
    if (report) {
      failure <- list(stage = state$stage, message = res$message, calls = err_calls)
      dir <- tryCatch(write_failure_diagnostics(cfg, state, log_lines, failure, flows, cache_only, run_id),
                      error = function(e) NULL)
      if (!is.null(dir)) message("Diagnostics report of the failed run: ", file.path(dir, "report.md"))
    }
    stop("The pipeline stopped while ", state$stage, ": ", res$message, call. = FALSE)
  }

  if (report) {
    previous <- previous_diagnostics(cfg, run_id)
    diag <- build_diagnostics(cfg, res, log_lines, previous)
    dir <- write_diagnostics(diag, cfg, run_id)
    n_att <- sum(diag$findings$severity == "attention")
    message("Diagnostics report: ", file.path(dir, "report.md"), " (",
            if (n_att == 0) "nothing needs attention" else paste(n_att, "point(s) need attention"), ")")
    res$diagnostics_dir <- dir
  }
  if (length(res$failures)) {
    stop(length(res$failures), " flow(s) failed: ",
         paste0(toupper(names(res$failures)), " (", vapply(res$failures, function(r) r$error, ""), ")", collapse = "; "),
         if (!is.null(res$diagnostics_dir)) paste0(". The other flows were written; see ", file.path(res$diagnostics_dir, "report.md")),
         call. = FALSE)
  }
  res
}
