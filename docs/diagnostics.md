# The run report

After every run, Combiner writes a report. The report shows **what changed since the last run**, and **what went wrong** if something failed.

Use it to check your results. You can also give it to a data scientist or to an AI assistant when you need help. It contains no data rows and no passwords.

## Where is it?

The newest report is always here:

`output/diagnostics/latest/report.md`

Every run also has its own folder, named with the date and time:

```
output/diagnostics/
  latest/                 a copy of the newest run
  2026-10-12_103000/      one folder for each run
    report.md             the report: read this first
    findings.csv          the points of the report, one row each
    trace.csv             the row trace: how many rows after each step
    inputs.csv            one row for each Excel file that was used
    schema.csv            the columns found in each kind of table
    outputs.csv           the columns of each result and how many cells are empty
    run.log               every message and warning of the run
    profile.rds           numbers that the next run compares with
```

Combiner compares each run with the **newest earlier run that worked**. To start from zero, delete the folders.

## How to read the report

Start at the top. The first lines tell you the **status**:

-   *Nothing needs attention.* Everything looks as before.
-   *N point(s) need attention.* Read section 1.
-   *1 flow(s) FAILED.* One combiner could not be made. The other combiners were made.
-   *THE RUN FAILED.* Combiner stopped. The report says where and why.

| Section | What it tells you |
|----|----|
| **Attention** | Things that changed and that you should look at |
| **Information** | Changes that are usually fine |
| **Output size** | The number of rows and columns of each combiner |
| **Row trace** | The number of rows after each step (see below) |
| **Input workbooks** | How many Excel files were used, how many were read and how many came from the cache |
| **Messages and warnings** | Everything Combiner printed during the run |
| **Environment** | The versions of R and of the packages |
| **Settings** | Your settings. Passwords are removed and paths are shortened. |

## What the attention points mean

| Point | What probably happened | What to do |
|----|----|----|
| `new column in workbooks` or `column no longer in any workbook` | An Excel template changed | Look at the template. A renamed column may need a change in the lookup tables or in the code. |
| `new output column` or `output column disappeared` | A template or a step changed | Tell the people who use the results |
| `new value(s) in …` | There is a new category, spelling or unit in the data | Decide if the cleaning rules need the new value, or ask for a correction in the Excel file |
| `share of empty cells changed in …` | A column is no longer filled in, or it was renamed | Compare with the Excel files |
| `row count changed` | A filter, a join or the input data changed | Look at the row trace |
| `row counts start to differ from the last run at this step` | This is the step where this run first differs from the last run | Look at this step first |
| `the flow failed` | One flow stopped with an error | Read the section "Failed flows" |
| `workbook could not be read` | The Excel file is damaged, protected or open in another program | Ask for a new copy |
| `workbooks without any configured table` | The Excel table has a new name or was removed | Check `tables:` in your settings and the Excel file |
| `issues to send to the workbook owners` | There are data problems in Excel files | See [Problems in the Excel files](data-quality-checks.md) |
| `warnings during the run` | R printed a warning | Read `run.log` |

Combiner reports a change in these cases:

-   The share of empty cells in a column moves by 10 percentage points or more.
-   A number of rows changes by 10 % or more, and by at least 5 rows.

It compares value by value only in columns with at most 60 different values.

## The row trace

Every flow counts its rows after each main step. For example: "after keeping formal and non-formal education" or "after joining the GMS". The report shows the counts in order:

| step | rows | change | last_run |
|----|----|----|----|
| CR source: after dropping rows without a GRN | 12,345 | -210 | 12,330 |
| CR join: after joining the GMS (should not add rows) | 12,345 | +0 | 12,330 |

How to use it:

-   **Find where rows are lost.** A big negative number in `change` shows the step that removed rows.
-   **Find duplicates.** A step marked "should not add rows" must show `+0`. If it shows a plus, a key appears twice in the GMS or in the reporting windows.
-   **Compare with the last run.** The column `last_run` shows the same step in the last run. The report also names the first step where the two runs differ.

`trace.csv` has the same numbers for all flows.

*For developers:* a step is recorded with one line, `... |> trace_step("what this step is")`. The text is also the key for the comparison with the last run, so do not change it without a reason.

## When something fails

The report is written **even if the run fails**.

| What failed | What Combiner does | What the report shows |
|----|----|----|
| **One flow** (CR, PR, AF or DCM) | The other flows go on and their results are written. After the report, Combiner stops with an error. In `run_log.csv` the flow is named `flow_<name>_FAILED`. | The error, the functions where it happened, the last step that worked, and the row trace up to that point |
| **A step before the flows** (reading Excel files, GMS, reporting windows, lookup tables, last year's combiners) | Combiner stops with a message such as "stopped while loading the GMS export: …" | The step, the error, the functions, the Excel files read so far, and the whole log |
| **Empty cache** with `--cache-only` | Combiner stops with a clear message | The same kind of report |

A failed run is **not** used for the next comparison. The next run is compared with the last run that worked.

## Getting help with the report

You can share `report.md`. If someone asks, also share `findings.csv` and `run.log`.

**What is in them:**

-   names of Excel files, columns and tables
-   counts and percentages
-   the values of columns with few different values, but only in lines that report a change (for example a new unit or a new organisation name)

**What is not in them:** data rows, free-text comments, passwords. Paths are shortened to the last folder.

Names of Excel files can contain grant numbers. If that is a problem for the person who will read the report, remove `inputs.csv` and the file names from the report first.

*A good question to ask:* "This is the report of our reporting tool. The run for this year shows these attention points. Which ones point to a change in an Excel template, and what must we change in the settings or in the code?"

## Settings

``` yaml
diagnostics:
  enabled: true     # false = no report
```

The report is written only when the results are written. With `--cache-only` it describes the saved data.

## Limits

-   The report counts rows. It tells you **where** rows are lost, not **which** rows. To see which rows, run the step on its own in R.
-   A step is in the trace only if someone placed a trace point there.
