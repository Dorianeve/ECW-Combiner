# Generic table extraction ----
# One pass per workbook: every configured Excel table is pulled out in a single
# wb_load(). Results are cached per file (keyed on modification time + size), and
# files are processed in parallel. This replaces the former one-loader-per-table
# design, in which each workbook was opened once per loader.

# Header names ----
# Blank/NA headers get a positional name and duplicates are made unique. Downstream
# steps override headers from a header row inside the data, so this only guarantees a
# valid, unique set of names at read time.
fix_blank_names <- function(x) {
  x <- as.character(x)
  x <- ifelse(is.na(x) | trimws(x) == "", paste0("col_", seq_along(x)), trimws(x))
  make.unique(x)
}

#' Rows filled in directly below an Excel table
#'
#' Grantees sometimes keep typing under a table without extending it; those rows are not part
#' of the table and are not read. This counts the non-empty rows that follow the table without
#' a gap (looking at most `max_rows` down) so the problem can be reported.
#'
#' @return list(n = number of rows, texts = first cell text of each of them, cut at 60 characters)
rows_below_table <- function(wb, sheet, ref, max_rows = 30) {
  none <- list(n = 0L, sample = character())
  m <- stringr::str_match(ref, "^\\$?([A-Z]+)\\$?([0-9]+):\\$?([A-Z]+)\\$?([0-9]+)$")
  if (is.na(m[1, 1])) return(none)
  last_row <- as.integer(m[1, 5])
  dims <- sprintf("%s%d:%s%d", m[1, 2], last_row + 1L, m[1, 4], last_row + max_rows)
  d <- tryCatch(openxlsx2::wb_to_df(wb, sheet = sheet, dims = dims, col_names = FALSE,
                                    skip_empty_rows = FALSE, skip_empty_cols = FALSE),
                error = function(e) NULL)
  if (is.null(d) || nrow(d) == 0) return(none)
  blank <- apply(d, 1, function(r) all(is.na(r) | trimws(as.character(r)) == ""))
  first_blank <- which(blank)[1]
  n <- if (is.na(first_blank)) nrow(d) else first_blank - 1L
  if (n == 0) return(none)
  texts <- vapply(seq_len(n), function(i) {
    v <- as.character(unlist(d[i, ])); v <- v[!is.na(v) & trimws(v) != ""]
    substr(trimws(v[1]), 1, 60)
  }, "")
  list(n = as.integer(n), texts = texts)
}

#' Read the requested Excel tables from one workbook
#'
#' @param file Path to an .xlsx file.
#' @param tables Excel table names to extract.
#' @return list(tables = named list (one entry per requested table) of lists of
#'   data.frames, errors = character vector, issues = data frame of data-collection problems
#'   found in the workbook). Each data.frame carries `file_name` and `table_index` columns.
read_workbook_tables <- function(file, tables) {
  errors <- character()
  issues <- list()
  empty <- stats::setNames(rep(list(list()), length(tables)), tables)

  # openxlsx2 warns about "unknown folders" (e.g. ink drawings) in some workbooks. This is harmless
  # for reading tables, and gave hundreds of messages, so only this warning is silenced.
  wb <- tryCatch(withCallingHandlers(openxlsx2::wb_load(file), warning = function(w) {
    if (grepl("unknown folders", conditionMessage(w), fixed = TRUE)) invokeRestart("muffleWarning")
  }), error = function(e) {
    errors <<- c(errors, paste0("wb_load failed: ", conditionMessage(e)))
    NULL
  })
  if (is.null(wb)) return(list(tables = empty, errors = errors, issues = empty_issues()))

  wb_tables <- wb$tables
  if (is.null(wb_tables) || !"tab_name" %in% names(wb_tables)) {
    return(list(tables = empty, errors = errors, issues = empty_issues()))
  }

  out <- lapply(tables, function(tn) {
    hit <- wb_tables[wb_tables$tab_name == tn, , drop = FALSE]
    lapply(seq_len(nrow(hit)), function(i) {
      tryCatch({
        sheet <- wb$sheet_names[as.integer(hit$tab_sheet[i])]
        df <- openxlsx2::wb_to_df(wb, sheet = sheet, dims = hit$tab_ref[i])
        names(df) <- fix_blank_names(names(df))
        df$file_name <- basename(file)
        df$table_index <- i

        below <- rows_below_table(wb, sheet, hit$tab_ref[i])
        if (below$n > 0) {
          issues[[length(issues) + 1]] <<- data.frame(
            file = basename(file), table = tn, issue = "content_below_table", n_rows = below$n,
            detail = below_detail(hit$tab_ref[i], sheet, below$texts),
            where = paste0(hit$tab_ref[i], " on sheet '", sheet, "'"),
            texts = paste(below$texts, collapse = TEXT_SEP),
            stringsAsFactors = FALSE)
        }
        df
      }, error = function(e) {
        errors <<- c(errors, paste0(tn, "[", i, "]: ", conditionMessage(e)))
        NULL
      })
    }) |> purrr::compact()
  })
  names(out) <- tables
  list(tables = out, errors = errors,
       issues = if (length(issues)) do.call(rbind, issues) else empty_issues())
}

