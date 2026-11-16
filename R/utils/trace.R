# Row trace ----
# `trace_step()` records how many rows a table has at a given point of a flow and returns the
# table unchanged, so it can sit inside a pipe:
#
#   df |> dplyr::filter(...) |> trace_step("CR source: after keeping formal/non-formal education")
#
# The diagnostics report shows these counts step by step and compares them with the previous run,
# so it is easy to see where rows enter, leave, or where a year behaves differently. Each flow runs
# in its own R process, so the trace is collected per flow (see `run_flow_job()`).

.trace_env <- new.env()
.trace_env$steps <- list()

trace_reset <- function() {
  .trace_env$steps <- list()
  invisible(NULL)
}

#' Record the number of rows of `x` under `label` and return `x`
#'
#' A list of tables (for example the raw tables of all workbooks) counts the rows of all of them.
trace_step <- function(x, label) {
  n <- if (is.data.frame(x)) nrow(x) else if (is.list(x)) {
    sum(vapply(x, function(d) if (is.data.frame(d)) nrow(d) else 0L, integer(1)))
  } else length(x)
  .trace_env$steps[[length(.trace_env$steps) + 1]] <- list(step = as.character(label), rows = as.integer(n))
  x
}

#' The recorded steps as a data frame (step, rows), in the order they happened
trace_get <- function() {
  s <- .trace_env$steps
  if (length(s) == 0) return(data.frame(step = character(), rows = integer(), stringsAsFactors = FALSE))
  data.frame(step = vapply(s, function(z) z$step, ""), rows = vapply(s, function(z) z$rows, 1L),
             stringsAsFactors = FALSE)
}
