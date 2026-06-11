$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$resourceGroup = $env:resourceGroup

$logFilePath = Join-Path -Path $Env:ArcBoxLogsDir -ChildPath ('WinGet-provisioning-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

$DeploymentStatusScript = Join-Path -Path $Env:ArcBoxDir -ChildPath 'DeploymentStatus.ps1'
$CurrentDeploymentComponent = 'WinGet and host configuration'
trap {
    if (Test-Path $DeploymentStatusScript) {
        & $DeploymentStatusScript -Action Complete -Component $CurrentDeploymentComponent -Status Failed -Message $_.Exception.Message
        & $DeploymentStatusScript -Action Report -Open
    }
    try { Stop-Transcript } catch { }
    throw
}

if (Test-Path $DeploymentStatusScript) {
    & $DeploymentStatusScript -Action Start -Component $CurrentDeploymentComponent -Message 'Installing WinGet, DSC resources, and Hyper-V host configuration.'
}

Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId

if (Test-Path $DeploymentStatusScript) {
    & $DeploymentStatusScript -Action Start -Component $CurrentDeploymentComponent -Message 'Installing WinGet packages...' -ResourceGroup $resourceGroup -SubscriptionId $subscriptionId -TenantId $tenantId
}

# Install WinGet PowerShell modules
# Pinned to version 1.11.460 to avoid known issue: https://github.com/microsoft/winget-cli/issues/5826
Install-PSResource -Name Microsoft.WinGet.Client -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Version 1.11.460
Install-PSResource -Name Microsoft.WinGet.DSC -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Version 1.11.460

# Install DSC resources required for ArcBox
Install-PSResource -Name DSCR_Font -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
Install-PSResource -Name HyperVDsc -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Prerelease
Install-PSResource -Name NetworkingDsc -Scope AllUsers -Quiet -AcceptLicense -TrustRepository

# Update WinGet package manager to the latest version (running twice due to a known issue regarding WinAppSDK)
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose

# Apply WinGet Configuration files
winget configure --file C:\ArcBox\DSC\common.dsc.yml --accept-configuration-agreements --disable-interactivity
winget configure --file C:\ArcBox\DSC\itpro.dsc.yml --accept-configuration-agreements --disable-interactivity

if (Test-Path $DeploymentStatusScript) {
    & $DeploymentStatusScript -Action Complete -Component $CurrentDeploymentComponent -Status Completed -Message 'WinGet packages and host DSC configuration completed.'
}

# Start remaining logon script
Get-ScheduledTask -TaskName 'ArcServersLogonScript' | Start-ScheduledTask

#Cleanup
Unregister-ScheduledTask -TaskName 'WinGetLogonScript' -Confirm:$false
Stop-Transcript