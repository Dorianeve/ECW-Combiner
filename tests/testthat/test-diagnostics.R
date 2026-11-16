test_that("compare_profiles reports schema, value, empty-share and row-count changes", {
  mk <- function(cols, n, na, cats) list(n = n, columns = cols, na_rate = na, categories = cats, by_exercise = NULL)
  base <- list(outputs = list(cr = mk(c("a", "b", "Unit"), 1000, c(a = 0, b = 0.1, Unit = 0),
                                       list(Unit = c(Number = 900, US = 100)))),
               schema = data.frame(table = "children", column = c("x", "y"), n_tables = 3, n_tables_with = 3),
               n_workbooks = 5)
  cur <- list(outputs = list(cr = mk(c("a", "c", "Unit"), 1300, c(a = 0.5, c = 0, Unit = 0),
                                      list(Unit = c(Number = 1000, Euro = 300)))),
              schema = data.frame(table = "children", column = c("x", "z"), n_tables = 3, n_tables_with = 3),
              n_workbooks = 6)
  f <- compare_profiles(cur, base)
  has <- function(item, pattern = "") any(f$item == item & grepl(pattern, f$detail))
  expect_true(has("new output column", "^c$"))
  expect_true(has("output column disappeared", "^b$"))
  expect_true(has("new value(s) in Unit", "Euro"))
  expect_true(has("value(s) no longer in Unit", "US"))
  expect_true(any(grepl("share of empty cells changed in a", f$item)))
  expect_true(has("row count changed", "[+]30%"))
  expect_true(has("new column in workbooks", "^z$"))
  expect_true(has("column no longer in any workbook", "^y$"))
  expect_true(has("number of workbooks changed", "5 -> 6"))
  expect_equal(nrow(compare_profiles(base, base)), 0)
})

