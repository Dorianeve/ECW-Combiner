# Diagnostics report ----
# One folder per run under <output_dir>/diagnostics/, with a report that a person (or an AI
# assistant) can read to see what changed since the last run: schema, values, empty-cell rates,
# row counts, the row trace of each flow, input workbooks, warnings. It is also written when a
# run fails. It contains NO data rows and NO credentials: only names, counts and the values of
# low-cardinality (category-like) columns.

DIAG <- list(max_levels = 60,          # columns with more distinct values are not profiled by value
             na_jump = 0.10,           # empty-cell share change that is reported
             rows_change = 0.10,       # relative change in a flow's row count that is reported
             trace_min_rows = 5)       # smallest change in a trace step that is reported

# Profiles ----

#' Profile the outputs of the flows: columns, row counts, empty-cell rates, category values
profile_outputs <- function(results, max_levels = DIAG$max_levels) {
  lapply(results, function(r) {
    d <- r$combiner
    cats <- list()
    for (col in names(d)) {
      x <- d[[col]]
      if (!(is.character(x) || is.factor(x))) next
      if (length(unique(x[!is.na(x)])) > max_levels) next
      tab <- table(as.character(x))
      cats[[col]] <- stats::setNames(as.integer(tab), names(tab))
    }
    list(n = nrow(d), columns = names(d),
         na_rate = if (nrow(d)) round(colMeans(is.na(d)), 4) else numeric(),
         categories = cats,
         by_exercise = if ("Exercise" %in% names(d)) {
           t <- table(as.character(d$Exercise)); stats::setNames(as.integer(t), names(t))
         } else NULL)
  })
}

#' Inventory of the workbooks used and the columns found in each kind of input table
profile_inputs <- function(extracted, cfg) {
  tbl_names <- unlist(cfg$tables)
  inventory <- purrr::imap_dfr(extracted, function(r, nm) {
    counts <- vapply(tbl_names, function(tn) length(r$tables[[tn]] %||% list()), integer(1))
    rows <- vapply(tbl_names, function(tn) sum(vapply(r$tables[[tn]] %||% list(), nrow, integer(1))), numeric(1))
    tibble::tibble(file = nm, origin = r$origin %||% NA_character_,
                   size_kb = round((r$signature$size %||% NA_real_) / 1024),
                   modified = format(as.POSIXct(r$signature$mtime %||% NA_real_, origin = "1970-01-01"), "%Y-%m-%d"),
                   tables_found = sum(counts), rows = sum(rows),
                   read_errors = paste(r$errors, collapse = " | "),
                   tables = paste(names(counts)[counts > 0], collapse = ", "))
  })

  # which columns each kind of table has, and in how many workbooks
  schema <- purrr::map_dfr(names(tbl_names), function(key) {
    tn <- tbl_names[[key]]
    sets <- unlist(lapply(extracted, function(r) {
      lapply(r$tables[[tn]] %||% list(), function(df) setdiff(janitor::make_clean_names(names(df)), META_COLS))
    }), recursive = FALSE)
    if (length(sets) == 0) return(NULL)
    all_cols <- unique(unlist(sets))
    tibble::tibble(table = key, column = all_cols,
                   n_tables_with = vapply(all_cols, function(cn) sum(vapply(sets, function(s) cn %in% s, logical(1))), integer(1)),
                   n_tables = length(sets))
  })
  list(inventory = inventory, schema = schema)
}

#' Row traces of all flows as one table (flow, order, step, rows)
trace_table <- function(traces, gms_trace = NULL) {
  all <- c(if (!is.null(gms_trace) && nrow(gms_trace)) list(gms = gms_trace), traces)
  out <- purrr::imap_dfr(all, function(t, flow) {
    if (is.null(t) || nrow(t) == 0) return(NULL)
    data.frame(flow = flow, order = seq_len(nrow(t)), step = t$step, rows = t$rows, stringsAsFactors = FALSE)
  })
  if (nrow(out) == 0) data.frame(flow = character(), order = integer(), step = character(), rows = integer()) else out
}

# Findings (what changed since the last run) ----

