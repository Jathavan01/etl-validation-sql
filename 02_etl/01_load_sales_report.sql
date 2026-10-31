USE WWI_Reporting;
GO

-- Reloads the whole reporting table from the source database.
-- Truncate-and-reload means running it twice never creates duplicates.
CREATE OR ALTER PROCEDURE etl.LoadSalesReport
    AS
BEGIN
    SET NOCOUNT ON;

    -- Empty the target first
TRUNCATE TABLE dbo.SalesReport;

-- Extract from the source tables, apply the transformations, and load into the target
INSERT INTO dbo.SalesReport (
    InvoiceLineID, InvoiceID, InvoiceDate, DateKey,
    CustomerID, CustomerName, CustomerCategory,
    StockItemID, StockItemName,
    Quantity, UnitPrice, LineTotal, ExtendedPrice
)
SELECT
    il.InvoiceLineID,
    il.InvoiceID,
    i.InvoiceDate,
    -- Transformation 1: date as a number like 20160531 (style 112 = yyyymmdd)
    CONVERT(INT, CONVERT(CHAR(8), i.InvoiceDate, 112)),
    i.CustomerID,
    c.CustomerName,
    -- Transformation 2: category name looked up from a second table
    cc.CustomerCategoryName,
    il.StockItemID,
    si.StockItemName,
    il.Quantity,
    il.UnitPrice,
    -- Transformation 3: calculated line total
    il.Quantity * il.UnitPrice,
    il.ExtendedPrice
FROM WideWorldImporters.Sales.InvoiceLines        AS il
         JOIN WideWorldImporters.Sales.Invoices            AS i  ON i.InvoiceID = il.InvoiceID
         JOIN WideWorldImporters.Sales.Customers           AS c  ON c.CustomerID = i.CustomerID
         JOIN WideWorldImporters.Sales.CustomerCategories  AS cc ON cc.CustomerCategoryID = c.CustomerCategoryID
         JOIN WideWorldImporters.Warehouse.StockItems      AS si ON si.StockItemID = il.StockItemID;
END;
GO