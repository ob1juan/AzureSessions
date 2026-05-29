param (
    [string]$adminUsername,
    [string]$spnClientId,
    [string]$tenantId,
    [string]$spnAuthority,
    [string]$subscriptionId,
    [string]$resourceGroup,
    [string]$azdataUsername,
    [string]$acceptEula,
    [string]$registryUsername,
    [string]$arcDcName,
    [string]$azureLocation,
    [string]$mssqlmiName,
    [string]$POSTGRES_NAME,
    [string]$POSTGRES_WORKER_NODE_COUNT,
    [string]$POSTGRES_DATASIZE,
    [string]$POSTGRES_SERVICE_TYPE,
    [string]$stagingStorageAccountName,
    [string]$workspaceName,
    [string]$k3sArcDataClusterName,
    [string]$k3sArcClusterName,
    [string]$aksArcClusterName,
    [string]$aksdrArcClusterName,
    [string]$githubBranch,
    [string]$githubUser,
    [string]$templateBaseUrl,
    [string]$flavor,
    [string]$rdpPort,
    [string]$sshPort,
    [string]$vmAutologon,
    [string]$addsDomainName,
    [string]$customLocationRPOID,
    [object]$resourceTags,
    [string]$namingPrefix,
    [string]$debugEnabled,
    [string]$sqlServerEdition,
    [string]$autoShutdownEnabled
)

