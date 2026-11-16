# Synthetic fixtures: no real data is ever used in tests.

# Build a synthetic source folder with a few workbooks containing Excel tables.
make_fixture_dir <- function() {
  dir <- tempfile("src_")
  dir.create(file.path(dir, "sub"), recursive = TRUE)

  add_book <- function(path, tables) {
    wb <- openxlsx2::wb_workbook()
    for (nm in names(tables)) {
      wb$add_worksheet(nm)
      wb$add_data_table(nm, x = tables[[nm]], table_name = nm)
    }
    wb$save(path)
  }

  add_book(file.path(dir, "Results template A.xlsx"),
           list(tbl_children = data.frame(a = 1:3, b = letters[1:3]),
                tbl_other = data.frame(z = 1)))
  add_book(file.path(dir, "sub", "Programme template B.xlsx"),
           list(tbl_children = data.frame(a = 4:5, b = c("d", "e"))))
  add_book(file.path(dir, "Unrelated.xlsx"),
           list(tbl_children = data.frame(a = 99, b = "x")))
  # Office lock file: must be ignored
  file.create(file.path(dir, "~$Results template A.xlsx"))
  dir
}

make_cfg <- function(src_dir, workers = 1) {
  list(
    paths = list(source_dir = src_dir, cache_dir = tempfile("cache_"), output_dir = tempfile("out_")),
    source = list(backend = "local",
                  file_patterns = list(results = "Results template.*\\.xlsx$",
                                       programme = "Programme template.*\\.xlsx$")),
    tables = list(children = "tbl_children", other = "tbl_other"),
    parallel = list(enabled = workers > 1, workers = workers)
  )
}
