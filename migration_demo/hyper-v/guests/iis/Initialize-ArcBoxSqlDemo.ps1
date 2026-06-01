param(
    [Parameter(Mandatory = $true)][string]$WebSqlPassword
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue)) {
    throw 'SQL Server default instance MSSQLSERVER was not found on this VM.'
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

$tsql = @"
USE master;
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'ArcBoxDemo')
    CREATE DATABASE ArcBoxDemo;
"@
Invoke-Sqlcmd -Query $tsql -TrustServerCertificate

$tsql = @"
USE ArcBoxDemo;
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Products')
BEGIN
    CREATE TABLE dbo.Products (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(100) NOT NULL,
        Price DECIMAL(10,2) NOT NULL,
        Stock INT NOT NULL
    );
    INSERT INTO dbo.Products (Name, Price, Stock) VALUES
        (N'ArcBox Sticker Pack', 9.99, 250),
        (N'Jumpstart Hoodie', 49.99, 75),
        (N'Azure Arc Mug', 14.99, 180),
        (N'Hybrid Cloud Notebook', 19.99, 120);
END
"@
Invoke-Sqlcmd -Query $tsql -TrustServerCertificate

$escapedPwd = $WebSqlPassword.Replace("'", "''")
$tsql = @"
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'arcboxweb')
    CREATE LOGIN [arcboxweb] WITH PASSWORD = N'$escapedPwd', CHECK_POLICY = OFF;
ELSE
    ALTER LOGIN [arcboxweb] WITH PASSWORD = N'$escapedPwd';
"@
Invoke-Sqlcmd -Query $tsql -TrustServerCertificate

$tsql = @"
USE ArcBoxDemo;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'arcboxweb')
    CREATE USER [arcboxweb] FOR LOGIN [arcboxweb];
IF IS_ROLEMEMBER(N'db_datareader', N'arcboxweb') <> 1
    ALTER ROLE db_datareader ADD MEMBER [arcboxweb];
IF IS_ROLEMEMBER(N'db_datawriter', N'arcboxweb') <> 1
    ALTER ROLE db_datawriter ADD MEMBER [arcboxweb];
"@
Invoke-Sqlcmd -Query $tsql -TrustServerCertificate

Write-Host 'ArcBoxDemo database and arcboxweb login ready'
