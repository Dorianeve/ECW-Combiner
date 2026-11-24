# Google Drive export (optional) ----
# A pre-step, only needed when you read source workbooks from Google Drive AND some of them
# are Google Sheets rather than real .xlsx files (see docs/google-drive.md). Pulls everything
# matching `source$file_patterns` out of a Drive folder into `drive_export$dest_dir`, converting
# Google Sheets to real .xlsx on the way, and keeps a manifest so an unchanged file is not
# re-fetched. Point `paths$source_dir` at the destination folder afterwards.
#
# Needs the `googledrive` package. Needs `drive_export: folder_id:` set in config.yml.

SHEET_MIME <- "application/vnd.google-apps.spreadsheet"
XLSX_MIME  <- "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

#' Sign in to Google Drive
#'
#' Uses a service account if `GDRIVE_SERVICE_ACCOUNT_JSON` is set (unattended runs); otherwise
#' the normal interactive sign-in, whose token `googledrive` caches after the first run.
drive_export_auth <- function() {
  sa <- Sys.getenv("GDRIVE_SERVICE_ACCOUNT_JSON", unset = NA_character_)
  if (!is.na(sa) && nzchar(sa)) googledrive::drive_auth(path = sa) else googledrive::drive_auth()
  invisible(TRUE)
}

#' Every Google Sheet or real .xlsx file below a Drive folder (recursive)
#'
#' @return A dribble with extra columns `mime_type`, `kind` (`"sheet"` or `"xlsx"`), `modified`
#'   (Drive's `modifiedTime`), `md5` (Drive's `md5Checksum`, `NA` for a Google Sheet), and
#'   `match_name` (the name a Google Sheet would have once exported, i.e. with `.xlsx` added,
#'   so file patterns can be matched the same way for both kinds).
drive_export_candidates <- function(folder_id) {
  all_files <- googledrive::drive_ls(googledrive::as_id(folder_id), recursive = TRUE)
  if (nrow(all_files) == 0) return(all_files)

  mime <- vapply(all_files$drive_resource, function(r) r$mimeType %||% NA_character_, NA_character_)
  keep <- mime %in% c(SHEET_MIME, XLSX_MIME)
  out <- all_files[keep, ]
  out$mime_type <- mime[keep]
  out$kind <- ifelse(out$mime_type == SHEET_MIME, "sheet", "xlsx")
  out$modified <- vapply(out$drive_resource, function(r) r$modifiedTime %||% NA_character_, NA_character_)
  out$md5 <- vapply(out$drive_resource, function(r) r$md5Checksum %||% NA_character_, NA_character_)
  out$match_name <- ifelse(out$kind == "sheet", paste0(out$name, ".xlsx"), out$name)
  out
}

#' Keep only the files that match `source$file_patterns` and not `source$exclude_patterns`
#'
#' Reuses the same matching rules as the local backend ([is_excluded_name()]), so a Drive export
#' picks up exactly the workbooks the pipeline would otherwise look for in a mirrored folder.
drive_export_filter <- function(files, cfg) {
  if (nrow(files) == 0) return(files)
  patterns <- unlist(cfg$source$file_patterns)
  regex <- paste0("(", paste(patterns, collapse = "|"), ")")
  keep <- grepl(regex, files$match_name, ignore.case = TRUE) & !is_excluded_name(files$match_name, cfg)
  files[keep, ]
}

#' Export/download every matching Drive workbook into `drive_export$dest_dir`
#'
#' A file whose Drive `modifiedTime` has not changed since the last run (and whose destination
#' file still exists) is left alone; pass `refresh = TRUE` to re-fetch everything anyway.
#'
#' @param cfg Config from [load_config()]; needs `drive_export$folder_id`.
#' @param refresh Ignore the manifest and re-download/re-export everything.
#' @return The manifest (one row per matching Drive file): `id`, `name`, `kind`, `dest`,
#'   `modified`, `md5`, `status` (`downloaded`/`updated`/`up_to_date`/`error`), `n_tables`
#'   (Excel Tables found in the result -- `0` for a converted Google Sheet is a warning sign:
#'   the table definitions did not survive the export), `exported_at`.
drive_export_all <- function(cfg, refresh = FALSE) {
  de <- cfg$drive_export
  if (is.null(de) || is.null(de$folder_id) || !nzchar(de$folder_id)) {
    stop("Set drive_export: folder_id: in config.yml first (see docs/google-drive.md).", call. = FALSE)
  }
  dest_dir <- de$dest_dir %||% "cache/drive_export"
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  manifest_path <- file.path(dest_dir, "drive_export_manifest.csv")

  previous <- if (file.exists(manifest_path)) {
    readr::read_csv(manifest_path, col_types = readr::cols(.default = "c"))
  } else {
    tibble::tibble(id = character(), modified = character(), n_tables = character())
  }

  drive_export_auth()
  files <- drive_export_filter(drive_export_candidates(de$folder_id), cfg)
  if (nrow(files) == 0) {
    stop("No Google Sheet or .xlsx file in the Drive folder matches source$file_patterns.", call. = FALSE)
  }

  message("Checking ", nrow(files), " Drive file(s) against ", basename(dest_dir), "/...")
  rows <- purrr::pmap(list(files$id, files$match_name, files$kind, files$modified, files$md5),
                       drive_export_one, dest_dir = dest_dir, previous = previous, refresh = refresh)

  manifest <- dplyr::bind_rows(rows)
  manifest$exported_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  readr::write_csv(manifest, manifest_path)
  manifest
}

#' One Drive file: download/export it if needed, and build its manifest row
drive_export_one <- function(id, name, kind, modified, md5, dest_dir, previous, refresh) {
  dest <- file.path(dest_dir, name)
  prior <- previous[previous$id == id, ]
  unchanged <- !refresh && nrow(prior) == 1 && identical(prior$modified, modified) && file.exists(dest)

  if (unchanged) {
    return(tibble::tibble(id = id, name = name, kind = kind, dest = basename(dest), modified = modified,
                          md5 = md5 %||% NA_character_, status = "up_to_date",
                          n_tables = suppressWarnings(as.integer(prior$n_tables))))
  }

  status <- if (nrow(prior) == 1) "updated" else "downloaded"
  ok <- tryCatch({
    if (kind == "sheet") {
      googledrive::drive_download(googledrive::as_id(id), path = dest, type = "xlsx", overwrite = TRUE)
    } else {
      googledrive::drive_download(googledrive::as_id(id), path = dest, overwrite = TRUE)
    }
    TRUE
  }, error = function(e) { message("  ! ", name, ": ", conditionMessage(e)); FALSE })

  n_tables <- NA_integer_
  if (!ok) {
    status <- "error"
  } else {
    n_tables <- tryCatch(nrow(openxlsx2::wb_load(dest)$tables), error = function(e) NA_integer_)
    if (identical(n_tables, 0L)) {
      warning(name, ": the exported file has no Excel Table. Google Sheets does not keep named ",
              "Excel tables across an export; Combiner needs them. Check the sheet, or export it ",
              "from Excel/Drive by hand instead.", call. = FALSE)
    }
  }
  tibble::tibble(id = id, name = name, kind = kind, dest = basename(dest), modified = modified,
                 md5 = md5 %||% NA_character_, status = status, n_tables = n_tables)
}

#' Small, console-friendly summary of a [drive_export_all()] manifest
drive_export_report <- function(manifest) {
  statuses <- c("downloaded", "updated", "up_to_date", "error")
  tibble::tibble(status = statuses, n = vapply(statuses, function(s) sum(manifest$status == s), integer(1)))
}
