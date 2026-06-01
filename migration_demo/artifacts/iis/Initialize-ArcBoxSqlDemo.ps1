param(
    [Parameter(Mandatory = $true)][PSCredential]$WebSqlCredential
)

$ErrorActionPreference = 'Stop'

function Invoke-ArcBoxSql {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [int]$QueryTimeout = 180
    )

    Invoke-Sqlcmd -Query $Query -TrustServerCertificate -QueryTimeout $QueryTimeout
}

$sqlService = Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue
if (-not $sqlService) {
    throw 'SQL Server default instance MSSQLSERVER was not found on this VM.'
}
if ($sqlService.Status -ne 'Running') {
    Write-Host 'Waiting for SQL Server default instance MSSQLSERVER to start'
    if ($sqlService.Status -eq 'Stopped') {
        Start-Service -Name MSSQLSERVER
    }
    $sqlService.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(5))
}

if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module -Name SqlServer -AllowClobber -Force -Scope AllUsers | Out-Null
}
Import-Module SqlServer -Force

Write-Host 'Ensuring SQL Server is in mixed-mode authentication'
$loginModeKey = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQLServer'
if (-not (Test-Path $loginModeKey)) {
    $loginModeKey = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'MSSQL\d+\.MSSQLSERVER$' } |
        Select-Object -First 1).PSPath + '\MSSQLServer'
}
if ($loginModeKey -and (Test-Path $loginModeKey)) {
    $current = (Get-ItemProperty -Path $loginModeKey -Name LoginMode -ErrorAction SilentlyContinue).LoginMode
    if ($current -ne 2) {
        Set-ItemProperty -Path $loginModeKey -Name LoginMode -Value 2
        Restart-Service -Name MSSQLSERVER -Force
        Start-Sleep -Seconds 10
    }
}

$tsql = @'
USE master;
IF DB_ID(N'ArcBoxDemo') IS NULL
    CREATE DATABASE ArcBoxDemo;
'@
Invoke-ArcBoxSql -Query $tsql

$tsql = @'
USE ArcBoxDemo;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'SalesLT')
    EXEC(N'CREATE SCHEMA SalesLT AUTHORIZATION dbo');

