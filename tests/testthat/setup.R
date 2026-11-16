# Load project functions into the global env (so parallel workers can see them).
root <- normalizePath(testthat::test_path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", recursive = TRUE, full.names = TRUE)) {
  sys.source(f, envir = globalenv())
}
