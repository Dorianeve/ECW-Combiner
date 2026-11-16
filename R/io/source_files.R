# Source layer ----
# All file discovery goes through here, so the pipeline does not care whether the
# folder is SharePoint/OneDrive-synced, Google Drive for Desktop, or a network share.
# Only the `local` backend exists for now; a new backend (e.g. Drive API) only needs
# to return local file paths from list_source_files().

#' List workbook files in the source folder
#'
#' @param cfg Config from [load_config()].
#' @param patterns Character vector of regexes; a file is kept if it matches any.
#'   Defaults to all `source$file_patterns`.
#' @return Sorted character vector of full paths. Office lock files (`~$...`) are dropped,
#'   and so are files whose *name* matches any `source$exclude_patterns` regex
#'   (default `"^ARCHIVED"`; set `exclude_patterns: []` to exclude nothing).
list_source_files <- function(cfg, patterns = unlist(cfg$source$file_patterns)) {
  backend <- cfg$source$backend %||% "local"
  if (!identical(backend, "local")) {
    stop("Unsupported source backend: ", backend, call. = FALSE)
  }
  if (length(patterns) == 0) stop("No file patterns configured.", call. = FALSE)

  files <- list.files(
    cfg$paths$source_dir,
    pattern = paste0("(", paste(patterns, collapse = "|"), ")"),
    recursive = TRUE, full.names = TRUE, ignore.case = TRUE
  )
  files <- files[!startsWith(basename(files), "~$")]

  drop <- is_excluded_name(basename(files), cfg)
  if (any(drop)) message("Excluded ", sum(drop), " workbook(s) matching exclude_patterns (",
                         paste(unlist(cfg$source$exclude_patterns %||% "^ARCHIVED"), collapse = ", "), ").")
  files <- files[!drop]
  sort(files)
}

#' TRUE for file names that `source$exclude_patterns` (default `^ARCHIVED`) tells us to ignore
is_excluded_name <- function(names, cfg) {
  exclude <- unlist(cfg$source$exclude_patterns %||% "^ARCHIVED")
  if (length(exclude) == 0) return(rep(FALSE, length(names)))
  grepl(paste0("(", paste(exclude, collapse = "|"), ")"), names, ignore.case = TRUE)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