finding <- function(severity, area, item, detail) {
  data.frame(severity = severity, area = area, item = item, detail = detail, stringsAsFactors = FALSE)
}

#' Compare this run's profile with the previous one
compare_profiles <- function(cur, base) {
  out <- list()
  add <- function(...) out[[length(out) + 1]] <<- finding(...)

  # outputs
  for (flow in intersect(names(cur$outputs), names(base$outputs))) {
    c1 <- cur$outputs[[flow]]; b1 <- base$outputs[[flow]]
    for (cn in setdiff(c1$columns, b1$columns)) add("attention", flow, "new output column", cn)
    for (cn in setdiff(b1$columns, c1$columns)) add("attention", flow, "output column disappeared", cn)

    if (b1$n > 0 && abs(c1$n - b1$n) / b1$n >= DIAG$rows_change) {
      add("attention", flow, "row count changed",
          sprintf("%s -> %s rows (%+.0f%%)", format(b1$n, big.mark = ","), format(c1$n, big.mark = ","),
                  100 * (c1$n - b1$n) / b1$n))
    }
    for (cn in intersect(names(c1$categories), names(b1$categories))) {
      new <- setdiff(names(c1$categories[[cn]]), names(b1$categories[[cn]]))
      gone <- setdiff(names(b1$categories[[cn]]), names(c1$categories[[cn]]))
      if (length(new)) add("attention", flow, paste0("new value(s) in ", cn), paste(utils::head(new, 8), collapse = " | "))
      if (length(gone)) add("info", flow, paste0("value(s) no longer in ", cn), paste(utils::head(gone, 8), collapse = " | "))
    }
    for (cn in intersect(names(c1$na_rate), names(b1$na_rate))) {
      d <- c1$na_rate[[cn]] - b1$na_rate[[cn]]
      if (abs(d) >= DIAG$na_jump) {
        add("attention", flow, paste0("share of empty cells changed in ", cn),
            sprintf("%.0f%% -> %.0f%% empty", 100 * b1$na_rate[[cn]], 100 * c1$na_rate[[cn]]))
      }
    }
  }
  # row trace: where in a flow does this run start to differ from the last one?
  if (!is.null(cur$trace) && !is.null(base$trace) && nrow(cur$trace) && nrow(base$trace)) {
    for (flow in intersect(unique(cur$trace$flow), unique(base$trace$flow))) {
      ct <- cur$trace[cur$trace$flow == flow, ]; bt <- base$trace[base$trace$flow == flow, ]
      m <- merge(ct, bt[, c("step", "rows")], by = "step", suffixes = c("", "_before"), all.x = TRUE)
      m <- m[order(m$order), ]
      differs <- !is.na(m$rows_before) & abs(m$rows - m$rows_before) >= DIAG$trace_min_rows &
        abs(m$rows - m$rows_before) / pmax(m$rows_before, 1) >= DIAG$rows_change
      if (any(differs)) {
        i <- which(differs)[1]
        add("attention", flow, "row counts start to differ from the last run at this step",
            sprintf("%s: %s -> %s rows%s", m$step[i], format(m$rows_before[i], big.mark = ","),
                    format(m$rows[i], big.mark = ","),
                    if (i > 1) "; the steps before it are the same" else ""))
      }
      new_steps <- setdiff(ct$step, bt$step); gone_steps <- setdiff(bt$step, ct$step)
      if (length(new_steps) || length(gone_steps)) {
        add("info", flow, "the steps of the row trace changed",
            paste0(length(new_steps), " new, ", length(gone_steps), " no longer recorded"))
      }
    }
  }
  # inputs
  if (!is.null(cur$schema) && !is.null(base$schema) && nrow(cur$schema) && nrow(base$schema)) {
    for (tb in intersect(unique(cur$schema$table), unique(base$schema$table))) {
      cc <- cur$schema$column[cur$schema$table == tb]; bc <- base$schema$column[base$schema$table == tb]
      for (cn in setdiff(cc, bc)) add("attention", paste0("input: ", tb), "new column in workbooks", cn)
      for (cn in setdiff(bc, cc)) add("attention", paste0("input: ", tb), "column no longer in any workbook", cn)
    }
  }
  if (!is.null(base$n_workbooks) && cur$n_workbooks != base$n_workbooks) {
    add("info", "inputs", "number of workbooks changed", sprintf("%d -> %d", base$n_workbooks, cur$n_workbooks))
  }
  if (length(out)) do.call(rbind, out) else finding("info", "", "", "")[0, ]
}

