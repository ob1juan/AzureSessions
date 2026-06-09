param(
    [ValidateSet('Init', 'Start', 'Complete', 'Report')]
    [string]$Action = 'Report',

    [string]$Component,

    [ValidateSet('Pending', 'InProgress', 'Completed', 'Failed', 'Skipped')]
    [string]$Status = 'Completed',

    [string]$Message = '',
    [switch]$Open,
    [string]$LogsDir = $(if ($env:ArcBoxLogsDir) { $env:ArcBoxLogsDir } else { 'C:\ArcBox\Logs' }),
    [string]$ResourceGroup = $env:resourceGroup,
    [string]$SubscriptionId = $env:subscriptionId,
    [string]$TenantId = $env:tenantId
)

$ErrorActionPreference = 'Stop'
$statePath = Join-Path -Path $LogsDir -ChildPath 'DeploymentStatus.json'
$htmlPath = Join-Path -Path $LogsDir -ChildPath 'DeploymentStatus.html'

$defaultComponents = @(
    @{
        Name = 'Client bootstrap'
        Description = 'Custom Script Extension bootstrap, artifact download, module install, autologon, and scheduled task registration.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'Custom Script Extension download folder\Bootstrap.ps1'
        Command = 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername <template value> -tenantId <tenant id> -subscriptionId <subscription id> -resourceGroup <resource group> -azureLocation <location> -templateBaseUrl <artifact url> -flavor ITPro -vmAutologon <true|false> -rdpPort <port> -namingPrefix <prefix> -debugEnabled <true|false> -sqlServerEdition <edition> -autoShutdownEnabled <true|false> -autoShutdownTimezone <Windows time zone>'
        RerunCommand = 'Redeploy the Bootstrap VM extension or rerun the ARM deployment after fixing the reported issue.'
        LogPath = 'C:\ArcBox\Logs\Bootstrap.log'
        WorkingDirectory = 'Custom Script Extension download folder'
        RecoveryInstructions = 'If this step fails, review Bootstrap.log first. Because it runs as the Azure VM extension, the most reliable rerun is to redeploy the Bootstrap extension or rerun the template.'
    }
    @{
        Name = 'Hyper-V feature installation'
        Description = 'Client VM Hyper-V, Containers, and Virtual Machine Platform feature enablement before restart.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'Custom Script Extension download folder\Bootstrap.ps1'
        Command = 'Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart; Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart; Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools; Restart-Computer'
        RerunCommand = 'Run the feature install command from an elevated PowerShell session, then restart the client VM.'
        LogPath = 'C:\ArcBox\Logs\Bootstrap.log'
        WorkingDirectory = 'Custom Script Extension download folder'
        RecoveryInstructions = 'If this step fails, confirm the Azure VM size supports nested virtualization, then rerun the command from an elevated session.'
    }
    @{
        Name = 'WinGet and host configuration'
        Description = 'WinGet/DSC package installation, including Azure CLI, AzCopy, SQL Server Management Studio, Visual Studio Code, and host networking configuration.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\WinGet.ps1'
        Command = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\WinGet.ps1"; applies C:\ArcBox\DSC\common.dsc.yml, which installs Microsoft.AzureCLI, Microsoft.Azure.AZCopy.10, Microsoft.SQLServerManagementStudio, Microsoft.VisualStudioCode, DHCP, and RSAT-DHCP.'
        RerunCommand = 'Start-ScheduledTask -TaskName WinGetLogonScript; or run pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\WinGet.ps1" from an elevated PowerShell session.'
        LogPath = 'C:\ArcBox\Logs\WinGet-provisioning-*.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'If this step fails, rerun WinGet.ps1 after fixing package or DSC errors. It will start ArcServersLogonScript when it completes.'
    }
    @{
        Name = 'Hyper-V network setup'
        Description = 'DHCP, NAT, VM credentials, and Hyper-V host preparation.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        RerunCommand = 'Start-ScheduledTask -TaskName ArcServersLogonScript; or run pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1" from an elevated PowerShell session.'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'This script is idempotent for existing VHDs and VMs. Rerun ArcServersLogonScript after fixing the reported error.'
    }
    @{
        Name = 'Azure resource provider registration'
        Description = 'Azure CLI login and required Arc plus Azure Migrate resource provider registration.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'az login --identity; az account set -s $env:subscriptionId; az provider register --namespace Microsoft.HybridCompute --wait; az provider register --namespace Microsoft.GuestConfiguration --wait; az provider register --namespace Microsoft.Migrate --wait'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the client VM managed identity has subscription Owner access, then rerun ArcServersLogonScript.'
    }
    @{
        Name = 'ArcBox-SQL VM'
        Description = 'SQL nested VM VHD download, Hyper-V VM creation, rename, and firewall preparation.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'Downloads the SQL VHD with AzCopy, applies C:\ArcBox\DSC\virtual_machines_sql.dsc.yml with winget configure, renames the VM if needed, and opens SQL TCP 1433.'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Fix VHD download, disk, or Hyper-V errors, then rerun ArcServersLogonScript. Existing VHDs are reused.'
    }
    @{
        Name = 'Azure Migrate Appliance VM'
        Description = 'Azure Migrate appliance ZIP download, VHD extraction/rename, and Hyper-V VM creation for <prefix>-am (not Arc-enabled by this script).'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'Downloads the Azure Migrate appliance .zip, extracts the appliance .vhd to the Hyper-V storage path as <prefix>-am.vhd, creates Hyper-V VM <prefix>-am on InternalNATSwitch, starts it, and updates hosts mapping.'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Set environment variable azureMigrateApplianceVhdUrl to the appliance ZIP download URL if needed, then rerun ArcServersLogonScript.'
    }
    @{
        Name = 'ArcBox-SQL Arc onboarding'
        Description = 'Azure Connected Machine agent installation and onboarding for the SQL VM.'
        RunsOn = 'Nested VM: SQL'
        ScriptPath = 'C:\ArcBox\agentScript\installArcAgent.ps1 copied into C:\ArcBox\installArcAgent.ps1 on the nested SQL VM'
        Command = 'Invoke-Command -VMName <prefix>-SQL -ScriptBlock { powershell -File C:\ArcBox\installArcAgent.ps1 -accessToken <token> -tenantId <tenant> -subscriptionId <subscription> -resourceGroup <resource group> -azureLocation <location> }'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the nested SQL VM is running and has network access, then rerun ArcServersLogonScript to acquire a fresh token and retry onboarding.'
    }
    @{
        Name = 'ArcBox-Ubuntu VM'
        Description = 'Ubuntu nested VM VHD download, Hyper-V VM creation, SSH preparation, and hostname setup.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'Downloads ArcBox-Ubuntu-01.vhdx with AzCopy, applies C:\ArcBox\DSC\virtual_machines_itpro.dsc.yml with winget configure, configures SSH key access, and sets the hostname.'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Fix VHD download, SSH, or Hyper-V errors, then rerun ArcServersLogonScript. Existing VHDs are reused.'
    }
    @{
        Name = 'ArcBox-SQL website and database'
        Description = 'AdventureWorksLT SQL Server database, IIS, and legacy ASP.NET Web Forms storefront setup.'
        RunsOn = 'Nested VM: SQL'
        ScriptPath = 'C:\ArcBox\Initialize-ArcBoxSqlDemo.ps1 and C:\ArcBox\Configure-IIS.ps1 copied to the nested SQL VM'
        Command = 'Invoke-Command -VMName <prefix>-SQL to run Initialize-ArcBoxSqlDemo.ps1 and Configure-IIS.ps1 with SQL authentication parameters.'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the SQL VM is reachable through PowerShell Direct, then rerun ArcServersLogonScript. The database/site scripts are designed to be rerunnable.'
    }
    @{
        Name = 'ArcBox-Ubuntu website and database'
        Description = 'AdventureWorksLT PostgreSQL schema conversion, Apache/PHP, and legacy PHP storefront setup.'
        RunsOn = 'Nested VM: Ubuntu'
        ScriptPath = 'C:\ArcBox\Configure-Postgres.sh copied to /home/jumpstart/Configure-Postgres.sh on the nested Ubuntu VM'
        Command = 'Invoke-JSSudoCommand -Session <Ubuntu session> -Command "WEB_USER=<user> WEB_PASSWORD=<password> WEB_DB=<db> ALLOW_CIDR=10.10.1.0/24 bash /home/jumpstart/Configure-Postgres.sh"'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm SSH key access to the Ubuntu VM works for user jumpstart, then rerun ArcServersLogonScript.'
    }
    @{
        Name = 'ArcBox-Ubuntu Arc onboarding'
        Description = 'Azure Connected Machine agent installation and onboarding for the Ubuntu VM.'
        RunsOn = 'Nested VM: Ubuntu'
        ScriptPath = 'C:\ArcBox\agentScript\installArcAgentUbuntu.sh rendered as installArcAgentModifiedUbuntu.sh and copied to /home/jumpstart on the nested Ubuntu VM'
        Command = 'Invoke-JSSudoCommand -Session <Ubuntu session> -Command "sh /home/jumpstart/installArcAgentModifiedUbuntu.sh"'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the Ubuntu VM is running and reachable over SSH, then rerun ArcServersLogonScript to render a fresh token and retry onboarding.'
    }
    @{
        Name = 'Time zone configuration'
        Description = 'Aligns the Hyper-V host and both nested VMs (SQL and Ubuntu) to the time zone specified by the template.'
        RunsOn = 'Client VM / Hyper-V host and nested VMs'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'Set-TimeZone -Id <Windows time zone> on the host and SQL VM (via PowerShell Direct); timedatectl set-timezone <IANA time zone> on the Ubuntu VM (via SSH).'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the autoShutdownTimezone value is a valid Windows time zone ID, then rerun ArcServersLogonScript. Setting the time zone is idempotent.'
    }
    @{
        Name = 'Re-enable auto-shutdown'
        Description = 'Re-enables the Azure DevTest Labs auto-shutdown schedule that was temporarily disabled during automation.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\ArcServersLogonScript.ps1'
        Command = 'Invoke-AzRestMethod -Method PUT against the Microsoft.DevTestLab/schedules resource to set properties.status = Enabled.'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\ArcServersLogonScript.ps1"'
        LogPath = 'C:\ArcBox\Logs\ArcServersLogonScript.log'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Confirm the client VM managed identity can write to the schedule resource, then rerun ArcServersLogonScript or enable auto-shutdown from the Azure portal.'
    }
    @{
        Name = 'Deployment report'
        Description = 'Final HTML status report generation and browser launch.'
        RunsOn = 'Client VM / Hyper-V host'
        ScriptPath = 'C:\ArcBox\DeploymentStatus.ps1'
        Command = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\DeploymentStatus.ps1" -Action Report -Open'
        RerunCommand = 'pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ArcBox\DeploymentStatus.ps1" -Action Report -Open'
        LogPath = 'C:\ArcBox\Logs\DeploymentStatus.json and C:\ArcBox\Logs\DeploymentStatus.html'
        WorkingDirectory = 'C:\ArcBox'
        RecoveryInstructions = 'Rerun the report command after Azure CLI login is available if Azure resource status is missing.'
    }
)

