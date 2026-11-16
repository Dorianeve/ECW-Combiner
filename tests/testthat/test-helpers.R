test_that("cycle_params derives names from the reporting year", {
  cp <- test_cp(2025)
  expect_equal(cp$active_year, "Activein2025")
  expect_equal(cp$old_active_year, "Activein2024")
  expect_equal(cp$exercise_annual, "ARR25 Annual")
  expect_equal(cp$exercise_cumulative, "ARR25 Cumulative")
  expect_equal(cp$old_exercise_cumulative, "ARR24 Cumulative")
  expect_equal(cp$exercise_cols, c("ARR25Cumulative", "ARR25Annual"))
  expect_equal(cp$active_years, 2023:2025)
  expect_equal(test_cp(2026)$active_year, "Activein2026")
})

test_that("find_header_rows and promote_header build a clean table", {
  raw <- raw_sheet(list(c("", "junk", "x"), c("", "Name", "Value  "), c("", " a ", "1"), c("", "", "")))
  expect_equal(find_header_rows(raw, 2, equals = "name"), 2L)
  out <- promote_header(raw, 2)
  expect_equal(names(out), c("name", "value", "file_name", "table_index"))
  expect_equal(out$name[1], "a")
  expect_equal(out$file_name[1], "Results template X.xlsx")   # forced meta header
  # regex + whitespace collapse
  raw2 <- raw_sheet(list(c("Sub-grantee/IP\n  name", "v")))
  expect_equal(find_header_rows(raw2, 1, regex = "sub-grantee/ip name", collapse_ws = TRUE), 1L)
})

test_that("blank_to_na and lead_grn_from_grid", {
  df <- data.frame(a = c("x", "", "  "), b = c("1", "2", NA))
  out <- suppressMessages(blank_to_na(df))
  expect_equal(out$a, c("x", NA, NA))
  expect_equal(lead_grn_from_grid(c("a | b | c | d | G-1 | f", NA)), c("G-1", NA))
})

test_that("filter_global_regional modes", {
  df <- data.frame(Country = c("Chad", "Global", "Regional", NA))
  expect_equal(filter_global_regional(df, "legacy")$Country, c("Chad", "Global", "Regional"))  # NA dropped only
  expect_equal(filter_global_regional(df, "exclude")$Country, c("Chad", NA))
  expect_equal(nrow(filter_global_regional(df, "keep")), 4)
  expect_error(filter_global_regional(df, "nope"))
})

test_that("trim_active_columns keeps the latest two years", {
  df <- data.frame(Activein2023 = 1, Activein2024 = 1, Activein2025 = 1, x = 1)
  expect_equal(names(trim_active_columns(df)), c("Activein2024", "Activein2025", "x"))
})

test_that("standardise_columns repairs grid and analysis code names", {
  df <- data.frame(na_1 = 1, ar_grid_2021 = "g", anaysis_code = "a", z = 2)
  out <- standardise_columns(df)
  expect_equal(names(out), c("GRID", "analysis_code", "z"))
})

test_that("excel_time_to_fraction converts clock times only", {
  out <- excel_time_to_fraction(c("03:01:00", "3:01", "0.5", "12", "text", NA, "2024-12-31", "25:00:00"))
  expect_equal(as.numeric(out[1]), 3 * 3600 / 86400 + 60 / 86400)       # 0.1256944...
  expect_equal(as.numeric(out[2]), as.numeric(out[1]))
  expect_equal(out[3:7], c("0.5", "12", "text", NA, "2024-12-31"))
  expect_equal(as.numeric(out[8]), 25 / 24)                             # durations over 24 h stay valid
})

test_that("fill_year_template fills year, yy and offsets", {
  expect_equal(fill_year_template("ARR{yy} Annual", 2025), "ARR25 Annual")
  expect_equal(fill_year_template("ARR{yy-1} Cumulative", 2025), "ARR24 Cumulative")
  expect_equal(fill_year_template("{year-1}-07-01", 2025), "2024-07-01")
  expect_equal(fill_year_template("{year+1}", 2025), "2026")
  expect_equal(fill_year_template("no placeholder", 2025), "no placeholder")
  expect_equal(fill_year_template(c("{yy}", "{year}"), 2007), c("07", "2007"))
})

test_that("cycle_params defaults reproduce the earlier behaviour and accept overrides", {
  cp <- test_cp(2025)
  expect_equal(cp$active_in, list(start = "{year}-01-01", end = "{year}-12-31", lead_rule = TRUE))
  expect_false(cp$strategic_plan$include_boundary_end)
  expect_true(cp$carry_over_inactive)
  expect_equal(cp$exercise_cols, c("ARR25Cumulative", "ARR25Annual"))

  custom <- cp_with(list(exercises = list(annual_label = "Cycle {year} yearly", create = list("annual"),
                                          carry_over_inactive = FALSE)))
  expect_equal(custom$exercise_annual, "Cycle 2025 yearly")
  expect_equal(custom$exercise_cols, "ARR25Annual")
  expect_false(custom$carry_over_inactive)
})

test_that("cycle_params rejects invalid settings", {
  expect_error(cp_with(list(active_in = list(start = "not-a-date"))), "active_in")
  expect_error(cp_with(list(exercises = list(create = list("monthly")))), "create")
  expect_error(cp_with(list(strategic_plan = list(start = "x", end = "y"))), "strategic_plan")
})

test_that("add_exercise_flags: no rule = every row; a rule needs the window end inside from..to", {
  df <- data.frame(id = 1:4)
  period <- c("2024-12-31", "2025-06-30", "2026-03-31", NA)

  all_yes <- add_exercise_flags(df, period, test_cp())
  expect_equal(all_yes$ARR25Annual, rep("Yes", 4))
  expect_equal(all_yes$ARR25Cumulative, rep("Yes", 4))

  cp <- cp_with(list(exercises = list(annual_rule = list(from = "{year}-01-01", to = "{year}-12-31"))))
  out <- add_exercise_flags(df, period, cp)
  expect_equal(out$ARR25Annual, c("No", "Yes", "No", "No"))     # missing date = No
  expect_equal(out$ARR25Cumulative, rep("Yes", 4))              # no rule for cumulative

  only_from <- cp_with(list(exercises = list(cumulative_rule = list(from = "2025-01-01"))))
  expect_equal(add_exercise_flags(df, period, only_from)$ARR25Cumulative, c("No", "Yes", "Yes", "No"))
})

test_that("an exercise rule with an invalid date is rejected", {
  expect_error(cp_with(list(exercises = list(annual_rule = list(from = "soon")))), "annual_rule")
})

test_that("numbers become plain text, never scientific notation", {
  expect_equal(as_plain_text(c(500000, 1e6, 100000, 0.5, 1234.56, NA)), c("500000", "1000000", "100000", "0.5", "1234.56", NA))
  expect_equal(as_plain_text(0.1 + 0.2), "0.3")
  expect_equal(as_plain_text(1:2), c("1", "2"))
  expect_equal(as_plain_text(as.Date("2025-03-04")), "2025-03-04")
  df <- data.frame(x = c(500000, 1e6), y = c("a", "b"), stringsAsFactors = FALSE)
  expect_equal(tidy_body(df)$x, c("500000", "1000000"))
})