#' Findings that do not need a previous run
current_findings <- function(inventory, issues, log_lines, failures = list()) {
  out <- list()
  add <- function(...) out[[length(out) + 1]] <<- finding(...)
  for (fl in names(failures)) {
    add("attention", fl, "the flow failed",
        paste0(failures[[fl]]$error, if (length(failures[[fl]]$calls)) paste0(" [in: ", paste(failures[[fl]]$calls, collapse = " > "), "]")))
  }
  if (!is.null(inventory) && nrow(inventory)) {
    err <- inventory[nzchar(inventory$read_errors), ]
    for (i in seq_len(nrow(err))) add("attention", "inputs", "workbook could not be read", paste0(err$file[i], ": ", err$read_errors[i]))
    nt <- inventory[inventory$tables_found == 0, ]
    if (nrow(nt)) add("attention", "inputs", "workbooks without any configured table",
                      paste0(nrow(nt), " (e.g. ", paste(utils::head(nt$file, 3), collapse = " | "), ")"))
  }
  if (!is.null(issues) && nrow(issues)) add("attention", "data collection", "issues to send to the workbook owners",
                        paste0(nrow(issues), " in ", length(unique(issues$file)),
                               " workbook(s): see checks/data_collection_issues.csv"))
  w <- grep("^WARNING", log_lines, value = TRUE)
  if (length(w)) add("attention", "run", "warnings during the run", paste0(length(w), ": ", substr(w[1], 1, 160)))
  if (length(out)) do.call(rbind, out) else finding("info", "", "", "")[0, ]
}

# Environment ----

run_environment <- function(root = getwd()) {
  pk <- c("openxlsx2", "dplyr", "tidyr", "purrr", "stringr", "janitor", "readr", "future", "furrr", "httr", "yaml")
  versions <- vapply(pk, function(p) tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed"), "")
  commit <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(root), "rev-parse", "--short", "HEAD"),
                                              stdout = TRUE, stderr = FALSE)), error = function(e) character())
  dirty <- tryCatch(length(suppressWarnings(system2("git", c("-C", shQuote(root), "status", "--porcelain"),
                                                    stdout = TRUE, stderr = FALSE))) > 0, error = function(e) NA)
  list(r = R.version.string, platform = R.version$platform, packages = versions,
       git_commit = if (length(commit)) commit[1] else NA_character_, git_uncommitted_changes = dirty)
}

#' The configuration without secrets, and with paths reduced to their last folder name
sanitised_config <- function(cfg) {
  x <- cfg
  x$gms$user <- NULL; x$gms$password <- NULL
  short <- function(p) if (is.character(p) && length(p) == 1 && nzchar(p)) paste0(".../", basename(p)) else p
  x$paths <- lapply(x$paths, short)
  x$inputs <- lapply(x$inputs, short)
  if (!is.null(x$gms$from_file)) x$gms$from_file <- short(x$gms$from_file)
  if (!is.null(x$outputs$share_dir)) x$outputs$share_dir <- short(x$outputs$share_dir)
  x
}

# Report ----

md_table <- function(df, max_rows = 40) {
  if (is.null(df) || nrow(df) == 0) return("(none)")
  shown <- utils::head(df, max_rows)
  esc <- function(x) gsub("\\|", "/", gsub("[\r\n]+", " ", as.character(x)))
  rows <- apply(shown, 1, function(r) paste0("| ", paste(esc(r), collapse = " | "), " |"))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), rows,
    if (nrow(df) > max_rows) paste0("\n... and ", nrow(df) - max_rows, " more (see the CSV files)"))
}

