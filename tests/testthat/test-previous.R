# Last year's combiner: Combiner names are restored, ARR-added columns are dropped ----
# The previous combiner may be the file that ARR cleaned for analysis. It must not change what the
# Combiner makes: renamed columns get their Combiner name, columns that ARR adds are dropped.

test_that("CR: renamed columns get the Combiner names and the ARR columns are dropped", {
  old <- data.frame(ProgrammeID = c("P1", "P2"), Grantee = c("Org A", "Org B"), Covid19related = c("x", "y"),
                    Number = c("1", "2"), date = "yes", yearstart = 2020, yearend = 2025, exercice = 10,
                    stringsAsFactors = FALSE)
  out <- suppressMessages(restore_combiner_names(old, "cr"))
  expect_equal(names(out), c("ProgrammeID", "Granteeorganization", "Covid19relateddata", "Number"))
  expect_equal(out$Granteeorganization, c("Org A", "Org B"))     # the values are kept
  expect_equal(nrow(out), 2)
  expect_message(restore_combiner_names(old, "cr"), "renamed to the Combiner names: Grantee, Covid19related")
  expect_message(restore_combiner_names(old, "cr"), "dropped .*: date, yearstart, yearend, exercice")
})

test_that("PR: renamed columns get the Combiner names and the ARR columns are dropped", {
  old <- data.frame(ProgrammeID = "P1", Grantee = "Org", unit = "Number #", Reportingwindow = "RW1", code = "e1",
                    indicatoradmin = "i", Sourceofdata = "PR24", Covid19related = "No", Value = "5",
                    exercice = 8, c19 = "No", Total = 5, revised_unit = NA, unit2 = "n", yearend = 2025,
                    yearstart = 2020, monthstart = 1, monthend = 12, daystart = 1, dayend = 31, concat = "a",
                    Priority = 1, level_code = "Child", RW_number = 1, stringsAsFactors = FALSE)
  out <- suppressMessages(restore_combiner_names(old, "pr"))
  expect_equal(names(out), c("ProgrammeID", "Granteeorganization", "UnitOfMeasurement", "ReportingWindow",
                             "AnalysisCode", "IndicatorAdmin", "SourceOfData", "Covid19related", "Value"))
  expect_equal(out$UnitOfMeasurement, "Number #")
  expect_equal(out$Covid19related, "No")        # in PR this is a raw column: it keeps its name
})

test_that("a plain Combiner file is not changed and gives no message", {
  cr <- data.frame(ProgrammeID = "P1", Granteeorganization = "Org", Covid19relateddata = "x", Number = "1")
  pr <- data.frame(ProgrammeID = "P1", Granteeorganization = "Org", UnitOfMeasurement = "u", Value = "1")
  expect_silent(res_cr <- restore_combiner_names(cr, "cr"))
  expect_silent(res_pr <- restore_combiner_names(pr, "pr"))
  expect_identical(res_cr, cr)
  expect_identical(res_pr, pr)
})

test_that("the Combiner name wins when both names are present", {
  old <- data.frame(ProgrammeID = "P1", Granteeorganization = "Real", Grantee = "Other", stringsAsFactors = FALSE)
  out <- suppressMessages(restore_combiner_names(old, "cr"))
  expect_equal(out$Granteeorganization, "Real")
})

test_that("read_previous_combiner reads the CSV and applies the same rules", {
  f <- tempfile(fileext = ".csv"); on.exit(unlink(f), add = TRUE)
  utils::write.csv(data.frame(ProgrammeID = "P1", Grantee = "Org", exercice = 10), f, row.names = FALSE)
  out <- suppressMessages(read_previous_combiner(list(inputs = list(previous_cr_combiner = f)), "cr"))
  expect_equal(names(out), c("ProgrammeID", "Granteeorganization"))
})

test_that("dates saved as month/day/year become YYYY-MM-DD; ISO dates and NA are not touched", {
  old <- data.frame(Startdate = c("12/26/2023", "10/3/2023", "2024-05-31", NA, ""),
                    CurrentEndDate = c("1/22/2024", "8/13/2024", "2025-01-31", "6/1/2025", NA),
                    Comments = c("a", "b", "c", "d", "e"), stringsAsFactors = FALSE)
  out <- suppressMessages(normalise_previous_dates(old))
  expect_equal(out$Startdate, c("2023-12-26", "2023-10-03", "2024-05-31", NA, ""))
  expect_equal(out$CurrentEndDate, c("2024-01-22", "2024-08-13", "2025-01-31", "2025-06-01", NA))
  expect_equal(out$Comments, old$Comments)
  expect_message(normalise_previous_dates(old), "month/day/year were changed to YYYY-MM-DD in: Startdate, CurrentEndDate")
})

test_that("dates saved as day/month/year are read as day first when the data says so", {
  old <- data.frame(d = c("26/12/2023", "3/10/2023"), stringsAsFactors = FALSE)
  expect_equal(suppressMessages(normalise_previous_dates(old))$d, c("2023-12-26", "2023-10-03"))
})

test_that("when the data cannot decide the order, nothing is changed and there is a warning", {
  old <- data.frame(d = c("5/6/2023", "3/10/2023"), stringsAsFactors = FALSE)
  expect_warning(res <- normalise_previous_dates(old), "cannot be decided")
  expect_identical(res, old)
  mixed <- data.frame(d = c("26/12/2023", "12/26/2023"), stringsAsFactors = FALSE)
  expect_warning(res2 <- normalise_previous_dates(mixed), "cannot be decided")
  expect_identical(res2, mixed)
})

test_that("a file with only ISO dates is not changed and gives no message", {
  old <- data.frame(d = c("2023-12-26", NA), n = 1:2, stringsAsFactors = FALSE)
  expect_silent(res <- normalise_previous_dates(old))
  expect_identical(res, old)
})