function Get-UtcIsoTime {
    (Get-Date).ToUniversalTime().ToString('o')
}

function Convert-ToArray {
    param([object]$Value)
    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [array]) {
        return @($Value)
    }

    return @($Value)
}

function New-StatusState {
    [pscustomobject]@{
        GeneratedAt      = Get-UtcIsoTime
        OverallStatus    = 'Pending'
        OverallStartTime = $null
        OverallStopTime  = $null
        OverallSeconds   = $null
        TotalComponents  = 0
        FinishedComponents = 0
        ProgressPercent  = 0
        Components       = @()
        AzureDeployments = @()
        AzureResources   = @()
        ArcMachines      = @()
        ReportPath       = $htmlPath
    }
}

function Get-StatusState {
    if (Test-Path $statePath) {
        try {
            $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
        }
        catch {
            $state = New-StatusState
        }
    }
    else {
        $state = New-StatusState
    }

    foreach ($propertyName in @('Components', 'AzureDeployments', 'AzureResources', 'ArcMachines')) {
        if (-not ($state.PSObject.Properties.Name -contains $propertyName)) {
            $state | Add-Member -MemberType NoteProperty -Name $propertyName -Value @()
        }
        $state.$propertyName = @(Convert-ToArray -Value $state.$propertyName)
    }

    return $state
}

