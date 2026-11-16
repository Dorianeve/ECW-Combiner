# Settings

All settings are in one file: `config/config.yml`. You make it by copying `config/config.example.yml`. The file stays on your computer and is never uploaded to GitHub.

To use a different settings file, set the environment variable `COMBINER_CONFIG` to its path.

## How to edit the file

The file is written in a simple format called YAML. Five rules are enough:

-   `name: value` sets a value.
-   The spaces at the start of a line matter. Keep the same indent as in the example.
-   A line that starts with `#` is a comment. Combiner ignores it.
-   `~` means "empty". Put text in quotes if it contains special signs, for example `"C:/Folder"`.
-   In paths, use `/` and not `\`.

## Your GMS login

The best place for your login is the file `.Renviron`:

```
GMS_USER=your.name@example.org
GMS_PASSWORD=your-password
```

Restart R after you change it.

You can also write `user` and `password` under `gms:` in `config.yml`. If both exist, `.Renviron` wins. **Never** send these files to other people.

## All settings

### paths: where things are

| Setting | What it does | Example |
|----|----|----|
| `source_dir` | The folder with your Excel files. Combiner **only reads** here. | `"C:/Data/SharePoint/Grants DB"` |
| `reference_dir` | The folder with the three lookup tables for PR. | `"reference"` |
| `cache_dir` | Where Combiner keeps its saved copy of the data. Must **not** be inside `source_dir`. | `"cache"` |
| `output_dir` | Where the results go. Must **not** be inside `source_dir`. | `"output"` |

A path without a drive letter, like `"output"`, starts from the folder where you run the command.

### source: which Excel files to use

| Setting | What it does |
|----|----|
| `backend` | Keep `local`. It means "a normal folder on this computer". |
| `file_patterns` | One pattern for each kind of Excel file: `results`, `programme`, `finance`, `aligned`. A pattern is a part of the file name. Capital letters do not matter. |
| `exclude_patterns` | Files whose name matches one of these patterns are **skipped**. The default is `"^ARCHIVED"` (names that start with ARCHIVED). Write `exclude_patterns: []` to skip nothing. |

Which kinds of file does each combiner read?

| Combiner | Kinds of file |
|----|----|
| CR | `results`, `programme` |
| PR | `results`, `programme` |
| AF | `programme`, `aligned` |
| DCM | `finance`, `programme` |

### tables: names of the Excel tables

Combiner reads **Excel tables**, not loose cells. In this section you give the name of each table. The names must be exactly the same as in your Excel files.

| Setting | Used by |
|----|----|
| `children` | CR |
| `results_framework` | PR |
| `standard_indicators` | PR |
| `reporting_windows` | CR and PR |
| `leverage_funding` | AF |
| `finance_dcm` | DCM |

The first row of each Excel table must be its header row (the column names).

### parallel: work on several files at once

| Setting | What it does |
|----|----|
| `enabled` | `true` = several workers. `false` = one thing at a time. |
| `workers` | `auto` or a number. `auto` uses the number of cores minus one, but at most 6. |

Each worker needs its own memory. If R runs out of memory, use fewer workers.

### gms: the grants system

| Setting | What it does |
|----|----|
| `base_url` and `endpoints` | The address of the GMS and its download paths. |
| `from_file` | A saved GMS file. If you set it, Combiner does **not** call the GMS. Leave it as `~` for live data. |
| `user`, `password` | Your login. Prefer `.Renviron`. |

### reporting: the year and its rules

| Setting | What it does |
|----|----|
| `year` | The reporting year, for example `2025`. Many names are made from it, for example `Activein2025` and `ARR25 Annual`. |
| `window_cutoff_date` | Use reporting periods that end **before** this date. |
| `apply_approval_filter` | `true` = keep only reports approved by M&E. `false` = keep all. |
| `active_years` | The years that get an `ActiveinYYYY` column, for example `[2023, 2024, 2025]`. |

#### Year words in settings

Some settings can contain a **year word**. Combiner replaces it with a year.

| Write | You get (for year 2025) |
|----|----|
| `{year}` | `2025` |
| `{yy}` | `25` |
| `{year-1}` | `2024` |
| `{yy-1}` | `24` |
| `{year+1}` | `2026` |

#### active_in: the ActiveinYYYY columns

Each column says if a grant was running in a year. "Yes" means the dates of the grant overlap that period.

| Setting | Default | What it does |
|----|----|----|
| `start` | `"{year}-01-01"` | First day of the period |
| `end` | `"{year}-12-31"` | Last day of the period |
| `lead_rule` | `true` | `true` = all grantees of a programme take the value of the lead grantee. `false` = each grantee keeps its own value. |

The column name is always `Activein` and the year. The names cannot be changed.

*Example: a year that runs from July to June.*

``` yaml
active_in:
  start: "{year-1}-07-01"
  end: "{year}-06-30"
