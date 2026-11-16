test_that("AF: header found, rows without lead GRN dropped, alignment score and totals", {
  af <- suppressMessages(build_af_source(list(synthetic_af_sheet())))
  expect_equal(nrow(af), 3)
  expect_equal(unique(af$LeadGRN), "G-LEAD")
  expect_equal(unique(af$source_of_data), "Finance Aligned Funding")

  out <- af_join(af, synthetic_grants_finance())
  expect_equal(out$alignment_score, c("Strongly aligned", "Not aligned", "Weakly aligned"))
  expect_equal(out$sum_total_funding, c(100, 50, 150))     # New / Pre-existing / both
  expect_equal(unique(out$ProgrammeID), "P1")
  expect_equal(names(out)[1:4], c("Typeofinvestment", "Country", "Granteeorganization", "ProgrammeID"))
})

test_that("AF: French or doubled header rows are promoted", {
  df <- data.frame(donateur = c("Donor", "D1"), x = c("Amount", "5"), file_name = "f", table_index = 1)
  out <- first_row_as_header(df)
  expect_equal(names(out), c("donor", "amount", "file_name", "table_index"))
  expect_equal(nrow(out), 1)
})

test_that("DCM: sub-grantee sheet is parsed, joined to GMS, amounts numeric", {
  dcm <- suppressMessages(build_dcm_source(list(synthetic_dcm_sheet())))
  expect_equal(nrow(dcm), 1)
  expect_equal(dcm$source_of_data, "Finance | DCM | subgrantees")

  out <- dcm_join(csv_roundtrip(dcm), synthetic_grants_finance())
  expect_equal(out$GMGRN, "24-ABC-LD1-RT2-ZZ9")
  expect_equal(out$ProgrammeID, "P9")
  expect_equal(out$LocalTransfer, "Yes")                      # National NGO
  expect_equal(out$TotalAmountAllocatedToBeDiscursedToConsortiumPartner, 1234.57)
  expect_equal(out$SubgranteeIPName, "Sub A")
  expect_true(all(c("Source", "GRID", "FileName") %in% names(out)))
})

test_that("parse_amount keeps round amounts and still cleans currency text", {
  expect_equal(parse_amount(c("5e+05", "1e+06", "500000", "$1,234.567", " 2 000.5 ", "1.5E3", NA, "n/a")),
               c(500000, 1e6, 500000, 1234.57, 2000.5, 1500, NA, NA))
})

test_that("DCM amounts that are round numbers survive the whole chain (numeric cells in the table)", {
  sheet <- synthetic_dcm_sheet()
  col <- "total_amount_allocated_to_be_disbursed_to_consortium_partner"
  names(sheet)[names(sheet) == "Total amount allocated to be disbursed to consortium partner"] <- col
  hdr_col <- grep("total_amount_allocated", janitor::make_clean_names(names(sheet)))
  sheet[[hdr_col]] <- 500000                                   # a real number, as read from an Excel table
  dcm <- suppressMessages(build_dcm_source(list(sheet)))
  out <- dcm_join(csv_roundtrip(dcm), synthetic_grants_finance())
  expect_equal(out$TotalAmountAllocatedToBeDiscursedToConsortiumPartner, 500000)
})
