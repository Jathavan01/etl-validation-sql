USE WWI_Reporting;
GO

-- Runs every validation check and returns a pass/fail table.
-- Each test counts "failures": 0 means the check passed.
-- The checks compare the target (dbo.SalesReport) against the SOURCE tables,
-- not against the ETL's own logic, so a bug in the ETL can't hide itself.
-- COLLATE DATABASE_DEFAULT is needed because the two databases use different text
-- collations, and SQL Server refuses to compare text across them without it.
CREATE OR ALTER PROCEDURE etl.RunValidationTests
    AS
BEGIN
    SET NOCOUNT ON;

    -- Temp table that collects one row per test (dropped automatically at the end)
CREATE TABLE #results (
                          TestOrder INT IDENTITY(1,1),
                          TestName  VARCHAR(100),
                          Failures  INT
);

-- TEST 1: Row count reconciliation. Target count should equal source count.
INSERT INTO #results (TestName, Failures)
SELECT 'Row count matches source',
       ABS((SELECT COUNT(*) FROM WideWorldImporters.Sales.InvoiceLines)
           - (SELECT COUNT(*) FROM dbo.SalesReport));

-- TEST 2: Completeness. Source invoice lines that never reached the target.
INSERT INTO #results (TestName, Failures)
SELECT 'No source rows missing from target', COUNT(*)
FROM WideWorldImporters.Sales.InvoiceLines AS il
WHERE NOT EXISTS (SELECT 1 FROM dbo.SalesReport AS r
                  WHERE r.InvoiceLineID = il.InvoiceLineID);

-- TEST 3: Target rows that don't exist in the source (invented or leftover data).
INSERT INTO #results (TestName, Failures)
SELECT 'No unexpected rows in target', COUNT(*)
FROM dbo.SalesReport AS r
WHERE NOT EXISTS (SELECT 1 FROM WideWorldImporters.Sales.InvoiceLines AS il
                  WHERE il.InvoiceLineID = r.InvoiceLineID);

-- TEST 4: Duplicates. Each invoice line should appear in the target exactly once.
INSERT INTO #results (TestName, Failures)
SELECT 'No duplicate invoice lines', COUNT(*)
FROM (SELECT InvoiceLineID
      FROM dbo.SalesReport
      GROUP BY InvoiceLineID
      HAVING COUNT(*) > 1) AS d;

-- TEST 5: Blank text. The columns are NOT NULL, so check for empty strings instead.
INSERT INTO #results (TestName, Failures)
SELECT 'No blank names or categories', COUNT(*)
FROM dbo.SalesReport
WHERE LTRIM(RTRIM(CustomerName)) = ''
   OR LTRIM(RTRIM(CustomerCategory)) = ''
   OR LTRIM(RTRIM(StockItemName)) = '';

-- TEST 6a: Field-by-field comparison, source minus target.
-- EXCEPT returns source rows that have no identical row in the target.
INSERT INTO #results (TestName, Failures)
SELECT 'Every source row matches target (source minus target)', COUNT(*)
FROM (
         SELECT il.InvoiceLineID, il.InvoiceID, i.InvoiceDate, i.CustomerID,
                c.CustomerName COLLATE DATABASE_DEFAULT AS CustomerName,
                il.StockItemID,
                si.StockItemName COLLATE DATABASE_DEFAULT AS StockItemName,
                il.Quantity, il.UnitPrice, il.ExtendedPrice
         FROM WideWorldImporters.Sales.InvoiceLines AS il
                  JOIN WideWorldImporters.Sales.Invoices     AS i  ON i.InvoiceID = il.InvoiceID
                  JOIN WideWorldImporters.Sales.Customers    AS c  ON c.CustomerID = i.CustomerID
                  JOIN WideWorldImporters.Warehouse.StockItems AS si ON si.StockItemID = il.StockItemID
         EXCEPT
         SELECT InvoiceLineID, InvoiceID, InvoiceDate, CustomerID,
                CustomerName, StockItemID, StockItemName,
                Quantity, UnitPrice, ExtendedPrice
         FROM dbo.SalesReport
     ) AS diff;

