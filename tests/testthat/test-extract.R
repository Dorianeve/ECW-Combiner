test_that("list_source_files matches patterns recursively and skips lock files", {
  src <- make_fixture_dir()
  files <- list_source_files(make_cfg(src))
  expect_equal(sort(basename(files)), c("Programme template B.xlsx", "Results template A.xlsx"))
})

test_that("extract_all pulls every requested table in one pass", {
  src <- make_fixture_dir()
  cfg <- make_cfg(src)
  ex <- extract_all(cfg)

  expect_setequal(names(ex), c("Programme template B.xlsx", "Results template A.xlsx"))
  children <- collect_tables(ex, "tbl_children")
  expect_length(children, 2)
  expect_true(all(c("file_name", "table_index") %in% names(children[[1]])))
  expect_equal(sum(vapply(children, nrow, integer(1))), 5)

  # only the Results workbook has tbl_other
  expect_length(collect_tables(ex, "tbl_other"), 1)
  # file_pattern restricts contributing files
  expect_length(collect_tables(ex, "tbl_children", "^Programme"), 1)
})

test_that("second run is served from cache; a changed file is re-read", {
  src <- make_fixture_dir()
  cfg <- make_cfg(src)

  first <- extract_all(cfg)
  expect_true(all(vapply(first, function(r) r$origin, "") == "read"))

  second <- extract_all(cfg)
  expect_true(all(vapply(second, function(r) r$origin, "") == "cache"))
  expect_equal(collect_tables(first, "tbl_children"), collect_tables(second, "tbl_children"))

  # modify one workbook -> only that one is re-read
  target <- file.path(src, "sub", "Programme template B.xlsx")
  wb <- openxlsx2::wb_workbook()
  wb$add_worksheet("tbl_children")
  wb$add_data_table("tbl_children", data.frame(a = 1:10, b = "n"), table_name = "tbl_children")
  wb$save(target)
  Sys.setFileTime(target, Sys.time() + 5)

  third <- extract_all(cfg)
  origin <- vapply(third, function(r) r$origin, "")
  expect_equal(origin[["Programme template B.xlsx"]], "read")
  expect_equal(origin[["Results template A.xlsx"]], "cache")

  # refresh = TRUE bypasses the cache
  fourth <- extract_all(cfg, refresh = TRUE)
  expect_true(all(vapply(fourth, function(r) r$origin, "") == "read"))
})

test_that("parallel and sequential extraction give identical results", {
  src <- make_fixture_dir()
  seq_res <- extract_all(make_cfg(src), workers = 1)
  par_res <- extract_all(make_cfg(src, workers = 2), workers = 2)
  expect_equal(collect_tables(seq_res, "tbl_children"), collect_tables(par_res, "tbl_children"))
  expect_equal(names(seq_res), names(par_res))
})

test_that("unreadable workbook is reported, not fatal, and not cached", {
  src <- make_fixture_dir()
  writeLines("not an xlsx", file.path(src, "Results template broken.xlsx"))
  cfg <- make_cfg(src)

  expect_warning(ex <- extract_all(cfg), "read errors")
  rep <- extraction_report(ex)
  expect_true(nzchar(rep$errors[rep$file == "Results template broken.xlsx"]))
  expect_length(collect_tables(ex, "tbl_children"), 2)

  # failed file is retried next time (not cached)
  expect_warning(ex2 <- extract_all(cfg), "read errors")
  expect_equal(ex2[["Results template broken.xlsx"]]$origin, "read")
})

test_that("fix_blank_names gives valid unique names", {
  expect_equal(fix_blank_names(c("a", NA, " ", "a")), c("a", "col_2", "col_3", "a.1"))
})

test_that("ARCHIVED workbooks are excluded by default and the setting can be changed", {
  src <- make_fixture_dir()
  file.copy(file.path(src, "Results template A.xlsx"), file.path(src, "ARCHIVED - Results template A.xlsx"))
  file.copy(file.path(src, "Results template A.xlsx"), file.path(src, "sub", "archived - Programme template Z.xlsx"))
  cfg <- make_cfg(src)

  files <- suppressMessages(list_source_files(cfg))                 # default: ^ARCHIVED, any case
  expect_equal(sort(basename(files)), c("Programme template B.xlsx", "Results template A.xlsx"))

  cfg$source$exclude_patterns <- list()                              # exclude nothing
  expect_length(list_source_files(cfg), 4)

  cfg$source$exclude_patterns <- list("Programme")                   # custom pattern
  expect_false(any(grepl("Programme", basename(list_source_files(cfg)))))
})

test_that("cache_only uses the cache and ignores the source folder entirely", {
  src <- make_fixture_dir(); cfg <- make_cfg(src)
  first <- suppressMessages(extract_all(cfg))

  # change a workbook after it was cached
  target <- file.path(src, "sub", "Programme template B.xlsx")
  wb <- openxlsx2::wb_workbook(); wb$add_worksheet("tbl_children")
  wb$add_data_table("tbl_children", data.frame(a = 1:10, b = "changed"), table_name = "tbl_children")
  wb$save(target); Sys.setFileTime(target, Sys.time() + 10)

  cached <- suppressMessages(extract_all(cfg, cache_only = TRUE))
  expect_equal(collect_tables(cached, "tbl_children"), collect_tables(first, "tbl_children"))  # still the old data
  expect_true(all(vapply(cached, function(r) r$origin, "") == "cache"))
  fresh <- suppressMessages(extract_all(cfg))                                                # normal run re-reads it
  expect_equal(sum(vapply(collect_tables(fresh, "tbl_children"), nrow, integer(1))), 3 + 10)

  # the source folder can even disappear
  unlink(src, recursive = TRUE)
  gone <- suppressMessages(extract_all(cfg, cache_only = TRUE))
  expect_length(gone, 2)
})

