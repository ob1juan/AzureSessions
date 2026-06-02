$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = 'F:\Virtual Machines'
$Env:ArcBoxIconDir = "$Env:ArcBoxDir\Icons"
$Env:ArcBoxTestsDir = "$Env:ArcBoxDir\Tests"
$Env:ArcBoxDscDir = "$Env:ArcBoxDir\DSC"
$agentScript = "$Env:ArcBoxDir\agentScript"

# Set variables to execute remote powershell scripts on guest VMs
$nestedVMArcBoxDir = $Env:ArcBoxDir
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$azureLocation = $env:azureLocation
$resourceGroup = $env:resourceGroup
$namingPrefix = $env:namingPrefix

# Moved VHD storage account details here to keep only in place to prevent duplicates.
$vhdSourceFolder = 'https://jumpstartprodsg.blob.core.windows.net/arcbox/prod/*'

function Write-Header {
    param(
        [string]$Title
    )

    Write-Host
    Write-Host ('#' * ($Title.Length + 8))
    Write-Host "# - $Title"
    Write-Host ('#' * ($Title.Length + 8))
    Write-Host
}

# Archive existing log file and create new one
$logFilePath = "$Env:ArcBoxLogsDir\ArcServersLogonScript.log"
if (Test-Path $logFilePath) {
    $archivefile = "$Env:ArcBoxLogsDir\ArcServersLogonScript-" + (Get-Date -Format 'yyyyMMddHHmmss')
    Rename-Item -Path $logFilePath -NewName $archivefile -Force
}

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

$DeploymentStatusScript = Join-Path -Path $Env:ArcBoxDir -ChildPath 'DeploymentStatus.ps1'
$CurrentDeploymentComponent = 'Hyper-V network setup'

function Start-DeploymentComponent {
    param(
        [string]$Name,
        [string]$Message = ''
    )

    $script:CurrentDeploymentComponent = $Name
    if (Test-Path $script:DeploymentStatusScript) {
        & $script:DeploymentStatusScript -Action Start -Component $Name -Message $Message
    }
}

function Test-ComponentCompleted {
    param([string]$Name)
    $statusFile = "$Env:ArcBoxLogsDir\DeploymentStatus.json"
    if (Test-Path $statusFile) {
        $state = Get-Content $statusFile -Raw | ConvertFrom-Json
        $comp = @($state.Components | Where-Object { $_.Name -eq $Name })
        if ($comp.Count -gt 0 -and $comp[0].Status -eq 'Completed') {
            return $true
        }
    }
    return $false
}

function Complete-DeploymentComponent {
    param(
        [string]$Name = $script:CurrentDeploymentComponent,
        [string]$Message = '',
        [ValidateSet('Completed', 'Failed', 'Skipped')]
        [string]$Status = 'Completed'
    )

    if (Test-Path $script:DeploymentStatusScript) {
        & $script:DeploymentStatusScript -Action Complete -Component $Name -Status $Status -Message $Message
    }
}

function Set-HostFileEntry {
    param(
        [string]$HostName,
        [string]$IPAddress
    )

    if ([string]::IsNullOrWhiteSpace($HostName) -or [string]::IsNullOrWhiteSpace($IPAddress)) {
        throw "Host file entry requires both host name and IP address. HostName='$HostName', IPAddress='$IPAddress'."
    }

    $hostsPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
    $existingLines = if (Test-Path $hostsPath) { Get-Content -Path $hostsPath } else { @() }
    $updatedLines = @(
        foreach ($existingLine in $existingLines) {
            $line = [string]$existingLine
            $tokens = @($line -split '\s+' | Where-Object { $_ })
            if ($tokens.Count -lt 2 -or $tokens[0].StartsWith('#')) {
                $line
                continue
            }

            $aliases = @($tokens[1..($tokens.Count - 1)])
            if (-not ($aliases -contains $HostName)) {
                $line
            }
        }
    )

    $updatedLines += ('{0}`t{1}' -f $IPAddress, $HostName)
    Set-Content -Path $hostsPath -Value $updatedLines -Encoding ASCII -Force
    Write-Output "Updated hosts file: $HostName -> $IPAddress"
}