function Save-StatusState {
    param([pscustomobject]$State)
    $State.GeneratedAt = Get-UtcIsoTime
    $null = New-Item -Path $LogsDir -ItemType Directory -Force
    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $statePath -Encoding UTF8 -Force
}

function Get-Component {
    param(
        [pscustomobject]$State,
        [string]$Name,
        [string]$Description = ''
    )

    $definition = @($defaultComponents | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    $sectionNumber = [array]::IndexOf(@($defaultComponents.Name), $Name) + 1
    if ($sectionNumber -le 0) {
        $sectionNumber = $null
    }
    $metadataFields = @('RunsOn', 'ScriptPath', 'Command', 'RerunCommand', 'LogPath', 'WorkingDirectory', 'RecoveryInstructions')
    if ($definition.Count -gt 0 -and [string]::IsNullOrWhiteSpace($Description)) {
        $Description = $definition[0].Description
    }

    $componentEntry = @($State.Components | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    if ($componentEntry.Count -eq 0) {
        $component = [pscustomobject]@{
            SectionNumber        = $sectionNumber
            Name                 = $Name
            Description          = $Description
            Status               = 'Pending'
            StartTime            = $null
            StopTime             = $null
            TotalSeconds         = $null
            Message              = ''
            RunsOn               = ''
            ScriptPath           = ''
            Command              = ''
            RerunCommand         = ''
            LogPath              = ''
            WorkingDirectory     = ''
            RecoveryInstructions = ''
        }
        if ($definition.Count -gt 0) {
            foreach ($field in $metadataFields) {
                if ($definition[0].ContainsKey($field)) {
                    $component.$field = $definition[0][$field]
                }
            }
        }
        $State.Components = @(Convert-ToArray -Value $State.Components) + $component
        return $component
    }

    $component = $componentEntry[0]
    if (-not ($component.PSObject.Properties.Name -contains 'SectionNumber')) {
        $component | Add-Member -MemberType NoteProperty -Name SectionNumber -Value $sectionNumber
    }
    elseif ($null -ne $sectionNumber -and ($null -eq $component.SectionNumber -or [int]$component.SectionNumber -le 0)) {
        $component.SectionNumber = $sectionNumber
    }

    if ($Description -and [string]::IsNullOrWhiteSpace([string]$component.Description)) {
        $component.Description = $Description
    }

    foreach ($field in $metadataFields) {
        $metadataValue = ''
        if ($definition.Count -gt 0 -and $definition[0].ContainsKey($field)) {
            $metadataValue = $definition[0][$field]
        }

        if (-not ($component.PSObject.Properties.Name -contains $field)) {
            $component | Add-Member -MemberType NoteProperty -Name $field -Value $metadataValue
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$component.$field) -and -not [string]::IsNullOrWhiteSpace([string]$metadataValue)) {
            $component.$field = $metadataValue
        }
    }

    return $component
}

function Initialize-StatusState {
    $state = Get-StatusState
    foreach ($componentDefinition in $defaultComponents) {
        $null = Get-Component -State $state -Name $componentDefinition.Name -Description $componentDefinition.Description
    }
    Save-StatusState -State $state
}

function Set-ComponentStatus {
    param(
        [string]$Name,
        [string]$NewStatus,
        [string]$StatusMessage
    )

    $state = Get-StatusState
    $definition = @($defaultComponents | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    $description = if ($definition.Count -gt 0) { $definition[0].Description } else { '' }
    $component = Get-Component -State $state -Name $Name -Description $description
    $now = Get-UtcIsoTime

    if ($NewStatus -eq 'InProgress' -and [string]::IsNullOrWhiteSpace([string]$component.StartTime)) {
        $component.StartTime = $now
    }

    if ($NewStatus -in @('Completed', 'Failed', 'Skipped')) {
        if ([string]::IsNullOrWhiteSpace([string]$component.StartTime)) {
            $component.StartTime = $now
        }
        $component.StopTime = $now
        $component.TotalSeconds = [math]::Round((New-TimeSpan -Start ([datetime]$component.StartTime) -End ([datetime]$component.StopTime)).TotalSeconds, 1)
    }

    $component.Status = $NewStatus
    if ($StatusMessage) {
        $component.Message = $StatusMessage
    }

    Update-OverallStatus -State $state
    Update-DeploymentProgressTag -State $state -ComponentName $Name -ComponentStatus $NewStatus -StatusMessage $StatusMessage
    Save-StatusState -State $state
}

function Format-Duration {
    param([object]$Seconds)
    if ($null -eq $Seconds -or [string]::IsNullOrWhiteSpace([string]$Seconds)) {
        return '-'
    }

    $duration = [TimeSpan]::FromSeconds([double]$Seconds)
    if ($duration.TotalHours -ge 1) {
        return '{0:00}:{1:00}:{2:00}' -f [math]::Floor($duration.TotalHours), $duration.Minutes, $duration.Seconds
    }

    return '{0:00}:{1:00}' -f $duration.Minutes, $duration.Seconds
}

function Format-DateTime {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return '-'
    }

    return ([datetime]$Value).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
}

function ConvertTo-HtmlText {
    param([object]$Value)
    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-ReportTitle {
    if ([string]::IsNullOrWhiteSpace($env:namingPrefix)) {
        return 'Migration Demo Deployment Status'
    }

    return "$($env:namingPrefix) Migration Demo Deployment Status"
}

function Get-DisplayComponentName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($env:namingPrefix) -or [string]::IsNullOrWhiteSpace($Name)) {
        return $Name
    }

    return ($Name -replace 'ArcBox', $env:namingPrefix)
}

