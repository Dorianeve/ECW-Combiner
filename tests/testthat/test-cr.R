test_that("build_cr_source keeps formal / non-formal rows with a GRN", {
  cp <- test_cp()
  src <- suppressMessages(build_cr_source(list(synthetic_cr_sheet()), cp))
  expect_equal(nrow(src), 2)
  expect_equal(src$type_of_education, c("Formal education", "Non-formal education"))
  expect_equal(unique(src$LeadGRN), "G-LEAD")
  expect_equal(unique(src$source_of_data), "ARR25 - CR")
  expect_true(all(c("GRID", "file_name") %in% names(src)))
})

test_that("build_cr_source warns about a table that is not a children table", {
  bad <- data.frame(a = "x", b = "y", file_name = "f.xlsx", table_index = 1)
  expect_warning(suppressMessages(try(build_cr_source(list(bad), test_cp()), silent = TRUE)),
                 "unexpected first column")
})

test_that("cr_prepare_previous carries inactive grants into the new cumulative exercise", {
  cp <- test_cp()
  db <- synthetic_grants_db(cp)
  old <- cr_prepare_previous(synthetic_old_cr(), db, cp)
  # P2 ended in 2023 -> inactive in 2025 -> its ARR24 Cumulative row is duplicated as ARR25 Cumulative
  expect_equal(sum(old$Exercise == "ARR25 Cumulative"), 1)
  expect_equal(old$Number[old$Exercise == "ARR25 Cumulative"], 20)
  # P1 is active -> not duplicated; 'Mutiple Grantees' repaired from LeadGRN
  expect_false("Mutiple Grantees" %in% old$GMGRN)
  # thousands separators parsed
  expect_equal(old$Number[1], 1000)
  # older Activein columns trimmed
  expect_false("Activein2023" %in% names(old))
})

test_that("run_cr produces annual + cumulative long output and appends history", {
  cp <- test_cp()
  res <- suppressMessages(run_cr(list(synthetic_cr_sheet()), synthetic_grants_db(cp),
                                 csv_roundtrip(synthetic_rw()), synthetic_old_cr(), cp))
  root <- res$root
  # 2 source rows x 30 value columns
  expect_equal(nrow(root), 60)
  expect_equal(sort(unique(root$Gender)), c("Female", "Male", "Total"))
  expect_equal(sort(unique(root$Status)), c("Reached", "Targeted"))
  expect_equal(sort(unique(root$Levelofeducation)),
               c("Pre-primary", "Primary", "Secondary", "Total", "Unknown level of education"))
  expect_equal(unique(root$Sourceofdata), "ARR25 CR")
  expect_equal(unique(root$Covid19relateddata), "Non-Covid-19 related data")
  # totals computed from the female + male columns of a level
  pp <- root[root$Levelofeducation == "Pre-primary" & root$Gender == "Total" &
               root$Status == "Targeted" & root$Typeofeducation == "Formal education", ]
  expect_equal(pp$Number, 2)

  comb <- res$combiner
  expect_true(all(c("ARR25 Annual", "ARR25 Cumulative") %in% comb$Exercise))
  expect_equal(sum(comb$Exercise == "ARR25 Annual"), 60)
  expect_equal(sum(comb$Exercise == "ARR25 Cumulative"), 60 + 1)   # +1 carried-over inactive grant
  expect_true(any(comb$Exercise == "ARR24 Cumulative"))            # history appended
  # reporting window joined (latest before cutoff for P1)
  expect_equal(unique(root$ReportingWindow), "Window 2")
})

test_that("carry_over_inactive = FALSE keeps last cycle's rows only", {
  cp <- cp_with(list(exercises = list(carry_over_inactive = FALSE)))
  old <- cr_prepare_previous(synthetic_old_cr(), synthetic_grants_db(test_cp()), cp)
  expect_equal(sum(old$Exercise == "ARR25 Cumulative"), 0)
  expect_equal(nrow(old), 3)
})

test_that("exercises$create and the labels control the current-cycle rows", {
  # carry-over is a separate switch: turn it off so that no "Cumulative" row of this cycle exists
  cp <- cp_with(list(exercises = list(create = list("annual"), annual_label = "Cycle {year} yearly",
                                      carry_over_inactive = FALSE)))
  res <- suppressMessages(run_cr(list(synthetic_cr_sheet()), synthetic_grants_db(cp),
                                 csv_roundtrip(synthetic_rw()), synthetic_old_cr(), cp))
  comb <- res$combiner
  expect_equal(sum(comb$Exercise == "Cycle 2025 yearly"), 60)
  expect_false(any(comb$Exercise == "ARR25 Cumulative"))
  expect_true(any(comb$Exercise == "ARR24 Cumulative"))             # history still appended
})

test_that("annual_rule keeps a row in the annual exercise only if its reporting window qualifies", {
  # the programme's latest window ends 2025-12-31
  cp_in <- cp_with(list(exercises = list(annual_rule = list(from = "{year}-01-01"))))
  cp_out <- cp_with(list(exercises = list(annual_rule = list(from = "{year+1}-01-01"))))
  run <- function(cp) suppressMessages(run_cr(list(synthetic_cr_sheet()), synthetic_grants_db(cp),
                                              csv_roundtrip(synthetic_rw()), synthetic_old_cr(), cp))$combiner
  expect_equal(sum(run(cp_in)$Exercise == "ARR25 Annual"), 60)
  expect_equal(sum(run(cp_out)$Exercise == "ARR25 Annual"), 0)
  expect_equal(sum(run(cp_out)$Exercise == "ARR25 Cumulative"), 61)    # unaffected
})

test_that("a dash in a number column means empty and gives no warning", {
  df <- data.frame(a = 1)
  levels <- c("pre_primary", "primary", "secondary", "unknown_level_of_education")
  for (l in levels) for (p in c("targeted", "reached")) {
    df[[paste0(l, "_", p, "_female")]] <- "-"
    df[[paste0(l, "_", p, "_male")]] <- "5"
  }
  df$level_check <- NULL
  res <- tryCatch(withCallingHandlers(cr_pivot_long(df), warning = function(w) stop("warning: ", conditionMessage(w))),
                  error = function(e) conditionMessage(e))
  expect_false(is.character(res) && grepl("^warning", res))
})
