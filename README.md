# Combiner

Combiner is a tool written in R. It reads many Excel files and makes four clean tables from them.

Every year, grantees send reports in Excel files. Combiner collects the numbers from all these files and puts them together with information from the grants system (the "GMS"). The result is four tables, called **combiners**:

| Combiner | What is inside | What it is used for |
|----|----|----|
| **CR** | Children targeted and children reached, by education level and gender | Counting children |
| **PR** | Results of each programme: indicators, targets and values for each reporting period | Tracking results |
| **AF** | Aligned funding: other money that supports the same work | Funding overview |
| **DCM** | Money passed on to partners and sub-grantees | Tracking transfers |

## What Combiner does for you

- It reads every Excel file in a folder. It opens each file only **once**.
- It works on several files at the same time, so it is fast.
- It saves what it read. The next run only reads files that are new or changed.
- It **never changes your Excel files**. It only reads them.
- After every run it writes a **report** that shows what changed since the last run, so you find problems early.
- It makes a **list of problems in the Excel files**. You can send this list to the people who filled in the files.

## Works together with AnnualResultsReport

Combiner has a partner project: **AnnualResultsReport** (ARR). It takes the CR and PR combiners, cleans them, checks them and makes the tables for the Annual Results Report.

**Download both projects together, into the same parent folder, side by side:**

```         
my-folder/
├─ Combiner/               this project
└─ AnnualResultsReport/    the partner project (it reads what Combiner writes)
```

After every run, Combiner copies three files into `AnnualResultsReport/data/input/`, which is the folder that ARR reads:

| File | What it is |
|----|----|
| `cr_clean.xlsx` | The CR combiner |
| `pr_clean.xlsx` | The PR combiner |
| `grants_db.csv` | The list of grants from the GMS, after the processing for the ARR |

So you run Combiner first, then ARR. You do not have to copy files by hand. If the two folders are somewhere else, change `outputs: arr_input_dir` in your settings (see [Settings](docs/configuration.md)). If ARR is not found, Combiner still works: it only warns you that the files were not copied.

## Quick start

You need R (version 4.3 or newer). Then:

1.  **Install the R packages.** Run this once:

    ``` bash
    Rscript scripts/install_packages.R
    ```

2.  **Make your settings file.** Copy `config/config.example.yml` to `config/config.yml`. Open it and change the folder paths and the table names.

3.  **Add your GMS login.** Copy `.Renviron.example` to `.Renviron` and fill in your user name and password. Then restart R.

4.  **Run everything:**

    ``` bash
    Rscript scripts/run_pipeline.R
    ```

The first run reads all Excel files, so it takes the longest. Later runs are much faster.

A longer, step-by-step guide is in [Getting started](docs/getting-started.md).

## Where are the results?

| What | Where |
|----|----|
| The four combiners (CSV and Excel) | `output/cr/`, `output/pr/`, `output/af/`, `output/dcm/` |
| The grants list for the ARR (`grants_db.csv`) | `output/gms/` |
| The three files for AnnualResultsReport (`cr_clean.xlsx`, `pr_clean.xlsx`, `grants_db.csv`) | also copied to `../AnnualResultsReport/data/input/` |
| Report of the run (read this first) | `output/diagnostics/latest/report.md` |
| Problems to fix in the Excel files | `output/checks/data_collection_issues.csv` |
| How long each step took | `output/run_log.csv` |

## Useful commands

| You want to… | Run this |
|----|----|
| Run everything | `Rscript scripts/run_pipeline.R` |
| Run only some combiners | `Rscript scripts/run_pipeline.R cr pr` |
| Read all Excel files again | `Rscript scripts/run_pipeline.R --refresh` |
| Use only the saved data (no Excel files, no login) | `Rscript scripts/run_pipeline.R --cache-only` |
| Save the GMS data for later use | `Rscript scripts/save_gms.R` |

## Read more

| Document | Read it to… |
|----|----|
| [Getting started](docs/getting-started.md) | set up and run Combiner for the first time |
| [Glossary](docs/glossary.md) | understand the words used in this project |
| [How it works](docs/architecture.md) | see the steps from Excel files to results |
| [Settings](docs/configuration.md) | change what Combiner does |
| [Column guide](docs/data-dictionary.md) | know what each column in the results means |
| [Start a new year](docs/yearly-checklist.md) | prepare the next reporting year |
| [Google Drive](docs/google-drive.md) | use Google Drive instead of SharePoint |
| [Problems in the Excel files](docs/data-quality-checks.md) | read and use the list of data problems |
| [The run report](docs/diagnostics.md) | understand the report and find out what went wrong |
| [Troubleshooting](docs/troubleshooting.md) | fix common errors |
| [For developers](docs/development.md) | change the code and run the tests |

## Safety

- **Your Excel files are safe.** Combiner only reads them. It refuses to write anything inside the folder with your Excel files. After each run it also checks that no file in that folder changed.
- **No data or passwords go to GitHub.** Your settings file, your password file, the saved data and the results are all excluded. A check runs before each commit and stops you if it finds an email address, a personal path, a password or a data file. Turn it on once with `git config core.hooksPath .githooks`.
- **The tests use made-up data only.**

## Folders

```         
config/      example settings (your own settings file stays on your computer)
R/           the code
scripts/     the commands you run
reference/   small lookup tables used by the PR combiner
tests/       automatic tests, with made-up data
docs/        this documentation
```

## Licence

MIT. See [LICENSE](LICENSE).

## Tests

The tests use made-up data only. Run them on your own computer (see [For developers](docs/development.md)). They are not run on GitHub, because the real Excel files are only available inside the organisation.