test_that("a pipeline run writes a diagnostics report without secrets", {
  cfg <- make_pipeline_fixture(1)
  cfg$gms$user <- "SECRET-USER-NAME"; cfg$gms$password <- "SECRET-PASSWORD-123"
  out <- suppressMessages(run_pipeline(cfg, root = repo_root()))

  dir <- out$diagnostics_dir
  expect_true(dir.exists(dir))
  for (f in c("report.md", "findings.csv", "inputs.csv", "schema.csv", "outputs.csv", "run.log", "profile.rds")) {
    expect_true(file.exists(file.path(dir, f)))
  }
  expect_true(file.exists(file.path(cfg$paths$output_dir, "diagnostics", "latest", "report.md")))

  report <- paste(readLines(file.path(dir, "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("# Run diagnostics", report, fixed = TRUE))
  expect_true(grepl("No earlier successful run to compare with", report, fixed = TRUE))
  expect_true(grepl("Input workbooks", report, fixed = TRUE))
  everything <- paste(c(report, unlist(lapply(list.files(dir, "[.](csv|log)$", full.names = TRUE), readLines, warn = FALSE))), collapse = "\n")
  expect_false(grepl("SECRET-USER-NAME|SECRET-PASSWORD-123", everything))        # no credentials anywhere
  expect_false(grepl(cfg$paths$source_dir, report, fixed = TRUE))                 # full paths are shortened
  inv <- utils::read.csv(file.path(dir, "inputs.csv"))
  expect_equal(nrow(inv), 5)                                                      # the five fixture workbooks
})

test_that("a second run is compared with the first and a change in the outputs is flagged", {
  cfg <- make_pipeline_fixture(1)
  suppressMessages(run_pipeline(cfg, root = repo_root()))
  Sys.sleep(1.1)                                                                  # different run folder name

  cfg$reporting$exercises <- list(annual_label = "Yearly report {year}")          # a changed label = a new category value
  out2 <- suppressMessages(run_pipeline(cfg, root = repo_root()))
  f <- utils::read.csv(file.path(out2$diagnostics_dir, "findings.csv"))
  expect_true(any(f$item == "new value(s) in Exercise" & grepl("Yearly report 2025", f$detail)))
  expect_true(any(f$item == "value(s) no longer in Exercise" & grepl("ARR25 Annual", f$detail)))
  report <- paste(readLines(file.path(out2$diagnostics_dir, "report.md"), warn = FALSE), collapse = "\n")
  expect_false(grepl("No earlier successful run to compare with", report, fixed = TRUE))
})

test_that("diagnostics can be switched off and are skipped when nothing is written", {
  cfg <- make_pipeline_fixture(1)
  r1 <- suppressMessages(run_pipeline(cfg, flows = "af", write = FALSE, root = repo_root()))
  expect_null(r1$diagnostics_dir)
  cfg$diagnostics <- list(enabled = FALSE)
  r2 <- suppressMessages(run_pipeline(cfg, flows = "af", root = repo_root()))
  expect_null(r2$diagnostics_dir)
  expect_false(dir.exists(file.path(cfg$paths$output_dir, "diagnostics")))
})

test_that("trace_step passes data through and counts rows, also of lists of tables", {
  trace_reset()
  df <- data.frame(a = 1:5)
  out <- trace_step(df, "five")
  expect_identical(out, df)
  trace_step(list(df, df[1:2, , drop = FALSE], "not a table"), "list of tables")
  t <- trace_get()
  expect_equal(t$step, c("five", "list of tables"))
  expect_equal(t$rows, c(5L, 7L))
  trace_reset()
  expect_equal(nrow(trace_get()), 0)
})

test_that("a successful run records a row trace per flow and writes trace.csv", {
  cfg <- make_pipeline_fixture(1)
  out <- suppressMessages(run_pipeline(cfg, root = repo_root()))
  tr <- utils::read.csv(file.path(out$diagnostics_dir, "trace.csv"))
  expect_true(all(c("gms", "cr", "pr", "af", "dcm") %in% tr$flow))
  expect_true("CR source: after dropping rows without a GRN" %in% tr$step)
  expect_true("PR pivot: rows after pivoting to long format" %in% tr$step)
  expect_true("AF join: after joining the GMS (should not add rows)" %in% tr$step)
  # the join steps must not add rows
  cr <- tr[tr$flow == "cr", ]
  expect_equal(cr$rows[cr$step == "CR join: after joining the GMS (should not add rows)"],
               cr$rows[cr$step == "CR source: after dropping rows without a GRN"])
  report <- paste(readLines(file.path(out$diagnostics_dir, "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("## Row trace", report, fixed = TRUE))
})

test_that("the trace shows where this run starts to differ from the previous one", {
  cfg <- make_pipeline_fixture(1)
  suppressMessages(run_pipeline(cfg, root = repo_root()))
  Sys.sleep(1.1)
  cfg$reporting$exercises <- list(create = list("annual"), carry_over_inactive = FALSE)   # fewer rows at the end of CR
  out2 <- suppressMessages(run_pipeline(cfg, root = repo_root()))
  f <- utils::read.csv(file.path(out2$diagnostics_dir, "findings.csv"))
  hit <- f[f$area == "cr" & f$item == "row counts start to differ from the last run at this step", ]
  expect_equal(nrow(hit), 1)
  expect_true(grepl("CR final: current-cycle rows x exercises", hit$detail, fixed = TRUE))
  expect_true(grepl("the steps before it are the same", hit$detail, fixed = TRUE))
})

test_that("one failing flow does not stop the others; the report says which and where", {
  cfg <- make_pipeline_fixture(1)
  bad <- file.path(dirname(cfg$inputs$previous_cr_combiner), "broken_cr.csv")
  utils::write.csv(data.frame(unexpected = 1), bad, row.names = FALSE)               # no usable previous CR combiner
  cfg$inputs$previous_cr_combiner <- bad

  expect_error(suppressWarnings(suppressMessages(run_pipeline(cfg, root = repo_root()))), "CR [(]")
  # the other flows were written
  for (flow in c("pr", "af", "dcm")) {
    expect_true(file.exists(file.path(cfg$paths$output_dir, flow, paste0(flow, "_clean.xlsx"))))
  }
  expect_false(file.exists(file.path(cfg$paths$output_dir, "cr", "cr_clean.xlsx")))

  latest <- file.path(cfg$paths$output_dir, "diagnostics", "latest")
  report <- paste(readLines(file.path(latest, "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("1 flow(s) FAILED (CR)", report, fixed = TRUE))
  expect_true(grepl("## Failed flows", report, fixed = TRUE))
  expect_true(grepl("cr_prepare_previous", report, fixed = TRUE))                    # where it failed
  expect_true(grepl("Last step completed: CR clean:", report, fixed = TRUE))          # how far it got
  f <- utils::read.csv(file.path(latest, "findings.csv"))
  expect_true(any(f$area == "cr" & f$item == "the flow failed"))
  log <- readLines(file.path(cfg$paths$output_dir, "run_log.csv"))
  expect_true(any(grepl("flow_cr_FAILED", log)))
})

test_that("a failure before the flows still writes a report, and does not spoil the baseline", {
  cfg <- make_pipeline_fixture(1)
  suppressMessages(run_pipeline(cfg, root = repo_root()))                             # a good run first
  Sys.sleep(1.1)

  broken <- cfg; broken$paths$reference_dir <- tempfile("no_reference_")              # PR needs its lookup tables
  expect_error(suppressWarnings(suppressMessages(run_pipeline(broken, flows = "pr", root = repo_root()))),
               "stopped while preparing the flows")
  latest <- file.path(cfg$paths$output_dir, "diagnostics", "latest")
  report <- paste(readLines(file.path(latest, "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("THE RUN FAILED while preparing the flows", report, fixed = TRUE))
  expect_true(grepl("## The run failed", report, fixed = TRUE))
  expect_true(grepl("load_pr_reference", report, fixed = TRUE))                        # function where it failed
  expect_true(grepl("[0-9]+ workbook[(]s[)] used", report))                            # inputs known by then (only the PR workbooks)
  expect_false(file.exists(file.path(latest, "profile.rds")))                          # no baseline from a failed run

  Sys.sleep(1.1)
  out <- suppressMessages(run_pipeline(cfg, root = repo_root()))                       # next good run
  report2 <- paste(readLines(file.path(out$diagnostics_dir, "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("Compared with the run of", report2, fixed = TRUE))                # compared with the good one
})

test_that("an empty cache in cache-only mode fails with a report, not silently", {
  cfg <- make_pipeline_fixture(1)
  expect_error(suppressMessages(run_pipeline(cfg, root = repo_root(), cache_only = TRUE)),
               "stopped while reading the cached workbook tables")
  report <- paste(readLines(file.path(cfg$paths$output_dir, "diagnostics", "latest", "report.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("The cache is empty", report, fixed = TRUE))
  expect_true(grepl("not available: the run stopped before the workbooks were read", report, fixed = TRUE))
})