#' The row trace of one flow as a table with the change per step and the value of the last run
trace_view <- function(trace, flow, base_trace = NULL) {
  t <- trace[trace$flow == flow, ]
  if (nrow(t) == 0) return(NULL)
  change <- c(NA, diff(t$rows))
  last <- if (!is.null(base_trace) && nrow(base_trace)) {
    b <- base_trace[base_trace$flow == flow, ]
    b$rows[match(t$step, b$step)]
  } else rep(NA, nrow(t))
  data.frame(step = t$step, rows = format(t$rows, big.mark = ","),
             change = ifelse(is.na(change), "", sprintf("%+d", change)),
             last_run = ifelse(is.na(last), "", format(last, big.mark = ",")), stringsAsFactors = FALSE)
}

render_report <- function(info) {
  f <- info$findings
  att <- f[f$severity == "attention", ]
  failed <- info$failed
  flow_fail <- info$flow_failures %||% list()

  status <- if (!is.null(failed)) {
    paste0("**Status: THE RUN FAILED while ", failed$stage, ".**")
  } else if (length(flow_fail)) {
    paste0("**Status: ", length(flow_fail), " flow(s) FAILED (", paste(toupper(names(flow_fail)), collapse = ", "),
           "); the others were written.**")
  } else if (nrow(att) == 0) "**Status: nothing needs attention.**" else
    paste0("**Status: ", nrow(att), " point(s) need attention.**")

  failure_block <- NULL
  if (!is.null(failed)) {
    failure_block <- c("## The run failed", "",
      paste0("- Stage: ", failed$stage),
      paste0("- Error: ", failed$message),
      paste0("- In (outermost first): ", if (length(failed$calls)) paste(failed$calls, collapse = " > ") else "(unknown)"),
      "- No outputs were written for the flows that had not yet run. Fix the cause and run again; this report is also in `latest/`.", "")
  }
  if (length(flow_fail)) {
    blocks <- lapply(names(flow_fail), function(fl) {
      x <- flow_fail[[fl]]
      tr <- x$trace
      c(paste0("### ", toupper(fl), " flow"), "",
        paste0("- Error: ", x$error),
        paste0("- In (outermost first): ", if (length(x$calls)) paste(x$calls, collapse = " > ") else "(unknown)"),
        paste0("- Last step completed: ", if (!is.null(tr) && nrow(tr)) paste0(tr$step[nrow(tr)], " (", format(tr$rows[nrow(tr)], big.mark = ","), " rows)") else "none"),
        "", md_table(if (!is.null(tr) && nrow(tr)) utils::tail(data.frame(step = tr$step, rows = format(tr$rows, big.mark = ","), stringsAsFactors = FALSE), 8) else NULL), "")
    })
    failure_block <- c(failure_block, "## Failed flows", "", unlist(blocks))
  }

  trace_block <- NULL
  if (!is.null(info$trace) && nrow(info$trace)) {
    flows <- unique(info$trace$flow)
    trace_block <- c("## Row trace", "",
      "Rows at each recorded step of a flow, the change from the previous step, and the same step in the last run. ",
      "Read it from the top: the first step that differs from the last run, or that loses an unexpected number of rows, is where to look.", "",
      unlist(lapply(flows, function(fl) c(paste0("### ", fl), "", md_table(trace_view(info$trace, fl, info$base_trace), 60), ""))))
  }

  inv <- info$inventory
  lines <- c(
    "# Run diagnostics", "",
    paste0("Run: ", info$timestamp, " | flows: ", paste(info$flows, collapse = ", "),
           if (isTRUE(info$cache_only)) " | cache only" else "", " | reporting year: ", info$cp$year %||% "?"), "",
    status,
    if (is.null(info$baseline_time)) "No earlier successful run to compare with: the next run will be compared with this one." else
      paste0("Compared with the run of ", info$baseline_time, "."), "",
    failure_block,
    "## 1. Attention", "", md_table(att[, c("area", "item", "detail")]), "",
    "## 2. Information", "", md_table(f[f$severity == "info", c("area", "item", "detail")]), "",
    if (!is.null(info$sizes)) c("## 3. Output size", "", md_table(info$sizes), ""),
    trace_block,
    "## 4. Input workbooks", "",
    if (is.null(inv)) "(not available: the run stopped before the workbooks were read)" else c(
      paste0(nrow(inv), " workbook(s) used; ", sum(inv$origin == "read", na.rm = TRUE), " read, ",
             sum(inv$origin == "cache", na.rm = TRUE), " from the cache; ",
             sum(inv$tables_found == 0), " without a configured table."), "",
      "Workbooks per kind of table:", "",
      md_table(if (!is.null(info$schema) && nrow(info$schema)) stats::aggregate(n_tables ~ table, info$schema, max) else data.frame())), "",
    "## 5. Messages and warnings of the run", "",
    if (length(info$log_lines)) c("```", utils::head(info$log_lines, 60), if (length(info$log_lines) > 60) "... (full log in run.log)", "```") else "(none)", "",
    "## 6. Environment", "",
    paste0("- ", info$env$r, " on ", info$env$platform),
    paste0("- code version: ", if (is.na(info$env$git_commit %||% NA)) "no commit yet" else info$env$git_commit,
           if (isTRUE(info$env$git_uncommitted_changes)) " (with uncommitted changes)" else ""),
    paste0("- packages: ", paste0(names(info$env$packages), " ", info$env$packages, collapse = ", ")), "",
    "## 7. Settings of this run (secrets removed)", "", "```yaml",
    trimws(yaml::as.yaml(info$config), "right"), "```", "",
    "## How to use this report", "",
    "- Files in this folder: `findings.csv` (the lists above), `trace.csv` (the row trace), `inputs.csv` (one row per workbook), `schema.csv` (columns per kind of input table), `outputs.csv` (columns and empty-cell rates per output), `run.log`.",
    "- They contain no data rows and no credentials: only names, counts and the values of columns with few distinct values.",
    "- To get help, share this report. Starting points: an *attention* item with a column name usually means a workbook template changed; a row-count change with no input change usually means a filter or a join changed, and the row trace shows at which step.")
  paste(lines[!vapply(lines, is.null, logical(1))], collapse = "\n")
}