# Rows below a table are kept in the cache as text, so that the list of known template text can
# be changed without reading the workbooks again.
TEXT_SEP <- " || "

below_detail <- function(ref, sheet, texts) {
  paste0("table ", ref, " on sheet '", sheet, "'; ", length(texts),
         " filled row(s) directly below it are not part of the table (e.g. ",
         paste0("\"", utils::head(substr(texts, 1, 40), 3), "\"", collapse = ", "), ")")
}

empty_issues <- function() {
  data.frame(file = character(), table = character(), issue = character(), n_rows = integer(),
             detail = character(), stringsAsFactors = FALSE)
}

# Cache ----
file_signature <- function(file) {
  info <- file.info(file)
  list(mtime = as.numeric(info$mtime), size = as.numeric(info$size))
}

# A path in one comparable form: lower case, and the WSL form /mnt/c/... written as C:/...
same_path_key <- function(path) {
  p <- tolower(gsub("\\\\", "/", path))
  sub("^/mnt/([a-z])/", "\\1:/", p)
}

# The key is the path INSIDE the source folder, not the full path. So the same workbook has the
# same cache entry whether the folder is called /mnt/c/... (WSL) or C:/... (Windows).
cache_file_for <- function(cfg, file) {
  full <- normalizePath(file, winslash = "/")
  root <- sub("/+$", "", normalizePath(cfg$paths$source_dir, winslash = "/", mustWork = FALSE))
  key <- if (startsWith(tolower(full), paste0(tolower(root), "/"))) substring(full, nchar(root) + 2) else full
  file.path(cfg$paths$cache_dir, "extract", paste0(digest::digest(tolower(key), algo = "md5"), ".rds"))
}

#' Extract tables from one file, using the cache when the file is unchanged
extract_file_cached <- function(file, tables, cfg, refresh = FALSE) {
  cache_path <- cache_file_for(cfg, file)
  sig <- file_signature(file)

  if (!refresh && file.exists(cache_path)) {
    cached <- tryCatch(readRDS(cache_path), error = function(e) NULL)
    if (!is.null(cached) &&
        identical(cached$signature, sig) &&
        all(tables %in% names(cached$tables))) {
      cached$tables <- cached$tables[tables]
      cached$origin <- "cache"
      return(cached)
    }
  }

  res <- read_workbook_tables(file, tables)
  rec <- list(file = file, signature = sig, tables = res$tables,
              errors = res$errors, issues = res$issues, origin = "read")

  # Only cache clean reads, so a transient failure is retried on the next run.
  if (length(res$errors) == 0) {
    assert_outside_source(cache_path, cfg, "the cache")
    dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
    tmp <- paste0(cache_path, ".", Sys.getpid(), ".tmp")
    saveRDS(rec, tmp)
    file.rename(tmp, cache_path)
  }
  rec
}

