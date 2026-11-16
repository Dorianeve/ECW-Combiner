test_that("the full pipeline runs end to end on synthetic workbooks (sequential)", {
  cfg <- make_pipeline_fixture(workers = 1)
  out <- suppressMessages(run_pipeline(cfg, root = repo_root()))

  expect_setequal(names(out$results), c("cr", "pr", "af", "dcm"))
  expect_true(all(c("ARR25 Annual", "ARR25 Cumulative") %in% out$results$cr$combiner$Exercise))
  expect_true("Strongly aligned" %in% out$results$af$combiner$alignment_score)
  expect_equal(out$results$dcm$combiner$ProgrammeID, "P9")
  expect_true(any(out$results$pr$combiner$Gender == "Total", na.rm = TRUE))

  # files written
  for (flow in c("cr", "pr", "af", "dcm")) {
    expect_true(file.exists(file.path(cfg$paths$output_dir, flow, paste0(flow, "_clean.xlsx"))))
  }
  expect_true(file.exists(file.path(cfg$paths$output_dir, "run_log.csv")))

  # PR mirrors the legacy outputs: dated CSV = before the final tidy-up, XLSX/pr_clean.csv = tidied
  pr_dir <- file.path(cfg$paths$output_dir, "pr")
  raw_csv <- read_combiner_file(list.files(pr_dir, pattern = "cleaned\\.csv$", full.names = TRUE))
  final_csv <- read_combiner_file(file.path(pr_dir, "pr_clean.csv"))
  expect_true("Yes" %in% raw_csv$DisaggregatedBySex)          # not yet normalised
  expect_false("Yes" %in% final_csv$DisaggregatedBySex)       # lower-cased by the final step
  expect_true("yes" %in% final_csv$DisaggregatedBySex)
  expect_false("table_index" %in% names(out$results$pr$combiner))
  expect_true(all(c("extract", "gms", "flows_wall", "flow_cr") %in% out$log$step))
})

test_that("parallel and sequential runs give the same combiners", {
  seq_out <- suppressMessages(run_pipeline(make_pipeline_fixture(1), write = FALSE, root = repo_root()))
  par_out <- suppressMessages(run_pipeline(make_pipeline_fixture(2), write = FALSE, root = repo_root()))
  for (flow in c("cr", "pr", "af", "dcm")) {
    cmp <- compare_tables(par_out$results[[flow]]$combiner, seq_out$results[[flow]]$combiner)
    expect_true(cmp$identical)
  }
})

test_that("a subset of flows can be run", {
  out <- suppressMessages(run_pipeline(make_pipeline_fixture(1), flows = "af", write = FALSE, root = repo_root()))
  expect_equal(names(out$results), "af")
})

test_that("written CSV matches the in-memory result and compare_tables detects changes", {
  cfg <- make_pipeline_fixture(1)
  out <- suppressMessages(run_pipeline(cfg, flows = "af", root = repo_root()))
  csv <- list.files(file.path(cfg$paths$output_dir, "af"), pattern = "csv$", full.names = TRUE)
  written <- read_combiner_file(csv)
  expect_true(compare_tables(written, out$results$af$combiner)$identical)

  changed <- written
  changed$sum_total_funding[1] <- "999"
  cmp <- compare_tables(changed, written, key = "donor")
  expect_false(cmp$identical)
  expect_equal(nrow(cmp$cell_diffs), 1)
  expect_equal(cmp$cell_diffs$column, "sum_total_funding")

  dropped <- compare_tables(written[-1, ], written)
  expect_equal(dropped$rows[["only_old"]], 1)
  renamed <- written; names(renamed)[1] <- "renamed"
  expect_true(length(compare_tables(renamed, written)$columns$only_in_new) == 1)
})

test_that("normalise_column treats 1, 1.0 and ' 1 ' alike and blanks as NA", {
  expect_equal(normalise_column(c("1", "1.0", " 1 ", "", "NA")), c("1", "1", "1", NA, NA))
  expect_equal(normalise_column(c("a", " b ")), c("a", "b"))
})

test_that("normalise_column compares numbers cell by cell in mixed columns", {
  expect_equal(normalise_column(c("1e+05", "100000", "100000.0", "text", "0.28999999999999998", "0.29")),
               c("100000", "100000", "100000", "text", "0.29", "0.29"))
})

test_that("the GMS export is saved on download and reused in cache-only mode", {
  cfg <- make_pipeline_fixture(1); cfg$gms$from_file <- NULL
  old <- get("gms_fetch", envir = globalenv())
  assign("gms_fetch", function(cfg, endpoint = "grants") synthetic_gms_raw(), envir = globalenv())
  on.exit(assign("gms_fetch", old, envir = globalenv()))

  expect_error(gms_load(cfg, cache_only = TRUE), "No saved GMS export")
  live <- gms_load(cfg)
  expect_true(file.exists(file.path(cfg$paths$cache_dir, "gms", "grants_latest.csv")))
  assign("gms_fetch", function(cfg, endpoint = "grants") stop("must not be called"), envir = globalenv())
  saved <- suppressMessages(gms_load(cfg, cache_only = TRUE))
  expect_equal(nrow(saved), nrow(live))
  expect_equal(as.data.frame(saved)$GMGRN, as.data.frame(live)$GMGRN)
})

