test_that("template builders find their headers and tag the source", {
  cp <- test_cp()
  pt <- suppressMessages(build_pr_programme(list(synthetic_pt_sheet()), cp))
  expect_equal(pt$outcome_output_numbering, "1.1")
  expect_equal(pt$LeadGRN, "G-LEAD")
  expect_equal(pt$source_of_data, "ARR25 - PT")
  expect_true(all(c("file_name", "GRID", "total_rw1") %in% names(pt)))

  si <- suppressMessages(build_pr_standard_indicators(list(synthetic_si_sheet()), cp))
  expect_equal(nrow(si), 2)
  expect_equal(unique(si$source_of_data), "ARR25 - SI")

  rt <- suppressMessages(build_pr_results(list(synthetic_rt_sheet()), cp))
  expect_equal(nrow(rt), 1)
  expect_equal(rt$source_of_verification, "survey|visit")
  expect_true("ecw_analysis_code" %in% names(rt))
  expect_false(any(c("analysis_code", "means_of_verification", "comments_rw1_2") %in% names(rt)))
  expect_equal(unique(rt$source_of_data), "ARR25 - RT")
})

test_that("pr_merge_templates harmonises columns and joins GMS and reporting windows", {
  cp <- test_cp(); ref <- synthetic_pr_reference()
  rt <- csv_roundtrip(suppressMessages(build_pr_results(list(synthetic_rt_sheet()), cp)))
  pr <- csv_roundtrip(suppressMessages(build_pr_programme(list(synthetic_pt_sheet()), cp)))
  si <- csv_roundtrip(suppressMessages(build_pr_standard_indicators(list(synthetic_si_sheet()), cp)))

  m <- pr_merge_templates(rt, pr, si, ref$columns, ref$order, synthetic_grants_db(cp),
                          csv_roundtrip(synthetic_rw()), cp)
  expect_equal(sort(unique(m$source)), c("Programme", "Results", "SI"))
  # the correspondence table renamed ecw_analysis_code -> analysis_code, indicator_text -> indicator
  expect_equal(m$analysis_code[m$source == "Results"], "R1code")
  expect_equal(m$indicator[m$source == "Programme"], "Ind A")
  # configured column order is applied first
  expect_equal(names(m)[1:3], c("LeadGRN", "outcome_output_numbering", "level"))
  # GMS + latest reporting window joined
  expect_equal(unique(m$ProgrammeID), "P1")
  expect_equal(unique(m$MnEReview), "Approved")
  expect_equal(unique(m$report_year), "Window 2")
})

test_that("run_pr pivots, filters empty SI groups, and appends history", {
  cp <- test_cp(); ref <- synthetic_pr_reference()
  raw <- list(results = list(synthetic_rt_sheet()), programme = list(synthetic_pt_sheet()),
              standard_indicators = list(synthetic_si_sheet()))
  res <- suppressMessages(run_pr(raw, synthetic_grants_db(cp), csv_roundtrip(synthetic_rw()),
                                 synthetic_old_pr(), ref, cp))
  out <- res$combiner

  # SI row with no values at all is dropped; the one with values is kept
  si <- out[out$source %in% "SI", ]
  expect_equal(unique(si$AnalysisCode), "s1")
  # programme row: Total/Female/Male for the reporting window
  pt <- out[out$source %in% "Programme" & out$ReportingWindow == "Rw1" & out$Exercise == "ARR25 Annual", ]
  expect_equal(sort(pt$Gender), c("Female", "Male", "Total"))
  expect_equal(pt$Value[pt$Gender == "Total"], 10)
  expect_equal(unique(pt$ReportEndDate), as.Date("2024-12-31"))
  expect_equal(unique(pt$Comments), "c1")
  # codes and units cleaned
  expect_equal(unique(pt$AnalysisCode), "a1")
  expect_equal(unique(pt$UnitOfMeasurement), "# Number")
  expect_equal(unique(pt$DisaggregatedBySex), "yes")
  # Excel serial date converted
  expect_equal(unique(pt$DateIndicatorProposed), as.Date("2023-03-15"))
  # both exercises exist for the current year, plus history with renamed columns
  expect_true(all(c("ARR25 Annual", "ARR25 Cumulative") %in% out$Exercise))
  hist <- out[out$Exercise == "ARR24 Cumulative", ]
  expect_equal(hist$Indicator, c("old ind 1", "old ind 2"))
  expect_equal(sort(hist$Value), c(300, 1500))
})

test_that("pr_final_clean leaves Excel's zero date empty on every platform", {
  df <- data.frame(
    DateIndicatorProposed = c("0", "1899-12-31", "45000", NA),
    ReportEndDate = c("1899-12-30", "1899-12-31", "2024-12-31", "12/31/2024"),
    Value = "1", AnalysisCode = "a1", DisaggregatedBySex = "yes", UnitOfMeasurement = "number",
    Covid19related = NA, covid_flag = NA, covid_19_related_report = NA, stringsAsFactors = FALSE)
  out <- suppressWarnings(pr_final_clean(df))
  expect_equal(as.character(out$DateIndicatorProposed), c(NA, NA, "2023-03-15", NA))
  expect_equal(as.character(out$ReportEndDate), c(NA, NA, "2024-12-31", "2024-12-31"))
})

test_that("PR: an annual rule that no window satisfies removes the annual rows only", {
  ref <- synthetic_pr_reference()
  raw <- list(results = list(synthetic_rt_sheet()), programme = list(synthetic_pt_sheet()),
              standard_indicators = list(synthetic_si_sheet()))
  cp <- cp_with(list(exercises = list(annual_rule = list(from = "{year+1}-01-01"))))
  res <- suppressMessages(run_pr(raw, synthetic_grants_db(cp), csv_roundtrip(synthetic_rw()),
                                 synthetic_old_pr(), ref, cp))
  expect_false("ARR25 Annual" %in% res$combiner$Exercise)
  expect_true("ARR25 Cumulative" %in% res$combiner$Exercise)
})
