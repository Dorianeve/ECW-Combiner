# Source-folder protection ----
# The source folder (the grants database) is read-only for this project. Two layers:
#   1. every place that writes calls `assert_outside_source()` first, and refuses
#      to write below the source folder;
#   2. `source_fingerprint()` / `verify_source_untouched()` record size and modification time
#      of every file in the source folder before and after a run, and report any difference.

#' Resolve a path to an absolute, normalised, lower-case form (works for paths that do not exist yet)
resolve_path <- function(path) {
  p <- as.character(fs::path_abs(path))
  rest <- character()
  while (!file.exists(p) && !identical(dirname(p), p)) {   # walk up to the first existing folder
    rest <- c(basename(p), rest)
    p <- dirname(p)
  }
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  tolower(paste(c(sub("/+$", "", p), rest), collapse = "/"))
}

#' Is `path` the folder `root` or somewhere below it?
path_inside <- function(path, root) {
  p <- resolve_path(path); r <- resolve_path(root)
  p == r || startsWith(p, paste0(r, "/"))
}

#' Stop if `path` is inside the source folder
assert_outside_source <- function(path, cfg, what = "output") {
  src <- cfg$paths$source_dir
  if (!is.null(src) && nzchar(src) && path_inside(path, src)) {
    stop("Refusing to write ", what, " inside the source folder (it is read-only for this project):\n  ",
         path, "\n  source folder: ", src, call. = FALSE)
  }
  invisible(path)
}

#' Check every configured write location
assert_config_paths_safe <- function(cfg) {
  assert_outside_source(cfg$paths$cache_dir, cfg, "the cache")
  assert_outside_source(cfg$paths$output_dir, cfg, "outputs")
  if (!is.null(cfg$outputs$share_dir) && nzchar(cfg$outputs$share_dir)) {
    assert_outside_source(cfg$outputs$share_dir, cfg, "the shared output copy")
  }
  if (!is.null(cfg$outputs$arr_input_dir) && nzchar(cfg$outputs$arr_input_dir)) {
    assert_outside_source(cfg$outputs$arr_input_dir, cfg, "the hand-over to AnnualResultsReport")
  }
  invisible(TRUE)
}

#' Size and modification time of every file below the source folder
source_fingerprint <- function(cfg) {
  files <- list.files(cfg$paths$source_dir, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, include.dirs = FALSE)
  info <- file.info(files)
  tibble::tibble(file = files, size = info$size, mtime = as.numeric(info$mtime))
}

#' Compare two fingerprints; returns the files added, removed or changed
source_changes <- function(before, after) {
  m <- dplyr::full_join(before, after, by = "file", suffix = c(".before", ".after"))
  added <- m$file[is.na(m$size.before)]
  removed <- m$file[is.na(m$size.after)]
  changed <- m$file[!is.na(m$size.before) & !is.na(m$size.after) &
                      (m$size.before != m$size.after | m$mtime.before != m$mtime.after)]
  list(added = added, removed = removed, changed = changed,
       untouched = length(added) + length(removed) + length(changed) == 0)
}

#' Warn loudly if the source folder changed while the pipeline ran
verify_source_untouched <- function(before, cfg) {
  ch <- source_changes(before, source_fingerprint(cfg))
  if (!ch$untouched) {
    shown <- utils::head(c(paste("added:", ch$added), paste("removed:", ch$removed),
                           paste("changed:", ch$changed)), 10)
    warning("The source folder changed during the run (", length(ch$added), " added, ",
            length(ch$removed), " removed, ", length(ch$changed), " changed). This pipeline never ",
            "writes there, so this is most likely a sync client or another user. Examples:\n  ",
            paste(shown, collapse = "\n  "), call. = FALSE)
  }
  invisible(ch)
}