function Get-DisplayText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $displayText = $Text
    if (-not [string]::IsNullOrWhiteSpace($env:namingPrefix)) {
        $displayText = $displayText -replace 'ArcBox', $env:namingPrefix
        $displayText = $displayText -replace 'migdem-am', "$($env:namingPrefix)-am"
        $displayText = $displayText -replace '<prefix>', $env:namingPrefix
    }

    return $displayText
}

function ConvertTo-FileHref {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\') {
        return ''
    }

    return 'file:///' + (($Path -replace '\\', '/') -replace ' ', '%20')
}

function Ensure-AzCliContext {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        return 'Azure CLI was not found on this machine.'
    }

    $null = & az account show --only-show-errors -o none 2>$null
    if ($LASTEXITCODE -ne 0) {
        return 'Azure CLI is not authenticated. Azure resource status could not be collected.'
    }

    if ($SubscriptionId) {
        $null = & az account set --subscription $SubscriptionId --only-show-errors 2>$null
    }

    return $null
}

function Invoke-AzCliJson {
    param([string[]]$Arguments)
    try {
        $output = & az @Arguments 2>&1
        $rawOutput = ($output | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            return @([pscustomobject]@{ Error = $rawOutput })
        }

        if ([string]::IsNullOrWhiteSpace($rawOutput)) {
            return @()
        }

        return @(Convert-ToArray -Value ($rawOutput | ConvertFrom-Json))
    }
    catch {
        return @([pscustomobject]@{ Error = $_.Exception.Message })
    }
}