-- TEST 6b: Same comparison in the other direction, target minus source.
-- Both directions are needed: one direction alone misses extra or altered rows.
INSERT INTO #results (TestName, Failures)
SELECT 'Every target row matches source (target minus source)', COUNT(*)
FROM (
         SELECT InvoiceLineID, InvoiceID, InvoiceDate, CustomerID,
                CustomerName, StockItemID, StockItemName,
                Quantity, UnitPrice, ExtendedPrice
         FROM dbo.SalesReport
         EXCEPT
         SELECT il.InvoiceLineID, il.InvoiceID, i.InvoiceDate, i.CustomerID,
                c.CustomerName COLLATE DATABASE_DEFAULT,
                il.StockItemID,
                si.StockItemName COLLATE DATABASE_DEFAULT,
                il.Quantity, il.UnitPrice, il.ExtendedPrice
         FROM WideWorldImporters.Sales.InvoiceLines AS il
                  JOIN WideWorldImporters.Sales.Invoices     AS i  ON i.InvoiceID = il.InvoiceID
                  JOIN WideWorldImporters.Sales.Customers    AS c  ON c.CustomerID = i.CustomerID
                  JOIN WideWorldImporters.Warehouse.StockItems AS si ON si.StockItemID = il.StockItemID
     ) AS diff;

-- TEST 7a: Transformation rule. DateKey must equal yyyymmdd of the invoice date.
-- Written with YEAR/MONTH/DAY on purpose, so it doesn't copy the ETL's CONVERT logic.
INSERT INTO #results (TestName, Failures)
SELECT 'DateKey matches invoice date', COUNT(*)
FROM dbo.SalesReport
WHERE DateKey <> YEAR(InvoiceDate) * 10000 + MONTH(InvoiceDate) * 100 + DAY(InvoiceDate);

-- TEST 7b: Transformation rule. LineTotal must equal quantity times unit price,
-- checked against the original source values.
INSERT INTO #results (TestName, Failures)
SELECT 'LineTotal equals quantity times unit price', COUNT(*)
FROM dbo.SalesReport AS r
         JOIN WideWorldImporters.Sales.InvoiceLines AS il ON il.InvoiceLineID = r.InvoiceLineID
WHERE r.LineTotal <> il.Quantity * il.UnitPrice;

-- TEST 7c: Transformation rule. CustomerCategory must match the source lookup table.
INSERT INTO #results (TestName, Failures)
SELECT 'Customer category matches source lookup', COUNT(*)
FROM dbo.SalesReport AS r
         JOIN WideWorldImporters.Sales.Customers AS c ON c.CustomerID = r.CustomerID
         JOIN WideWorldImporters.Sales.CustomerCategories AS cc
              ON cc.CustomerCategoryID = c.CustomerCategoryID
WHERE r.CustomerCategory <> cc.CustomerCategoryName COLLATE DATABASE_DEFAULT;

-- TEST 8a: Totals reconciliation on a copied column (1 = totals differ).
INSERT INTO #results (TestName, Failures)
SELECT 'Total extended price matches source',
       CASE WHEN (SELECT SUM(ExtendedPrice) FROM dbo.SalesReport)
           = (SELECT SUM(ExtendedPrice) FROM WideWorldImporters.Sales.InvoiceLines)
                THEN 0 ELSE 1 END;

-- TEST 8b: Totals reconciliation on the calculated column.
INSERT INTO #results (TestName, Failures)
SELECT 'Total line value matches source',
       CASE WHEN (SELECT SUM(LineTotal) FROM dbo.SalesReport)
           = (SELECT SUM(Quantity * UnitPrice) FROM WideWorldImporters.Sales.InvoiceLines)
                THEN 0 ELSE 1 END;

-- Result set 1: one row per test
SELECT TestOrder, TestName, Failures,
       CASE WHEN Failures = 0 THEN 'PASS' ELSE 'FAIL' END AS Result
FROM #results
ORDER BY TestOrder;

-- Result set 2: overall summary
SELECT SUM(CASE WHEN Failures = 0 THEN 1 ELSE 0 END) AS Passed,
       SUM(CASE WHEN Failures <> 0 THEN 1 ELSE 0 END) AS Failed
FROM #results;
END;
GO