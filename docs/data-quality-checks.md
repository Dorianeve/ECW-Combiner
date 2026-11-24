# Problems in the Excel files

Some problems cannot be fixed by Combiner. They are inside the Excel files, and only the people who fill in the files can fix them. Combiner finds these problems and writes them in a list.

**The list is here:** `output/checks/data_collection_issues.csv`

Combiner also prints one line when it finishes, for example: `Data-collection checks: 4 issue(s) in 1 workbook(s)`.

If the list is empty, Combiner found no problems.

## What to do with the list

1.  Open the file in Excel.
2.  Each line names one Excel file and one problem.
3.  Send the lines to the owner of that Excel file. Ask them to fix it.
4.  Run Combiner again. The problem should be gone.

## The columns of the list

| Column | What it means |
|------------------------------------|------------------------------------|
| `file` | The Excel file that has the problem |
| `table` | The table in that file (or the combiner, for the second problem below) |
| `issue` | The kind of problem |
| `n_rows` | How many rows are affected |
| `detail` | Where to look, and what Combiner found |

## The two kinds of problem

### 1. `content_below_table`: rows under the table

**What it means.** Someone typed rows directly under an Excel table, but did not make the table longer. These rows are not part of the table. Combiner does not read them.

**How to fix it in Excel.**

1.  Click in the table.
2.  Open the *Table Design* tab.
3.  Choose *Resize Table*.
4.  Select all the rows, including the new ones.
5.  Save the file.

You can also drag the small handle in the bottom right corner of the table downwards.

The column `detail` shows the range of the table, the sheet and the first words of the extra rows. This makes the rows easy to find.

*Good to know:* Combiner counts only rows that follow the table **without an empty row between**. It looks at most 30 rows down.

**Text that belongs to the template.** Some templates have fixed text under a table, for example a footer such as "Please use the link to confirm…". This is not data, so Combiner should not report it. Write the start of that text in your settings:

``` yaml
checks:
  known_text_below_tables:
    reporting_windows:                      # the name under "tables:"
      - "^Please use the link to confirm"   # the first words of the row
```

Everything else under the table is still reported. After you change this list you do not need to read the Excel files again. But files that were cached before this feature existed need one run with `--refresh` first.

### 2. `no_programme_match`: rows without a programme

**What it means.** Some rows of the current year have no `ProgrammeID`. Their grant reference is empty or Combiner cannot find it in the GMS. These rows cannot be linked to a programme, a country or dates.

**How to fix it.**

- Fill in the grant reference (the "grid" cell) in the Excel file. This is result of a formula, check it if it broke.
- If the reference is correct, check that the grant exists in the GMS.

## Good to know

- Combiner looks for rows under tables when it **reads** a file. Files that were saved in the cache before this check existed are reported as "not checked". Run once with `--refresh` to check all files.
- With `--cache-only`, the list shows what Combiner found when it last read the files.
- Combiner never changes Excel files. The people who own the files fix them.
