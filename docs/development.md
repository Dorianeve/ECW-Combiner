# For developers

This page is for people who want to change the code.

## Set up

Run these two commands once:

``` bash
Rscript scripts/install_packages.R
git config core.hooksPath .githooks
```

The first command installs the R packages. The second turns on the check that runs before each commit. It stops you if you try to commit an email address, a personal path, a password or a data file.

Copy `.sensitive-patterns.example` to `.sensitive-patterns`. Write in it the names, domains and paths that must never be committed, one per line. This file stays on your computer.

## Run the tests

In R:

``` r
testthat::test_dir("tests/testthat")
```

Or in the terminal, from the project folder:

``` bash
Rscript tests/testthat.R
```

The tests use **made-up data only**. They are in `tests/testthat`. The files `helper-*.R` build the made-up Excel files and data.

The tests cover these parts:

-   reading the Excel files and the cache
-   the grant list and the four flows
-   the full run
-   the protection of the Excel folder
-   the list of data problems and the run report

**If the tests stop with an error about `compare_proxy`:** the R package `waldo` is broken on your computer. Reinstall it with `install.packages("waldo")`.

## Where the code is

| Folder | What is inside |
|----|----|
| `R/extract` | `extract_all()`: reads the Excel tables, with the cache and several workers |
| `R/io` | Finding files, safety checks, lookup tables, writing results |
| `R/transform` | `gms.R`, `reporting_windows.R`, `cr.R`, `pr_templates.R`, `pr.R`, `finance.R` |
| `R/pipeline` | `run_pipeline()`, the data-problem checks and the run report |
| `R/utils` | Settings, year rules, row trace, small helpers |
| `scripts` | The commands |

## Rules for the code

1.  **A transform step only takes tables and gives tables.** It does not read or write files. The pipeline does the reading and writing.
2.  **Never write inside the folder with the Excel files.** Every function that writes calls `assert_outside_source()` first. Add this call to every new function that writes.
3.  **No year or name in the code.** Take them from `cycle_params(cfg)` (`R/utils/cycle.R`).
4.  **Names of Excel files and tables come from the settings,** not from the code.
5.  **No real data in the repository,** also not in tests. Make test data in `tests/testthat/helper-*.R`.
6.  **Put a trace point at every step that can change the number of rows.** Write `... |> trace_step("what this step is")`. See [The run report](diagnostics.md#the-row-trace).

## Add a new flow

1.  Add the Excel table name under `tables:` in `config/config.example.yml`. Add a line to `FLOW_TABLES` in `R/pipeline/run_pipeline.R`.
2.  In `R/transform/<flow>.R`, write `build_<flow>_source()` (cleans the raw tables), the join and derive functions, and `run_<flow>()` that calls them in order. Add trace points.
3.  Add the flow to `run_flow_job()` and to the `jobs` list in `run_pipeline_core()`.
4.  Write made-up data and tests. Include a full run (see `tests/testthat/test-pipeline.R`).
5.  Describe the new columns in `docs/data-dictionary.md`.

## One odd step: `csv_roundtrip()`

The old scripts passed data between steps through CSV files. Reading a CSV changes the type of some columns (for example dates become text) and some column names (for example `Covid-19related` becomes `Covid.19related`). The later steps depend on this.

`csv_roundtrip()` in `R/utils/legacy.R` repeats this change at the same places. This keeps the column types and names the same as before. Later, you can replace it step by step with clear column types. Change one step and keep the tests green.

## Style

-   Use base R and the tidyverse. Write `package::function()` inside the `R` folder.
-   A comment explains **why**, not what.
-   Make one change at a time. Do not commit data, results or settings files.