[System.Environment]::SetEnvironmentVariable('adminUsername', $adminUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('spnAuthority', $spnAuthority, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('tenantId', $tenantId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceGroup', $resourceGroup, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('AZDATA_USERNAME', $azdataUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ACCEPT_EULA', $acceptEula, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('registryUsername', $registryUsername, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('arcDcName', $arcDcName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('subscriptionId', $subscriptionId, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('azureLocation', $azureLocation, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('mssqlmiName', $mssqlmiName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_NAME', $POSTGRES_NAME, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_WORKER_NODE_COUNT', $POSTGRES_WORKER_NODE_COUNT, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_DATASIZE', $POSTGRES_DATASIZE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('POSTGRES_SERVICE_TYPE', $POSTGRES_SERVICE_TYPE, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('stagingStorageAccountName', $stagingStorageAccountName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('workspaceName', $workspaceName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('k3sArcDataClusterName', $k3sArcDataClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('k3sArcClusterName', $k3sArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('githubBranch', $githubBranch, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('githubUser', $githubUser, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('templateBaseUrl', $templateBaseUrl, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('flavor', $flavor, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('automationTriggerAtLogon', $automationTriggerAtLogon, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('addsDomainName', $addsDomainName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aksArcClusterName', $aksArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('aksdrArcClusterName', $aksdrArcClusterName, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('customLocationRPOID', $customLocationRPOID, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('resourceTags', $resourceTags, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('namingPrefix', $namingPrefix, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('ArcBoxDir', "C:\ArcBox", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('sqlServerEdition', $sqlServerEdition, [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('autoShutdownEnabled', $autoShutdownEnabled, [System.EnvironmentVariableTarget]::Machine)

if ($debugEnabled -eq "true") {
    [System.Environment]::SetEnvironmentVariable('ErrorActionPreference', "Break", [System.EnvironmentVariableTarget]::Machine)
} else {
    [System.Environment]::SetEnvironmentVariable('ErrorActionPreference', "Continue", [System.EnvironmentVariableTarget]::Machine)
}

# Formatting VMs disk
$disk = (Get-Disk | Where-Object partitionstyle -eq 'raw')[0]
$driveLetter = "F"
$label = "VMsDisk"
$disk | Initialize-Disk -PartitionStyle MBR -PassThru | `
    New-Partition -UseMaximumSize -DriveLetter $driveLetter | `
    Format-Volume -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false -Force

# Creating ArcBox path
Write-Output "Creating ArcBox path"
$Env:ArcBoxDir = "C:\ArcBox"
$Env:ArcBoxDscDir = "$Env:ArcBoxDir\DSC"
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = "F:\Virtual Machines"
$Env:ArcBoxKVDir = "$Env:ArcBoxDir\KeyVault"
$Env:ArcBoxGitOpsDir = "$Env:ArcBoxDir\GitOps"
$Env:ArcBoxIconDir = "$Env:ArcBoxDir\Icons"
$Env:agentScript = "$Env:ArcBoxDir\agentScript"
$Env:ArcBoxTestsDir = "$Env:ArcBoxDir\Tests"
$Env:ToolsDir = "C:\Tools"
$Env:tempDir = "C:\Temp"

New-Item -Path $Env:ArcBoxDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxDscDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxLogsDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxVMDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxKVDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxGitOpsDir -ItemType directory -Force
New-Item -Path $Env:ArcBoxIconDir -ItemType directory -Force
New-Item -Path $Env:ToolsDir -ItemType Directory -Force
New-Item -Path $Env:tempDir -ItemType directory -Force
New-Item -Path $Env:agentScript -ItemType directory -Force
New-Item -Path $Env:ArcBoxTestsDir -ItemType directory -Force

Start-Transcript -Path $Env:ArcBoxLogsDir\Bootstrap.log

# Set SyncForegroundPolicy to 1 to ensure that the scheduled task runs after the client VM joins the domain
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "SyncForegroundPolicy" 1

# Copy PowerShell Profile and Reload
Invoke-WebRequest ($templateBaseUrl + "artifacts/PSProfile.ps1") -OutFile $PsHome\Profile.ps1
.$PsHome\Profile.ps1

# Extending C:\ partition to the maximum size
Write-Host "Extending C:\ partition to the maximum size"
Resize-Partition -DriveLetter C -Size $(Get-PartitionSupportedSize -DriveLetter C).SizeMax

# Installing PowerShell Modules
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force

Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force

# Pin Az-modules after other modules to avoid version conflicts
# See: https://github.com/microsoft/azure_arc/issues/3359
Install-PSResource -Name Az.Accounts -Version 5.3.1 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.KeyVault -Version 6.4.1 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Compute -Version 11.1.0 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Resources -Version 9.0.0 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Az.Storage -Version 9.4.0  -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall
Install-PSResource -Name Microsoft.PowerShell.SecretManagement -Version 1.1.2 -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Reinstall

# Import the module to ensure the correct version is loaded
Import-Module Az.Accounts -RequiredVersion 5.3.1 -Force
Import-Module Az.KeyVault -RequiredVersion 6.4.1 -Force
Import-Module Az.Resources -RequiredVersion 9.0.0 -Force

$DeploymentProgressString = "Started bootstrap-script..."

Connect-AzAccount -Identity

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags

$KeyVault = Get-AzKeyVault -ResourceGroupName $resourceGroup

# Set Key Vault Name as an environment variable
[System.Environment]::SetEnvironmentVariable('keyVaultName', $KeyVault.VaultName, [System.EnvironmentVariableTarget]::Machine)

# Import required module
Import-Module Microsoft.PowerShell.SecretManagement

# Register the Azure Key Vault as a secret vault if not already registered
# Ensure you have installed the SecretManagement and SecretStore modules along with the Key Vault extension

if (-not (Get-SecretVault -Name $KeyVault.VaultName -ErrorAction Ignore)) {
    Register-SecretVault -Name $KeyVault.VaultName -ModuleName Az.KeyVault -VaultParameters @{ AZKVaultName = $KeyVault.VaultName } -DefaultVault
}

$adminPassword = Get-Secret -Name windowsAdminPassword -AsPlainText

if ($vmAutologon -eq "true") {

    Write-Host "Configuring VM Autologon"

    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoAdminLogon" "1"
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultUserName" $adminUsername
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "DefaultPassword" $adminPassword
} else {

    Write-Host "Not configuring VM Autologon"

}

# Temporarily disabling Azure VM Auto-shutdown while automation is in progress
if ($autoShutdownEnabled -eq "true") {

    $ScheduleResource = Get-AzResource -ResourceGroup $resourceGroup -ResourceType Microsoft.DevTestLab/schedules
    $Uri = "https://management.azure.com$($ScheduleResource.ResourceId)?api-version=2018-09-15"

    $Schedule = Invoke-AzRestMethod -Uri $Uri

    $ScheduleSettings = $Schedule.Content | ConvertFrom-Json
    $ScheduleSettings.properties.status = "Disabled"

    Invoke-AzRestMethod -Uri $Uri -Method PUT -Payload ($ScheduleSettings | ConvertTo-Json)

}

# Installing tools and module

Write-Header "Installing PowerShell 7"

$ProgressPreference = 'SilentlyContinue'
$url = "https://github.com/PowerShell/PowerShell/releases/latest"
$latestVersion = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content | Select-String -Pattern "v[0-9]+\.[0-9]+\.[0-9]+" | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
$downloadUrl = "https://github.com/PowerShell/PowerShell/releases/download/$latestVersion/PowerShell-$($latestVersion.Substring(1,5))-win-x64.msi"
Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile .\PowerShell7.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I PowerShell7.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1'
Remove-Item .\PowerShell7.msi

Copy-Item $PsHome\Profile.ps1 -Destination "C:\Program Files\PowerShell\7\"


$modules = @("Az.ConnectedMachine", "Az.ConnectedKubernetes", "Az.CustomLocation", "Azure.Arc.Jumpstart.Common", "Pester")

foreach ($module in $modules) {
    Install-PSResource -Name $module -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
}

Write-Header "Fetching GitHub Artifacts"

# All flavors
Write-Host "Fetching Artifacts for All Flavors"
Invoke-WebRequest "https://raw.githubusercontent.com/Azure/arc_jumpstart_docs/main/img/wallpaper/arcbox_wallpaper_dark.png" -OutFile $Env:ArcBoxDir\wallpaper.png
Invoke-WebRequest ($templateBaseUrl + "artifacts/MonitorWorkbookLogonScript.ps1") -OutFile $Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/mgmtMonitorWorkbook.parameters.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.parameters.json
Invoke-WebRequest ($templateBaseUrl + "artifacts/monitoring/arc-inventory-workbook.json") -OutFile "$Env:ArcBoxDir\arc-inventory-workbook.json"
Invoke-WebRequest ($templateBaseUrl + "artifacts/monitoring/arc-osperformance-workbook.json") -OutFile "$Env:ArcBoxDir\arc-osperformance-workbook.json"
Invoke-WebRequest ($templateBaseUrl + "artifacts/DeploymentStatus.ps1") -OutFile $Env:ArcBoxDir\DeploymentStatus.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/LogInstructions.txt") -OutFile $Env:ArcBoxLogsDir\LogInstructions.txt
Invoke-WebRequest ($templateBaseUrl + "artifacts/dsc/common.dsc.yml") -OutFile $Env:ArcBoxDscDir\common.dsc.yml
Invoke-WebRequest ($templateBaseUrl + "artifacts/dsc/virtual_machines_sql.dsc.yml") -OutFile $Env:ArcBoxDscDir\virtual_machines_sql.dsc.yml
Invoke-WebRequest ($templateBaseUrl + "artifacts/tests/arcbox-bginfo.bgi") -OutFile $Env:ArcBoxTestsDir\arcbox-bginfo.bgi
Invoke-WebRequest ($templateBaseUrl + "artifacts/tests/common.tests.ps1") -OutFile $Env:ArcBoxTestsDir\common.tests.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/tests/Invoke-Test.ps1") -OutFile $Env:ArcBoxTestsDir\Invoke-Test.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/WinGet.ps1") -OutFile $Env:ArcBoxDir\WinGet.ps1

# Workbook template
Write-Host "Fetching Workbook Template Artifact for ITPro"
Invoke-WebRequest ($templateBaseUrl + "artifacts/mgmtMonitorWorkbookITPro.json") -OutFile $Env:ArcBoxDir\mgmtMonitorWorkbook.json

# ITPro
Write-Host "Fetching Artifacts for ITPro Flavor"
Invoke-WebRequest ($templateBaseUrl + "artifacts/ArcServersLogonScript.ps1") -OutFile $Env:ArcBoxDir\ArcServersLogonScript.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/installArcAgent.ps1") -OutFile $Env:ArcBoxDir\agentScript\installArcAgent.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/installArcAgentUbuntu.sh") -OutFile $Env:ArcBoxDir\agentScript\installArcAgentUbuntu.sh
Invoke-WebRequest ($templateBaseUrl + "artifacts/icons/arcsql.ico") -OutFile $Env:ArcBoxIconDir\arcsql.ico
Invoke-WebRequest ($templateBaseUrl + "artifacts/installArcAgentSQLUser.ps1") -OutFile $Env:ArcBoxDir\installArcAgentSQLUser.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/SqlAdvancedThreatProtectionShell.psm1") -OutFile $Env:ArcBoxDir\SqlAdvancedThreatProtectionShell.psm1
Invoke-WebRequest ($templateBaseUrl + "artifacts/defendersqldcrtemplate.json") -OutFile $Env:ArcBoxDir\defendersqldcrtemplate.json
Invoke-WebRequest ($templateBaseUrl + "artifacts/testDefenderForSQL.ps1") -OutFile $Env:ArcBoxDir\testDefenderForSQL.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/tests/itpro.tests.ps1") -OutFile $Env:ArcBoxTestsDir\itpro.tests.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/dsc/itpro.dsc.yml") -OutFile $Env:ArcBoxDscDir\itpro.dsc.yml
Invoke-WebRequest ($templateBaseUrl + "artifacts/dsc/virtual_machines_itpro.dsc.yml") -OutFile $Env:ArcBoxDscDir\virtual_machines_itpro.dsc.yml

# IIS + PostgreSQL demo VM artifacts
Invoke-WebRequest ($templateBaseUrl + "artifacts/dsc/virtual_machines_iis_pg.dsc.yml") -OutFile $Env:ArcBoxDscDir\virtual_machines_iis_pg.dsc.yml
Invoke-WebRequest ($templateBaseUrl + "artifacts/iis/Configure-IIS.ps1") -OutFile $Env:ArcBoxDir\Configure-IIS.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/iis/Initialize-ArcBoxSqlDemo.ps1") -OutFile $Env:ArcBoxDir\Initialize-ArcBoxSqlDemo.ps1
Invoke-WebRequest ($templateBaseUrl + "artifacts/postgres/Configure-Postgres.sh") -OutFile $Env:ArcBoxDir\Configure-Postgres.sh

New-Item -path alias:azdata -value 'C:\Program Files (x86)\Microsoft SDKs\Azdata\CLI\wbin\azdata.cmd'

# Disable Microsoft Edge sidebar
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name = 'HubsSidebarEnabled'
$Value = '00000000'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Disable Microsoft Edge first-run Welcome screen
$RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$Name = 'HideFirstRunExperience'
$Value = '00000001'
# Create the key if it does not exist
If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
New-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -PropertyType DWORD -Force

# Set Diagnostic Data settings

$telemetryPath = "HKLM:\Software\Policies\Microsoft\Windows\DataCollection"
$telemetryProperty = "AllowTelemetry"
$telemetryValue = 3

$oobePath = "HKLM:\Software\Policies\Microsoft\Windows\OOBE"
$oobeProperty = "DisablePrivacyExperience"
$oobeValue = 1

# Create the registry key and set the value for AllowTelemetry
if (-not (Test-Path $telemetryPath)) {
    New-Item -Path $telemetryPath -Force | Out-Null
}
Set-ItemProperty -Path $telemetryPath -Name $telemetryProperty -Value $telemetryValue

# Create the registry key and set the value for DisablePrivacyExperience
if (-not (Test-Path $oobePath)) {
    New-Item -Path $oobePath -Force | Out-Null
}
Set-ItemProperty -Path $oobePath -Name $oobeProperty -Value $oobeValue

Write-Host "Registry keys and values for Diagnostic Data settings have been set successfully."

# Change RDP Port
Write-Host "RDP port number from configuration is $rdpPort"
if (($null -ne $rdpPort) -and ($rdpPort -ne "") -and ($rdpPort -ne "3389")) {
    Write-Host "Configuring RDP port number to $rdpPort"
    $TSPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $RDPTCPpath = $TSPath + '\Winstations\RDP-Tcp'
    Set-ItemProperty -Path $TSPath -name 'fDenyTSConnections' -Value 0

    # RDP port
    $portNumber = (Get-ItemProperty -Path $RDPTCPpath -Name 'PortNumber').PortNumber
    Write-Host "Current RDP PortNumber: $portNumber"
    if (!($portNumber -eq $rdpPort)) {
        Write-Host Setting RDP PortNumber to $rdpPort
        Set-ItemProperty -Path $RDPTCPpath -name 'PortNumber' -Value $rdpPort
        Restart-Service TermService -force
    }

    #Setup firewall rules
    if ($rdpPort -eq 3389) {
        netsh advfirewall firewall set rule group="remote desktop" new Enable=Yes
    }
    else {
        $systemroot = get-content env:systemroot
        netsh advfirewall firewall add rule name="Remote Desktop - Custom Port" dir=in program=$systemroot\system32\svchost.exe service=termservice action=allow protocol=TCP localport=$RDPPort enable=yes
    }

    Write-Host "RDP port configuration complete."
}

# Workaround for https://github.com/microsoft/azure_arc/issues/3035

# Define firewall rule name
$ruleName = "Block RDP UDP 3389"

# Check if the rule already exists
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Host "Firewall rule '$ruleName' already exists. No changes made."
} else {
    # Create a new firewall rule to block UDP traffic on port 3389
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol UDP -LocalPort 3389 -Action Block -Enabled True
    Write-Host "Firewall rule '$ruleName' created successfully. RDP UDP is now blocked."
}

# Define the registry path
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"

# Define the registry key name
$registryName = "fClientDisableUDP"

# Define the value (1 = Disable Connect Time Detect and Continuous Network Detect)
$registryValue = 1

# Check if the registry path exists, if not, create it
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

# Set the registry key
Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValue -Type DWord

# Confirm the change
Write-Host "Registry setting applied successfully. fClientDisableUDP set to $registryValue"

Write-Header "Configuring Logon Scripts"

$ScheduledTaskExecutable = "pwsh.exe"

$DeploymentProgressString = "Restarting and installing WinGet packages..."

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags

# Creating scheduled task for WinGet.ps1
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\WinGet.ps1
Register-ScheduledTask -TaskName "WinGetLogonScript" -Trigger $Trigger -User $adminUsername -Action $Action -RunLevel "Highest" -Force

# Creating scheduled task for ArcServersLogonScript.ps1
$Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\ArcServersLogonScript.ps1
Register-ScheduledTask -TaskName "ArcServersLogonScript" -User $adminUsername -Action $Action -RunLevel "Highest" -Force

# Creating scheduled task for MonitorWorkbookLogonScript.ps1
$Action = New-ScheduledTaskAction -Execute $ScheduledTaskExecutable -Argument $Env:ArcBoxDir\MonitorWorkbookLogonScript.ps1
Register-ScheduledTask -TaskName "MonitorWorkbookLogonScript" -User $adminUsername -Action $Action -RunLevel "Highest" -Force

# Disabling Windows Server Manager Scheduled Task
Get-ScheduledTask -TaskName ServerManager | Disable-ScheduledTask

Write-Header "Installing Hyper-V"
Write-Host "Installing Hyper-V and restart"
Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools -Restart

# Clean up Bootstrap.log
Write-Host "Clean up Bootstrap.log"
Stop-Transcript
$logSuppress = Get-Content $Env:ArcBoxLogsDir\Bootstrap.log | Where-Object { $_ -notmatch "Host Application: $ScheduledTaskExecutable" }
$logSuppress | Set-Content $Env:ArcBoxLogsDir\Bootstrap.log -Force

# Restart computer
Restart-Computer