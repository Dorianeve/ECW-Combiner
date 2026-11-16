test_that("gms_process (arr) builds flags, applies lead tweak and filters", {
  cp <- test_cp(2025)
  db <- gms_process(synthetic_gms_raw(), cp, "arr")

  # AF investment dropped; legacy country filter keeps Global
  expect_equal(db$GMGRN, c("G-LEAD", "G-PART", "G-TWO"))
  # syntactic names, as the legacy CSV hand-off produced
  expect_true("Covid.19related" %in% names(db))
  expect_true(all(c("Activein2023", "Activein2024", "Activein2025", "ActiveStrategicPlan") %in% names(db)))
  # P1's partner (ended 2024) takes the lead grantee's flag (active in 2025)
  expect_equal(db$Activein2025[db$GMGRN == "G-PART"], "Yes")
  # P2 ended 2023
  expect_equal(db$Activein2025[db$GMGRN == "G-TWO"], "No")
  expect_equal(db$Activein2023[db$GMGRN == "G-TWO"], "Yes")
  # dates come back as text (legacy types)
  expect_true(is.character(db$Startdate))
  expect_equal(db$Startdate[1], "2023-01-01")
  # crisis flags
  expect_equal(db$Crisis_Protracted, c("Yes", "No", "No"))
  expect_equal(db$Emergency_Climate[1], "Yes")
})

test_that("gms_process (finance) has no filters or lead tweak", {
  db <- gms_process(synthetic_gms_raw(), test_cp(2025), "finance")
  expect_equal(nrow(db), 4)
  expect_false("ActiveStrategicPlan" %in% names(db))
  expect_equal(db$Activein2025[db$GMGRN == "G-PART"], "No")   # no lead tweak
})

test_that("global_regional = exclude removes Global grants", {
  db <- gms_process(synthetic_gms_raw(), test_cp(2025, "exclude"), "arr")
  expect_equal(db$GMGRN, c("G-LEAD", "G-PART"))
})

test_that("gms_fetch refuses to run without credentials", {
  cfg <- list(gms = list(user = NA_character_, password = NA_character_, base_url = "x",
                         endpoints = list(grants = "g")))
  expect_error(gms_fetch(cfg), "credentials")
})

test_that("active_in can define a fiscal-year period", {
  # fiscal year {year-1}-07-01 .. {year}-06-30
  cp <- cp_with(list(active_in = list(start = "{year-1}-07-01", end = "{year}-06-30")))
  db <- gms_process(synthetic_gms_raw(), cp, "arr")
  # G-TWO ended 2023-12-31: calendar 2024 = No, but fiscal 2024 (2023-07-01..2024-06-30) = Yes
  expect_equal(db$Activein2024[db$GMGRN == "G-TWO"], "Yes")
  expect_equal(gms_process(synthetic_gms_raw(), test_cp(), "arr")$Activein2024[2:3], c("Yes", "No"))
})

test_that("active_in lead_rule can be switched off", {
  off <- gms_process(synthetic_gms_raw(), cp_with(list(active_in = list(lead_rule = FALSE))), "arr")
  expect_equal(off$Activein2025[off$GMGRN == "G-PART"], "No")      # keeps its own value
  on <- gms_process(synthetic_gms_raw(), test_cp(), "arr")
  expect_equal(on$Activein2025[on$GMGRN == "G-PART"], "Yes")       # takes the lead's
})

test_that("strategic plan boundary rule and dates are configurable", {
  # G-PART ends exactly on the plan's start date (2024-12-31)
  strict <- cp_with(list(strategic_plan = list(start = "2024-12-31", end = "2026-12-31")))
  incl <- cp_with(list(strategic_plan = list(start = "2024-12-31", end = "2026-12-31",
                                             include_boundary_end = TRUE)))
  a <- gms_process(synthetic_gms_raw(), strict, "arr"); b <- gms_process(synthetic_gms_raw(), incl, "arr")
  expect_equal(a$ActiveStrategicPlan[a$GMGRN == "G-PART"], "No")    # legacy: strictly after
  expect_equal(b$ActiveStrategicPlan[b$GMGRN == "G-PART"], "Yes")
})
