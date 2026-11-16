# Legacy compatibility ----
# The original scripts handed data from one stage to the next through CSV files. Reading a
# CSV back changes types (dates become text, logical/numeric inference) and makes names
# syntactic (e.g. "Covid-19related" -> "Covid.19related"). Downstream code depends on that.
# `csv_roundtrip()` reproduces it in memory at exactly the places where the legacy flow read
# a CSV, so results can be compared with the legacy output. It is a parity scaffold: once
# types are handled explicitly it can be replaced stage by stage.

csv_roundtrip <- function(df) {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  utils::write.csv(df, tmp, row.names = FALSE, fileEncoding = "UTF-8")
  utils::read.csv(tmp, encoding = "UTF-8")
}