test_that("a cache-only pipeline run gives the same combiners with the source folder gone", {
  cfg <- make_pipeline_fixture(1)
  normal <- suppressMessages(run_pipeline(cfg, write = FALSE, root = repo_root()))
  unlink(cfg$paths$source_dir, recursive = TRUE)
  cached <- suppressMessages(run_pipeline(cfg, write = FALSE, root = repo_root(), cache_only = TRUE))
  for (flow in c("cr", "pr", "af", "dcm")) {
    expect_true(compare_tables(cached$results[[flow]]$combiner, normal$results[[flow]]$combiner)$identical)
  }
  expect_false("source_folder_untouched" %in% cached$log$step)       # nothing was read, nothing to verify
})

test_that("compare_tables can ignore columns such as the run date", {
  new <- data.frame(id = 1:3, v = c("a", "b", "c"), ExportDate = "2026-10-08")
  old <- data.frame(id = 1:3, v = c("a", "b", "c"), ExportDate = "2026-10-06")
  expect_false(compare_tables(new, old)$identical)
  expect_true(compare_tables(new, old, ignore = "ExportDate")$identical)
  expect_true(compare_tables(new, old, key = "id", ignore = "ExportDate")$identical)
})

test_that("flow_unmatched lists current-cycle rows without a ProgrammeID, by workbook", {
  cp <- test_cp()
  results <- list(
    cr = list(combiner = data.frame(
      ProgrammeID = c("P1", NA, NA, NA), Filename = c("a.xlsx", "b.xlsx", "b.xlsx", "old.xlsx"),
      Exercise = c("ARR25 Annual", "ARR25 Annual", "ARR25 Cumulative", "ARR24 Cumulative"))),
    af = list(combiner = data.frame(ProgrammeID = c("P1", NA), file_name = c("c.xlsx", "c.xlsx"))))
  out <- flow_unmatched(results, cp)
  expect_equal(nrow(out), 2)
  expect_equal(out$n_rows[out$file == "b.xlsx"], 2L)               # history row (ARR24) is not counted
  expect_equal(out$table[out$file == "c.xlsx"], "af")
  expect_equal(nrow(flow_unmatched(list(cr = list(combiner = data.frame(ProgrammeID = "P1", Exercise = "ARR25 Annual"))), cp)), 0)
})

test_that("a pipeline run writes the data-collection issues file", {
  cfg <- make_pipeline_fixture(1)
  # grantee keeps typing under the aligned-funding table
  f <- file.path(cfg$paths$source_dir, "Programme template Z.xlsx")
  wb <- openxlsx2::wb_load(f)
  wb$add_data("tbl_af", data.frame(a = "typed below", b = "x"), start_row = 6, col_names = FALSE)
  wb$save(f)

  out <- suppressMessages(run_pipeline(cfg, flows = "af", root = repo_root()))
  path <- file.path(cfg$paths$output_dir, "checks", "data_collection_issues.csv")
  expect_true(file.exists(path))
  issues <- utils::read.csv(path)
  expect_true("content_below_table" %in% issues$issue)
  expect_equal(issues$file[issues$issue == "content_below_table"], "Programme template Z.xlsx")
  expect_equal(out$issues$issue, issues$issue)
})

test_that("data-collection checks cover every flow and every extracted table", {
  # no-programme-match: PR and DCM use the file column FileName, like their real outputs
  cp <- test_cp()
  results <- list(
    pr = list(combiner = data.frame(ProgrammeID = c("P1", NA, NA), FileName = c("p1.xlsx", "p2.xlsx", "p2.xlsx"),
                                    Exercise = c("ARR25 Annual", "ARR25 Annual", "ARR25 Cumulative"))),
    dcm = list(combiner = data.frame(ProgrammeID = c(NA, "P9"), FileName = c("d1.xlsx", "d2.xlsx"))))
  out <- flow_unmatched(results, cp)
  expect_setequal(out$table, c("pr", "dcm"))
  expect_equal(out$n_rows[out$table == "pr"], 2L)
  expect_equal(out$file[out$table == "dcm"], "d1.xlsx")

  # rows below a table: the check lives in the generic reader, so it applies to all six tables
  dir <- tempfile("all_tables_"); dir.create(dir)
  file <- file.path(dir, "Results template A.xlsx")
  wb <- openxlsx2::wb_workbook()
  tables <- c("tbl_children", "tbl_results", "tbl_si", "tbl_rw", "tbl_af", "tbl_dcm")
  for (tn in tables) {
    wb$add_worksheet(tn)
    wb$add_data_table(tn, data.frame(a = c("r1", "r2"), b = 1:2), table_name = tn)             # A1:B3
    wb$add_data(tn, data.frame(a = "below", b = 9), start_row = 4, col_names = FALSE)
  }
  wb$save(file)
  res <- read_workbook_tables(file, tables)
  expect_setequal(res$issues$table, tables)
  expect_true(all(res$issues$n_rows == 1L))
})

test_that("normalise_column ignores the carriage return of Windows line breaks", {
  expect_equal(normalise_column(c("a\r\nb", "a\nb")), c("a\nb", "a\nb"))
  new <- data.frame(id = 1:2, txt = c("x\ny", "z"))
  old <- data.frame(id = 1:2, txt = c("x\r\ny", "z"))
  expect_true(compare_tables(new, old)$identical)
})