```

#### strategic_plan: the ActiveStrategicPlan column

| Setting | Default | What it does |
|----|----|----|
| `start`, `end` | (you set them) | "Yes" if the grant overlaps this period |
| `include_boundary_end` | `false` | Should a grant that ends **exactly on the start day** count as active? The old scripts said no. Keep `false` to get the same results as before. |

#### exercises: the Annual and Cumulative rows

For the current year, Combiner adds the rows once for each **exercise**. Last year's rows come from last year's combiner.

| Setting | Default | What it does |
|----|----|----|
| `annual_label` | `"ARR{yy} Annual"` | The text for the annual rows |
| `cumulative_label` | `"ARR{yy} Cumulative"` | The text for the cumulative rows |
| `previous_cumulative_label` | `"ARR{yy-1} Cumulative"` | The text of the cumulative rows in last year's combiner |
| `create` | `[cumulative, annual]` | Which exercises to make. You can use only one. |
| `carry_over_inactive` | `true` | Copy last year's cumulative rows of grants that are no longer active into this year's cumulative report. |
| `annual_rule`, `cumulative_rule` | none | Choose which rows belong to the exercise. See below. |

**Without a rule, every row belongs to both exercises.** This is what the old scripts did.

**With a rule,** a row belongs to the exercise only if the end date of the programme's latest reporting window is between `from` and `to`. A row without a date does not belong to it.

``` yaml
exercises:
  annual_rule:
    from: "{year}-01-01"
    to: "{year}-12-31"
```

### filters: grants without a country

| Value | What it does |
|----|----|
| `legacy` (default) | The same as the old scripts. "Global" and "Regional" grants are **kept**. Only rows with an empty country are removed. (The old filter said `Country != "Global" | Country != "Regional"`. A country cannot be both, so this is true for every country.) |
| `exclude` | "Global" and "Regional" grants are **removed**. Rows with an empty country are kept. This **changes the numbers**. |
| `keep` | Nothing is removed, not even rows with an empty country. |

### checks: text that is not a problem

| Setting | What it does |
|----|----|
| `known_text_below_tables` | Template text that sits under a table, for example a footer. Combiner does not report it as "rows under the table". Give the name under `tables:` and the first words of the row. See [Problems in the Excel files](data-quality-checks.md). |

### inputs: last year's combiners

| Setting | What it does |
|----|----|
| `previous_cr_combiner` | The path of last year's CR combiner (CSV). |
| `previous_pr_combiner` | The path of last year's PR combiner (CSV). |

### outputs and safety

| Setting | What it does |
|----|----|
| `outputs: arr_input_dir` | The `data/input` folder of the partner project AnnualResultsReport. After every run, Combiner copies `cr_clean.xlsx`, `pr_clean.xlsx` and `grants_db.csv` there. The default is `../AnnualResultsReport/data/input`, which works when both projects are downloaded side by side in the same parent folder. Write `~` to switch it off. Must **not** be inside `source_dir`. |
| `outputs: share_dir` | An extra folder that gets a copy of each Excel result, for example a shared drive. Must **not** be inside `source_dir`. |
| `safety: verify_source` | `false` turns off the check that your Excel folder did not change during the run. It is on by default. |
| `diagnostics: enabled` | `false` turns off the report of the run. It is on by default. |

## The lookup tables for PR

The PR combiner needs three small CSV files in the folder `reference_dir`:

| File | What it holds |
|----|----|
| `pr_columns.csv` | The column names of the three result templates and the names they get when they are put together |
| `pr_columns_order.csv` | The order of the columns. One column named `Results`. |
| `pr_old_new_names.csv` | Two columns, `clean` and `old_combiner`. They match the column names of last year's PR combiner to the current names. |

Without them, the PR flow stops with a "file not found" message. The other flows do not need them.

## Command options, the cache and offline work

| Command | What it does |
|----|----|
| `Rscript scripts/run_pipeline.R` | Normal run. Files that are new or changed are read again. All others come from the cache. The GMS list is downloaded and saved in `cache/gms`. |
| `... --refresh` | Reads **all** Excel files again. |
| `... --cache-only` | Uses **only** saved data. No Excel file is opened, your Excel folder is not looked at, and there is no GMS login. |
| `Rscript scripts/save_gms.R` | Downloads the GMS list and saves it, without touching any Excel file. |

`--cache-only` stops with a clear message if the cache is empty, if a table is missing in the cache, or if no GMS list was saved. In this mode, files that changed or were deleted after they were cached still show their old data.

The cache holds copies of your data. Keep it private. It is never uploaded to GitHub.
