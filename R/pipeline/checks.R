# Data-collection checks ----
# These problems are fixed in the workbooks (or in the GMS), not in the pipeline. The pipeline
# lists them so that the right person can be asked, with the exact workbook.

#' Rows of the current cycle that could not be linked to a programme in the GMS
#'
#' Typical causes: an empty or mistyped grant reference (grid) in the workbook, or a grant
#' missing from the GMS export.
flow_unmatched <- function(results, cp) {
  file_cols <- c("Filename", "FileName", "file_name")
  out <- lapply(names(results), function(flow) {
    d <- results[[flow]]$combiner
    if (!"ProgrammeID" %in% names(d)) return(NULL)
    if ("Exercise" %in% names(d)) d <- d[d$Exercise %in% c(cp$exercise_annual, cp$exercise_cumulative), ]
    fc <- file_cols[file_cols %in% names(d)][1]
    bad <- d[is.na(d$ProgrammeID), , drop = FALSE]
    if (nrow(bad) == 0) return(NULL)
    f <- if (is.na(fc)) rep(NA_character_, nrow(bad)) else as.character(bad[[fc]])
    tab <- table(f, useNA = "ifany")
    data.frame(file = names(tab), table = flow, issue = "no_programme_match", n_rows = as.integer(tab),
               detail = paste0(as.integer(tab), " row(s) of the ", toupper(flow),
                               " combiner have no ProgrammeID: empty or unknown grant reference"),
               stringsAsFactors = FALSE)
  })
  out <- Filter(Negate(is.null), out)
  if (length(out)) do.call(rbind, out) else empty_issues()
}

#' All data-collection issues of a run, as one table for the grants team
collect_data_issues <- function(extracted, results, cp, cfg = NULL) {
  ex <- extraction_issues(extracted, cfg)
  all <- rbind(ex$issues, flow_unmatched(results, cp))
  all <- all[order(all$file, all$issue), , drop = FALSE]
  rownames(all) <- NULL
  list(issues = all, unchecked = ex$unchecked)
}