#' Extract all configured tables from all source workbooks
#'
#' @param cfg Config from [load_config()].
#' @param tables Excel table names. Defaults to every entry of `cfg$tables`.
#' @param files Optional explicit file list (defaults to [list_source_files()]).
#' @param refresh Ignore the cache and re-read everything.
#' @param workers Number of parallel workers (defaults to [resolve_workers()]).
#' @param families Names under `source$file_patterns` to read (default: all of them), e.g.
#'   `c("results", "programme")` when only CR and PR run.
#' @param cache_only Use only what is in the cache: the source folder is not read at all, and
#'   no workbook is opened, even if it changed since it was cached. See [cached_extraction()].
#' @return A list with one element per file, in sorted file order.
extract_all <- function(cfg, tables = unlist(cfg$tables), files = NULL,
                        refresh = FALSE, workers = resolve_workers(cfg), cache_only = FALSE,
                        families = NULL) {
  patterns <- if (is.null(families)) unlist(cfg$source$file_patterns) else unlist(cfg$source$file_patterns[families])
  if (cache_only) return(cached_extraction(cfg, tables, patterns))
  files <- files %||% list_source_files(cfg, patterns)
  if (length(files) == 0) stop("No source files found in ", cfg$paths$source_dir, call. = FALSE)

  use_parallel <- workers > 1 && length(files) > 1
  if (use_parallel) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }
  mapper <- if (use_parallel) {
    function(.x, .f) furrr::future_map(.x, .f, .options = furrr::furrr_options(seed = TRUE))
  } else purrr::map

  message("Extracting ", length(tables), " table(s) from ", length(files),
          " workbook(s) with ", if (use_parallel) workers else 1, " worker(s)...")

  progressr::with_progress({
    p <- progressr::progressor(along = files)
    res <- mapper(files, function(f) {
      r <- extract_file_cached(f, tables, cfg, refresh = refresh)
      p(basename(f))
      r
    })
  })
  names(res) <- basename(files)

  n_err <- sum(vapply(res, function(r) length(r$errors) > 0, logical(1)))
  if (n_err > 0) warning(n_err, " workbook(s) had read errors; see extraction_report().", call. = FALSE)
  res
}

#' Flatten the extracted tables of one kind into a list of data.frames
#'
#' Mirrors the old loaders' output (one data.frame per table instance, in file order).
#'
#' @param extracted Output of [extract_all()].
#' @param table Excel table name.
#' @param file_pattern Optional regex on the file name (case-insensitive) to restrict
#'   which files contribute, e.g. only "Programme" workbooks.
collect_tables <- function(extracted, table, file_pattern = NULL) {
  keep <- if (is.null(file_pattern)) rep(TRUE, length(extracted)) else
    grepl(file_pattern, names(extracted), ignore.case = TRUE)
  unname(purrr::list_flatten(lapply(extracted[keep], function(r) r$tables[[table]])))
}

#' One-row-per-file summary of an extraction (origin, tables found, errors)
extraction_report <- function(extracted) {
  purrr::imap_dfr(extracted, function(r, nm) {
    counts <- vapply(r$tables, length, integer(1))
    tibble::tibble(
      file = nm,
      origin = r$origin,
      tables_found = sum(counts),
      detail = paste0(names(counts), "=", counts, collapse = "; "),
      errors = paste(r$errors, collapse = " | ")
    )
  })
}

