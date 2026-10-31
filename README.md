# ETL Validation Suite (T-SQL)

A small T-SQL ETL process built on Microsoft's WideWorldImporters sample database, with a suite of 12 SQL validation checks that compare the loaded data against the source. Seven defects were then injected on purpose to confirm each one is caught by the checks that should catch it.

**What this is:** a learning project for ETL and data testing. I built a small ETL so I could see how data defects occur and test for them. It is not a production pipeline.

## How it works

- **Source:** `WideWorldImporters` (Sales and Warehouse tables, left untouched)
- **Target:** `WWI_Reporting.dbo.SalesReport`, a flattened table with one row per invoice line (228,265 rows)
- **Extract:** invoice lines joined to invoices, customers, customer categories, and stock items
- **Transform:** `DateKey` (the invoice date as yyyymmdd), `CustomerCategory` (looked up from a second table), and `LineTotal` (quantity times unit price)
- **Load:** `etl.LoadSalesReport` truncates and reloads the target, so running it twice never creates duplicates

## The 12 validation checks

`etl.RunValidationTests` returns one PASS or FAIL row per check, plus a summary.

| # | Check | Type |
|---|---|---|
| 1 | Row count matches source | Reconciliation |
| 2 | No source rows missing from target | Completeness |
| 3 | No unexpected rows in target | Completeness |
| 4 | No duplicate invoice lines | Duplicates |
| 5 | No blank names or categories | Data quality |
| 6 | Every source row matches target (EXCEPT, source minus target) | Field-by-field |
| 7 | Every target row matches source (EXCEPT, target minus source) | Field-by-field |
| 8 | DateKey matches the invoice date | Transformation rule |
| 9 | LineTotal equals quantity times unit price | Transformation rule |
| 10 | Customer category matches the source lookup | Transformation rule |
| 11 | Total extended price matches source | Totals |
| 12 | Total line value matches source | Totals |

The checks compare against the source tables, not against the ETL's own logic, so a bug in the ETL can't hide itself.

## Defect injection results

Each scenario reloads clean data, breaks the target in one way, and runs all 12 checks. All results below were observed, and they matched what I predicted before running.

| Defect | What was done | Checks that failed | Passed / Failed |
|---|---|---|---|
| Dropped rows | Deleted 100 rows | 1, 2, 6 (100 each), 11, 12 | 7 / 5 |
| Duplicated rows | Added 50 copies (primary key removed first) | 1, 4 (50 each), 11, 12 | 8 / 4 |
| Wrong calculation | LineTotal x 1.15 on every 100th row | 9 (2,282), 12 | 10 / 2 |
| Bad date key | DateKey + 1 on every 50th row | 8 (4,565) | 11 / 1 |
| Truncated text | CustomerName cut to 10 characters on every 100th row | 6, 7 (2,159 each) | 10 / 2 |
| Failed lookup | Category set to 'Unknown' on every 100th row | 10 (2,282) | 11 / 1 |
| Extra row | One row with a customer ID not in the source | 1, 3, 7, 11, 12 | 7 / 5 |

## What the results show

- **`EXCEPT` ignores duplicates.** With 50 duplicated rows, checks 6 and 7 still passed. Only the row count (1), the duplicate check (4), and the totals (11, 12) caught it.
- **Both directions are needed.** An extra row in the target passes check 6 (nothing is missing) and is caught only by check 7 and the unexpected-rows check.
- **Cheap checks can miss real defects.** Truncated names passed the blank-value check (5) and were caught only by the full field comparison.
- **Aggregate checks aren't enough alone.** Totals caught the calculation error, but the row-level rule (9) is what pinpoints which rows are wrong.

## Project structure

```
01_setup/     creates the WWI_Reporting database, etl schema, and SalesReport table
02_etl/       etl.LoadSalesReport (extract, transform, load)
03_tests/     etl.RunValidationTests (the 12 checks)
04_defects/   seven defect scenarios, run one block at a time
```

## How to run

1. Install SQL Server Developer Edition and SSMS, and restore `WideWorldImporters-Full.bak` from [microsoft/sql-server-samples](https://github.com/microsoft/sql-server-samples)
2. Run the scripts in order: `01_setup`, `02_etl`, `03_tests`
3. Load and test:
   ```sql
   USE WWI_Reporting;
   EXEC etl.LoadSalesReport;
   EXEC etl.RunValidationTests;
   ```
   All 12 checks should PASS on clean data.
4. In `04_defects`, highlight one block at a time and press F5

## Limitations

- Defects are simulated by changing the loaded data, not by rewriting the ETL
- Truncate-and-reload only; there is no incremental load or history handling
- Single local SQL Server instance, with no scheduler or ETL tool

## Tech stack

SQL Server, T-SQL, SSMS