function Wait-ArcBoxVmRunning {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSeconds = 900
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $vm = Get-VM -Name $Name -ErrorAction Stop
        if ($vm.State -eq 'Running') {
            Write-Host "VM $Name is running."
            return
        }

        if ($vm.State -eq 'Off' -or $vm.State -eq 'Saved') {
            Write-Host "Starting VM $Name. Current state: $($vm.State)"
            Start-VM -Name $Name | Out-Null
        } elseif ($vm.State -eq 'Paused') {
            Write-Host "Resuming VM $Name. Current state: $($vm.State)"
            Resume-VM -Name $Name | Out-Null
        }

        Write-Host "Waiting for VM $Name to start. Current state: $($vm.State)"
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for VM $Name to reach Running state."
}

function Wait-ArcBoxVmIPv4 {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutSeconds = 900
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $ipAddress = Get-VM -Name $Name -ErrorAction Stop |
            Select-Object -ExpandProperty NetworkAdapters |
            Select-Object -ExpandProperty IPAddresses |
            Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
            Select-Object -First 1

        if (-not [string]::IsNullOrWhiteSpace($ipAddress)) {
            Write-Host "VM $Name has IPv4 address $ipAddress."
            return $ipAddress
        }

        Write-Host "Waiting for VM $Name to report an IPv4 address."
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for VM $Name to report an IPv4 address."
}

function Wait-ArcBoxWindowsVmReady {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][pscredential]$Credential,
        [int]$TimeoutSeconds = 900
    )

    Wait-ArcBoxVmRunning -Name $Name -TimeoutSeconds $TimeoutSeconds
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $ready = Invoke-Command -VMName $Name -Credential $Credential -ScriptBlock { 'ready' } -ErrorAction Stop
            if ($ready -contains 'ready') {
                Write-Host "Windows VM $Name is ready for PowerShell Direct commands."
                return
            }
        } catch {
            Write-Host "Waiting for Windows VM $Name PowerShell Direct readiness: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for Windows VM $Name to accept PowerShell Direct commands."
}

function Wait-ArcBoxLinuxSshReady {
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$KeyFilePath,
        [Parameter(Mandatory = $true)][string]$UserName,
        [int]$TimeoutSeconds = 900
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $session = $null
        try {
            $session = New-PSSession -HostName $IPAddress -KeyFilePath $KeyFilePath -UserName $UserName -ErrorAction Stop
            $ready = Invoke-Command -Session $session -ScriptBlock { 'ready' } -ErrorAction Stop
            if ($ready -contains 'ready') {
                Write-Host "Linux VM at $IPAddress is ready for SSH PowerShell commands."
                return
            }
        } catch {
            Write-Host "Waiting for Linux VM at $IPAddress SSH readiness: $($_.Exception.Message)"
        } finally {
            if ($null -ne $session) {
                Remove-PSSession $session -ErrorAction SilentlyContinue
            }
        }

        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for Linux VM at $IPAddress to accept SSH PowerShell commands."
}

trap {
    if (Test-Path $DeploymentStatusScript) {
        Complete-DeploymentComponent -Name $CurrentDeploymentComponent -Status Failed -Message $_.Exception.Message
        & $DeploymentStatusScript -Action Report -Open
    }
    try { Stop-Transcript } catch { }
    throw
}

# Remove registry keys that are used to automatically logon the user (only used for first-time setup)
$registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$keys = @('AutoAdminLogon', 'DefaultUserName', 'DefaultDomainName', 'DefaultPassword', 'ForceAutoLogon')

foreach ($key in $keys) {
    try {
        Get-ItemProperty -Path $registryPath -Name $key -ErrorAction Stop | Out-Null
        Remove-ItemProperty -Path $registryPath -Name $key
        Write-Host "Removed registry key that are used to automatically logon the user: $key"
    } catch {
        Write-Verbose "Key $key does not exist."
    }
}

# Create desktop shortcut for Logs-folder
$WshShell = New-Object -ComObject WScript.Shell
$LogsPath = 'C:\ArcBox\Logs'
$Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Logs.lnk")
$Shortcut.TargetPath = $LogsPath
$shortcut.WindowStyle = 3
$shortcut.Save()

$Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Refresh Azure Deployment Status.lnk")
$Shortcut.TargetPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File C:\ArcBox\DeploymentStatus.ps1 -Action Report -Open"
$shortcut.Save()