test_that("cache_only fails clearly when the cache is empty or lacks a table", {
  src <- make_fixture_dir(); cfg <- make_cfg(src)
  expect_error(extract_all(cfg, cache_only = TRUE), "cache is empty")
  suppressMessages(extract_all(cfg, tables = "tbl_children"))
  expect_error(suppressMessages(extract_all(cfg, tables = c("tbl_children", "tbl_other"), cache_only = TRUE)),
               "lack a requested table")
  cfg$source$exclude_patterns <- list("template")                    # excludes everything cached
  expect_error(suppressMessages(extract_all(cfg, tables = "tbl_children", cache_only = TRUE)), "No cached workbooks")
})

test_that("rows typed directly below a table are reported, but not read", {
  dir <- tempfile("below_"); dir.create(dir)
  file <- file.path(dir, "Results template A.xlsx")
  wb <- openxlsx2::wb_workbook(); wb$add_worksheet("s")
  wb$add_data_table("s", data.frame(a = c("r1", "r2", "r3"), b = 1:3), table_name = "tbl_children")   # A1:B4
  wb$add_data("s", data.frame(a = c("extra1", "extra2"), b = 8:9), start_row = 5, col_names = FALSE)   # directly below
  wb$add_data("s", data.frame(a = "far away", b = 0), start_row = 9, col_names = FALSE)                # after a gap
  wb$save(file)

  res <- read_workbook_tables(file, "tbl_children")
  expect_equal(nrow(res$tables$tbl_children[[1]]), 3)               # only the table is read
  expect_equal(nrow(res$issues), 1)
  expect_equal(res$issues$issue, "content_below_table")
  expect_equal(res$issues$n_rows, 2L)                               # the row after the gap is not counted
  expect_true(grepl("extra1", res$issues$detail))
  expect_equal(res$issues$file, "Results template A.xlsx")
})

test_that("a clean workbook has no issues; extraction_issues collects them and counts unchecked caches", {
  src <- make_fixture_dir(); cfg <- make_cfg(src)
  ex <- suppressMessages(extract_all(cfg))
  chk <- extraction_issues(ex)
  expect_equal(nrow(chk$issues), 0)
  expect_equal(chk$unchecked, 0)

  # a cache entry written before the checks existed has no `issues` field
  ex[[1]]$issues <- NULL
  expect_equal(extraction_issues(ex)$unchecked, 1)
})

test_that("known template text under a table is not reported, anything else is", {
  dir <- tempfile("known_"); dir.create(dir)
  file <- file.path(dir, "Results template K.xlsx")
  wb <- openxlsx2::wb_workbook(); wb$add_worksheet("s")
  wb$add_data_table("s", data.frame(a = c("r1", "r2"), b = 1:2), table_name = "tbl_children")   # A1:B3
  wb$add_data("s", data.frame(a = c("Footer text of the template", "A donor line"), b = NA), start_row = 4, col_names = FALSE)
  wb$save(file)
  ex <- list(k = c(read_workbook_tables(file, "tbl_children"), list(file = file)))

  all <- extraction_issues(ex)$issues                      # no list of known text: both rows reported
  expect_equal(all$n_rows, 2L)

  cfg <- list(tables = list(children = "tbl_children"),
              checks = list(known_text_below_tables = list(children = list("^Footer text"))))
  some <- extraction_issues(ex, cfg)$issues
  expect_equal(some$n_rows, 1L)                            # only the donor line is left
  expect_true(grepl("A donor line", some$detail) && !grepl("Footer", some$detail))

  cfg$checks$known_text_below_tables$children <- list("^Footer text", "^A donor")
  expect_equal(nrow(extraction_issues(ex, cfg)$issues), 0) # nothing left: no issue
})

test_that("only the requested workbook families are read", {
  src <- make_fixture_dir(); cfg <- make_cfg(src)
  all <- suppressMessages(extract_all(cfg))
  res <- suppressMessages(extract_all(cfg, families = "results"))
  expect_true(length(res) < length(all))
  expect_true(all(grepl("^Results template", names(res))))
  expect_equal(FLOW_FAMILIES$af, c("programme", "aligned"))
})

test_that("the cache key does not depend on how the source folder is written", {
  a <- file.path(tempfile("srcA_"), "sub"); b <- file.path(tempfile("srcB_"), "sub")
  dir.create(a, recursive = TRUE); dir.create(b, recursive = TRUE)
  file.create(file.path(a, "Results template X.xlsx")); file.create(file.path(b, "Results template X.xlsx"))
  cfg_a <- list(paths = list(source_dir = dirname(a), cache_dir = "cache"))
  cfg_b <- list(paths = list(source_dir = dirname(b), cache_dir = "cache"))
  # same workbook inside two differently named source folders -> same cache entry
  expect_equal(cache_file_for(cfg_a, file.path(a, "Results template X.xlsx")),
               cache_file_for(cfg_b, file.path(b, "Results template X.xlsx")))
  file.create(file.path(a, "Results template Y.xlsx"))
  expect_false(identical(cache_file_for(cfg_a, file.path(a, "Results template X.xlsx")),
                         cache_file_for(cfg_a, file.path(a, "Results template Y.xlsx"))))
})

test_that("same_path_key treats WSL and Windows forms of a path as the same", {
  expect_equal(same_path_key("/mnt/c/Data/Grants DB/A.xlsx"), same_path_key("C:/Data/Grants DB/a.xlsx"))
  expect_false(same_path_key("C:/Data/x/A.xlsx") == same_path_key("C:/Data/y/A.xlsx"))   # same name, other folder
})
