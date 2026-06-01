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

# Archive existing log file and create new one
$logFilePath = "$Env:ArcBoxLogsDir\ArcServersLogonScript.log"
if (Test-Path $logFilePath) {
    $archivefile = "$Env:ArcBoxLogsDir\ArcServersLogonScript-" + (Get-Date -Format 'yyyyMMddHHmmss')
    Rename-Item -Path $logFilePath -NewName $archivefile -Force
}

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

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
    # Install and configure DHCP service (used by Hyper-V nested VMs)
    Write-Host 'Configuring DHCP Service'
    $dnsClient = Get-DnsClient | Where-Object { $_.InterfaceAlias -eq 'Ethernet' }
    $dhcpScope = Get-DhcpServerv4Scope
    if ($dhcpScope.Name -ne 'ArcBox') {
        Add-DhcpServerv4Scope -Name 'ArcBox' `
            -StartRange 10.10.1.100 `
            -EndRange 10.10.1.200 `
            -SubnetMask 255.255.255.0 `
            -LeaseDuration 1.00:00:00 `
            -State Active
    }

    $dhcpOptions = Get-DhcpServerv4OptionValue
    if ($dhcpOptions.Count -lt 3) {
        Set-DhcpServerv4OptionValue -ComputerName localhost `
            -DnsDomain $dnsClient.ConnectionSpecificSuffix `
            -DnsServer 168.63.129.16, 10.16.2.100 `
            -Router 10.10.1.1 `
            -Force
    }

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

    # Required for CLI commands
    Write-Header 'Az CLI Login'
    az login --identity
    az account set -s $subscriptionId

    Write-Header 'Register Arc resource providers'
    $requiredResourceProviders = @(
        'Microsoft.HybridCompute'
        'Microsoft.GuestConfiguration'
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
    Start-Sleep -Seconds 5
    Invoke-Command -VMName $SQLvmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
    Start-Sleep -Seconds 20

    # Rename server if hostname is not as ArcBox-SQL or doesn't match naming prefix
    $hostname = Invoke-Command -VMName $SQLvmName -ScriptBlock { hostname } -Credential $winCreds

    if ($hostname -ne $SQLvmName) {

        Write-Header 'Renaming the nested SQL VM'
        Invoke-Command -VMName $SQLvmName -ScriptBlock { Rename-Computer -NewName $using:SQLvmName -Restart } -Credential $winCreds

        Get-VM *SQL* | Wait-VM -For IPAddress

        Write-Host 'Waiting for the nested Windows SQL VM to come back online...waiting for 30 seconds'
        Start-Sleep -Seconds 30

        # Wait for VM to start again
        while ((Get-VM -vmName $SQLvmName).State -ne 'Running') {
            Write-Host 'Waiting for VM to start...'
            Start-Sleep -Seconds 5
        }

        Write-Host 'VM has rebooted successfully!'
    }

    # Enable Windows Firewall rule for SQL Server
    Invoke-Command -VMName $SQLvmName -ScriptBlock { New-NetFirewallRule -DisplayName 'Allow SQL Server TCP 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow } -Credential $winCreds

    # Copy installation script to nested Windows VMs
    Write-Output 'Transferring installation script to nested Windows VMs...'
    Copy-VMFile $SQLvmName -SourcePath "$agentScript\installArcAgent.ps1" -DestinationPath "$Env:ArcBoxDir\installArcAgent.ps1" -CreateFullPath -FileSource Host -Force

    Write-Header 'Onboarding Arc-enabled servers'

    # Onboarding the nested VMs as Azure Arc-enabled servers
    Write-Output 'Onboarding the nested Windows VMs as Azure Arc-enabled servers'
    $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
    Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\installArcAgent.ps1 -accessToken $using:accessToken, -tenantId $Using:tenantId, -subscriptionId $Using:subscriptionId, -resourceGroup $Using:resourceGroup, -azureLocation $Using:azureLocation } -Credential $winCreds
    Write-Output 'Azure Arc client installation command completed on SQL VM.'

    # Deploy the single Ubuntu nested VM and configure the two legacy app stacks.
    if ($Env:flavor -eq 'ITPro') {
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

        # Configure automatic start & stop action for the nested VMs
        Get-VM -Name $SQLvmName, $ubuntuVmName | Where-Object { $_.State -eq 'Running' } |
            ForEach-Object -Parallel {
                Stop-VM -Force -Name $PSItem.Name
                Set-VM -Name $PSItem.Name -AutomaticStopAction ShutDown -AutomaticStartAction Start
                Start-VM -Name $PSItem.Name
            }
        Start-Sleep -Seconds 30

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
        Get-VM $ubuntuVmName | Wait-VM -For IPAddress

        $ubuntuVmIp = Get-VM -Name $ubuntuVmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

        Write-Output 'Ensuring nested Ubuntu VM hostname matches its Hyper-V name'
        Invoke-Command -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ScriptBlock {
            if ((hostname) -cne $using:ubuntuVmName) {
                Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntuVmName"
            }
        }

        Get-VM $ubuntuVmName | Wait-VM -For IPAddress

        Write-Host 'Waiting for the nested Linux VM to come back online...waiting for 10 seconds'

        Start-Sleep -Seconds 10

        $SQLvmIp = Get-VM -Name $SQLvmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        $ubuntuVmIp = Get-VM -Name $ubuntuVmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

        Write-Output "SQL VM IP    : $SQLvmIp"
        Write-Output "Ubuntu VM IP : $ubuntuVmIp"

        $arcBoxWebSqlPassword = 'ArcBoxWeb1!'
        $arcBoxWebPgPassword = 'ArcBoxWeb1!'
        $arcBoxWebPgUser = 'arcboxweb'
        $arcBoxWebPgDb = 'arcboxdemo'
        $arcBoxSqlDb = 'ArcBoxDemo'
        $arcBoxWebSqlUser = 'arcboxweb'

        Write-Header 'Seeding SQL Server and configuring IIS on SQL VM'
        Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\Initialize-ArcBoxSqlDemo.ps1" -DestinationPath "$nestedVMArcBoxDir\Initialize-ArcBoxSqlDemo.ps1" -CreateFullPath -FileSource Host -Force
        Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\Configure-IIS.ps1" -DestinationPath "$nestedVMArcBoxDir\Configure-IIS.ps1" -CreateFullPath -FileSource Host -Force
        $artifactBaseUrl = $Env:templateBaseUrl
        Invoke-Command -VMName $SQLvmName -ScriptBlock {
            powershell.exe -ExecutionPolicy Bypass -File $Using:nestedVMArcBoxDir\Initialize-ArcBoxSqlDemo.ps1 -WebSqlPassword $Using:arcBoxWebSqlPassword
            powershell.exe -ExecutionPolicy Bypass -File $Using:nestedVMArcBoxDir\Configure-IIS.ps1 `
                -SqlServerAddress 'localhost' `
                -SqlDatabase $Using:arcBoxSqlDb `
                -SqlUser $Using:arcBoxWebSqlUser `
                -SqlPassword $Using:arcBoxWebSqlPassword `
                -ArtifactBaseUrl $Using:artifactBaseUrl
        } -Credential $winCreds

        Write-Header 'Installing PostgreSQL and web services on Ubuntu VM'
        Get-VM $ubuntuVmName | Copy-VMFile -SourcePath "$Env:ArcBoxDir\Configure-Postgres.sh" -DestinationPath "/home/$nestedLinuxUsername/Configure-Postgres.sh" -FileSource Host -Force -CreateFullPath
        $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
        Invoke-Command -Session $ubuntuSession -ScriptBlock {
            chmod +x "/home/$using:nestedLinuxUsername/Configure-Postgres.sh"
        }
        Invoke-JSSudoCommand -Session $ubuntuSession -Command "WEB_USER='$arcBoxWebPgUser' WEB_PASSWORD='$arcBoxWebPgPassword' WEB_DB='$arcBoxWebPgDb' ALLOW_CIDR='10.10.1.0/24' bash /home/$nestedLinuxUsername/Configure-Postgres.sh"
        Remove-PSSession $ubuntuSession

        # Update Linux VM onboarding script connect to Azure Arc, get new token as it might have been expired by the time execution reached this line.
        $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
        (Get-Content -Path "$agentScript\installArcAgentUbuntu.sh" -Raw) -replace '\$accessToken', "'$accessToken'" -replace '\$resourceGroup', "'$resourceGroup'" -replace '\$tenantId', "'$Env:tenantId'" -replace '\$azureLocation', "'$Env:azureLocation'" -replace '\$subscriptionId', "'$subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu.sh"

        # Copy installation script to nested Linux VM
        Write-Output 'Transferring installation script to nested Linux VM...'

        Get-VM $ubuntuVmName | Copy-VMFile -SourcePath "$agentScript\installArcAgentModifiedUbuntu.sh" -DestinationPath "/home/$nestedLinuxUsername" -FileSource Host -Force

        Write-Header 'Onboarding Arc-enabled servers'

        Write-Output 'Onboarding the nested Linux VM as an Azure Arc-enabled server'
        $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
        Invoke-JSSudoCommand -Session $ubuntuSession -Command "sh /home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
        Remove-PSSession $ubuntuSession

        Write-Header "Legacy SQL site reachable at http://$SQLvmIp/"
        Write-Header "Legacy PostgreSQL site reachable at http://$ubuntuVmIp/"
    }

    # Removing the LogonScript Scheduled Task so it won't run on next reboot
    Write-Header 'Removing Logon Task'
    if ($null -ne (Get-ScheduledTask -TaskName 'ArcServersLogonScript' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName 'ArcServersLogonScript' -Confirm:$false
    }
}