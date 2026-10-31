-- Creates a separate reporting database so the source stays untouched.
-- Keeping source and target apart is what makes this a real source-to-target test.
IF DB_ID('WWI_Reporting') IS NULL
    CREATE DATABASE WWI_Reporting;
GO

USE WWI_Reporting;
GO

-- Schema that will hold the ETL procedures
IF SCHEMA_ID('etl') IS NULL
    EXEC('CREATE SCHEMA etl');
GO

-- Drop and recreate the table so this script can be re-run safely
IF OBJECT_ID('dbo.SalesReport') IS NOT NULL
DROP TABLE dbo.SalesReport;
GO

-- Flattened reporting table: one row per invoice line, with customer and product details
CREATE TABLE dbo.SalesReport (
                                 InvoiceLineID     INT           NOT NULL PRIMARY KEY,  -- one row per source invoice line
                                 InvoiceID         INT           NOT NULL,
                                 InvoiceDate       DATE          NOT NULL,
                                 DateKey           INT           NOT NULL,              -- derived: InvoiceDate as yyyymmdd
                                 CustomerID        INT           NOT NULL,
                                 CustomerName      NVARCHAR(100) NOT NULL,
                                 CustomerCategory  NVARCHAR(50)  NOT NULL,              -- looked up from CustomerCategories
                                 StockItemID       INT           NOT NULL,
                                 StockItemName     NVARCHAR(100) NOT NULL,
                                 Quantity          INT           NOT NULL,
                                 UnitPrice         DECIMAL(18,2) NOT NULL,
                                 LineTotal         DECIMAL(18,2) NOT NULL,              -- derived: Quantity * UnitPrice (before tax)
                                 ExtendedPrice     DECIMAL(18,2) NOT NULL,              -- copied from source; as far as I know this includes tax, so it won't equal LineTotal
                                 LoadedAt          DATETIME2     NOT NULL DEFAULT SYSDATETIME()  -- audit column: when the row was loaded
);
GO