#' Extraction result taken only from the cache
#'
#' Nothing in the source folder is listed or opened. The workbooks are those found in the
#' cache that match `source$file_patterns` and are not excluded by `source$exclude_patterns`,
#' as they were when they were cached (a workbook deleted since still appears; one changed
#' since appears in its cached state).
cached_extraction <- function(cfg, tables = unlist(cfg$tables), patterns = unlist(cfg$source$file_patterns)) {
  paths <- list.files(file.path(cfg$paths$cache_dir, "extract"), pattern = "[.]rds$", full.names = TRUE)
  if (length(paths) == 0) {
    stop("The cache is empty (", cfg$paths$cache_dir, "). Run once without --cache-only first.", call. = FALSE)
  }
  paths <- paths[order(file.info(paths)$mtime, decreasing = TRUE)]     # newest first
  recs <- Filter(Negate(is.null), lapply(paths, function(p) tryCatch(readRDS(p), error = function(e) NULL)))
  recs <- recs[!duplicated(vapply(recs, function(r) same_path_key(r$file), ""))]   # one entry per workbook

  regex <- paste0("(", paste(patterns, collapse = "|"), ")")
  nm <- vapply(recs, function(r) basename(r$file), "")
  keep <- grepl(regex, nm, ignore.case = TRUE) & !startsWith(nm, "~$") & !is_excluded_name(nm, cfg)
  recs <- recs[keep]
  if (length(recs) == 0) stop("No cached workbooks match the configured file patterns.", call. = FALSE)

  recs <- recs[order(vapply(recs, function(r) r$file, ""))]
  lacking <- vapply(recs, function(r) !all(tables %in% names(r$tables)), logical(1))
  if (any(lacking)) {
    stop(sum(lacking), " cached workbook(s) lack a requested table (e.g. ",
         basename(recs[lacking][[1]]$file), "). Run once without --cache-only to read it.", call. = FALSE)
  }
  message("Using the cache only: ", length(recs), " workbook(s), none opened.")
  recs <- lapply(recs, function(r) { r$tables <- r$tables[tables]; r$origin <- "cache"; r })
  stats::setNames(recs, vapply(recs, function(r) basename(r$file), ""))
}

#' Data-collection problems found in the workbooks
#'
#' @param extracted Output of [extract_all()].
#' @return list(issues = data frame, unchecked = number of workbooks cached before the checks
#'   existed; re-read them with `--refresh` to check them).
extraction_issues <- function(extracted, cfg = NULL) {
  has <- vapply(extracted, function(r) !is.null(r$issues), logical(1))
  tbl <- purrr::imap_dfr(extracted[has], function(r, nm) r$issues)
  if (nrow(tbl) == 0) return(list(issues = empty_issues(), unchecked = sum(!has)))
  tbl <- drop_known_text(tbl, known_text_below_tables(cfg))
  list(issues = tbl[, names(empty_issues()), drop = FALSE], unchecked = sum(!has))
}

#' Known template text under tables, as a named list: Excel table name -> regexes
#'
#' Set in the settings under `checks: known_text_below_tables:` with the logical table names
#' (the names under `tables:`). A row whose first text matches one of the regexes is template
#' text (for example a footer), not data that a grantee forgot to put into the table.
known_text_below_tables <- function(cfg) {
  if (is.null(cfg)) return(list())
  known <- cfg$checks$known_text_below_tables
  if (length(known) == 0) return(list())
  out <- lapply(known, function(p) unlist(p))
  names(out) <- vapply(names(known), function(k) cfg$tables[[k]] %||% k, "")
  out
}

#' Remove the template text from the `content_below_table` issues; drop issues with nothing left
drop_known_text <- function(tbl, known) {
  if (length(known) == 0 || !"texts" %in% names(tbl)) return(tbl)
  keep <- rep(TRUE, nrow(tbl))
  for (i in which(tbl$issue == "content_below_table" & tbl$table %in% names(known) & !is.na(tbl$texts))) {
    texts <- strsplit(tbl$texts[i], TEXT_SEP, fixed = TRUE)[[1]]
    is_known <- grepl(paste(known[[tbl$table[i]]], collapse = "|"), texts, ignore.case = TRUE)
    left <- texts[!is_known]
    if (length(left) == 0) { keep[i] <- FALSE; next }
    ref <- sub(" on sheet.*$", "", tbl$where[i]); sheet <- sub("^.* on sheet '(.*)'$", "\\1", tbl$where[i])
    tbl$n_rows[i] <- length(left)
    tbl$detail[i] <- below_detail(ref, sheet, left)
  }
  tbl[keep, , drop = FALSE]
}
