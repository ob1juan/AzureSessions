param(
    [Parameter(Mandatory = $true)][string]$SqlServerAddress,
    [Parameter(Mandatory = $true)][string]$SqlDatabase,
    [Parameter(Mandatory = $true)][string]$SqlUser,
    [Parameter(Mandatory = $true)][string]$SqlPassword,
    [Parameter(Mandatory = $true)][string]$PgServerAddress,
    [Parameter(Mandatory = $true)][string]$PgDatabase,
    [Parameter(Mandatory = $true)][string]$PgUser,
    [Parameter(Mandatory = $true)][string]$PgPassword,
    [Parameter(Mandatory = $true)][string]$ArtifactBaseUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$siteRoot = 'C:\inetpub\arcboxapp'
$pgRoot = 'C:\inetpub\arcboxapp_pg'
$siteName = 'ArcBoxApp'
$vdirName = 'pg'

Write-Host 'Installing IIS and ASP.NET 4.x role features'
Install-WindowsFeature -Name `
    Web-Server, Web-WebServer, Web-Common-Http, Web-Default-Doc, Web-Dir-Browsing, `
    Web-Http-Errors, Web-Static-Content, Web-Http-Redirect, Web-Http-Logging, `
    Web-Stat-Compression, Web-Filtering, Web-Asp-Net45, Web-Net-Ext45, `
    Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Mgmt-Console -IncludeManagementTools | Out-Null

Import-Module WebAdministration

New-Item -ItemType Directory -Path $siteRoot -Force | Out-Null
New-Item -ItemType Directory -Path $pgRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $pgRoot 'bin') -Force | Out-Null

Write-Host 'Downloading ASPX sample pages'
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/default.aspx') -OutFile (Join-Path $siteRoot 'default.aspx') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/sql.aspx') -OutFile (Join-Path $siteRoot 'sql.aspx') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/site/web.config') -OutFile (Join-Path $siteRoot 'web.config') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/pg/pg.aspx') -OutFile (Join-Path $pgRoot 'pg.aspx') -UseBasicParsing
Invoke-WebRequest -Uri ($ArtifactBaseUrl + 'artifacts/iis/pg/web.config') -OutFile (Join-Path $pgRoot 'web.config') -UseBasicParsing

Write-Host 'Downloading Npgsql .NET Framework 4.6.2 assemblies from NuGet'
$nupkgDir = Join-Path $env:TEMP 'npgsql-nupkg'
$extractDir = Join-Path $env:TEMP 'npgsql-extract'
Remove-Item -Recurse -Force $nupkgDir, $extractDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $nupkgDir -Force | Out-Null
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

# Pin to a Npgsql version that still ships net462 binaries.
$npgsqlVersion = '6.0.11'
$npgsqlPackages = @(
    @{ id = 'Npgsql'; version = $npgsqlVersion },
    @{ id = 'System.Threading.Tasks.Extensions'; version = '4.5.4' },
    @{ id = 'System.Runtime.CompilerServices.Unsafe'; version = '6.0.0' },
    @{ id = 'System.Memory'; version = '4.5.5' },
    @{ id = 'System.Buffers'; version = '4.5.1' },
    @{ id = 'System.Numerics.Vectors'; version = '4.5.0' },
    @{ id = 'System.ValueTuple'; version = '4.5.0' },
    @{ id = 'Microsoft.Bcl.AsyncInterfaces'; version = '6.0.0' },
    @{ id = 'System.Text.Encodings.Web'; version = '6.0.0' },
    @{ id = 'System.Text.Json'; version = '6.0.7' }
)

foreach ($pkg in $npgsqlPackages) {
    $url = "https://www.nuget.org/api/v2/package/$($pkg.id)/$($pkg.version)"
    $nupkgPath = Join-Path $nupkgDir "$($pkg.id).$($pkg.version).nupkg"
    Invoke-WebRequest -Uri $url -OutFile $nupkgPath -UseBasicParsing
    $pkgExtract = Join-Path $extractDir $pkg.id
    Expand-Archive -Path $nupkgPath -DestinationPath $pkgExtract -Force
    # Prefer net462 then net461 then net46 then netstandard2.0
    $candidates = @('lib\net462', 'lib\net461', 'lib\net46', 'lib\netstandard2.0', 'lib\netstandard2.1')
    foreach ($c in $candidates) {
        $libDir = Join-Path $pkgExtract $c
        if (Test-Path $libDir) {
            Get-ChildItem $libDir -Filter '*.dll' | ForEach-Object {
                Copy-Item $_.FullName -Destination (Join-Path $pgRoot 'bin') -Force
            }
            break
        }
    }
}

Write-Host 'Configuring IIS site and virtual directory'
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
New-WebVirtualDirectory -Site $siteName -Name $vdirName -PhysicalPath $pgRoot -Force | Out-Null
ConvertTo-WebApplication "IIS:\Sites\$siteName\$vdirName" -ApplicationPool $siteName | Out-Null

Write-Host 'Writing connection strings to site web.config'
$sqlConn = "Server=$SqlServerAddress;Database=$SqlDatabase;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;Encrypt=False;Connection Timeout=10"
$pgConn = "Host=$PgServerAddress;Username=$PgUser;Password=$PgPassword;Database=$PgDatabase;Timeout=10"

$siteConfigPath = Join-Path $siteRoot 'web.config'
(Get-Content -Raw -Path $siteConfigPath) `
    -replace '__SQL_CONN__', [System.Security.SecurityElement]::Escape($sqlConn) `
    | Set-Content -Path $siteConfigPath -Encoding UTF8

$pgConfigPath = Join-Path $pgRoot 'web.config'
(Get-Content -Raw -Path $pgConfigPath) `
    -replace '__PG_CONN__', [System.Security.SecurityElement]::Escape($pgConn) `
    | Set-Content -Path $pgConfigPath -Encoding UTF8

Write-Host 'Allowing HTTP through Windows Firewall'
if (-not (Get-NetFirewallRule -DisplayName 'ArcBox IIS HTTP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'ArcBox IIS HTTP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 | Out-Null
}

Restart-WebAppPool -Name $siteName
Write-Host 'IIS configuration complete'
