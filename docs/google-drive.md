# Using Google Drive

Combiner reads a normal folder on your computer. It does not matter if the folder comes from SharePoint, OneDrive or Google Drive.

The easiest way to use Google Drive is **Google Drive for Desktop**. It shows your Drive as a folder on your computer.

## Set-up

1.  Install **Google Drive for Desktop** and sign in.

2.  Open its settings. For **My Drive** (and for any shared drive you use), choose **Mirror files**. Do **not** choose "Stream files".

    -   *Mirror files* keeps a full copy of every file on your computer.
    -   *Stream files* downloads a file only when you open it. Combiner opens many files at once. With streamed files it is slow and can fail.

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

-   **Only real Excel files are read.** A file saved as a *Google Sheet* is not an Excel file. Combiner ignores it. Upload your files as `.xlsx`, or download them from Google Sheets as Excel files.
-   **Shortcuts are not followed.** A shortcut to a folder is not a copy. Add the folder to your own Drive, or open it through *Shared drives*, so the files are on your computer.
-   **Double names.** Google Drive adds `(1)` to the name of a second file with the same name. Such a file may match your patterns. Look for these copies.
-   **Lock files.** Files whose names start with `~$` are temporary Excel files. Combiner ignores them.
-   **Changes are found by file size and date.** If you replace a file with a different file of the same size and date, run with `--refresh`.

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