#' Build the diagnostics of a finished run (also when some flows failed)
build_diagnostics <- function(cfg, res, log_lines, previous = NULL) {
  outputs <- profile_outputs(res$results)
  inputs <- profile_inputs(res$extracted, cfg)
  trace <- trace_table(res$traces[names(res$results)], res$gms_trace)
  cur <- list(outputs = outputs, schema = inputs$schema, n_workbooks = nrow(inputs$inventory), trace = trace)

  # a flow that failed keeps its earlier baseline, so that the next good run is still compared
  profile_to_save <- cur
  for (fl in names(res$failures)) {
    if (!is.null(previous$profile$outputs[[fl]])) profile_to_save$outputs[[fl]] <- previous$profile$outputs[[fl]]
    if (!is.null(previous$profile$trace)) {
      profile_to_save$trace <- rbind(profile_to_save$trace, previous$profile$trace[previous$profile$trace$flow == fl, ])
    }
  }

  findings <- rbind(current_findings(inputs$inventory, res$issues, log_lines, res$failures),
                    if (!is.null(previous)) compare_profiles(cur, previous$profile))
  findings <- findings[order(findings$severity, findings$area), , drop = FALSE]

  sizes <- do.call(rbind, lapply(names(outputs), function(fl) {
    ex <- outputs[[fl]]$by_exercise
    data.frame(flow = fl, rows = outputs[[fl]]$n, columns = length(outputs[[fl]]$columns),
               by_exercise = if (is.null(ex)) "" else paste0(names(ex), ": ", format(ex, big.mark = ","), collapse = "; "),
               stringsAsFactors = FALSE)
  }))
  flow_failures <- lapply(res$failures, function(x) list(error = x$error, calls = x$calls, trace = x$trace))
  # the trace of the failed flows is shown too, up to the point where they stopped
  show_trace <- rbind(trace, trace_table(lapply(res$failures, function(x) x$trace)))
  list(profile = profile_to_save, findings = findings, inventory = inputs$inventory, schema = inputs$schema,
       sizes = sizes, env = run_environment(), config = sanitised_config(cfg), log_lines = log_lines,
       timestamp = format(Sys.time(), "%Y-%m-%d %H:%M"), flows = c(names(res$results), names(res$failures)),
       cp = res$cp, cache_only = isTRUE(res$cache_only), baseline_time = previous$time,
       trace = show_trace, base_trace = previous$profile$trace, flow_failures = flow_failures)
}

