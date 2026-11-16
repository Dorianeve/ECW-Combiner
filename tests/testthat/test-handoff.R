# Hand-over to the AnnualResultsReport repository ----
# cr_clean.xlsx, pr_clean.xlsx and grants_db.csv are copied to <ARR>/data/input/.

handoff_cfg <- function(root, arr = TRUE, arr_exists = TRUE) {
  dir.create(file.path(root, "src"), recursive = TRUE)
  if (arr_exists) dir.create(file.path(root, "ARR", "data"), recursive = TRUE)
  list(paths = list(source_dir = file.path(root, "src"), output_dir = file.path(root, "out")),
       outputs = list(share_dir = NULL,
                      arr_input_dir = if (arr) file.path(root, "ARR", "data", "input")))
}

test_that("the combiners and the GMS table are copied to the AnnualResultsReport input folder", {
  root <- tempfile("handoff"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cfg <- handoff_cfg(root)
  df <- data.frame(a = 1:3, b = c("x", "y", "z"))

  write_combiner(df, "cr", cfg)
  write_combiner(df, "pr", cfg)
  write_grants_db(df, cfg)

  arr <- cfg$outputs$arr_input_dir
  expect_true(all(file.exists(file.path(arr, c("cr_clean.xlsx", "pr_clean.xlsx", "grants_db.csv")))))
  # the GMS table is also kept in the Combiner's own output folder
  expect_true(file.exists(file.path(cfg$paths$output_dir, "gms", "grants_db.csv")))
  expect_equal(utils::read.csv(file.path(arr, "grants_db.csv")), df)
})

test_that("AF and DCM are not handed over", {
  root <- tempfile("handoff"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cfg <- handoff_cfg(root)
  write_combiner(data.frame(a = 1), "af", cfg)
  expect_false(file.exists(file.path(cfg$outputs$arr_input_dir, "af_clean.xlsx")))
})

test_that("nothing is copied when the hand-over is switched off", {
  root <- tempfile("handoff"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cfg <- handoff_cfg(root, arr = FALSE)
  expect_silent(write_combiner(data.frame(a = 1), "cr", cfg))
  expect_silent(write_grants_db(data.frame(a = 1), cfg))
  expect_true(file.exists(file.path(cfg$paths$output_dir, "gms", "grants_db.csv")))
})

test_that("a missing AnnualResultsReport folder gives a warning and does not stop the run", {
  root <- tempfile("handoff"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cfg <- handoff_cfg(root, arr_exists = FALSE)
  expect_warning(write_combiner(data.frame(a = 1), "cr", cfg), "AnnualResultsReport was not found")
  expect_true(file.exists(file.path(cfg$paths$output_dir, "cr", "cr_clean.xlsx")))
})

test_that("the hand-over folder may not be inside the source folder", {
  root <- tempfile("handoff"); on.exit(unlink(root, recursive = TRUE), add = TRUE)
  cfg <- handoff_cfg(root)
  cfg$outputs$arr_input_dir <- file.path(cfg$paths$source_dir, "ARR", "data", "input")
  expect_error(assert_config_paths_safe(cfg), "Refusing to write")
})
