# Column guide

This page explains the columns of the four combiners.

> **Please check these texts.** They were written from the code and from the column names. Someone who knows the Excel templates should check the lines marked *(check)*.

The column names are written exactly as Combiner writes them. Other tools may depend on these names, so they are not changed.

## Things that are the same everywhere

-   **Yes/No columns** hold the text `Yes` or `No`.
-   **An empty cell** means there is no value.
-   In names like `ARR<yy>`, `<yy>` stands for the last two digits of the year. For 2025 this is `25`. `<year>` stands for the full year.
-   **Exercise** is a label in the CR and PR combiners. It says which report a row belongs to:
    -   `ARR<yy> Annual` and `ARR<yy> Cumulative` are the rows of the current year. Every row of the current year appears once with each label.
    -   Rows of earlier years come from last year's combiner, for example `ARR<yy-1> Cumulative`.
    -   Grants that are no longer active keep their last cumulative rows. They are copied into `ARR<yy> Cumulative`.

## Columns that come from the GMS

These columns hold information about the grant. They are the same in every combiner that has them.

| Column | What it means |
|----|----|
| `ProgrammeID` | The number of the programme |
| `LeadGRN` | The grant reference of the lead grantee. It is the 5th part of the `GRID` text. |
| `GMGRN` | The grant reference of this grantee in the GMS |
| `Reportingrole` | The role of the grantee in the programme, for example lead or partner |
| `Granteeorganization` | The name of the grantee organisation |
| `Country` | The country of the programme |
| `Typeofinvestment` | The type of investment. Grants of type `AF` are removed from CR and PR. |
| `Startdate`, `Currentenddate`, `Excomapprovaldate` | The start date, the current end date and the approval date of the grant |
| `Covid19relatedgrant`, `Covid19related` | Is the grant about Covid-19? |
| `Activein<year-1>`, `Activein<year>` | `Yes` if the grant was running in that year. All grantees of a programme take the value of the lead grantee. |
| `ActiveStrategicPlan` | `Yes` if the grant was running during the strategic plan period |
| `GRID` | A text from the Excel file that identifies the grant. Its parts are separated by `\|`. |

## The grants list for the ARR (`output/gms/grants_db.csv`)

One row for each grant (GRN), made from the GMS export: the grant data, the `ActiveinYYYY` flags, `ActiveStrategicPlan`, the crisis and emergency flags. Grants of type AF and grants without a country are removed. This is the same list that the CR and PR flows join to. It is copied to `AnnualResultsReport/data/input/` after every run, because ARR uses it to check which programmes should be in the CR and PR.

## CR: children reached (`output/cr/`)

**One row** is one number of children, for one programme, report, indicator, type of beneficiary, education level, gender and status.

| Column | What it means |
|----|----|
| (the GMS columns above) | See above |
| `Covid19relateddata` | `Covid-19 related data` or `Non-Covid-19 related data`. A row is "Covid-19 related" when the name of its Excel file contains the word "Covid". |
| `Typeofreporting` | `Individual` or `Joint`. Empty if neither. |
| `Typeofeducation` | `Formal education` or `Non-formal education` |
| `Indicator` | The indicator that is reported |
| `Status` | `Targeted` or `Reached` |
| `Typeofbeneficiary` | The kind of beneficiary. The values "other", "total" and "unknown" are written in one standard way. |
| `Levelofeducation` | `Pre-primary`, `Primary`, `Secondary`, `Unknown level of education` or `Total` |
| `Gender` | `Female`, `Male` or `Total` |
| `Number` | The number of children |
| `Commentsandcontext` | Free text from the grantee |
| `Dateofreporting` | The date of the report, as the grantee typed it |
| `Sourceofdata` | Where the row comes from, `ARR<yy> CR` |
| `Filename` | The Excel file the row comes from |
| `MnEReview` | The M&E review status of the latest reporting window of the programme |
| `ReportingWindow`, `ReportingPeriodUpTo` | The latest reporting window before the cut-off date, and the date it covers |
| `ExportDate` | The day Combiner was run |
| `Exercise` | See "Things that are the same everywhere" |

Note: the totals of an education level are the female number plus the male number. The totals over all levels come from the totals in the Excel file.

## PR: programme results (`output/pr/`)

**One row** is one value of one result or indicator, for one reporting window and one gender (`Total`, `Female` or `Male`).

Combiner writes the PR result in two stages, like the old scripts:

| File | What it is |
|----|----|
| `<date>_pr cleaned.csv` | The combiner **before** the last tidy-up |
| `pr_clean.xlsx` and `pr_clean.csv` | The combiner **after** the last tidy-up. Dates are real dates, codes and units have one standard spelling, and yes/no answers are standard. |

### Main columns

