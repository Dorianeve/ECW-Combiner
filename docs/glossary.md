# Glossary

Short explanations of the words used in this project. They are in alphabetical order.

| Word | What it means |
|----|----|
| **AF** | Aligned funding. One of the four combiners. It lists other funding that supports the same programme. |
| **Annual** | One of the two "exercises". See **Exercise**. |
| **ARR** | The annual results report. In names like `ARR25` the number is the last two digits of the year. |
| **Archived workbook** | An old copy of an Excel file. Its name starts with `ARCHIVED`. Combiner ignores these files. |
| **Attention point** | A line in the run report that you should look at. |
| **Cache** | A saved copy of what Combiner read from the Excel files. It lives in the `cache` folder. It makes the next run fast. |
| **Combiner** | A final result table, for example the CR combiner. |
| **Config / settings file** | The file `config/config.yml`. It tells Combiner where your files are and how to work. |
| **CR** | Children reached. One of the four combiners. |
| **Cumulative** | One of the two "exercises". See **Exercise**. |
| **Data collection issue** | A problem inside an Excel file, for example rows typed below the table. Only the owner of the file can fix it. |
| **DCM** | One of the four combiners. It lists money passed on to partners and sub-grantees. |
| **Diagnostics report** | The report that Combiner writes after every run. It shows what changed and what went wrong. |
| **Exercise** | A label in the results that says if a row belongs to the **Annual** or the **Cumulative** report of a year, for example `ARR25 Annual`. |
| **Flow** | The set of steps that makes one combiner. There are four flows: CR, PR, AF and DCM. |
| **GMS** | The grants management system. It holds the list of grants, their dates and their partners. Combiner downloads this list. |
| **GRID** | A piece of text in the Excel files that identifies a grant. It has parts separated by the sign `\|`. The 5th part is the grant reference of the lead grantee. |
| **GRN** | Grant reference number. |
| **Lead grantee** | The main organisation of a programme. |
| **Lookup table** | A small table of names. The PR combiner uses it to match column names in different templates. They live in the `reference` folder. |
| **M&E** | Monitoring and evaluation. |
| **PR** | Programme results. One of the four combiners. |
| **Programme** | A group of grants that work together. It has a `ProgrammeID`. |
| **Reporting window** | A period for which a report is due, for example "Window 1". |
| **Row trace** | A list of how many rows there are after each step of a flow. It helps you see where rows are lost. |
| **Table (Excel table)** | A named table inside an Excel file (made with Insert → Table). Combiner reads these tables, not loose cells. |
| **Template** | The Excel file that grantees fill in. There are different kinds, for example a results template. |
| **Workbook** | An Excel file. |
| **Worker** | One copy of R that works on a part of the job. Several workers run at the same time to save time. |