function Update-OverallStatus {
    param([pscustomobject]$State)

    $components = @(Convert-ToArray -Value $State.Components)
    $failed = @($components | Where-Object { $_.Status -eq 'Failed' })
    $active = @($components | Where-Object { $_.Status -in @('Pending', 'InProgress') })
    $finished = @($components | Where-Object { $_.Status -in @('Completed', 'Failed', 'Skipped') })

    $State.TotalComponents = $components.Count
    $State.FinishedComponents = $finished.Count
    $State.ProgressPercent = if ($components.Count -gt 0) {
        [int][math]::Round((100 * $finished.Count) / $components.Count, 0)
    } else {
        0
    }

    if ($failed.Count -gt 0) {
        $State.OverallStatus = 'Failed'
    }
    elseif ($active.Count -gt 0) {
        $State.OverallStatus = 'InProgress'
    }
    else {
        $State.OverallStatus = 'Completed'
    }

    $started = @($components | Where-Object { $_.StartTime } | ForEach-Object { [datetime]$_.StartTime } | Sort-Object)
    $stopped = @($components | Where-Object { $_.StopTime } | ForEach-Object { [datetime]$_.StopTime } | Sort-Object)
    if ($started.Count -gt 0) {
        $State.OverallStartTime = $started[0].ToUniversalTime().ToString('o')
    }
    if ($stopped.Count -gt 0) {
        $State.OverallStopTime = $stopped[-1].ToUniversalTime().ToString('o')
    }
    if ($State.OverallStartTime -and $State.OverallStopTime) {
        $State.OverallSeconds = [math]::Round((New-TimeSpan -Start ([datetime]$State.OverallStartTime) -End ([datetime]$State.OverallStopTime)).TotalSeconds, 1)
    }
}

function Update-DeploymentProgressTag {
    param(
        [pscustomobject]$State,
        [string]$ComponentName,
        [string]$ComponentStatus,
        [string]$StatusMessage
    )

    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        return
    }

    $component = @($State.Components | Where-Object { $_.Name -eq $ComponentName } | Select-Object -First 1)
    $sectionLabel = Get-DisplayText $ComponentName
    if ($component.Count -gt 0 -and $component[0].SectionNumber) {
        $sectionLabel = '{0}. {1}' -f $component[0].SectionNumber, (Get-DisplayText $component[0].Name)
    }

    $shortDescription = if (-not [string]::IsNullOrWhiteSpace($StatusMessage)) {
        $StatusMessage
    }
    elseif ($component.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$component[0].Description)) {
        $component[0].Description
    }
    else {
        $ComponentStatus
    }

    $shortDescription = [regex]::Replace([string]$shortDescription, '\s+', ' ').Trim()
    $shortDescription = Get-DisplayText $shortDescription
    if ($shortDescription.Length -gt 100) {
        $shortDescription = $shortDescription.Substring(0, 97) + '...'
    }

    $progressText = '{0}% - {1} ({2})' -f $State.ProgressPercent, $sectionLabel, $shortDescription
    if ($progressText.Length -gt 255) {
        $progressText = $progressText.Substring(0, 255)
    }

    try {
        if (-not (Get-Command Get-AzResourceGroup -ErrorAction SilentlyContinue) -or -not (Get-Command Set-AzResourceGroup -ErrorAction SilentlyContinue)) {
            return
        }

        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction Stop
        $tags = @{}
        if ($null -ne $resourceGroup.Tags) {
            foreach ($key in $resourceGroup.Tags.Keys) {
                $tags[$key] = [string]$resourceGroup.Tags[$key]
            }
        }

        $tags['DeploymentProgress'] = $progressText
        $null = Set-AzResourceGroup -ResourceGroupName $ResourceGroup -Tag $tags -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($env:computername) -and (Get-Command Set-AzResource -ErrorAction SilentlyContinue)) {
            $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $ResourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Verbose "Unable to update DeploymentProgress tag: $($_.Exception.Message)"
    }
}