| Column | What it means |
|----|----|
| `ProgrammeID`, `LeadGRN`, `GMGRN`, `Typeofinvestment`, `Country`, `Granteeorganization`, `CurrentEndDate`, `Activein<year-1>`, `Activein<year>`, `GRID` | From the GMS. See above. |
| `OutcomeOutputNumbering`, `Level`, `ResultStatement` | The number, the level (outcome or output) and the text of the result |
| `Indicator`, `ProgramSpecificIndicator`, `IndicatorPSIMerged` | The standard indicator, the indicator of the programme, and the two together |
| `ReportingWindow` | `Baseline`, `Target`, `Revised_target`, or a reporting window (`Rw1` to `Rw6`) |
| `Year`, `ReportEndDate` | The year of the data and the end date of the window. An Excel "zero date" (a date cell that shows 0) is left empty. |
| `Gender` | `Total`, `Female` or `Male` |
| `Value` | The value. It is a number after the tidy-up. |
| `ChildrenWithDisabilities`, `OtherLevelsOfDisaggregation` | Extra breakdowns |
| `Comments`, `GeneralComments`, `DetailedComments` | Comments of the window, of the result, and longer notes |
| `AnalysisCode` | A code that sorts the indicator for analysis. After the tidy-up it is in lower case and has one standard spelling. |
| `UnitOfMeasurement` | `# Number`, `% Percentage`, `US$`, `Yes/No`, `Ratio`, `Scale`, and so on |
| `DisaggregatedBySex` | `yes` or `no` |
| `IndicatorApplicability`, `IndicatorAdmin`, `DuplicatedIndicator`, `DataAvailability`, `IndicatorType` | Fields filled in during review of the template *(check)* |
| `DateIndicatorProposed` | The date the indicator was proposed |
| `SourceOfVerification` | How the value is checked |
| `ContributingAgencies`, `AlignmentWithHRPIndicators` | As typed in the template *(check)* |
| `ECWComments`, `GranteeResponseToMEComment` | The comment of the reviewer and the answer of the grantee |
| `MnEReview` | The M&E review status of the latest reporting window |
| `SourceOfData` | The template the row comes from: `ARR<yy> - PT` (programme), `- RT` (results), `- SI` (standard indicators) |
| `FileName` | The Excel file the row comes from |
| `Exercise` | See "Things that are the same everywhere" |
| `ExportDate` | The day Combiner was run |

### Extra columns you can ignore

Some columns come along from the templates, the GMS or older combiners. Do not use them unless you know them:

`current_budget`, `ecw_indicator`, `dropdown_list_location`, `ar_grid_2022`, `grid`, `indicator_data_status`, `include_in_fer_dropdown`, `include_in_myrp_dropdown`, `Reportingrole`, `Startdate`, `ActiveStrategicPlan`, `Covid19related`, `covid_19_related_report`, `covid_flag`, `reporting_period_up_to`, `report_year`, `source`, `InterventionCategoryFromLibrary`, `IndicatorFromLibrary`, `LinkECWResult`, `OmitForBeneficiaryAnalysis`, `OmitForEduLevelAnalysis`.

A few more columns have no real content: `column1`, `kolom1`, `na`, `x1`, `Attribute_1`.

Two of them are useful to know:

-   `reporting_period_up_to` and `report_year` are the end date and the name of the latest reporting window of the programme.
-   `source` says which template the row comes from.

## AF: aligned funding (`output/af/`)

**One row** is one funding line of a programme.

| Column | What it means |
|----|----|
| `Typeofinvestment`, `Country`, `Granteeorganization`, `ProgrammeID`, `LeadGRN`, `Startdate`, `Currentenddate`, `Covid.19related` | From the GMS |
| `donor`, `recipient_agency`, `programme_name`, `programme_start_year`, `programme_end_year` | The funding line as reported |
| `programme_total_funding_in_original_currency`, `original_currency`, `programme_total_funding_in_usd` | The total funding of the programme |
| `new_pre_existing_programme_in_relation_to_myrp_start_year` | `New` or `Pre-existing` |
| `for_new_programmes_only_…` and `for_pre_existing_programmes_only_…` | The amount in USD that goes to the same people as the multi-year programme. The first is for new programmes, the second for programmes that already existed. |
| `to_what_extent_is_the_programme_aligned_with_the_myrp_strategy` and `to_what_extent_has_there_been_coordination_between_the_myrp_and_the_programme` | The answers `No`, `Weak` or `Strong` |
| `alignment_score` | `Not aligned`, `Weakly aligned` or `Strongly aligned`. It is worked out from the two answers above. |
| `sum_total_funding` | For new programmes: the new amount. For existing programmes: the existing amount. Otherwise: both added. |
| `target_group_alignment`, `strategic_alignment_comments`, `coordination_engagement_comments`, `contribution_to_leveraging_comments`, `source_of_information` | Comments and sources, as typed |
| `file_name`, `grid`, `grantee_lead_grn`, `source_of_data` | The Excel file, the grid text, the grant reference of the lead grantee, and the origin (`Finance Aligned Funding`) |
| `table_index` and the other `please_specify_…` columns | Not for analysis |

## DCM: money passed to partners (`output/dcm/`)

**One row** is one line for a consortium partner, a sub-grantee or a grantee.

| Column | What it means |
|----|----|
| `Typeofinvestment`, `Country`, `Granteeorganization`, `ProgrammeID`, `GMGRN`, `Startdate`, `Currentenddate`, `Covid19Related` | From the GMS. Combiner finds the grant with the reference inside `GRID`. |
| `ConsortiumPartner`, `ConsortiumPartnerType` | The partner and its type |
| `LocalTransfer` | `Yes` if the partner is a national NGO, a government, a local NGO or an in-country organisation |
| `TotalAmountAllocatedToBeDiscursedToConsortiumPartner` | The amount planned for the partner. The spelling of the name is kept as it was. |
| `CumulativeExpenditureByConsortiumPartner` | The total spent by the partner |
| `CumulativeECWFundsTransferredToPartnerinUSSinceInception` | The total sent to the partner since the start, in USD |
| `DateLastUpdated` | When the line was last updated |
| `WomenLedOrganization`, `RefugeeLedOrganization`, `OrganizationOfPWD` | Is the organisation led by women, led by refugees, or an organisation of persons with disabilities? |
| `CommentsRemarks`, `WorkingWithImplementingPartners` | Comments, and whether the partner works with implementing partners |
| `SubgranteeIPName`, `SubgranteeIPType` | The sub-grantee or implementing partner and its type |
| `Source` | Which part of the template the line comes from |
| `GRID`, `FileName` | The grid text and the Excel file |

Amounts are rounded to two decimals. Money signs and thousands separators are removed.
