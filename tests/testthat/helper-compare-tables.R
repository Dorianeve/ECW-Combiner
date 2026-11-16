# Comparing two tables (test helper) ----
# Used by the tests to check that two runs give the same table.

#' Normalise a column for comparison: trimmed text, empty -> NA, numbers compared as numbers
normalise_column <- function(x) {
  x <- trimws(gsub("\r", "", as.character(x), fixed = TRUE))   # Windows line breaks (CR+LF) = Unix (LF)
  x[x %in% c("", "NA")] <- NA
  # numbers are compared as numbers (10 significant digits), cell by cell, so a column that
  # mixes numbers and text is handled too: "1e+05", "100000" and "100000.0" all become "100000"
  num <- suppressWarnings(as.numeric(x))
  ok <- !is.na(num)
  x[ok] <- sprintf("%.10g", num[ok])       # per value (format() would pad to common decimals)
  x
}

#' Compare two tables
#'
#' @param new,old Data frames.
#' @param key Optional columns that identify a row. With a key, matching rows are compared
#'   cell by cell; without one, the two tables are compared as sets of rows.
#' @param ignore Column names to leave out of the comparison on both sides (for example
#'   `ExportDate`, which holds the day the pipeline was run).
#' @return A list: `columns` (name/order differences), `rows` (counts), `cell_diffs`
#'   (key, column, new, old; keyed mode), `only_new`, `only_old` (unmatched rows), `identical`.
compare_tables <- function(new, old, key = NULL, ignore = NULL) {
  new <- new[setdiff(names(new), ignore)]
  old <- old[setdiff(names(old), ignore)]
  cols_new <- names(new); cols_old <- names(old)
  common <- intersect(cols_new, cols_old)
  columns <- list(only_in_new = setdiff(cols_new, cols_old), only_in_old = setdiff(cols_old, cols_new),
                  same_order = identical(cols_new[cols_new %in% common], cols_old[cols_old %in% common]))

  n <- function(df) dplyr::mutate(df[common], dplyr::across(dplyr::everything(), normalise_column))
  nn <- n(new); oo <- n(old)

  if (is.null(key)) {
    sig <- function(df) do.call(paste, c(unname(as.list(df)), sep = "\u001f"))
    sn <- sig(nn); so <- sig(oo)
    cn <- table(sn); co <- table(so)
    all_sig <- union(names(cn), names(co))
    dn <- (cn[all_sig] %||% 0); dn[is.na(dn)] <- 0
    do <- (co[all_sig] %||% 0); do[is.na(do)] <- 0
    extra_new <- all_sig[dn > do]; extra_old <- all_sig[do > dn]
    only_new <- new[sn %in% extra_new, , drop = FALSE]
    only_old <- old[so %in% extra_old, , drop = FALSE]
    cell_diffs <- NULL
  } else {
    stopifnot(all(key %in% common))
    for (k in key) if (anyDuplicated(nn[key]) || anyDuplicated(oo[key])) {
      stop("`key` does not identify rows uniquely.", call. = FALSE)
    }
    joined <- dplyr::full_join(dplyr::mutate(nn, .in_new = TRUE), dplyr::mutate(oo, .in_old = TRUE),
                               by = key, suffix = c(".new", ".old"))
    only_new <- joined[is.na(joined$.in_old), key, drop = FALSE]
    only_old <- joined[is.na(joined$.in_new), key, drop = FALSE]
    both <- joined[!is.na(joined$.in_new) & !is.na(joined$.in_old), ]
    value_cols <- setdiff(common, key)
    cell_diffs <- purrr::map_dfr(value_cols, function(col) {
      a <- both[[paste0(col, ".new")]]; b <- both[[paste0(col, ".old")]]
      diff <- xor(is.na(a), is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
      if (!any(diff)) return(NULL)
      dplyr::bind_cols(both[diff, key, drop = FALSE],
                       tibble::tibble(column = col, new = a[diff], old = b[diff]))
    })
  }

  rows <- c(new = nrow(new), old = nrow(old), only_new = nrow(only_new), only_old = nrow(only_old))
  identical_tables <- length(columns$only_in_new) == 0 && length(columns$only_in_old) == 0 &&
    rows[["only_new"]] == 0 && rows[["only_old"]] == 0 && rows[["new"]] == rows[["old"]] &&
    (is.null(cell_diffs) || nrow(cell_diffs) == 0)
  structure(list(columns = columns, rows = rows, cell_diffs = cell_diffs,
                 only_new = only_new, only_old = only_old, identical = identical_tables),
            class = "table_comparison")
}

#' Print a short human-readable comparison report
print.table_comparison <- function(x, ...) {
  cat("Rows: new", x$rows[["new"]], "| old", x$rows[["old"]],
      "| only in new", x$rows[["only_new"]], "| only in old", x$rows[["only_old"]], "\n")
  if (length(x$columns$only_in_new)) cat("Columns only in new:", paste(x$columns$only_in_new, collapse = ", "), "\n")
  if (length(x$columns$only_in_old)) cat("Columns only in old:", paste(x$columns$only_in_old, collapse = ", "), "\n")
  cat("Common columns in the same order:", x$columns$same_order, "\n")
  if (!is.null(x$cell_diffs)) {
    cat("Cell differences:", nrow(x$cell_diffs), "\n")
    if (nrow(x$cell_diffs)) print(utils::head(dplyr::count(x$cell_diffs, column, sort = TRUE), 15))
  }
  cat(if (x$identical) "RESULT: identical\n" else "RESULT: differences found\n")
  invisible(x)
}

#' Read a combiner file (CSV or XLSX) for comparison, everything as text
#'
#' CSVs are read with readr (much lighter than read.csv: the real combiners are ~300 MB).
read_combiner_file <- function(path) {
  if (grepl("\\.xlsx$", path, ignore.case = TRUE)) {
    openxlsx2::read_xlsx(path)
  } else {
    as.data.frame(readr::read_csv(path, col_types = readr::cols(.default = "c"),
                                  na = c("NA", ""), show_col_types = FALSE, progress = FALSE))
  }
}