function New-HtmlTable {
    param(
        [object[]]$Rows,
        [string[]]$Columns,
        [string]$EmptyMessage
    )

    $rowsToRender = @(Convert-ToArray -Value $Rows)
    if ($rowsToRender.Count -eq 0) {
        return "<p class='muted'>$EmptyMessage</p>"
    }

    $header = ($Columns | ForEach-Object { '<th>' + (ConvertTo-HtmlText $_) + '</th>' }) -join ''
    $body = ($rowsToRender | ForEach-Object {
        $row = $_
        $cells = ($Columns | ForEach-Object {
            $value = if ($row.PSObject.Properties.Name -contains $_) { $row.$_ } else { '' }
            '<td>' + (ConvertTo-HtmlText $value) + '</td>'
        }) -join ''
        '<tr>' + $cells + '</tr>'
    }) -join [Environment]::NewLine

    return "<table><thead><tr>$header</tr></thead><tbody>$body</tbody></table>"
}

function Write-HtmlReport {
    $state = Get-StatusState
    $azCliMessage = Ensure-AzCliContext

    if ($ResourceGroup -and -not $azCliMessage) {
        $state.AzureDeployments = @(Invoke-AzCliJson -Arguments @('deployment', 'group', 'list', '--resource-group', $ResourceGroup, '--query', '[].{Name:name,ProvisioningState:properties.provisioningState,Timestamp:properties.timestamp,Mode:properties.mode}', '-o', 'json', '--only-show-errors'))
        $state.AzureResources = @(Invoke-AzCliJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroup, '--query', '[].{Name:name,Type:type,Location:location,ProvisioningState:properties.provisioningState}', '-o', 'json', '--only-show-errors'))
        $state.ArcMachines = @(Invoke-AzCliJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroup, '--resource-type', 'Microsoft.HybridCompute/machines', '--query', '[].{Name:name,Location:location,Status:properties.status,ProvisioningState:properties.provisioningState}', '-o', 'json', '--only-show-errors'))
    }
    elseif ($azCliMessage) {
        $state.AzureResources = @([pscustomobject]@{ Name = 'Azure CLI'; Type = 'Status'; Location = ''; ProvisioningState = $azCliMessage })
    }

    Update-OverallStatus -State $state
    Save-StatusState -State $state

    $reportTitle = Get-ReportTitle
    $applianceHostName = if ([string]::IsNullOrWhiteSpace($env:namingPrefix)) { 'migdem-am' } else { "$($env:namingPrefix)-am" }
    $applianceVmConnectShortcutPath = 'C:\ArcBox\Logs\Open Azure Migrate Appliance Console.lnk'
    $applianceVmConnectShortcutHref = ConvertTo-FileHref -Path $applianceVmConnectShortcutPath
    if ([string]::IsNullOrWhiteSpace($applianceVmConnectShortcutHref)) {
        $applianceVmConnectShortcutHref = '#'
    }

    $statusClass = ([string]$state.OverallStatus).ToLowerInvariant()
    $componentCards = (@(Convert-ToArray -Value $state.Components) | ForEach-Object {
        $componentStatusClass = ([string]$_.Status).ToLowerInvariant()
        $scriptMarkup = ConvertTo-HtmlText $_.ScriptPath
        $displayComponentName = Get-DisplayComponentName -Name $_.Name
        $componentTitle = if ($_.SectionNumber) { '{0}. {1}' -f $_.SectionNumber, $displayComponentName } else { $displayComponentName }
@"
        <section class='component-card'>
          <div class='component-heading'>
            <h3>$(ConvertTo-HtmlText $componentTitle)</h3>
            <span class='pill $componentStatusClass'>$(ConvertTo-HtmlText $_.Status)</span>
          </div>
          <p>$(ConvertTo-HtmlText (Get-DisplayText $_.Description))</p>
          <dl>
            <div><dt>Start</dt><dd>$(Format-DateTime $_.StartTime)</dd></div>
            <div><dt>Stop</dt><dd>$(Format-DateTime $_.StopTime)</dd></div>
            <div><dt>Total</dt><dd>$(Format-Duration $_.TotalSeconds)</dd></div>
          </dl>
          <p class='message'>$(ConvertTo-HtmlText (Get-DisplayText $_.Message))</p>
                    <details>
                        <summary>Script and rerun details</summary>
                        <dl class='execution-details'>
                            <div><dt>Runs on</dt><dd>$(ConvertTo-HtmlText (Get-DisplayText $_.RunsOn))</dd></div>
                            <div><dt>Working directory</dt><dd>$(ConvertTo-HtmlText (Get-DisplayText $_.WorkingDirectory))</dd></div>
                            <div><dt>Script</dt><dd>$scriptMarkup</dd></div>
                            <div><dt>Log</dt><dd>$(ConvertTo-HtmlText (Get-DisplayText $_.LogPath))</dd></div>
                        </dl>
                        <div class='command-block'><span>Executed command</span><pre>$(ConvertTo-HtmlText (Get-DisplayText $_.Command))</pre></div>
                        <div class='command-block'><span>Rerun command or action</span><pre>$(ConvertTo-HtmlText (Get-DisplayText $_.RerunCommand))</pre></div>
                        <p class='message'>$(ConvertTo-HtmlText (Get-DisplayText $_.RecoveryInstructions))</p>
                    </details>
        </section>
"@
    }) -join [Environment]::NewLine

    $deploymentTable = New-HtmlTable -Rows $state.AzureDeployments -Columns @('Name', 'ProvisioningState', 'Timestamp', 'Mode') -EmptyMessage 'No Azure deployment records were returned.'
    $resourceTable = New-HtmlTable -Rows $state.AzureResources -Columns @('Name', 'Type', 'Location', 'ProvisioningState') -EmptyMessage 'No Azure resources were returned.'
    $arcTable = New-HtmlTable -Rows $state.ArcMachines -Columns @('Name', 'Location', 'Status', 'ProvisioningState') -EmptyMessage 'No Azure Arc machines were returned.'

    $html = @"