#' Find the profile of the most recent earlier successful run
previous_diagnostics <- function(cfg, current_id = NULL) {
  root <- file.path(cfg$paths$output_dir, "diagnostics")
  dirs <- setdiff(list.dirs(root, recursive = FALSE, full.names = FALSE), c("latest", current_id))
  dirs <- sort(dirs[file.exists(file.path(root, dirs, "profile.rds"))], decreasing = TRUE)
  if (length(dirs) == 0) return(NULL)
  list(profile = readRDS(file.path(root, dirs[1], "profile.rds"))$profile, time = dirs[1])
}

copy_to_latest <- function(dir, root) {
  latest <- file.path(root, "latest")
  unlink(latest, recursive = TRUE)
  dir.create(latest, recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(dir, full.names = TRUE), latest)
  invisible(latest)
}

#' Write the report and its files; returns the folder
write_diagnostics <- function(diag, cfg, run_id) {
  root <- file.path(cfg$paths$output_dir, "diagnostics")
  dir <- file.path(root, run_id)
  assert_outside_source(dir, cfg, "the diagnostics")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  writeLines(render_report(diag), file.path(dir, "report.md"), useBytes = TRUE)
  writeLines(diag$log_lines, file.path(dir, "run.log"), useBytes = TRUE)
  utils::write.csv(diag$findings, file.path(dir, "findings.csv"), row.names = FALSE)
  utils::write.csv(diag$inventory, file.path(dir, "inputs.csv"), row.names = FALSE)
  utils::write.csv(diag$schema, file.path(dir, "schema.csv"), row.names = FALSE)
  utils::write.csv(diag$trace, file.path(dir, "trace.csv"), row.names = FALSE)
  out_tbl <- do.call(rbind, lapply(names(diag$profile$outputs), function(fl) {
    p <- diag$profile$outputs[[fl]]
    data.frame(flow = fl, column = p$columns, empty_share = unname(p$na_rate[p$columns]), stringsAsFactors = FALSE)
  }))
  utils::write.csv(out_tbl, file.path(dir, "outputs.csv"), row.names = FALSE)
  saveRDS(list(profile = diag$profile), file.path(dir, "profile.rds"))
  copy_to_latest(dir, root)
  dir
}

#' Report of a run that stopped before the flows finished
#'
#' Uses whatever the run had produced by then (`state`). No `profile.rds` is saved, so the next
#' run is still compared with the last run that worked.
write_failure_diagnostics <- function(cfg, state, log_lines, failure, flows, cache_only, run_id) {
  root <- file.path(cfg$paths$output_dir, "diagnostics")
  dir <- file.path(root, run_id)
  assert_outside_source(dir, cfg, "the diagnostics")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  inputs <- if (!is.null(state$extracted)) profile_inputs(state$extracted, cfg) else NULL
  findings <- rbind(
    finding("attention", "run", paste0("the run failed while ", failure$stage), failure$message),
    current_findings(inputs$inventory, NULL, log_lines))
  info <- list(
    findings = findings, failed = failure, inventory = inputs$inventory, schema = inputs$schema,
    sizes = NULL, trace = trace_table(list(), state$gms_trace), base_trace = NULL,
    env = run_environment(), config = sanitised_config(cfg), log_lines = log_lines,
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M"), flows = flows, cp = state$cp, cache_only = cache_only,
    baseline_time = NULL)
  writeLines(render_report(info), file.path(dir, "report.md"), useBytes = TRUE)
  writeLines(log_lines, file.path(dir, "run.log"), useBytes = TRUE)
  utils::write.csv(findings, file.path(dir, "findings.csv"), row.names = FALSE)
  if (!is.null(inputs)) {
    utils::write.csv(inputs$inventory, file.path(dir, "inputs.csv"), row.names = FALSE)
    utils::write.csv(inputs$schema, file.path(dir, "schema.csv"), row.names = FALSE)
  }
  copy_to_latest(dir, root)
  dir
}
