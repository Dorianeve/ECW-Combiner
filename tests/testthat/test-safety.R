test_that("path_inside handles nested, sibling, relative and case variants", {
  root <- tempfile("root_"); dir.create(root)
  expect_true(path_inside(file.path(root, "a", "b"), root))
  expect_true(path_inside(root, root))
  expect_true(path_inside(toupper(file.path(root, "a")), root))        # Windows is case-insensitive
  expect_false(path_inside(paste0(root, "_other"), root))              # sibling with same prefix
  expect_false(path_inside(tempfile("elsewhere_"), root))
  old <- setwd(root); on.exit(setwd(old))
  expect_true(path_inside("cache", root))                              # relative path resolves below cwd
})

test_that("assert_outside_source blocks cache, output and share dirs inside the source folder", {
  src <- make_fixture_dir()
  ok <- make_cfg(src)
  expect_true(assert_config_paths_safe(ok))

  bad_cache <- ok; bad_cache$paths$cache_dir <- file.path(src, "cache")
  expect_error(assert_config_paths_safe(bad_cache), "read-only")
  bad_out <- ok; bad_out$paths$output_dir <- file.path(src, "sub", "out")
  expect_error(assert_config_paths_safe(bad_out), "read-only")
  bad_share <- ok; bad_share$outputs <- list(share_dir = src)
  expect_error(assert_config_paths_safe(bad_share), "read-only")
})

test_that("nothing is written to the source folder and the extractor refuses to cache there", {
  src <- make_fixture_dir()
  before <- source_fingerprint(make_cfg(src))
  cfg <- make_cfg(src)
  ex <- extract_all(cfg)                                    # normal run
  expect_true(source_changes(before, source_fingerprint(cfg))$untouched)

  bad <- make_cfg(src); bad$paths$cache_dir <- file.path(src, "cache")
  expect_error(extract_all(bad, workers = 1), "read-only")
  expect_false(dir.exists(file.path(src, "cache")))
})

test_that("source_changes reports added, removed and modified files", {
  src <- make_fixture_dir(); cfg <- make_cfg(src)
  before <- source_fingerprint(cfg)
  file.create(file.path(src, "new.txt"))
  file.remove(file.path(src, "Unrelated.xlsx"))
  writeLines("x", file.path(src, "sub", "Programme template B.xlsx"))
  ch <- source_changes(before, source_fingerprint(cfg))
  expect_false(ch$untouched)
  expect_length(ch$added, 1); expect_length(ch$removed, 1); expect_length(ch$changed, 1)
  expect_warning(verify_source_untouched(before, cfg), "source folder changed")
})

test_that("a full pipeline run leaves the source folder untouched", {
  cfg <- make_pipeline_fixture(workers = 1)
  before <- source_fingerprint(cfg)
  out <- suppressMessages(run_pipeline(cfg, root = repo_root()))
  expect_true(source_changes(before, source_fingerprint(cfg))$untouched)
  expect_equal(out$log$rows[out$log$step == "source_folder_untouched"], 1)

  bad <- cfg; bad$paths$output_dir <- file.path(cfg$paths$source_dir, "out")
  expect_error(run_pipeline(bad, write = FALSE, root = repo_root()), "read-only")
  expect_false(dir.exists(file.path(cfg$paths$source_dir, "out")))
})
