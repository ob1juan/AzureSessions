param(
    [Parameter(Mandatory = $true)][string]$SqlServerAddress,
    [Parameter(Mandatory = $true)][string]$SqlDatabase,
    [Parameter(Mandatory = $true)][string]$SqlUser,
    [Parameter(Mandatory = $true)][string]$SqlPassword,
    [Parameter(Mandatory = $true)][string]$ArtifactBaseUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$siteRoot = 'C:\inetpub\arcboxapp'
$siteName = 'ArcBoxApp'

Write-Host 'Installing IIS and ASP.NET 4.x role features'
Install-WindowsFeature -Name `
    Web-Server, Web-WebServer, Web-Common-Http, Web-Default-Doc, Web-Dir-Browsing, `
    Web-Http-Errors, Web-Static-Content, Web-Http-Redirect, Web-Http-Logging, `
    Web-Stat-Compression, Web-Filtering, Web-Asp-Net45, Web-Net-Ext45, `
    Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console -IncludeManagementTools | Out-Null

Import-Module WebAdministration

New-Item -ItemType Directory -Path $siteRoot -Force | Out-Null

Write-Host 'Downloading ASPX sample pages'
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/default.aspx') -OutFile (Join-Path $siteRoot 'default.aspx') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/sql.aspx') -OutFile (Join-Path $siteRoot 'sql.aspx') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/web.config') -OutFile (Join-Path $siteRoot 'web.config') -UseBasicParsing

Write-Host 'Configuring IIS site'
if (Test-Path 'IIS:\Sites\Default Web Site') {
    Remove-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue
}
if (Test-Path "IIS:\Sites\$siteName") {
    Remove-Website -Name $siteName -ErrorAction SilentlyContinue
}
if (Test-Path "IIS:\AppPools\$siteName") {
    Remove-WebAppPool -Name $siteName -ErrorAction SilentlyContinue
}

New-WebAppPool -Name $siteName | Out-Null
Set-ItemProperty "IIS:\AppPools\$siteName" -Name managedRuntimeVersion -Value 'v4.0'
Set-ItemProperty "IIS:\AppPools\$siteName" -Name processModel.identityType -Value 'ApplicationPoolIdentity'

New-Website -Name $siteName -Port 80 -PhysicalPath $siteRoot -ApplicationPool $siteName -Force | Out-Null

Write-Host 'Writing connection strings to site web.config'
$sqlConn = "Server=$SqlServerAddress;Database=$SqlDatabase;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;Encrypt=False;Connection Timeout=10"

$siteConfigPath = Join-Path $siteRoot 'web.config'
(Get-Content -Raw -Path $siteConfigPath) `
    -replace '__SQL_CONN__', [System.Security.SecurityElement]::Escape($sqlConn) `
    | Set-Content -Path $siteConfigPath -Encoding UTF8

Write-Host 'Allowing HTTP through Windows Firewall'
if (-not (Get-NetFirewallRule -DisplayName 'ArcBox IIS HTTP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'ArcBox IIS HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 | Out-Null
}

Restart-WebAppPool -Name $siteName
Write-Host 'IIS configuration complete'