# Configure Windows Terminal as the default terminal application
$registryPath = 'HKCU:\Console\%%Startup'

if (Test-Path $registryPath) {
    Set-ItemProperty -Path $registryPath -Name 'DelegationConsole' -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
    Set-ItemProperty -Path $registryPath -Name 'DelegationTerminal' -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
} else {
    New-Item -Path $registryPath -Force | Out-Null
    Set-ItemProperty -Path $registryPath -Name 'DelegationConsole' -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
    Set-ItemProperty -Path $registryPath -Name 'DelegationTerminal' -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
}


################################################
# Setup Hyper-V server before deploying VMs for each flavor
################################################
if ($Env:flavor -ne 'DevOps') {
    if (-not (Test-ComponentCompleted -Name 'Hyper-V network setup')) {
        Start-DeploymentComponent -Name 'Hyper-V network setup' -Message 'Configuring NAT, VM credentials, and Hyper-V host shortcuts.'

        # Create the NAT network
        Write-Host 'Creating Internal NAT'
        $natName = 'InternalNat'
        $netNat = Get-NetNat
        if ($netNat.Name -ne $natName) {
            New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.1.0/24
        }

        Write-Host 'Creating VM Credentials'
        # Hard-coded username and password for the nested VMs
        $nestedWindowsUsername = 'Administrator'
        $nestedWindowsPassword = 'JS123!!'
        
        # Create Windows credential object
        $secWindowsPassword = ConvertTo-SecureString $nestedWindowsPassword -AsPlainText -Force
        $winCreds = New-Object System.Management.Automation.PSCredential ($nestedWindowsUsername, $secWindowsPassword)

        # Creating Hyper-V Manager desktop shortcut
        Write-Host 'Creating Hyper-V Shortcut'
        Copy-Item -Path 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk' -Destination 'C:\Users\All Users\Desktop' -Force

        $cliDir = New-Item -Path "$Env:ArcBoxDir\.cli\" -Name '.servers' -ItemType Directory -Force
        if (-not $($cliDir.Parent.Attributes.HasFlag([System.IO.FileAttributes]::Hidden))) {
            $folder = Get-Item $cliDir.Parent.FullName -ErrorAction SilentlyContinue
            $folder.Attributes += [System.IO.FileAttributes]::Hidden
        }

        Complete-DeploymentComponent -Name 'Hyper-V network setup' -Message 'NAT, credentials, and Hyper-V host shortcuts are ready.'
    }

    if (-not (Test-ComponentCompleted -Name 'Azure resource provider registration')) {
        Start-DeploymentComponent -Name 'Azure resource provider registration' -Message 'Logging in with managed identity and registering required Arc and Azure Migrate providers.'

        # Required for CLI commands
        Write-Header 'Az CLI Login'
        az login --identity
        az account set -s $subscriptionId

        Write-Header 'Register Arc and Azure Migrate resource providers'
        $requiredResourceProviders = @(
            'Microsoft.HybridCompute'
            'Microsoft.GuestConfiguration'
            'Microsoft.Migrate'
        )

        foreach ($providerNamespace in $requiredResourceProviders) {
            $registrationState = (az provider show --namespace $providerNamespace --query registrationState -o tsv --only-show-errors)
            if ($registrationState -ne 'Registered') {
                Write-Host "Registering provider $providerNamespace"
                az provider register --namespace $providerNamespace --wait --only-show-errors
                $registrationState = (az provider show --namespace $providerNamespace --query registrationState -o tsv --only-show-errors)
            }

            if ($registrationState -ne 'Registered') {
                throw "Provider $providerNamespace is in state '$registrationState'. Expected 'Registered'."
            }

            Write-Host "Provider $providerNamespace is Registered"
        }

        Complete-DeploymentComponent -Name 'Azure resource provider registration' -Message 'Required Arc and Azure Migrate resource providers are registered.'
    }

    Write-Header 'Az PowerShell Login'
    Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId

    $DeploymentProgressString = 'Started ArcServersLogonScript'

    $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

    if ($null -ne $tags) {
        $tags['DeploymentProgress'] = $DeploymentProgressString
    } else {
        $tags = @{'DeploymentProgress' = $DeploymentProgressString }
    }

    $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
    $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

    $existingVMDisk = Get-AzDisk -ResourceGroupName $env:resourceGroup | Where-Object name -Like *VMsDisk

    # Update disk IOPS and throughput before downloading nested VMs
    az disk update --resource-group $env:resourceGroup --name $existingVMDisk.Name --disk-iops-read-write 80000 --disk-mbps-read-write 1200

    $vhdImageToDownload = 'ArcBox-SQL-DEV.vhdx'
    if ($Env:sqlServerEdition -eq 'Standard') {
        $vhdImageToDownload = 'ArcBox-SQL-STD.vhdx'
    } elseif ($Env:sqlServerEdition -eq 'Enterprise') {
        $vhdImageToDownload = 'ArcBox-SQL-ENT.vhdx'
    }


    if (-not (Test-ComponentCompleted -Name 'ArcBox-SQL VM')) {
        Start-DeploymentComponent -Name 'ArcBox-SQL VM' -Message 'Downloading SQL VHD and creating the nested SQL Hyper-V VM.'

        $DeploymentProgressString = 'Downloading and configuring nested SQL VM'

        $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

        if ($null -ne $tags) {
            $tags['DeploymentProgress'] = $DeploymentProgressString
        } else {
            $tags = @{'DeploymentProgress' = $DeploymentProgressString }
        }

        $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
        $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

        Write-Host 'Fetching SQL VM'
        $SQLvmName = "$namingPrefix-SQL"
        $SQLvmvhdPath = "$Env:ArcBoxVMDir\$namingPrefix-SQL.vhdx"

        # Verify if VHD files already downloaded especially when re-running this script
        if (!(Test-Path $SQLvmvhdPath)) {
            Write-Output 'Downloading nested VMs VHDX file for SQL. This can take some time, hold tight...'
            azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern "$vhdImageToDownload" --recursive=true --check-length=false --log-level=ERROR

            # Rename VHD file
            Rename-Item -Path "$Env:ArcBoxVMDir\$vhdImageToDownload" -NewName $SQLvmvhdPath -Force
        }

        # Create the nested VMs if not already created
        Write-Header 'Create Hyper-V VMs'

        # Create the nested SQL VMs
        $sqlDscConfigurationFile = "$Env:ArcBoxDscDir\virtual_machines_sql.dsc.yml"
        (Get-Content -Path $sqlDscConfigurationFile) -replace 'namingPrefixStage', $namingPrefix | Set-Content -Path $sqlDscConfigurationFile
        winget configure --file C:\ArcBox\DSC\virtual_machines_sql.dsc.yml --accept-configuration-agreements --disable-interactivity

        # Restarting Windows VM Network Adapters
        Write-Host 'Restarting Network Adapters'
        Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
        Invoke-Command -VMName $SQLvmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        
        Write-Host 'Configuring Static IP for nested SQL VM'
        Invoke-Command -VMName $SQLvmName -ScriptBlock {
            $netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if ($netAdapter) {
                # Remove DHCP and set static IP
                New-NetIPAddress -InterfaceAlias $netAdapter.Name -IPAddress 10.10.1.101 -PrefixLength 24 -DefaultGateway 10.10.1.1 -ErrorAction SilentlyContinue
                Set-DnsClientServerAddress -InterfaceAlias $netAdapter.Name -ServerAddresses ('168.63.129.16', '10.16.2.100')
            }
        } -Credential $winCreds
        
        Start-Sleep -Seconds 20
        Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds

        # Rename server if hostname is not as ArcBox-SQL or doesn't match naming prefix
        $hostname = Invoke-Command -VMName $SQLvmName -ScriptBlock { hostname } -Credential $winCreds

        if ($hostname -ne $SQLvmName) {

            Write-Header 'Renaming the nested SQL VM'
            Invoke-Command -VMName $SQLvmName -ScriptBlock { Rename-Computer -NewName $using:SQLvmName -Restart } -Credential $winCreds

            Write-Host 'Waiting for the nested Windows SQL VM to come back online.'
            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
            Write-Host 'VM has rebooted successfully!'
        }

        # Enable Windows Firewall rule for SQL Server
        Invoke-Command -VMName $SQLvmName -ScriptBlock { New-NetFirewallRule -DisplayName 'Allow SQL Server TCP 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow } -Credential $winCreds

        # Copy installation script to nested Windows VMs
        Write-Output 'Transferring installation script to nested Windows VMs...'
        Copy-VMFile $SQLvmName -SourcePath "$agentScript\installArcAgent.ps1" -DestinationPath "$Env:ArcBoxDir\installArcAgent.ps1" -CreateFullPath -FileSource Host -Force

        Complete-DeploymentComponent -Name 'ArcBox-SQL VM' -Message 'SQL VM is created, renamed, networked, and ready for Arc onboarding.'
    }

    if (-not (Test-ComponentCompleted -Name 'ArcBox-SQL Arc onboarding')) {
        Start-DeploymentComponent -Name 'ArcBox-SQL Arc onboarding' -Message 'Installing the Azure Connected Machine agent on the SQL VM.'

        Write-Header 'Onboarding Arc-enabled servers'

        # Onboarding the nested VMs as Azure Arc-enabled servers
        Write-Output 'Onboarding the nested Windows VMs as Azure Arc-enabled servers'
        $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
        Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\installArcAgent.ps1 -accessToken $using:accessToken, -tenantId $Using:tenantId, -subscriptionId $Using:subscriptionId, -resourceGroup $Using:resourceGroup, -azureLocation $Using:azureLocation } -Credential $winCreds
        Write-Output 'Azure Arc client installation command completed on SQL VM.'
        Complete-DeploymentComponent -Name 'ArcBox-SQL Arc onboarding' -Message 'SQL VM Azure Connected Machine onboarding command completed.'
    }

    # Deploy the single Ubuntu nested VM and configure the two legacy app stacks.
    if ($Env:flavor -eq 'ITPro') {
        if (-not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu VM')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu VM' -Message 'Downloading Ubuntu VHD and creating the nested Ubuntu Hyper-V VM.'

            Write-Header 'Fetching Ubuntu VM'

            $ubuntuVmName = "$namingPrefix-Ubuntu"
            $ubuntuVhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-Ubuntu.vhdx"
            $ubuntuSourceVhdName = 'ArcBox-Ubuntu-01.vhdx'
            $ubuntuSourceVhdPath = Join-Path -Path $Env:ArcBoxVMDir -ChildPath $ubuntuSourceVhdName

            $DeploymentProgressString = 'Downloading and configuring nested VMs'

            $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags

            if ($null -ne $tags) {
                $tags['DeploymentProgress'] = $DeploymentProgressString
            } else {
                $tags = @{'DeploymentProgress' = $DeploymentProgressString }
            }

            $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
            $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

            # Verify if VHD file is already downloaded especially when re-running this script
            if (!(Test-Path $ubuntuVhdPath)) {
                $Env:AZCOPY_BUFFER_GB = 4
                if (!(Test-Path $ubuntuSourceVhdPath)) {
                    Write-Output 'Downloading nested Ubuntu VHDX file. This can take some time, hold tight...'
                    azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern $ubuntuSourceVhdName --recursive=true --check-length=false --log-level=ERROR
                }

                if (!(Test-Path $ubuntuSourceVhdPath)) {
                    throw "Unable to locate downloaded VHDX file $ubuntuSourceVhdName"
                }

                Move-Item -Path $ubuntuSourceVhdPath -Destination $ubuntuVhdPath -Force
            }

            # Update disk IOPS and throughput after downloading nested VMs (note: a disk's performance tier can be downgraded only once every 12 hours)
            az disk update --resource-group $env:resourceGroup --name $existingVMDisk.Name --disk-iops-read-write $existingVMDisk.DiskIOPSReadWrite --disk-mbps-read-write $existingVMDisk.DiskMBpsReadWrite

            # Create the nested Ubuntu VM if not already created
            Write-Header 'Create Hyper-V VM'
            $serversDscConfigurationFile = "$Env:ArcBoxDscDir\virtual_machines_itpro.dsc.yml"
            (Get-Content -Path $serversDscConfigurationFile) -replace 'namingPrefixStage', $namingPrefix | Set-Content -Path $serversDscConfigurationFile
            winget configure --file C:\ArcBox\DSC\virtual_machines_itpro.dsc.yml --accept-configuration-agreements --disable-interactivity

            # Configure static IP via netplan and restart
            $netplanConfig = @"
network:
  version: 2
  ethernets:
    default_cfg:
      match:
        name: e*
      dhcp4: false
      addresses:
        - 10.10.1.102/24
      routes:
        - to: default
          via: 10.10.1.1
      nameservers:
        addresses:
          - 168.63.129.16
          - 10.16.2.100
"@
            $netplanConfig | Set-Content -Path "$Env:TEMP\99-static.yaml" -Force
            
            Start-VM -Name $ubuntuVmName
            Start-Sleep -Seconds 15
            Write-Host 'Applying static IP to Ubuntu via Guest Services'
            Get-VM $ubuntuVmName | Copy-VMFile -SourcePath "$Env:TEMP\99-static.yaml" -DestinationPath "/etc/netplan/99-static.yaml" -FileSource Host -Force -CreateFullPath
            Restart-VM -Name $ubuntuVmName

            # Configure automatic start & stop action for the nested VMs
            foreach ($nestedVm in Get-VM -Name $SQLvmName, $ubuntuVmName) {
                if ($nestedVm.State -eq 'Running') {
                    Stop-VM -Force -Name $nestedVm.Name
                }
                Set-VM -Name $nestedVm.Name -AutomaticStopAction ShutDown -AutomaticStartAction Start
                Start-VM -Name $nestedVm.Name
            }
            Start-Sleep -Seconds 30
            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
            Wait-ArcBoxVmRunning -Name $ubuntuVmName

            Write-Header 'Creating VM Credentials'
            # Hard-coded username and password for the nested Linux VM
            $nestedLinuxUsername = 'jumpstart'

            # Configuring SSH for accessing Linux VMs
            Write-Output 'Generating SSH key for accessing nested Linux VMs'

            $sshDir = Join-Path -Path $Env:USERPROFILE -ChildPath '.ssh'
            $sshKeyPath = Join-Path -Path $sshDir -ChildPath 'id_rsa'
            $null = New-Item -Path $sshDir -ItemType Directory -Force
            if (!(Test-Path $sshKeyPath)) {
                ssh-keygen -t rsa -N '' -f $sshKeyPath
            }

            Copy-Item -Path "$sshKeyPath.pub" -Destination "$Env:TEMP\authorized_keys" -Force

            # Automatically accept unseen keys but will refuse connections for changed or invalid hostkeys.
            $sshConfigPath = Join-Path -Path $sshDir -ChildPath 'config'
            if (!(Test-Path $sshConfigPath) -or -not (Select-String -Path $sshConfigPath -Pattern '^StrictHostKeyChecking=accept-new$' -Quiet)) {
                Add-Content -Path $sshConfigPath -Value 'StrictHostKeyChecking=accept-new'
            }

            Get-VM $ubuntuVmName | Wait-VM -For Heartbeat
            Get-VM $ubuntuVmName | Copy-VMFile -SourcePath "$Env:TEMP\authorized_keys" -DestinationPath "/home/$nestedLinuxUsername/.ssh/" -FileSource Host -Force -CreateFullPath

            # We know the IP because we just set it!
            $ubuntuVmIp = '10.10.1.102'

            Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername

            Write-Output 'Ensuring nested Ubuntu VM hostname matches its Hyper-V name'
            Invoke-Command -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ScriptBlock {
                if ((hostname) -cne $using:ubuntuVmName) {
                    Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntuVmName"
                }
            }

            Write-Host 'Waiting for the nested Linux VM to accept SSH commands.'

            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
            $SQLvmIp = '10.10.1.101'
            Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername

            Write-Output "SQL VM IP    : $SQLvmIp"
            Write-Output "Ubuntu VM IP : $ubuntuVmIp"
            Set-HostFileEntry -HostName $SQLvmName -IPAddress $SQLvmIp
            Set-HostFileEntry -HostName $ubuntuVmName -IPAddress $ubuntuVmIp

            Complete-DeploymentComponent -Name 'ArcBox-Ubuntu VM' -Message "Ubuntu VM is created and reachable at $ubuntuVmIp."
        }

        $arcBoxWebSqlSecret = 'ArcBoxWeb1!'
        $arcBoxWebPgSecret = 'ArcBoxWeb1!'
        $arcBoxWebPgUser = 'arcboxweb'
        $arcBoxWebPgDb = 'arcboxdemo'
        $arcBoxSqlDb = 'ArcBoxDemo'
        $arcBoxWebSqlUser = 'arcboxweb'

        if (-not (Test-ComponentCompleted -Name 'ArcBox-SQL website and database')) {
            Start-DeploymentComponent -Name 'ArcBox-SQL website and database' -Message 'Seeding the AdventureWorksLT SQL database and configuring IIS/ASP.NET on the SQL VM.'
            Write-Header 'Seeding AdventureWorksLT SQL Server and configuring IIS on SQL VM'
            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
            Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\Initialize-ArcBoxSqlDemo.ps1" -DestinationPath "$nestedVMArcBoxDir\Initialize-ArcBoxSqlDemo.ps1" -CreateFullPath -FileSource Host -Force
            Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\Configure-IIS.ps1" -DestinationPath "$nestedVMArcBoxDir\Configure-IIS.ps1" -CreateFullPath -FileSource Host -Force
            $artifactBaseUrl = $Env:templateBaseUrl
            Invoke-Command -VMName $SQLvmName -ScriptBlock {
                Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
                $secureSqlSecret = ConvertTo-SecureString -String $Using:arcBoxWebSqlSecret -AsPlainText -Force
                $webSqlCredential = New-Object System.Management.Automation.PSCredential ($Using:arcBoxWebSqlUser, $secureSqlSecret)
                & (Join-Path -Path $Using:nestedVMArcBoxDir -ChildPath 'Initialize-ArcBoxSqlDemo.ps1') -WebSqlCredential $webSqlCredential
                powershell.exe -ExecutionPolicy Bypass -File $Using:nestedVMArcBoxDir\Configure-IIS.ps1 `
                    -SqlServerAddress 'localhost' `
                    -SqlDatabase $Using:arcBoxSqlDb `
                    -SqlUser $Using:arcBoxWebSqlUser `
                    -SqlPassword $Using:arcBoxWebSqlSecret `
                    -ArtifactBaseUrl $Using:artifactBaseUrl
            } -Credential $winCreds
            Complete-DeploymentComponent -Name 'ArcBox-SQL website and database' -Message "AdventureWorks SQL Server storefront is configured at http://$SQLvmIp/."
            
            $Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\IIS Website.lnk")
            $Shortcut.TargetPath = "http://$SQLvmIp/"
            $shortcut.Save()
        }

        if (-not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu website and database')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu website and database' -Message 'Installing the AdventureWorksLT PostgreSQL conversion and PHP storefront on Ubuntu.'
            Write-Header 'Installing PostgreSQL AdventureWorks storefront on Ubuntu VM'
            $ubuntuVmIp = '10.10.1.102'
            Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
            
            # Using copy-item over SSH instead of Guest Services due to intermittent failures
            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
            Copy-Item -Path "$Env:ArcBoxDir\Configure-Postgres.sh" -Destination "/home/$nestedLinuxUsername/Configure-Postgres.sh" -ToSession $ubuntuSession -Force
            
            Invoke-Command -Session $ubuntuSession -ScriptBlock {
                $scriptPath = "/home/$using:nestedLinuxUsername/Configure-Postgres.sh"
                (Get-Content -Path $scriptPath) | Set-Content -Path $scriptPath
                chmod +x "/home/$using:nestedLinuxUsername/Configure-Postgres.sh"
            }
            Invoke-JSSudoCommand -Session $ubuntuSession -Command "WEB_USER='$arcBoxWebPgUser' WEB_PASSWORD='$arcBoxWebPgSecret' WEB_DB='$arcBoxWebPgDb' ALLOW_CIDR='10.10.1.0/24' bash /home/$nestedLinuxUsername/Configure-Postgres.sh"
            Remove-PSSession $ubuntuSession
            Complete-DeploymentComponent -Name 'ArcBox-Ubuntu website and database' -Message "AdventureWorks PostgreSQL storefront is configured at http://$ubuntuVmIp/."
            
            $Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Ubuntu Website.lnk")
            $Shortcut.TargetPath = "http://$ubuntuVmIp/"
            $shortcut.Save()
        }

        if (-not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu Arc onboarding')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu Arc onboarding' -Message 'Installing the Azure Connected Machine agent on the Ubuntu VM.'
            # Update Linux VM onboarding script connect to Azure Arc, get new token as it might have been expired by the time execution reached this line.
            $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
            (Get-Content -Path "$agentScript\installArcAgentUbuntu.sh" -Raw) -replace '\$accessToken', "'$accessToken'" -replace '\$resourceGroup', "'$resourceGroup'" -replace '\$tenantId', "'$Env:tenantId'" -replace '\$azureLocation', "'$Env:azureLocation'" -replace '\$subscriptionId', "'$subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu.sh"

            # Copy installation script to nested Linux VM
            Write-Output 'Transferring installation script to nested Linux VM...'

            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
            Copy-Item -Path "$agentScript\installArcAgentModifiedUbuntu.sh" -Destination "/home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh" -ToSession $ubuntuSession -Force

            Write-Header 'Onboarding Arc-enabled servers'

            Write-Output 'Onboarding the nested Linux VM as an Azure Arc-enabled server'
            Invoke-Command -Session $ubuntuSession -ScriptBlock {
                $scriptPath = "/home/$using:nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
                (Get-Content -Path $scriptPath) | Set-Content -Path $scriptPath
                chmod +x "/home/$using:nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
            }
            Invoke-JSSudoCommand -Session $ubuntuSession -Command "sh /home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
            Remove-PSSession $ubuntuSession
            Complete-DeploymentComponent -Name 'ArcBox-Ubuntu Arc onboarding' -Message 'Ubuntu VM Azure Connected Machine onboarding command completed.'
        }
        
        Write-Header 'Setting up Self-Signed Certificates'
        if (-not (Test-ComponentCompleted -Name 'Certificates Setup')) {
            Start-DeploymentComponent -Name 'Certificates Setup' -Message 'Generating and installing self-signed certificates'
            $cert = New-SelfSignedCertificate -DnsName "$SQLvmName","$ubuntuVmName" -CertStoreLocation Cert:\LocalMachine\My
            $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList Root, LocalMachine
            $rootStore.Open('ReadWrite')
            $rootStore.Add($cert)
            $rootStore.Close()
            
            $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            $certBase64 = [Convert]::ToBase64String($certBytes)

            Invoke-Command -VMName $SQLvmName -Credential $winCreds -ScriptBlock {
                $certB64 = $using:certBase64
                $bytes = [Convert]::FromBase64String($certB64)
                $innerCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,$bytes)
                $rStore = New-Object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::Root, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
                $rStore.Open('ReadWrite')
                $rStore.Add($innerCert)
                $rStore.Close()
            }
            
            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
            Invoke-Command -Session $ubuntuSession -ScriptBlock {
                $certString = "-----BEGIN CERTIFICATE-----`n" + $using:certBase64 + "`n-----END CERTIFICATE-----"
                $certString | sudo tee /usr/local/share/ca-certificates/hyperv-host.crt > /dev/null
                sudo update-ca-certificates
            }
            Remove-PSSession $ubuntuSession
            Complete-DeploymentComponent -Name 'Certificates Setup' -Message 'Certificates configured'
        }

        Write-Header "AdventureWorks SQL Server storefront reachable at http://$SQLvmIp/"
        Write-Header "AdventureWorks PostgreSQL storefront reachable at http://$ubuntuVmIp/"
    }

    Start-DeploymentComponent -Name 'Deployment report' -Message 'Collecting Azure deployment/resource status and writing the final HTML report.'

    $DeploymentProgressString = 'Completed'
    $tags = Get-AzResourceGroup -Name $env:resourceGroup | Select-Object -ExpandProperty Tags
    if ($null -ne $tags) {
        $tags['DeploymentProgress'] = $DeploymentProgressString
        $tags['DeploymentStatus'] = 'Completed'
    } else {
        $tags = @{
            'DeploymentProgress' = $DeploymentProgressString
            'DeploymentStatus' = 'Completed'
        }
    }

    $null = Set-AzResourceGroup -ResourceGroupName $env:resourceGroup -Tag $tags
    $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $env:resourceGroup -ResourceType 'microsoft.compute/virtualmachines' -Tag $tags -Force

    if (Test-Path $DeploymentStatusScript) {
        & $DeploymentStatusScript -Action Report -Open
    }

    # Removing the LogonScript Scheduled Task so it won't run on next reboot
    Write-Header 'Removing Logon Task'
    if ($null -ne (Get-ScheduledTask -TaskName 'ArcServersLogonScript' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName 'ArcServersLogonScript' -Confirm:$false
    }

    Stop-Transcript
}