<!doctype html>
<html lang='en'>
<head>
  <meta charset='utf-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>$(ConvertTo-HtmlText $reportTitle)</title>
  <style>
    :root { color-scheme: light; --bg: #f5f7fb; --panel: #ffffff; --ink: #18212f; --muted: #607089; --line: #d9e1ec; --ok: #137333; --warn: #9a6700; --fail: #b3261e; --active: #0b57d0; }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink); font-family: 'Segoe UI', Tahoma, sans-serif; }
    header { background: #102033; color: white; padding: 28px 36px; }
    main { padding: 24px 36px 40px; }
    h1, h2, h3 { margin: 0; font-weight: 650; }
    h1 { font-size: 28px; }
    h2 { margin: 28px 0 14px; font-size: 20px; }
    h3 { font-size: 16px; }
    p { margin: 8px 0 0; color: var(--muted); }
    .summary { display: grid; grid-template-columns: repeat(5, minmax(140px, 1fr)); gap: 14px; margin-top: 18px; }
    .metric, .component-card, .table-card { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 16px; box-shadow: 0 1px 2px rgba(16, 32, 51, 0.06); }
    .metric span { display: block; color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    .metric strong { display: block; margin-top: 8px; font-size: 18px; }
    .pill { display: inline-flex; align-items: center; border-radius: 999px; padding: 4px 10px; font-size: 12px; font-weight: 650; border: 1px solid currentColor; }
    .completed { color: var(--ok); background: #e8f5e9; }
    .failed { color: var(--fail); background: #fce8e6; }
    .inprogress { color: var(--active); background: #e8f0fe; }
    .pending, .skipped { color: var(--warn); background: #fff7e0; }
    .components { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 14px; }
    .component-heading { display: flex; justify-content: space-between; gap: 12px; align-items: center; }
    dl { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 14px 0 0; }
    dt { color: var(--muted); font-size: 12px; }
    dd { margin: 4px 0 0; font-weight: 600; }
    details { margin-top: 14px; border-top: 1px solid var(--line); padding-top: 12px; }
    summary { cursor: pointer; font-weight: 650; color: var(--ink); }
    .execution-details { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .execution-details dd { overflow-wrap: anywhere; }
    .command-block { margin-top: 12px; }
    .command-block span { display: block; color: var(--muted); font-size: 12px; margin-bottom: 4px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; margin: 0; padding: 10px; background: #f8fafc; border: 1px solid var(--line); border-radius: 6px; font-size: 12px; }
    a { color: var(--active); }
    .message { min-height: 20px; }
    .table-card { overflow-x: auto; margin-bottom: 16px; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { border-bottom: 1px solid var(--line); padding: 9px 10px; text-align: left; vertical-align: top; }
    th { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
    .muted { color: var(--muted); }
    @media (max-width: 760px) { header, main { padding-left: 18px; padding-right: 18px; } .summary { grid-template-columns: 1fr; } dl { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <header>
        <h1>$(ConvertTo-HtmlText $reportTitle)</h1>
    <p>Generated $(Format-DateTime $state.GeneratedAt) on $env:COMPUTERNAME</p>
  </header>
  <main>
    <section class='summary'>
      <div class='metric'><span>Overall Status</span><strong><span class='pill $statusClass'>$(ConvertTo-HtmlText $state.OverallStatus)</span></strong></div>
            <div class='metric'><span>Progress</span><strong>$(ConvertTo-HtmlText $state.ProgressPercent)% ($(ConvertTo-HtmlText $state.FinishedComponents)/$(ConvertTo-HtmlText $state.TotalComponents))</strong></div>
      <div class='metric'><span>Start</span><strong>$(Format-DateTime $state.OverallStartTime)</strong></div>
      <div class='metric'><span>Stop</span><strong>$(Format-DateTime $state.OverallStopTime)</strong></div>
      <div class='metric'><span>Total Time</span><strong>$(Format-Duration $state.OverallSeconds)</strong></div>
    </section>

    <div style='margin-top: 20px; display: flex; gap: 14px;'>
      <a href='https://$($env:namingPrefix)-SQL/' target='_blank' class='pill inprogress' style='text-decoration: none;'>Open IIS Website</a>
      <a href='https://$($env:namingPrefix)-pgsql/' target='_blank' class='pill inprogress' style='text-decoration: none;'>Open Ubuntu Website</a>
            <a href='$applianceVmConnectShortcutHref' target='_blank' class='pill inprogress' style='text-decoration: none;'>Open Azure Migrate Appliance VM Console</a>
    </div>

    <h2>Startup Components</h2>
    <section class='components'>
$componentCards
    </section>

    <h2>Azure Deployment Status</h2>
    <section class='table-card'>$deploymentTable</section>

    <h2>Azure Resource Status</h2>
    <section class='table-card'>$resourceTable</section>

    <h2>Azure Arc Machine Status</h2>
    <section class='table-card'>$arcTable</section>
  </main>
</body>
</html>
"@

    $html | Set-Content -Path $htmlPath -Encoding UTF8 -Force
    return $htmlPath
}

function Open-HtmlReport {
    param([string]$Path)
    $edgeCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )
    $edgePath = $edgeCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($edgePath) {
        Start-Process -FilePath $edgePath -ArgumentList "`"$Path`""
    }
    else {
        Start-Process -FilePath $Path
    }
}

switch ($Action) {
    'Init' {
        Initialize-StatusState
    }
    'Start' {
        if ([string]::IsNullOrWhiteSpace($Component)) { throw 'Component is required for Start.' }
        Initialize-StatusState
        Set-ComponentStatus -Name $Component -NewStatus 'InProgress' -StatusMessage $Message
    }
    'Complete' {
        if ([string]::IsNullOrWhiteSpace($Component)) { throw 'Component is required for Complete.' }
        Initialize-StatusState
        Set-ComponentStatus -Name $Component -NewStatus $Status -StatusMessage $Message
    }
    'Report' {
        Initialize-StatusState
        $reportState = Get-StatusState
        $reportComponent = @(Convert-ToArray -Value $reportState.Components | Where-Object { $_.Name -eq 'Deployment report' } | Select-Object -First 1)
        if ($reportComponent.Count -gt 0 -and $reportComponent[0].Status -eq 'InProgress') {
            Set-ComponentStatus -Name 'Deployment report' -NewStatus 'Completed' -StatusMessage 'Final HTML report generated and opened in Microsoft Edge.'
        }
        $reportPath = Write-HtmlReport
        if ($Open) {
            Open-HtmlReport -Path $reportPath
        }
        Write-Output $reportPath
    }
}