IF OBJECT_ID(N'dbo.BuildVersion', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BuildVersion (
        SystemInformationID tinyint IDENTITY(1,1) NOT NULL CONSTRAINT PK_BuildVersion_SystemInformationID PRIMARY KEY,
        [Database Version] nvarchar(25) NOT NULL,
        VersionDate datetime NOT NULL,
        ModifiedDate datetime NOT NULL CONSTRAINT DF_BuildVersion_ModifiedDate DEFAULT (GETDATE())
    );
END
IF NOT EXISTS (SELECT 1 FROM dbo.BuildVersion WHERE [Database Version] = N'AdventureWorksLT ArcBox')
    INSERT INTO dbo.BuildVersion ([Database Version], VersionDate, ModifiedDate)
    VALUES (N'AdventureWorksLT ArcBox', CONVERT(datetime, '2024-01-01', 120), GETDATE());

IF OBJECT_ID(N'dbo.ErrorLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ErrorLog (
        ErrorLogID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ErrorLog_ErrorLogID PRIMARY KEY,
        ErrorTime datetime NOT NULL CONSTRAINT DF_ErrorLog_ErrorTime DEFAULT (GETDATE()),
        UserName nvarchar(128) NOT NULL,
        ErrorNumber int NOT NULL,
        ErrorSeverity int NULL,
        ErrorState int NULL,
        ErrorProcedure nvarchar(126) NULL,
        ErrorLine int NULL,
        ErrorMessage nvarchar(4000) NOT NULL
    );
END

IF OBJECT_ID(N'SalesLT.ProductCategory', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.ProductCategory (
        ProductCategoryID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductCategory_ProductCategoryID PRIMARY KEY,
        ParentProductCategoryID int NULL,
        Name nvarchar(50) NOT NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_ProductCategory_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_ProductCategory_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_ProductCategory_rowguid ON SalesLT.ProductCategory(rowguid);
    CREATE INDEX IX_ProductCategory_ParentProductCategoryID ON SalesLT.ProductCategory(ParentProductCategoryID);
END

IF OBJECT_ID(N'SalesLT.ProductModel', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.ProductModel (
        ProductModelID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductModel_ProductModelID PRIMARY KEY,
        Name nvarchar(50) NOT NULL,
        CatalogDescription nvarchar(max) NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_ProductModel_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_ProductModel_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_ProductModel_rowguid ON SalesLT.ProductModel(rowguid);
END

IF OBJECT_ID(N'SalesLT.ProductDescription', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.ProductDescription (
        ProductDescriptionID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProductDescription_ProductDescriptionID PRIMARY KEY,
        Description nvarchar(400) NOT NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_ProductDescription_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_ProductDescription_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_ProductDescription_rowguid ON SalesLT.ProductDescription(rowguid);
END

IF OBJECT_ID(N'SalesLT.ProductModelProductDescription', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.ProductModelProductDescription (
        ProductModelID int NOT NULL,
        ProductDescriptionID int NOT NULL,
        Culture nchar(6) NOT NULL CONSTRAINT DF_ProductModelProductDescription_Culture DEFAULT (N'en'),
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_ProductModelProductDescription_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_ProductModelProductDescription_ModifiedDate DEFAULT (GETDATE()),
        CONSTRAINT PK_ProductModelProductDescription_ProductModelID_ProductDescriptionID_Culture PRIMARY KEY (ProductModelID, ProductDescriptionID, Culture)
    );
    CREATE UNIQUE INDEX AK_ProductModelProductDescription_rowguid ON SalesLT.ProductModelProductDescription(rowguid);
END

IF OBJECT_ID(N'SalesLT.Product', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.Product (
        ProductID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Product_ProductID PRIMARY KEY,
        Name nvarchar(50) NOT NULL,
        ProductNumber nvarchar(25) NOT NULL,
        Color nvarchar(15) NULL,
        StandardCost money NOT NULL,
        ListPrice money NOT NULL,
        Size nvarchar(5) NULL,
        Weight decimal(8,2) NULL,
        ProductCategoryID int NULL,
        ProductModelID int NULL,
        SellStartDate datetime NOT NULL CONSTRAINT DF_Product_SellStartDate DEFAULT (GETDATE()),
        SellEndDate datetime NULL,
        DiscontinuedDate datetime NULL,
        ThumbNailPhoto varbinary(max) NULL,
        ThumbnailPhotoFileName nvarchar(50) NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_Product_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_Product_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_Product_ProductNumber ON SalesLT.Product(ProductNumber);
    CREATE UNIQUE INDEX AK_Product_rowguid ON SalesLT.Product(rowguid);
    CREATE INDEX IX_Product_ProductCategoryID ON SalesLT.Product(ProductCategoryID);
    CREATE INDEX IX_Product_ProductModelID ON SalesLT.Product(ProductModelID);
END

IF OBJECT_ID(N'SalesLT.Address', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.Address (
        AddressID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Address_AddressID PRIMARY KEY,
        AddressLine1 nvarchar(60) NOT NULL,
        AddressLine2 nvarchar(60) NULL,
        City nvarchar(30) NOT NULL,
        StateProvince nvarchar(50) NOT NULL,
        CountryRegion nvarchar(50) NOT NULL,
        PostalCode nvarchar(15) NOT NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_Address_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_Address_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_Address_rowguid ON SalesLT.Address(rowguid);
    CREATE INDEX IX_Address_StateProvince ON SalesLT.Address(StateProvince);
END

IF OBJECT_ID(N'SalesLT.Customer', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.Customer (
        CustomerID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Customer_CustomerID PRIMARY KEY,
        NameStyle bit NOT NULL CONSTRAINT DF_Customer_NameStyle DEFAULT (0),
        Title nvarchar(8) NULL,
        FirstName nvarchar(50) NOT NULL,
        MiddleName nvarchar(50) NULL,
        LastName nvarchar(50) NOT NULL,
        Suffix nvarchar(10) NULL,
        CompanyName nvarchar(128) NULL,
        SalesPerson nvarchar(256) NULL,
        EmailAddress nvarchar(50) NULL,
        Phone nvarchar(25) NULL,
        PasswordHash varchar(128) NOT NULL CONSTRAINT DF_Customer_PasswordHash DEFAULT ('PasswordHash'),
        PasswordSalt varchar(10) NOT NULL CONSTRAINT DF_Customer_PasswordSalt DEFAULT ('Salt'),
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_Customer_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_Customer_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_Customer_rowguid ON SalesLT.Customer(rowguid);
    CREATE INDEX IX_Customer_EmailAddress ON SalesLT.Customer(EmailAddress);
END

IF OBJECT_ID(N'SalesLT.CustomerAddress', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.CustomerAddress (
        CustomerID int NOT NULL,
        AddressID int NOT NULL,
        AddressType nvarchar(50) NOT NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_CustomerAddress_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_CustomerAddress_ModifiedDate DEFAULT (GETDATE()),
        CONSTRAINT PK_CustomerAddress_CustomerID_AddressID PRIMARY KEY (CustomerID, AddressID)
    );
    CREATE UNIQUE INDEX AK_CustomerAddress_rowguid ON SalesLT.CustomerAddress(rowguid);
END

IF OBJECT_ID(N'SalesLT.SalesOrderHeader', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.SalesOrderHeader (
        SalesOrderID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalesOrderHeader_SalesOrderID PRIMARY KEY,
        RevisionNumber tinyint NOT NULL CONSTRAINT DF_SalesOrderHeader_RevisionNumber DEFAULT (0),
        OrderDate datetime NOT NULL CONSTRAINT DF_SalesOrderHeader_OrderDate DEFAULT (GETDATE()),
        DueDate datetime NOT NULL CONSTRAINT DF_SalesOrderHeader_DueDate DEFAULT (DATEADD(day, 7, GETDATE())),
        ShipDate datetime NULL,
        Status tinyint NOT NULL CONSTRAINT DF_SalesOrderHeader_Status DEFAULT (1),
        OnlineOrderFlag bit NOT NULL CONSTRAINT DF_SalesOrderHeader_OnlineOrderFlag DEFAULT (1),
        SalesOrderNumber AS ISNULL(N'SO' + CONVERT(nvarchar(23), SalesOrderID), N'*** ERROR ***'),
        PurchaseOrderNumber nvarchar(25) NULL,
        AccountNumber nvarchar(15) NULL,
        CustomerID int NOT NULL,
        ShipToAddressID int NULL,
        BillToAddressID int NULL,
        ShipMethod nvarchar(50) NOT NULL CONSTRAINT DF_SalesOrderHeader_ShipMethod DEFAULT (N'CARGO TRANSPORT 5'),
        CreditCardApprovalCode varchar(15) NULL,
        SubTotal money NOT NULL CONSTRAINT DF_SalesOrderHeader_SubTotal DEFAULT (0.00),
        TaxAmt money NOT NULL CONSTRAINT DF_SalesOrderHeader_TaxAmt DEFAULT (0.00),
        Freight money NOT NULL CONSTRAINT DF_SalesOrderHeader_Freight DEFAULT (0.00),
        TotalDue money NOT NULL CONSTRAINT DF_SalesOrderHeader_TotalDue DEFAULT (0.00),
        Comment nvarchar(max) NULL,
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_SalesOrderHeader_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_SalesOrderHeader_ModifiedDate DEFAULT (GETDATE())
    );
    CREATE UNIQUE INDEX AK_SalesOrderHeader_rowguid ON SalesLT.SalesOrderHeader(rowguid);
    CREATE INDEX IX_SalesOrderHeader_CustomerID ON SalesLT.SalesOrderHeader(CustomerID);
END

IF OBJECT_ID(N'SalesLT.SalesOrderDetail', N'U') IS NULL
BEGIN
    CREATE TABLE SalesLT.SalesOrderDetail (
        SalesOrderID int NOT NULL,
        SalesOrderDetailID int IDENTITY(1,1) NOT NULL,
        OrderQty smallint NOT NULL,
        ProductID int NOT NULL,
        UnitPrice money NOT NULL,
        UnitPriceDiscount money NOT NULL CONSTRAINT DF_SalesOrderDetail_UnitPriceDiscount DEFAULT (0.00),
        LineTotal AS ISNULL(UnitPrice * ((1.0) - UnitPriceDiscount) * OrderQty, 0.0),
        rowguid uniqueidentifier NOT NULL CONSTRAINT DF_SalesOrderDetail_rowguid DEFAULT (NEWID()),
        ModifiedDate datetime NOT NULL CONSTRAINT DF_SalesOrderDetail_ModifiedDate DEFAULT (GETDATE()),
        CONSTRAINT PK_SalesOrderDetail_SalesOrderID_SalesOrderDetailID PRIMARY KEY (SalesOrderID, SalesOrderDetailID)
    );
    CREATE UNIQUE INDEX AK_SalesOrderDetail_rowguid ON SalesLT.SalesOrderDetail(rowguid);
    CREATE INDEX IX_SalesOrderDetail_ProductID ON SalesLT.SalesOrderDetail(ProductID);
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ProductCategory_ProductCategory_ParentProductCategoryID')
    ALTER TABLE SalesLT.ProductCategory WITH CHECK ADD CONSTRAINT FK_ProductCategory_ProductCategory_ParentProductCategoryID FOREIGN KEY (ParentProductCategoryID) REFERENCES SalesLT.ProductCategory(ProductCategoryID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Product_ProductCategory_ProductCategoryID')
    ALTER TABLE SalesLT.Product WITH CHECK ADD CONSTRAINT FK_Product_ProductCategory_ProductCategoryID FOREIGN KEY (ProductCategoryID) REFERENCES SalesLT.ProductCategory(ProductCategoryID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Product_ProductModel_ProductModelID')
    ALTER TABLE SalesLT.Product WITH CHECK ADD CONSTRAINT FK_Product_ProductModel_ProductModelID FOREIGN KEY (ProductModelID) REFERENCES SalesLT.ProductModel(ProductModelID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ProductModelProductDescription_ProductModel_ProductModelID')
    ALTER TABLE SalesLT.ProductModelProductDescription WITH CHECK ADD CONSTRAINT FK_ProductModelProductDescription_ProductModel_ProductModelID FOREIGN KEY (ProductModelID) REFERENCES SalesLT.ProductModel(ProductModelID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ProductModelProductDescription_ProductDescription_ProductDescriptionID')
    ALTER TABLE SalesLT.ProductModelProductDescription WITH CHECK ADD CONSTRAINT FK_ProductModelProductDescription_ProductDescription_ProductDescriptionID FOREIGN KEY (ProductDescriptionID) REFERENCES SalesLT.ProductDescription(ProductDescriptionID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CustomerAddress_Customer_CustomerID')
    ALTER TABLE SalesLT.CustomerAddress WITH CHECK ADD CONSTRAINT FK_CustomerAddress_Customer_CustomerID FOREIGN KEY (CustomerID) REFERENCES SalesLT.Customer(CustomerID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_CustomerAddress_Address_AddressID')
    ALTER TABLE SalesLT.CustomerAddress WITH CHECK ADD CONSTRAINT FK_CustomerAddress_Address_AddressID FOREIGN KEY (AddressID) REFERENCES SalesLT.Address(AddressID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SalesOrderHeader_Customer_CustomerID')
    ALTER TABLE SalesLT.SalesOrderHeader WITH CHECK ADD CONSTRAINT FK_SalesOrderHeader_Customer_CustomerID FOREIGN KEY (CustomerID) REFERENCES SalesLT.Customer(CustomerID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SalesOrderHeader_Address_BillToAddressID')
    ALTER TABLE SalesLT.SalesOrderHeader WITH CHECK ADD CONSTRAINT FK_SalesOrderHeader_Address_BillToAddressID FOREIGN KEY (BillToAddressID) REFERENCES SalesLT.Address(AddressID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SalesOrderHeader_Address_ShipToAddressID')
    ALTER TABLE SalesLT.SalesOrderHeader WITH CHECK ADD CONSTRAINT FK_SalesOrderHeader_Address_ShipToAddressID FOREIGN KEY (ShipToAddressID) REFERENCES SalesLT.Address(AddressID);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SalesOrderDetail_SalesOrderHeader_SalesOrderID')
    ALTER TABLE SalesLT.SalesOrderDetail WITH CHECK ADD CONSTRAINT FK_SalesOrderDetail_SalesOrderHeader_SalesOrderID FOREIGN KEY (SalesOrderID) REFERENCES SalesLT.SalesOrderHeader(SalesOrderID) ON DELETE CASCADE;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_SalesOrderDetail_Product_ProductID')
    ALTER TABLE SalesLT.SalesOrderDetail WITH CHECK ADD CONSTRAINT FK_SalesOrderDetail_Product_ProductID FOREIGN KEY (ProductID) REFERENCES SalesLT.Product(ProductID);
'@
Invoke-ArcBoxSql -Query $tsql

$tsql = @'
USE ArcBoxDemo;
GO
CREATE OR ALTER PROCEDURE dbo.uspPrintError
AS
BEGIN
    SELECT ERROR_NUMBER() AS ErrorNumber,
           ERROR_SEVERITY() AS ErrorSeverity,
           ERROR_STATE() AS ErrorState,
           ERROR_PROCEDURE() AS ErrorProcedure,
           ERROR_LINE() AS ErrorLine,
           ERROR_MESSAGE() AS ErrorMessage;
END;
GO
CREATE OR ALTER PROCEDURE dbo.uspLogError
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.ErrorLog (UserName, ErrorNumber, ErrorSeverity, ErrorState, ErrorProcedure, ErrorLine, ErrorMessage)
    VALUES (SUSER_SNAME(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE());
END;
GO
CREATE OR ALTER FUNCTION dbo.ufnGetCustomerInformation(@CustomerID int)
RETURNS TABLE
AS
RETURN (
    SELECT CustomerID, FirstName, LastName, CompanyName, EmailAddress, Phone
    FROM SalesLT.Customer
    WHERE CustomerID = @CustomerID
);
GO
CREATE OR ALTER VIEW SalesLT.vGetAllCategories
AS
WITH CategoryCTE (ParentProductCategoryID, ProductCategoryID, Name) AS (
    SELECT ParentProductCategoryID, ProductCategoryID, Name
    FROM SalesLT.ProductCategory
    WHERE ParentProductCategoryID IS NULL
    UNION ALL
    SELECT child.ParentProductCategoryID, child.ProductCategoryID, child.Name
    FROM SalesLT.ProductCategory AS child
    INNER JOIN CategoryCTE AS parent ON parent.ProductCategoryID = child.ParentProductCategoryID
)
SELECT parent.Name AS ParentProductCategoryName,
       child.Name AS ProductCategoryName,
       child.ProductCategoryID
FROM CategoryCTE AS child
LEFT JOIN SalesLT.ProductCategory AS parent ON parent.ProductCategoryID = child.ParentProductCategoryID;
GO
CREATE OR ALTER VIEW SalesLT.vProductAndDescription
AS
SELECT product.ProductID,
       product.Name,
       model.Name AS ProductModel,
       mapping.Culture,
       description.Description
FROM SalesLT.Product AS product
INNER JOIN SalesLT.ProductModel AS model ON product.ProductModelID = model.ProductModelID
INNER JOIN SalesLT.ProductModelProductDescription AS mapping ON model.ProductModelID = mapping.ProductModelID
INNER JOIN SalesLT.ProductDescription AS description ON mapping.ProductDescriptionID = description.ProductDescriptionID;
GO
CREATE OR ALTER VIEW SalesLT.vProductModelCatalogDescription
AS
SELECT ProductModelID,
       Name,
       CatalogDescription AS Summary
FROM SalesLT.ProductModel;
GO
CREATE OR ALTER VIEW SalesLT.vStorefrontCatalog
AS
SELECT product.ProductID,
       product.Name,
       product.ProductNumber,
       product.Color,
       product.Size,
       product.Weight,
       product.StandardCost,
       product.ListPrice,
       category.Name AS CategoryName,
       model.Name AS ProductModel,
       description.Description
FROM SalesLT.Product AS product
LEFT JOIN SalesLT.ProductCategory AS category ON category.ProductCategoryID = product.ProductCategoryID
LEFT JOIN SalesLT.ProductModel AS model ON model.ProductModelID = product.ProductModelID
OUTER APPLY (
    SELECT TOP (1) productDescription.Description
    FROM SalesLT.ProductModelProductDescription AS mapping
    INNER JOIN SalesLT.ProductDescription AS productDescription ON productDescription.ProductDescriptionID = mapping.ProductDescriptionID
    WHERE mapping.ProductModelID = product.ProductModelID
    ORDER BY CASE WHEN mapping.Culture = N'en' THEN 0 ELSE 1 END, mapping.Culture
) AS description;
GO
CREATE OR ALTER TRIGGER SalesLT.iduSalesOrderDetail ON SalesLT.SalesOrderDetail
AFTER INSERT, DELETE, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH ChangedOrders AS (
        SELECT SalesOrderID FROM inserted
        UNION
        SELECT SalesOrderID FROM deleted
    ), OrderTotals AS (
        SELECT SalesOrderID, SUM(LineTotal) AS SubTotal
        FROM SalesLT.SalesOrderDetail
        WHERE SalesOrderID IN (SELECT SalesOrderID FROM ChangedOrders)
        GROUP BY SalesOrderID
    )
    UPDATE header
    SET SubTotal = ISNULL(totals.SubTotal, 0.00),
        TaxAmt = ROUND(ISNULL(totals.SubTotal, 0.00) * 0.0825, 4),
        Freight = ROUND(ISNULL(totals.SubTotal, 0.00) * 0.0200, 4),
        TotalDue = ROUND(ISNULL(totals.SubTotal, 0.00) * 1.1025, 4),
        ModifiedDate = GETDATE()
    FROM SalesLT.SalesOrderHeader AS header
    LEFT JOIN OrderTotals AS totals ON totals.SalesOrderID = header.SalesOrderID
    WHERE header.SalesOrderID IN (SELECT SalesOrderID FROM ChangedOrders);
END;
GO
'@
Invoke-ArcBoxSql -Query $tsql

$tsql = @'
USE ArcBoxDemo;
SET NOCOUNT ON;

DECLARE @Bikes int, @Components int, @Clothing int, @RoadBikes int, @MountainBikes int, @TouringBikes int, @Helmets int, @Jerseys int, @Saddles int;

IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Bikes' AND ParentProductCategoryID IS NULL)
    INSERT INTO SalesLT.ProductCategory (Name) VALUES (N'Bikes');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Components' AND ParentProductCategoryID IS NULL)
    INSERT INTO SalesLT.ProductCategory (Name) VALUES (N'Components');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Clothing' AND ParentProductCategoryID IS NULL)
    INSERT INTO SalesLT.ProductCategory (Name) VALUES (N'Clothing');

SELECT @Bikes = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Bikes' AND ParentProductCategoryID IS NULL;
SELECT @Components = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Components' AND ParentProductCategoryID IS NULL;
SELECT @Clothing = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Clothing' AND ParentProductCategoryID IS NULL;

IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Road Bikes' AND ParentProductCategoryID = @Bikes)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Bikes, N'Road Bikes');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Mountain Bikes' AND ParentProductCategoryID = @Bikes)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Bikes, N'Mountain Bikes');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Touring Bikes' AND ParentProductCategoryID = @Bikes)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Bikes, N'Touring Bikes');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Helmets' AND ParentProductCategoryID = @Clothing)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Clothing, N'Helmets');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Jerseys' AND ParentProductCategoryID = @Clothing)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Clothing, N'Jerseys');
IF NOT EXISTS (SELECT 1 FROM SalesLT.ProductCategory WHERE Name = N'Saddles' AND ParentProductCategoryID = @Components)
    INSERT INTO SalesLT.ProductCategory (ParentProductCategoryID, Name) VALUES (@Components, N'Saddles');

SELECT @RoadBikes = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Road Bikes' AND ParentProductCategoryID = @Bikes;
SELECT @MountainBikes = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Mountain Bikes' AND ParentProductCategoryID = @Bikes;
SELECT @TouringBikes = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Touring Bikes' AND ParentProductCategoryID = @Bikes;
SELECT @Helmets = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Helmets' AND ParentProductCategoryID = @Clothing;
SELECT @Jerseys = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Jerseys' AND ParentProductCategoryID = @Clothing;
SELECT @Saddles = ProductCategoryID FROM SalesLT.ProductCategory WHERE Name = N'Saddles' AND ParentProductCategoryID = @Components;

DECLARE @Model TABLE (Name nvarchar(50), Description nvarchar(400));
INSERT INTO @Model (Name, Description) VALUES
    (N'Road-150', N'Aluminum road bike for long training rides and weekend events.'),
    (N'Road-350', N'Balanced road bike with endurance geometry and reliable components.'),
    (N'Mountain-200', N'Full suspension mountain bike for rough trail riding.'),
    (N'Mountain-500', N'Entry trail bike with durable frame and smooth shifting.'),
    (N'Touring-3000', N'Touring bike with rack mounts and comfort focused handling.'),
    (N'Sport Helmet', N'Vented helmet with adjustable fit system.'),
    (N'Classic Jersey', N'Moisture wicking jersey for daily rides.'),
    (N'Comfort Saddle', N'Ergonomic saddle for commuting and touring.');

INSERT INTO SalesLT.ProductModel (Name, CatalogDescription)
SELECT seed.Name, seed.Description
FROM @Model AS seed
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.ProductModel AS model WHERE model.Name = seed.Name);

INSERT INTO SalesLT.ProductDescription (Description)
SELECT seed.Description
FROM @Model AS seed
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.ProductDescription AS description WHERE description.Description = seed.Description);

INSERT INTO SalesLT.ProductModelProductDescription (ProductModelID, ProductDescriptionID, Culture)
SELECT model.ProductModelID, description.ProductDescriptionID, N'en'
FROM @Model AS seed
INNER JOIN SalesLT.ProductModel AS model ON model.Name = seed.Name
INNER JOIN SalesLT.ProductDescription AS description ON description.Description = seed.Description
WHERE NOT EXISTS (
    SELECT 1
    FROM SalesLT.ProductModelProductDescription AS mapping
    WHERE mapping.ProductModelID = model.ProductModelID
      AND mapping.ProductDescriptionID = description.ProductDescriptionID
      AND mapping.Culture = N'en'
);

DECLARE @Products TABLE (Name nvarchar(50), ProductNumber nvarchar(25), Color nvarchar(15), StandardCost money, ListPrice money, Size nvarchar(5), Weight decimal(8,2), CategoryID int, ModelName nvarchar(50));
INSERT INTO @Products (Name, ProductNumber, Color, StandardCost, ListPrice, Size, Weight, CategoryID, ModelName) VALUES
    (N'Road-150 Red, 62', N'BK-R93R-62', N'Red', 2171.29, 3578.27, N'62', 15.00, @RoadBikes, N'Road-150'),
    (N'Road-150 Black, 58', N'BK-R93B-58', N'Black', 2171.29, 3578.27, N'58', 15.20, @RoadBikes, N'Road-150'),
    (N'Road-350-W Yellow, 48', N'BK-R79Y-48', N'Yellow', 1082.51, 1700.99, N'48', 13.77, @RoadBikes, N'Road-350'),
    (N'Mountain-200 Silver, 42', N'BK-M68S-42', N'Silver', 1265.62, 2319.99, N'42', 23.77, @MountainBikes, N'Mountain-200'),
    (N'Mountain-200 Black, 46', N'BK-M68B-46', N'Black', 1251.98, 2294.99, N'46', 24.13, @MountainBikes, N'Mountain-200'),
    (N'Mountain-500 Silver, 44', N'BK-M18S-44', N'Silver', 308.22, 564.99, N'44', 27.35, @MountainBikes, N'Mountain-500'),
    (N'Touring-3000 Blue, 54', N'BK-T18B-54', N'Blue', 461.44, 742.35, N'54', 29.68, @TouringBikes, N'Touring-3000'),
    (N'Touring-3000 Yellow, 58', N'BK-T18Y-58', N'Yellow', 461.44, 742.35, N'58', 29.90, @TouringBikes, N'Touring-3000'),
    (N'Sport-100 Helmet, Red', N'HL-U509-R', N'Red', 13.09, 34.99, NULL, NULL, @Helmets, N'Sport Helmet'),
    (N'Sport-100 Helmet, Black', N'HL-U509', N'Black', 13.09, 34.99, NULL, NULL, @Helmets, N'Sport Helmet'),
    (N'Classic Vest, S', N'VE-C304-S', N'Blue', 23.75, 63.50, N'S', NULL, @Jerseys, N'Classic Jersey'),
    (N'LL Road Seat/Saddle', N'SE-R581', N'Black', 12.04, 27.12, NULL, NULL, @Saddles, N'Comfort Saddle');

INSERT INTO SalesLT.Product (Name, ProductNumber, Color, StandardCost, ListPrice, Size, Weight, ProductCategoryID, ProductModelID, SellStartDate)
SELECT seed.Name, seed.ProductNumber, seed.Color, seed.StandardCost, seed.ListPrice, seed.Size, seed.Weight, seed.CategoryID, model.ProductModelID, DATEADD(year, -2, GETDATE())
FROM @Products AS seed
INNER JOIN SalesLT.ProductModel AS model ON model.Name = seed.ModelName
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.Product AS product WHERE product.ProductNumber = seed.ProductNumber);

DECLARE @Customers TABLE (Title nvarchar(8), FirstName nvarchar(50), LastName nvarchar(50), CompanyName nvarchar(128), SalesPerson nvarchar(256), EmailAddress nvarchar(50), Phone nvarchar(25), AddressLine1 nvarchar(60), City nvarchar(30), StateProvince nvarchar(50), CountryRegion nvarchar(50), PostalCode nvarchar(15), AddressType nvarchar(50));
INSERT INTO @Customers (Title, FirstName, LastName, CompanyName, SalesPerson, EmailAddress, Phone, AddressLine1, City, StateProvince, CountryRegion, PostalCode, AddressType) VALUES
    (N'Ms.', N'Alicia', N'Keyes', N'Fourth Coffee', N'adventure-works\\pamela0', N'alicia@fourthcoffee.example', N'206-555-0101', N'1 Microsoft Way', N'Redmond', N'Washington', N'United States', N'98052', N'Main Office'),
    (N'Mr.', N'Diego', N'Martinez', N'Contoso Retail', N'adventure-works\\david8', N'diego@contoso.example', N'425-555-0112', N'800 Lake Union Ave', N'Seattle', N'Washington', N'United States', N'98109', N'Shipping'),
    (N'Ms.', N'Priya', N'Shah', N'Northwind Traders', N'adventure-works\\jillian0', N'priya@northwind.example', N'503-555-0140', N'250 Pearl Street', N'Portland', N'Oregon', N'United States', N'97209', N'Billing'),
    (N'Dr.', N'Marcus', N'Lee', N'Graphic Design Institute', N'adventure-works\\shu0', N'marcus@gdi.example', N'415-555-0199', N'100 Market Street', N'San Francisco', N'California', N'United States', N'94105', N'Main Office'),
    (N'Ms.', N'Elena', N'Garcia', N'Adventure Works Cycles', N'adventure-works\\linda3', N'elena@adventureworks.example', N'303-555-0100', N'1550 Blake Street', N'Denver', N'Colorado', N'United States', N'80202', N'Shipping');

INSERT INTO SalesLT.Customer (Title, FirstName, LastName, CompanyName, SalesPerson, EmailAddress, Phone, PasswordHash, PasswordSalt)
SELECT seed.Title, seed.FirstName, seed.LastName, seed.CompanyName, seed.SalesPerson, seed.EmailAddress, seed.Phone, CONVERT(varchar(128), HASHBYTES('SHA2_256', seed.EmailAddress + N':ArcBoxDemo'), 2), LEFT(CONVERT(varchar(36), NEWID()), 10)
FROM @Customers AS seed
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.Customer AS customer WHERE customer.EmailAddress = seed.EmailAddress);

INSERT INTO SalesLT.Address (AddressLine1, City, StateProvince, CountryRegion, PostalCode)
SELECT seed.AddressLine1, seed.City, seed.StateProvince, seed.CountryRegion, seed.PostalCode
FROM @Customers AS seed
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.Address AS address WHERE address.AddressLine1 = seed.AddressLine1 AND address.PostalCode = seed.PostalCode);

INSERT INTO SalesLT.CustomerAddress (CustomerID, AddressID, AddressType)
SELECT customer.CustomerID, address.AddressID, seed.AddressType
FROM @Customers AS seed
INNER JOIN SalesLT.Customer AS customer ON customer.EmailAddress = seed.EmailAddress
INNER JOIN SalesLT.Address AS address ON address.AddressLine1 = seed.AddressLine1 AND address.PostalCode = seed.PostalCode
WHERE NOT EXISTS (SELECT 1 FROM SalesLT.CustomerAddress AS customerAddress WHERE customerAddress.CustomerID = customer.CustomerID AND customerAddress.AddressID = address.AddressID);

DECLARE @CustomerID int, @BillTo int, @ShipTo int, @SalesOrderID int, @ProductA int, @ProductB int;

SELECT @CustomerID = CustomerID FROM SalesLT.Customer WHERE EmailAddress = N'alicia@fourthcoffee.example';
SELECT @BillTo = AddressID FROM SalesLT.CustomerAddress WHERE CustomerID = @CustomerID;
SELECT @ShipTo = @BillTo;
SELECT @ProductA = ProductID FROM SalesLT.Product WHERE ProductNumber = N'BK-R93R-62';
SELECT @ProductB = ProductID FROM SalesLT.Product WHERE ProductNumber = N'HL-U509-R';
IF @CustomerID IS NOT NULL AND @BillTo IS NOT NULL AND @ProductA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM SalesLT.SalesOrderHeader WHERE PurchaseOrderNumber = N'PO-DEMO-1001')
BEGIN
    INSERT INTO SalesLT.SalesOrderHeader (CustomerID, BillToAddressID, ShipToAddressID, PurchaseOrderNumber, AccountNumber, ShipMethod, Comment)
    VALUES (@CustomerID, @BillTo, @ShipTo, N'PO-DEMO-1001', N'10-4020-000001', N'CARGO TRANSPORT 5', N'Initial online storefront order');
    SET @SalesOrderID = SCOPE_IDENTITY();
    INSERT INTO SalesLT.SalesOrderDetail (SalesOrderID, OrderQty, ProductID, UnitPrice, UnitPriceDiscount)
    VALUES (@SalesOrderID, 1, @ProductA, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductA), 0.00),
           (@SalesOrderID, 2, @ProductB, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductB), 0.05);
END

SELECT @CustomerID = CustomerID FROM SalesLT.Customer WHERE EmailAddress = N'diego@contoso.example';
SELECT @BillTo = AddressID FROM SalesLT.CustomerAddress WHERE CustomerID = @CustomerID;
SELECT @ShipTo = @BillTo;
SELECT @ProductA = ProductID FROM SalesLT.Product WHERE ProductNumber = N'BK-M68S-42';
SELECT @ProductB = ProductID FROM SalesLT.Product WHERE ProductNumber = N'VE-C304-S';
IF @CustomerID IS NOT NULL AND @BillTo IS NOT NULL AND @ProductA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM SalesLT.SalesOrderHeader WHERE PurchaseOrderNumber = N'PO-DEMO-1002')
BEGIN
    INSERT INTO SalesLT.SalesOrderHeader (CustomerID, BillToAddressID, ShipToAddressID, PurchaseOrderNumber, AccountNumber, ShipMethod, Comment)
    VALUES (@CustomerID, @BillTo, @ShipTo, N'PO-DEMO-1002', N'10-4020-000002', N'OVERSEAS - DELUXE', N'Mountain launch order');
    SET @SalesOrderID = SCOPE_IDENTITY();
    INSERT INTO SalesLT.SalesOrderDetail (SalesOrderID, OrderQty, ProductID, UnitPrice, UnitPriceDiscount)
    VALUES (@SalesOrderID, 1, @ProductA, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductA), 0.00),
           (@SalesOrderID, 4, @ProductB, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductB), 0.00);
END

SELECT @CustomerID = CustomerID FROM SalesLT.Customer WHERE EmailAddress = N'priya@northwind.example';
SELECT @BillTo = AddressID FROM SalesLT.CustomerAddress WHERE CustomerID = @CustomerID;
SELECT @ShipTo = @BillTo;
SELECT @ProductA = ProductID FROM SalesLT.Product WHERE ProductNumber = N'BK-T18B-54';
SELECT @ProductB = ProductID FROM SalesLT.Product WHERE ProductNumber = N'SE-R581';
IF @CustomerID IS NOT NULL AND @BillTo IS NOT NULL AND @ProductA IS NOT NULL AND NOT EXISTS (SELECT 1 FROM SalesLT.SalesOrderHeader WHERE PurchaseOrderNumber = N'PO-DEMO-1003')
BEGIN
    INSERT INTO SalesLT.SalesOrderHeader (CustomerID, BillToAddressID, ShipToAddressID, PurchaseOrderNumber, AccountNumber, ShipMethod, Comment)
    VALUES (@CustomerID, @BillTo, @ShipTo, N'PO-DEMO-1003', N'10-4020-000003', N'CARGO TRANSPORT 5', N'Touring bundle');
    SET @SalesOrderID = SCOPE_IDENTITY();
    INSERT INTO SalesLT.SalesOrderDetail (SalesOrderID, OrderQty, ProductID, UnitPrice, UnitPriceDiscount)
    VALUES (@SalesOrderID, 2, @ProductA, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductA), 0.02),
           (@SalesOrderID, 2, @ProductB, (SELECT ListPrice FROM SalesLT.Product WHERE ProductID = @ProductB), 0.00);
END
'@
Invoke-ArcBoxSql -Query $tsql

$plainWebSqlSecret = $WebSqlCredential.GetNetworkCredential().Password
$escapedPwd = $plainWebSqlSecret.Replace("'", "''")
$tsql = @"
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'arcboxweb')
    CREATE LOGIN [arcboxweb] WITH PASSWORD = N'$escapedPwd', CHECK_POLICY = OFF;
ELSE
    ALTER LOGIN [arcboxweb] WITH PASSWORD = N'$escapedPwd';
"@
Invoke-ArcBoxSql -Query $tsql

$tsql = @'
USE ArcBoxDemo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'arcboxweb')
    CREATE USER [arcboxweb] FOR LOGIN [arcboxweb];
IF IS_ROLEMEMBER(N'db_datareader', N'arcboxweb') <> 1
    ALTER ROLE db_datareader ADD MEMBER [arcboxweb];
IF IS_ROLEMEMBER(N'db_datawriter', N'arcboxweb') <> 1
    ALTER ROLE db_datawriter ADD MEMBER [arcboxweb];
GRANT EXECUTE ON SCHEMA::dbo TO [arcboxweb];
GRANT EXECUTE ON SCHEMA::SalesLT TO [arcboxweb];
'@
Invoke-ArcBoxSql -Query $tsql

Write-Host 'ArcBoxDemo AdventureWorksLT database and arcboxweb login ready'
