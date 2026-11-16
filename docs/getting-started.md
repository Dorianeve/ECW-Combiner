# Getting started

This guide takes you from nothing to your first results. It needs about 30 minutes, plus the time of the first run.

If a word is new to you, look it up in the [Glossary](glossary.md).

## What you need

Before you start, check that you have:

-   [ ] **R**, version 4.3 or newer. You can get it from <https://cran.r-project.org>. RStudio is nice to have, but you do not need it.
-   [ ] **The folder with the Excel files** on your own computer. It must be a full copy, not just a shortcut.
    -   SharePoint or OneDrive: sync the whole folder to your computer.
    -   Google Drive: see [Google Drive](google-drive.md).
-   [ ] **Your GMS login** (user name and password).
-   [ ] **Last year's CR and PR combiners** as CSV files. Combiner adds this year's data to them.
-   [ ] **The partner project AnnualResultsReport** (optional), downloaded into the **same parent folder** as Combiner, side by side. Combiner then copies its results into it. See [the README](../README.md#works-together-with-annualresultsreport).
-   [ ] **The three lookup tables for the PR combiner**: `pr_columns.csv`, `pr_columns_order.csv` and `pr_old_new_names.csv`. Put them in the `reference` folder. Only the PR combiner needs them.

## Step 1. Open a terminal in the project folder

The project folder is the folder that contains `README.md`, `R` and `scripts`.

-   **Windows:** open the folder in File Explorer, click the address bar, type `powershell` and press Enter.
-   **RStudio:** open the project and use the *Terminal* tab.

All commands in this guide are typed in this terminal.

## Step 2. Install the R packages

Run this once on each computer:

``` bash
Rscript scripts/install_packages.R
```

It can take a few minutes. It installs the helper packages that Combiner needs.

## Step 3. Make your settings file

1.  Copy the file `config/config.example.yml`.
2.  Name the copy `config/config.yml`.
3.  Open it with any text editor and change these parts. Leave the rest as it is for now.

| Setting | What to put |
|----|----|
| `paths: source_dir` | The folder with your Excel files, for example `"C:/Data/SharePoint/Grants DB"`. Use `/` and not `\`. |
| `source: file_patterns` | A part of the file name of each kind of Excel file. For example `"Results template.*\\.xlsx$"`. |
| `tables` | The names of the Excel tables inside your files. See the tip below. |
| `reporting: year` | The reporting year, for example `2025`. |
| `reporting: window_cutoff_date` | Reports for periods that end **before** this date are used, for example `"2026-01-01"`. |
| `inputs` | The paths of last year's CR and PR combiners (CSV). |

**Tip: how to find the name of an Excel table.** Open one Excel file. Click inside the table. Open the *Table Design* tab. The name is in the box on the left (*Table Name*).

Every setting is explained in [Settings](configuration.md).

## Step 4. Add your GMS login

1.  Copy the file `.Renviron.example`.
2.  Name the copy `.Renviron`.
3.  Open it and fill in your user name and password:

    ```
    GMS_USER=your.name@example.org
    GMS_PASSWORD=your-password
    ```

4.  Save the file and restart R (or open a new terminal).

The file `.Renviron` stays on your computer. It is never uploaded to GitHub.

## Step 5. Run Combiner

``` bash
Rscript scripts/run_pipeline.R
```

### What you will see

Combiner prints short messages while it works. For example:

```
Extracting 6 table(s) from 540 workbook(s) with 5 worker(s)...
Excluded 2 workbook(s) matching exclude_patterns (^ARCHIVED).
OK CR tables: all tables have consistent headers.
Data-collection checks: 4 issue(s) in 1 workbook(s), see output/checks/data_collection_issues.csv.
Diagnostics report: output/diagnostics/2026-10-12_103000/report.md (2 point(s) need attention)
```

At the end it prints a small table with the time of each step.

### How long does it take?

-   The **first run** reads every Excel file. This is the slow part.
-   **Later runs** only read files that are new or changed. They are much faster.

## Step 6. Look at the results

1.  **Open the report first:** `output/diagnostics/latest/report.md`. It tells you if something needs your attention. See [The run report](diagnostics.md).
2.  **Open the list of data problems:** `output/checks/data_collection_issues.csv`. If it has lines, send them to the people who own those Excel files. See [Problems in the Excel files](data-quality-checks.md).
3.  **Use the combiners:** the files are in `output/cr`, `output/pr`, `output/af` and `output/dcm`. Each folder has an Excel file (for example `cr_clean.xlsx`) and a CSV file. The columns are explained in the [Column guide](data-dictionary.md).

## Running from the R console (RStudio)

If you prefer to work inside R, type this instead:

``` r
source("R/pipeline/run_pipeline.R")
source_project()
result <- run_pipeline(load_config())
```

## What next?

| You want to… | Read |
|----|----|
| Run it again after a few days | Just run the same command. Use `--refresh` if you want to read all Excel files again. |
| Change a setting | [Settings](configuration.md) |
| Prepare a new reporting year | [Start a new year](yearly-checklist.md) |
| Fix an error | [Troubleshooting](troubleshooting.md) |
