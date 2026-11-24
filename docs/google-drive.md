# Using Google Drive

Combiner reads a normal folder on your computer. It does not matter if the folder comes from SharePoint, OneDrive or Google Drive.

The easiest way to use Google Drive is **Google Drive for Desktop**. It shows your Drive as a folder on your computer.

## Step 1 (optional): export Google Sheets to real Excel files first

Skip this step if every source workbook is already a real `.xlsx` file. Read it if any of them
are **Google Sheets** -- a file saved as a Google Sheet is not an Excel file, and Combiner
ignores it (see *What is different from SharePoint* below). Instead of uploading or downloading
each one by hand, two scripts do this export for you, converting every matching Google Sheet to
a real `.xlsx` file and leaving a manifest of what happened:

| Script | Runs where | Needs |
|----|----|----|
| `scripts/00_drive_export.R` | Your computer | `install.packages("googledrive")`, `drive_export: folder_id:` in `config.yml`, a one-time Google sign-in (or a service account for unattended runs) |
| `scripts/drive_export.gs` | Inside Google (script.google.com), nothing to install | A Google account with access to the folders; fill in `SOURCE_FOLDER_ID` / `DEST_FOLDER_ID` at the top of the file |

Use the R script if you already run the rest of Combiner on your computer: it writes the
exported files straight into `drive_export: dest_dir:` (default `cache/drive_export`), which you
then point `paths: source_dir` at, or let Drive for Desktop mirror as usual.

```bash
Rscript scripts/00_drive_export.R
```

Use the Apps Script version if you would rather it run on Google's side -- for example with a
time-driven trigger so a destination folder always has fresh `.xlsx` copies, without needing R
or credentials on any particular computer. Paste `scripts/drive_export.gs` into a new project at
script.google.com, fill in the two folder ids, and run `exportDriveSheetsToXlsx()` once (see the
comments at the top of the file for the full set-up).

Both scripts skip a file that has not changed since the last run, and write a manifest CSV
(`drive_export_manifest.csv`, next to the exported files) with one row per source file:

| Column | Meaning |
|----|----|
| `id`, `name` | The Drive file's id and name. |
| `kind` | `sheet` (a Google Sheet that was converted) or `xlsx` (already a real Excel file). |
| `dest` | The exported file's name (the Google Sheet's name, with `.xlsx` added). |
| `modified`, `md5` | Drive's own last-modified time and checksum (`md5` is empty for a Google Sheet; Google does not keep one for its own formats). |
| `status` | `downloaded`, `updated`, `up_to_date`, or `error`. |
| `n_tables` | How many **Excel Tables** the exported file contains. Combiner reads Excel Tables, not loose cells (see [Settings](configuration.md)), and a Google Sheet does not have them -- they only exist once the file is exported to `.xlsx`. If this is `0`, the export did not produce one; open the result and add the table (or re-check the sheet) before relying on it. |
| `exported_at` | When this run happened. |

Once this folder has what you need, continue with the Set-up below as if it were any other
folder of real Excel files -- it does not have to be the same folder Drive for Desktop mirrors,
though it can be.

## Set-up

1.  Install **Google Drive for Desktop** and sign in.

2.  Open its settings. For **My Drive** (and for any shared drive you use), choose **Mirror files**. Do **not** choose "Stream files".

    - *Mirror files* keeps a full copy of every file on your computer.
    - *Stream files* downloads a file only when you open it. Combiner opens many files at once. With streamed files it is slow and can fail.

3.  Wait until Google Drive has finished its first sync.

4.  In `config/config.yml`, set `paths: source_dir` to the folder with your Excel files. Examples:

| Computer | Example path |
|----|----|
| Windows | `"G:/My Drive/Grants DB"` (use `/`, not `\`) |
| macOS | `"/Users/you/Library/CloudStorage/GoogleDrive-your.account/My Drive/Grants DB"` |
| Windows with WSL | `"/mnt/g/My Drive/Grants DB"` |

5.  Check `source: file_patterns`. They must match the names of your files.

Everything else works in the same way as with SharePoint.

## What is different from SharePoint

- **Only real Excel files are read.** A file saved as a *Google Sheet* is not an Excel file. Combiner ignores it. Upload your files as `.xlsx`, download them from Google Sheets as Excel files, or use one of the export scripts in Step 1 above to do this for every file at once.
- **Shortcuts are not followed.** A shortcut to a folder is not a copy. Add the folder to your own Drive, or open it through *Shared drives*, so the files are on your computer.
- **Double names.** Google Drive adds `(1)` to the name of a second file with the same name. Such a file may match your patterns. Look for these copies.
- **Lock files.** Files whose names start with `~$` are temporary Excel files. Combiner ignores them.
- **Changes are found by file size and date.** If you replace a file with a different file of the same size and date, run with `--refresh`.

## Where to keep the cache and the results

Keep the `cache` and `output` folders **on your computer, outside the Google Drive folder**. Combiner refuses to write inside the folder with your Excel files.

To share results with colleagues, set `outputs: share_dir` to another Drive folder. Combiner puts a copy of each Excel result there.

The partner project **AnnualResultsReport** should be on your computer too, in the same parent folder as Combiner. Combiner copies `cr_clean.xlsx`, `pr_clean.xlsx` and `grants_db.csv` into its `data/input/` folder (`outputs: arr_input_dir`). Keep both projects outside the Google Drive folder with your Excel files.

## If your computer has no Google Drive program

Linux has no official Google Drive program. A tool such as `rclone mount` can show Drive as a folder, and then the same settings work. **We have not tested this.** If you try it, use the full cache mode (`--vfs-cache-mode full`) so the files are really downloaded before Combiner reads them.

## Check that it works

Run:

``` bash
Rscript scripts/run_pipeline.R cr
```

The first messages tell you how many Excel files were found. If the number is `0` or much too small, check the path, the *Mirror files* setting and the file patterns.
