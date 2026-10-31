USE WWI_Reporting;
GO

/* =====================================================================
   DEFECT SCENARIOS
   Each block follows the same pattern:
     1. Reload clean data from the source
     2. Break the loaded data in one specific way (simulating an ETL bug)
     3. Run all 12 validation tests and see which ones fail
     4. Reload clean data again, so the next block starts clean
   HOW TO RUN: highlight ONE block at a time (from its heading comment to
   its last line) and press F5. Running the whole file at once produces a
   confusing pile of result sets.
   ===================================================================== */


/* ---------- BLOCK 0: BASELINE (no defect) ----------
   Expected: all 12 tests PASS. */
EXEC etl.LoadSalesReport;
EXEC etl.RunValidationTests;


/* ---------- BLOCK 1: DROPPED ROWS ----------
   Simulates an ETL that loses rows (for example a bad join or a failed batch).
   Expected FAIL: 1 (row count), 2 (missing from target), 6 (source minus target),
                  11 and 12 (totals no longer match) */
EXEC etl.LoadSalesReport;
DELETE TOP (100) FROM dbo.SalesReport;
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data


/* ---------- BLOCK 2: DUPLICATED ROWS ----------
   The primary key normally makes duplicates impossible. Staging tables often
   have no key, so this block removes the key first to simulate that case.
   Expected FAIL: 1 (row count), 4 (duplicates), 11 and 12 (totals inflated)
   Expected PASS: 6 and 7, because EXCEPT ignores duplicate rows.
   That is why the row count and duplicate checks are needed as well. */
EXEC etl.LoadSalesReport;

-- Find the primary key's name (system-generated the first time this runs)
DECLARE @pk  SYSNAME = (SELECT name FROM sys.key_constraints
                        WHERE parent_object_id = OBJECT_ID('dbo.SalesReport')
                          AND type = 'PK');
DECLARE @sql NVARCHAR(400);

-- Build the DROP command in a variable first. EXEC cannot call functions
-- like QUOTENAME inside its parentheses, which is what caused the syntax error.
IF @pk IS NOT NULL
BEGIN
    SET @sql = N'ALTER TABLE dbo.SalesReport DROP CONSTRAINT ' + QUOTENAME(@pk);
    EXEC (@sql);
END;

-- Insert copies of the first 50 rows
INSERT INTO dbo.SalesReport (
    InvoiceLineID, InvoiceID, InvoiceDate, DateKey, CustomerID, CustomerName,
    CustomerCategory, StockItemID, StockItemName, Quantity, UnitPrice,
    LineTotal, ExtendedPrice)
SELECT TOP (50)
    InvoiceLineID, InvoiceID, InvoiceDate, DateKey, CustomerID, CustomerName,
    CustomerCategory, StockItemID, StockItemName, Quantity, UnitPrice,
    LineTotal, ExtendedPrice
FROM dbo.SalesReport
ORDER BY InvoiceLineID;

EXEC etl.RunValidationTests;

-- Restore: reload clean data, then put the primary key back
EXEC etl.LoadSalesReport;
ALTER TABLE dbo.SalesReport ADD CONSTRAINT PK_SalesReport PRIMARY KEY (InvoiceLineID);

/* ---------- BLOCK 3: WRONG CALCULATION ----------
   Simulates a formula bug: tax applied to some line totals by mistake.
   Expected FAIL: 9 (LineTotal rule), 12 (total line value) */
EXEC etl.LoadSalesReport;
UPDATE dbo.SalesReport
SET LineTotal = LineTotal * 1.15
WHERE InvoiceLineID % 100 = 0;
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data


/* ---------- BLOCK 4: BAD DATE TRANSFORMATION ----------
   Simulates an off-by-one error when converting dates to the yyyymmdd key.
   Expected FAIL: 8 (DateKey) only */
EXEC etl.LoadSalesReport;
UPDATE dbo.SalesReport
SET DateKey = DateKey + 1
WHERE InvoiceLineID % 50 = 0;
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data


/* ---------- BLOCK 5: TRUNCATED TEXT ----------
   Simulates a target column that is too short, cutting names off at 10 characters.
   Expected FAIL: 6 and 7 (the field-by-field comparisons) */
EXEC etl.LoadSalesReport;
UPDATE dbo.SalesReport
SET CustomerName = LEFT(CustomerName, 10)
WHERE InvoiceLineID % 100 = 0
  AND LEN(CustomerName) > 10;
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data


/* ---------- BLOCK 6: FAILED LOOKUP ----------
   Simulates a lookup that falls back to a default value when it can't find a match.
   Expected FAIL: 10 (customer category) only */
EXEC etl.LoadSalesReport;
UPDATE dbo.SalesReport
SET CustomerCategory = 'Unknown'
WHERE InvoiceLineID % 100 = 0;
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data


/* ---------- BLOCK 7: EXTRA ROW NOT IN THE SOURCE ----------
   Simulates leftover or invented data in the target. The customer ID -1 does not
   exist in the source, so only the checks that compare against the source catch it.
   Expected FAIL: 1 (row count), 3 (unexpected rows), 7 (target minus source),
                  11 and 12 (totals) */
EXEC etl.LoadSalesReport;
INSERT INTO dbo.SalesReport (
    InvoiceLineID, InvoiceID, InvoiceDate, DateKey, CustomerID, CustomerName,
    CustomerCategory, StockItemID, StockItemName, Quantity, UnitPrice,
    LineTotal, ExtendedPrice)
VALUES (-1, -1, '2016-01-01', 20160101, -1, 'Ghost Customer',
        'Test', 1, 'Ghost Item', 1, 10.00, 10.00, 10.00);
EXEC etl.RunValidationTests;
EXEC etl.LoadSalesReport;   -- restore clean data