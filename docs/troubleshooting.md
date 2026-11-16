# Troubleshooting

Start with the run report: `output/diagnostics/latest/report.md`. After a failure it tells you at which step Combiner stopped, and what the error was. See [The run report](diagnostics.md).

Then find your message in the tables below.

## Combiner does not start

| Message | What it means and what to do |
|----|----|
| `Config file not found: config/config.yml` | You have no settings file yet. Copy `config/config.example.yml` to `config/config.yml`. Run the command in the project folder. |
| `paths$source_dir does not exist` | The folder with the Excel files is not there. Check the path. For Google Drive, check that it is mounted and set to *Mirror files*. With WSL, use paths like `/mnt/c/...`. |
| Warning `AnnualResultsReport was not found` | The partner project is not next to Combiner, so the three hand-over files were not copied | Download AnnualResultsReport into the same parent folder as Combiner, or set `outputs: arr_input_dir` in your settings to its `data/input` folder. Write `~` there if you do not use it. |
| `Refusing to write ... inside the source folder` | One of `cache_dir`, `output_dir` or `share_dir` is inside the folder with your Excel files. Choose a folder outside it. Also check the folder from which you run the command. |
| `GMS credentials missing` | Fill in `GMS_USER` and `GMS_PASSWORD` in `.Renviron` and restart R. |
| HTTP 401 or 403 from the GMS | The login is wrong, or the account may not download this list. |
| `No source files found in ...` | No Excel file matches your `file_patterns`, or all were skipped by `exclude_patterns`. Check both and check the folder. |
| `Previous CR/PR combiner not found` | Set `inputs: previous_cr_combiner` and `previous_pr_combiner` to files that exist. |
| `cannot open file 'reference/pr_columns.csv'` | The lookup tables for PR are missing. See [Settings](configuration.md#the-lookup-tables-for-pr). |

## Combiner stops during the run

| Message | What it means and what to do |
|----|----|
| `The pipeline stopped while …: …` | Combiner stopped before the flows. The words after "while" say at which step. The report has more detail. |
| `1 flow(s) failed: CR (…)` | One flow stopped. The other flows were made. The report shows where the flow stopped and the last step that worked. |
| `The cache is empty` or `lack a requested table` or `No saved GMS export in the cache` | You used `--cache-only`, but nothing is saved yet. Run once without it. Use `Rscript scripts/save_gms.R` to save the GMS list. |
| `Error: object '…' not found` | A template no longer has a column that Combiner expects. Find the Excel file and the column. Fix the template or the lookup tables. |

## Warnings

| Message | What it means |
|----|----|
| `N workbook(s) had read errors` | Some Excel files could not be opened: damaged, protected, or open in another program. The report lists them. Combiner tries them again next time. |
| `unexpected first column` | A table does not start with the column Combiner expects. Often the Excel table was moved or renamed, or its header is not in the first row. |
| `inconsistent headers` | Files of the same kind have different columns. Combiner fills the gaps, but check if a template changed. |
| `The source folder changed during the run` | A file in your Excel folder was added, removed or changed during the run. Combiner never writes there. Usually a sync program or another person did it. Run again when syncing is done. |

## The results look wrong

| What you see | Why |
|----|----|
| Fewer rows than before | Files that start with `ARCHIVED` are skipped. Check also the row trace in the report. |
| A change in an Excel file is not in the results | The file has the same size and date as before. Run with `--refresh`. |
| The same grant twice | Two Excel files of the same grant match your patterns (for example an old and a new copy). Skip one with `exclude_patterns`. |
| Some rows of an Excel file are missing | They may be typed **below** the Excel table. See `output/checks/data_collection_issues.csv` and [Problems in the Excel files](data-quality-checks.md). |
| Rows without a `ProgrammeID` | The grant reference in the Excel file is empty or unknown to the GMS. See the same list. |
| Small differences between Windows and Linux | Line breaks inside text cells are not the same. Numbers and dates are made equal by Combiner. The compare script ignores line breaks. |

## It is slow, or R runs out of memory

-   **The first run is slow.** It reads every Excel file. Files that exist only in the cloud must be downloaded first. Choose *Always keep on this device* (OneDrive) or *Mirror files* (Google Drive).
-   **R stops with "Killed" or a memory error.** Use fewer workers: set `parallel: workers` to a lower number, or `enabled: false`. Each worker needs its own memory. Comparing two big results also needs several GB.
-   **Later runs are slow too.** The cache may not be used. A new table name in `tables:` makes Combiner read the files again once. `--refresh` always reads again.

## You are still stuck

Run the failing step alone in R to see the full message:

``` r
source("R/pipeline/run_pipeline.R"); source_project()
cfg <- load_config()
extracted <- extract_all(cfg)       # only read the Excel files
extraction_report(extracted)        # for each file: read or cached, tables found, errors
```

Then send the report `output/diagnostics/latest/report.md` to someone who can help. See [The run report](diagnostics.md#getting-help-with-the-report).
