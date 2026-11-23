# Start a new reporting year

You do **not** need to change any code. Everything that changes each year is in `config/config.yml`.

Use this list every year. Tick each point when it is done.

## Before the run

-   [ ] **Keep last year's results.** You need last year's CR and PR combiners as CSV files.
-   [ ] **Point to them.** In `config/config.yml`, set `inputs: previous_cr_combiner` and `previous_pr_combiner`.
-   [ ] **You do not have to clean last year's files by hand.** If last year's CSV was cleaned by the ARR project, Combiner puts the Combiner column names back (for example `Grantee` becomes `Granteeorganization`) and drops the columns that ARR adds (`date`, `yearstart`, `yearend`, `exercice`, and for PR also `Total`, `unit2`, `RW_number` and similar). If the CSV was saved in Excel, dates like `12/26/2023` are changed back to `2023-12-26`. The run log says what was changed.
-   [ ] **Set the year.** Change `reporting: year` to the new year, for example `2026`. Names like `Activein2026` and `ARR26 Annual` are made from it. Last year's names (`Activein2025`, `ARR25 Cumulative`) are found by Combiner itself.
-   [ ] **Check the dates.**
    -   `window_cutoff_date`: reports for periods that end before this date are used.
    -   `active_years`: usually the last three years, up to the new year.
    -   `strategic_plan`: the start and end of the strategic plan.
-   [ ] **Decide about approval.** Should only reports approved by M&E be used? Set `apply_approval_filter`. Use `false` for a report in the middle of a cycle.
-   [ ] **Check the Excel folder.** Is the whole folder synced to your computer (not only a shortcut)? Do old copies of files start with `ARCHIVED`, so that they are skipped?
-   [ ] **Check the templates.** Did the Excel templates change this year? Did a table get a new name? If yes, change `tables:` in your settings and check the lookup tables in the `reference` folder.
-   [ ] **Check your login.** `GMS_USER` and `GMS_PASSWORD` must be set.
-   [ ] **Special rules?** If you need a different year period (for example July to June), or different Annual and Cumulative rules, see `active_in` and `exercises` in [Settings](configuration.md).

## Run


1.  Do the first run of the year with `--refresh`. This reads all Excel files.

    ``` bash
    Rscript scripts/run_pipeline.R --refresh
    ```

2.  Later runs in the same year need no option:

    ``` bash
    Rscript scripts/run_pipeline.R
    ```

## After the run

-   [ ] **Open the run report:** `output/diagnostics/latest/report.md`. Read the part "Attention". See [The run report](diagnostics.md).
-   [ ] **Open the list of data problems:** `output/checks/data_collection_issues.csv`. Send the lines to the people who own those Excel files. See [Problems in the Excel files](data-quality-checks.md).
-   [ ] **Check the file `output/run_log.csv`.** Each flow must have a number of rows. The line `source_folder_untouched` must show `1`.
-   [ ] **Compare with last year.** Look at the number of rows of each combiner. A big change you cannot explain usually means a template or a filter changed. The row trace in the report shows where.
-   [ ] **Check the hand-over to AnnualResultsReport.** The files `cr_clean.xlsx`, `pr_clean.xlsx` and `grants_db.csv` must be new in `../AnnualResultsReport/data/input/`. Combiner copies them there itself, if both projects are side by side. If you see the warning "AnnualResultsReport was not found", see [Troubleshooting](troubleshooting.md).
-   [ ] **Keep the new CR and PR combiners (CSV).** You need them next year.
-   [ ] **Give the Excel results to the people who use them.** You can also set `outputs: share_dir` so Combiner copies them to a shared folder.
