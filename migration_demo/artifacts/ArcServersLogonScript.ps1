param(
    # One or more deployment component names to force re-run, even if a previous run already marked
    # them Completed (e.g. -ForceComponents 'ArcBox-Ubuntu VM','Certificates Setup').
    [string[]]$ForceComponents = @(),

    # Force every deployment component to re-run, ignoring previously recorded Completed status.
    [switch]$ForceAllComponents
)

$ErrorActionPreference = if ([string]::IsNullOrWhiteSpace($env:ErrorActionPreference)) { 'Continue' } else { $env:ErrorActionPreference }

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
$autoShutdownTimezone = $env:autoShutdownTimezone

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

# Resolve which components should be forced to re-run. Values can come from the script parameters
# or, so the behavior also works when the script is relaunched by the scheduled task, from the
# 'forceComponents' / 'forceAllComponents' environment variables. Component names match the -Name
# values passed to Start-/Complete-DeploymentComponent (e.g. 'ArcBox-Ubuntu VM').
if ((-not $ForceComponents -or $ForceComponents.Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($env:forceComponents)) {
    $ForceComponents = @($env:forceComponents -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
if (-not $ForceAllComponents -and $env:forceAllComponents -eq 'true') {
    $ForceAllComponents = $true
}
$script:ForceComponents = @($ForceComponents | Where-Object { $_ })
$script:ForceAllComponents = [bool]$ForceAllComponents
if ($script:ForceAllComponents) {
    Write-Host 'Force re-run requested for ALL deployment components; previously completed components will be re-deployed.'
} elseif ($script:ForceComponents.Count -gt 0) {
    Write-Host "Force re-run requested for components: $($script:ForceComponents -join ', ')"
}

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

    # Honor on-demand force re-run requests: treating a component as "not completed" makes the
    # guarding 'if (-not (Test-ComponentCompleted ...))' block execute again.
    if ($script:ForceAllComponents) {
        return $false
    }
    if ($script:ForceComponents -and ($script:ForceComponents -contains $Name)) {
        return $false
    }

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

function ConvertTo-ArcBoxDhcpClientId {
    param([Parameter(Mandatory = $true)][string]$MacAddress)

    $hex = ($MacAddress -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    if ($hex.Length -ne 12) {
        throw "Invalid MAC address '$MacAddress'. Expected 12 hexadecimal digits."
    }

    return (($hex -split '(.{2})' | Where-Object { $_ }) -join '-')
}

function Get-ArcBoxHostDnsServers {
    param(
        [string]$InternalInterfaceAlias = 'vEthernet (InternalNATSwitch)'
    )

    $dnsServers = @()
    $defaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object -Property RouteMetric, InterfaceMetric |
        Select-Object -First 1

    if ($null -ne $defaultRoute) {
        $dnsServers = @(Get-DnsClientServerAddress -InterfaceIndex $defaultRoute.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ServerAddresses)
    }

    if ($dnsServers.Count -eq 0) {
        $candidateInterfaceIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' -and $_.Name -ne $InternalInterfaceAlias -and $_.Name -notlike 'vEthernet*' } |
            Select-Object -ExpandProperty ifIndex)

        foreach ($interfaceIndex in $candidateInterfaceIndexes) {
            $dnsServers += @(Get-DnsClientServerAddress -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty ServerAddresses)
        }
    }

    $dnsServers = @($dnsServers |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -ne '10.10.1.1' } |
        Select-Object -Unique)

    if ($dnsServers.Count -eq 0) {
        throw 'Unable to read DNS servers from the Azure VM network adapter.'
    }

    return $dnsServers
}

function Ensure-ArcBoxDhcpScope {
    <#
    .SYNOPSIS
    Configures the Hyper-V host DHCP service for the ArcBox InternalNAT network.

    .DESCRIPTION
    New-NetNat only provides NAT; it does not hand out addresses. The Ubuntu image uses DHCP for
    initial networking, so the host must provide a real DHCP scope. The
    DHCP role is installed on demand when missing; this function makes the runtime configuration
    idempotent and can be called safely after re-runs or partial deployments.
    #>
    param(
        [string]$ScopeId = '10.10.1.0',
        [string]$ScopeName = 'ArcBox Internal NAT',
        [string]$StartRange = '10.10.1.100',
        [string]$EndRange = '10.10.1.200',
        [string]$SubnetMask = '255.255.255.0',
        [string]$Router = '10.10.1.1',
        [string[]]$DnsServers = @(),
        [timespan]$LeaseDuration = ([timespan]::FromDays(1)),
        [string]$InterfaceAlias = 'vEthernet (InternalNATSwitch)'
    )

    if ($DnsServers.Count -eq 0) {
        $DnsServers = @(Get-ArcBoxHostDnsServers -InternalInterfaceAlias $InterfaceAlias)
    }

    if (-not (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
        Import-Module DhcpServer -ErrorAction SilentlyContinue
    }
    if (-not (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) -and $PSVersionTable.PSEdition -eq 'Core') {
        Import-Module DhcpServer -UseWindowsPowerShell -ErrorAction SilentlyContinue
    }

    if (-not (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue)) {
        Import-Module ServerManager -ErrorAction SilentlyContinue
        if (-not (Get-Command -Name Install-WindowsFeature -ErrorAction SilentlyContinue) -and $PSVersionTable.PSEdition -eq 'Core') {
            Import-Module ServerManager -UseWindowsPowerShell -ErrorAction SilentlyContinue
        }

        if (Get-Command -Name Install-WindowsFeature -ErrorAction SilentlyContinue) {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
        } else {
            throw 'DHCP Server PowerShell cmdlets are not available and Install-WindowsFeature was not found. Install the Windows DHCP Server role on the Hyper-V host.'
        }

        Import-Module DhcpServer -ErrorAction SilentlyContinue
        if (-not (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) -and $PSVersionTable.PSEdition -eq 'Core') {
            Import-Module DhcpServer -UseWindowsPowerShell -ErrorAction Stop
        }
    }

    if (Get-Command -Name Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue) {
        Add-DhcpServerSecurityGroup -ErrorAction SilentlyContinue
    }
    Set-Service -Name DHCPServer -StartupType Automatic -ErrorAction SilentlyContinue
    if ((Get-Service -Name DHCPServer -ErrorAction Stop).Status -ne 'Running') {
        Start-Service -Name DHCPServer -ErrorAction Stop
    }

    $scope = Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue
    if ($null -eq $scope) {
        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $StartRange -EndRange $EndRange -SubnetMask $SubnetMask -LeaseDuration $LeaseDuration -State Active -ErrorAction Stop | Out-Null
    } else {
        Set-DhcpServerv4Scope -ScopeId $ScopeId -Name $ScopeName -LeaseDuration $LeaseDuration -State Active -ErrorAction Stop
    }

    Write-Host "Configuring DHCP DNS servers from Azure VM DNS settings: $($DnsServers -join ', ')"
    Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer $DnsServers -ErrorAction Stop

    if (Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue) {
        $bindings = @(Get-DhcpServerv4Binding -ErrorAction SilentlyContinue)
        foreach ($binding in $bindings) {
            Set-DhcpServerv4Binding -InterfaceAlias $binding.InterfaceAlias -BindingState ($binding.InterfaceAlias -eq $InterfaceAlias) -ErrorAction SilentlyContinue
        }
        Set-DhcpServerv4Binding -InterfaceAlias $InterfaceAlias -BindingState $true -ErrorAction SilentlyContinue
    } else {
        Write-Warning "DHCP scope '$ScopeName' is configured, but interface '$InterfaceAlias' was not found for DHCP binding."
    }
}

function Set-ArcBoxDhcpReservation {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$MacAddress,
        [string]$ScopeId = '10.10.1.0'
    )

    Ensure-ArcBoxDhcpScope -ScopeId $ScopeId

    $clientId = ConvertTo-ArcBoxDhcpClientId -MacAddress $MacAddress
    $normalizedClientId = ($clientId -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
    $existingReservations = @(Get-DhcpServerv4Reservation -ScopeId $ScopeId -ErrorAction SilentlyContinue)
    foreach ($reservation in $existingReservations) {
        $reservationClientId = ([string]$reservation.ClientId -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
        if ($reservation.IPAddress.IPAddressToString -eq $IPAddress -or $reservationClientId -eq $normalizedClientId) {
            Remove-DhcpServerv4Reservation -ScopeId $ScopeId -ClientId $reservation.ClientId -ErrorAction SilentlyContinue
        }
    }

    Add-DhcpServerv4Reservation -ScopeId $ScopeId -IPAddress $IPAddress -ClientId $clientId -Name $Name -Description "ArcBox reserved address for $Name" -ErrorAction Stop | Out-Null

    Get-DhcpServerv4Lease -ScopeId $ScopeId -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress.IPAddressToString -eq $IPAddress -or
            (([string]$_.ClientId -replace '[^0-9A-Fa-f]', '').ToUpperInvariant() -eq $normalizedClientId)
        } |
        ForEach-Object { Remove-DhcpServerv4Lease -IPAddress $_.IPAddress -ErrorAction SilentlyContinue }

    Write-Host "DHCP reservation configured: $Name ($clientId) -> $IPAddress"
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
        [int]$TimeoutSeconds = 600
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
        [int]$TimeoutSeconds = 600
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

function Get-ArcBoxVmInternalIPv4 {
    <#
    .SYNOPSIS
    Returns the IPv4 address a VM actually obtained on the ArcBox internal subnet, read over
    Hyper-V KVP (no host-to-guest networking required).

    .DESCRIPTION
    Ubuntu's default netplan/systemd-networkd sends a DUID-based DHCP client identifier (RFC 4361)
    rather than its MAC, so the Hyper-V host's MAC-based reservation is frequently not matched and
    the VM receives the first free pool address instead of its reserved IP. Callers should therefore
    use whichever internal-subnet address the VM actually leased rather than assuming the reservation.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$SubnetPrefix = '10.10.1.',
        [int]$TimeoutSeconds = 600
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $ipAddress = @(Get-VM -Name $Name -ErrorAction Stop |
            Select-Object -ExpandProperty NetworkAdapters |
            Select-Object -ExpandProperty IPAddresses |
            Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_.StartsWith($SubnetPrefix) }) |
            Select-Object -First 1

        if (-not [string]::IsNullOrWhiteSpace($ipAddress)) {
            Write-Host "VM $Name reported internal IPv4 address $ipAddress."
            return $ipAddress
        }

        Write-Host "Waiting for VM $Name to report an IPv4 address in $SubnetPrefix*."
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for VM $Name to report an internal IPv4 address in $SubnetPrefix*."
}

function Set-ArcBoxLinuxVmAuthorizedKey {
    <#
    .SYNOPSIS
    Installs the host's SSH public key into a nested Linux VM's authorized_keys using a one-time
    password-authenticated SSH session, so all later key-based SSH/PowerShell-remoting calls work.

    .DESCRIPTION
    The cloud-init seed that previously delivered ssh_authorized_keys was removed, and the Hyper-V
    VMBus file-copy path (Copy-VMFile / Guest Service Interface) is not serviced by this Ubuntu
    image's guest daemon (it fails with 0x80004005). Because the image ships the 'jumpstart' user
    with a known password and SSH is reachable over the host DHCP network, this uses that password
    once (via the Posh-SSH module, which supports password credentials on both Windows PowerShell
    5.1 and PowerShell 7) to append the public key and set correct ~/.ssh ownership/permissions.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$PublicKeyPath,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [int]$TimeoutSeconds = 600
    )

    if (-not (Test-Path -Path $PublicKeyPath)) {
        throw "SSH public key not found for installation on '$IPAddress': $PublicKeyPath"
    }

    # After the first run the key is already installed, so prefer the generated id file: probe
    # key-based auth non-interactively and, if it already works, skip the password bootstrap (and
    # the Posh-SSH/password dependency) entirely. The private key sits next to the public key.
    $privateKeyPath = $PublicKeyPath -replace '\.pub$', ''
    if (Test-Path -Path $privateKeyPath) {
        & ssh -i $privateKeyPath -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$UserName@$IPAddress" 'true' 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SSH key auth to '$UserName@$IPAddress' already works; using the generated id file."
            return
        }
    }

    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        Write-Host 'Installing Posh-SSH module for the password-authenticated SSH key bootstrap.'
        try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
        if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
        Install-Module -Name Posh-SSH -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module Posh-SSH -ErrorAction Stop

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($UserName, $securePassword)

    # Wait until the guest accepts a password SSH session, then install the key. Retry because the
    # VM may still be finishing first boot when this runs.
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $session = $null
    while ($null -eq $session) {
        try {
            $session = New-SSHSession -ComputerName $IPAddress -Credential $credential -AcceptKey -Force -ConnectionTimeout 30 -ErrorAction Stop
        } catch {
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting to bootstrap the SSH key on '$IPAddress' using password authentication: $($_.Exception.Message)"
            }
            Write-Host "Waiting for password SSH on '$IPAddress' to bootstrap the SSH key: $($_.Exception.Message)"
            Start-Sleep -Seconds 10
        }
    }

    try {
        # The public key is a single line with no single quotes, so it is safe inside single quotes.
        $publicKey = (Get-Content -Path $PublicKeyPath -Raw).Trim()
        $installKeyCommand = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && grep -qxF '$publicKey' ~/.ssh/authorized_keys || printf '%s\n' '$publicKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $installKeyCommand -ErrorAction Stop
        if ($result.ExitStatus -ne 0) {
            throw "Failed to install SSH public key on '$IPAddress' (exit $($result.ExitStatus)): $($result.Output -join '; ')"
        }
        Write-Host "Installed SSH public key into '$UserName@${IPAddress}:~/.ssh/authorized_keys'."
    } finally {
        Remove-SSHSession -SessionId $session.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
}

function Wait-ArcBoxWindowsVmReady {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][pscredential]$Credential,
        [int]$TimeoutSeconds = 600
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
        [int]$TimeoutSeconds = 600
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

function Copy-FileToLinuxVm {
    <#
    .SYNOPSIS
    Reliably copies a file from the Hyper-V host to a nested Linux VM using scp.
    Normalizes CRLF line endings so shell scripts are not broken by Windows line endings.
    Retries transient failures and throws if the copy ultimately fails.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$IPAddress,
        [Parameter(Mandatory = $true)][string]$KeyFilePath,
        [Parameter(Mandatory = $true)][string]$UserName,
        [int]$TimeoutSeconds = 600,
        [switch]$NormalizeLineEndings
    )

    if (-not (Test-Path -Path $LocalPath)) {
        throw "Local file not found for copy to Linux VM: $LocalPath"
    }

    $sourcePath = $LocalPath
    $tempPath = $null
    if ($NormalizeLineEndings) {
        $tempPath = Join-Path -Path $env:TEMP -ChildPath ('arcbox-' + [System.IO.Path]::GetFileName($LocalPath))
        $content = [System.IO.File]::ReadAllText($LocalPath) -replace "`r`n", "`n" -replace "`r", "`n"
        [System.IO.File]::WriteAllText($tempPath, $content, (New-Object System.Text.UTF8Encoding($false)))
        $sourcePath = $tempPath
    }

    try {
        $target = '{0}@{1}:{2}' -f $UserName, $IPAddress, $RemotePath
        $attempt = 0
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ($true) {
            $attempt++
            $scpOutput = & scp -i $KeyFilePath -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=30 $sourcePath $target 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Copied '$LocalPath' to '${IPAddress}:$RemotePath'."
                return
            }

            if ((Get-Date) -ge $deadline) {
                throw "Failed to copy '$LocalPath' to '${IPAddress}:$RemotePath' after $attempt attempts within $TimeoutSeconds seconds (scp exit code $LASTEXITCODE). $scpOutput"
            }

            Write-Host "scp attempt $attempt for '$RemotePath' failed (exit code $LASTEXITCODE). Retrying in 10 seconds..."
            Start-Sleep -Seconds 10
        }
    } finally {
        if ($tempPath -and (Test-Path $tempPath)) {
            Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ArcBoxLinuxScript {
    <#
    .SYNOPSIS
    Runs a bash command inside a remote Linux PowerShell session, surfaces its output,
    and throws when the command exits with a non-zero status so callers can detect failures.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $result = Invoke-Command -Session $Session -ScriptBlock {
        param($innerCommand)
        $output = bash -c $innerCommand 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output | Out-String)
        }
    } -ArgumentList $Command

    if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Host $result.Output
    }

    if ($result.ExitCode -ne 0) {
        throw "Remote Linux command failed with exit code $($result.ExitCode): $Command"
    }
}

function Copy-FileToWindowsVm {
    <#
    .SYNOPSIS
    Reliably copies a file from the Hyper-V host to a nested Windows VM over PowerShell Direct
    (VMBus). Unlike Copy-VMFile -FileSource Host, this does NOT require the Hyper-V Guest Service
    Interface integration component (which is disabled by default), so it works against the
    nested VMs as-is. Retries transient failures, verifies the file landed, and throws on failure.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$VMName,
        [Parameter(Mandatory = $true)][pscredential]$Credential,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [int]$TimeoutSeconds = 600
    )

    if (-not (Test-Path -Path $LocalPath)) {
        throw "Local file not found for copy to Windows VM: $LocalPath"
    }

    $attempt = 0
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        $attempt++
        $session = $null
        try {
            $session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop

            $remoteDir = Split-Path -Path $RemotePath -Parent
            if ($remoteDir) {
                Invoke-Command -Session $session -ScriptBlock {
                    param($dir)
                    if (-not (Test-Path -Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                } -ArgumentList $remoteDir -ErrorAction Stop
            }

            Copy-Item -Path $LocalPath -Destination $RemotePath -ToSession $session -Force -ErrorAction Stop

            $exists = Invoke-Command -Session $session -ScriptBlock {
                param($path)
                Test-Path -Path $path
            } -ArgumentList $RemotePath -ErrorAction Stop
            if (-not $exists) {
                throw "File '$RemotePath' was not found on '$VMName' after copy."
            }

            Write-Host "Copied '$LocalPath' to '${VMName}:$RemotePath'."
            return
        } catch {
            if ((Get-Date) -ge $deadline) {
                throw "Failed to copy '$LocalPath' to '${VMName}:$RemotePath' after $attempt attempts within $TimeoutSeconds seconds. $($_.Exception.Message)"
            }
            Write-Host "Copy attempt $attempt for '$RemotePath' on '$VMName' failed ($($_.Exception.Message)). Retrying in 10 seconds..."
            Start-Sleep -Seconds 10
        } finally {
            if ($null -ne $session) {
                Remove-PSSession $session -ErrorAction SilentlyContinue
            }
        }
    }
}

# Maps the Windows time zone IDs accepted by the ARM/Bicep template (and Azure DevTest Labs
# auto-shutdown schedule) to their IANA equivalents, which Linux (timedatectl) requires.
$script:WindowsToIanaTimeZone = @{
    'UTC'                            = 'Etc/UTC'
    'Hawaiian Standard Time'         = 'Pacific/Honolulu'
    'Alaskan Standard Time'          = 'America/Anchorage'
    'Pacific Standard Time'          = 'America/Los_Angeles'
    'Mountain Standard Time'         = 'America/Denver'
    'Central Standard Time'          = 'America/Chicago'
    'Eastern Standard Time'          = 'America/New_York'
    'Atlantic Standard Time'         = 'America/Halifax'
    'E. South America Standard Time' = 'America/Sao_Paulo'
    'Argentina Standard Time'        = 'America/Argentina/Buenos_Aires'
    'Greenwich Standard Time'        = 'Atlantic/Reykjavik'
    'GMT Standard Time'              = 'Europe/London'
    'W. Europe Standard Time'        = 'Europe/Berlin'
    'Central Europe Standard Time'   = 'Europe/Budapest'
    'Romance Standard Time'          = 'Europe/Paris'
    'South Africa Standard Time'     = 'Africa/Johannesburg'
    'E. Africa Standard Time'        = 'Africa/Nairobi'
    'Arabian Standard Time'          = 'Asia/Dubai'
    'Russian Standard Time'          = 'Europe/Moscow'
    'India Standard Time'            = 'Asia/Kolkata'
    'China Standard Time'            = 'Asia/Shanghai'
    'Singapore Standard Time'        = 'Asia/Singapore'
    'Tokyo Standard Time'            = 'Asia/Tokyo'
    'AUS Eastern Standard Time'      = 'Australia/Sydney'
    'New Zealand Standard Time'      = 'Pacific/Auckland'
}

function ConvertTo-IanaTimeZone {
    <#
    .SYNOPSIS
    Returns the IANA time zone name for a given Windows time zone ID, for use on Linux.
    #>
    param([Parameter(Mandatory = $true)][string]$WindowsTimeZoneId)

    if ($script:WindowsToIanaTimeZone.ContainsKey($WindowsTimeZoneId)) {
        return $script:WindowsToIanaTimeZone[$WindowsTimeZoneId]
    }
    throw "No IANA time zone mapping is defined for Windows time zone ID '$WindowsTimeZoneId'."
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
    # Shared, deterministic values are defined here (outside the per-component blocks) so that
    # re-running the script to retry only failed components still has every variable it needs,
    # even when earlier components are skipped because they already completed.
    $nestedWindowsUsername = 'Administrator'
    $nestedWindowsPassword = 'JS123!!'
    $secWindowsPassword = ConvertTo-SecureString $nestedWindowsPassword -AsPlainText -Force
    $winCreds = New-Object System.Management.Automation.PSCredential ($nestedWindowsUsername, $secWindowsPassword)
    $SQLvmName = "$namingPrefix-SQL"
    $SQLvmvhdPath = "$Env:ArcBoxVMDir\$namingPrefix-SQL.vhdx"
    $SQLvmIp = '10.10.1.101'

    if (-not (Test-ComponentCompleted -Name 'Hyper-V network setup')) {
        Start-DeploymentComponent -Name 'Hyper-V network setup' -Message 'Configuring NAT, VM credentials, and Hyper-V host shortcuts.'
        try {

        # Create the NAT network
        Write-Host 'Creating Internal NAT'
        $natName = 'InternalNat'
        $netNat = Get-NetNat
        if ($netNat.Name -ne $natName) {
            New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.1.0/24
        }

        Write-Host 'Configuring DHCP scope for Internal NAT'
        Ensure-ArcBoxDhcpScope

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
        } catch {
            Write-Warning "Component 'Hyper-V network setup' failed: $($_.Exception.Message)"
            Complete-DeploymentComponent -Name 'Hyper-V network setup' -Status Failed -Message $_.Exception.Message
        }
    }

    if (-not (Test-ComponentCompleted -Name 'Azure resource provider registration')) {
        Start-DeploymentComponent -Name 'Azure resource provider registration' -Message 'Logging in with managed identity and registering required Arc and Azure Migrate providers.'
        try {

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
        } catch {
            Write-Warning "Component 'Azure resource provider registration' failed: $($_.Exception.Message)"
            Complete-DeploymentComponent -Name 'Azure resource provider registration' -Status Failed -Message $_.Exception.Message
        }
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
        try {

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

        $sqlVmMacAddress = (Get-VMNetworkAdapter -VMName $SQLvmName -ErrorAction Stop | Select-Object -First 1 -ExpandProperty MacAddress)
        Set-ArcBoxDhcpReservation -Name $SQLvmName -IPAddress '10.10.1.101' -MacAddress $sqlVmMacAddress

        # Restarting Windows VM Network Adapters
        Write-Host 'Restarting Network Adapters'
        Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
        Invoke-Command -VMName $SQLvmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        
        $arcBoxDnsServers = @(Get-ArcBoxHostDnsServers)
        Write-Host 'Configuring Static IP for nested SQL VM'
        Invoke-Command -VMName $SQLvmName -ScriptBlock {
            $netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if ($netAdapter) {
                # Remove DHCP and set static IP
                New-NetIPAddress -InterfaceAlias $netAdapter.Name -IPAddress 10.10.1.101 -PrefixLength 24 -DefaultGateway 10.10.1.1 -ErrorAction SilentlyContinue
                Set-DnsClientServerAddress -InterfaceAlias $netAdapter.Name -ServerAddresses $using:arcBoxDnsServers
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
        Copy-FileToWindowsVm -VMName $SQLvmName -Credential $winCreds -LocalPath "$agentScript\installArcAgent.ps1" -RemotePath "$nestedVMArcBoxDir\installArcAgent.ps1"

        Complete-DeploymentComponent -Name 'ArcBox-SQL VM' -Message 'SQL VM is created, renamed, networked, and ready for Arc onboarding.'
        } catch {
            Write-Warning "Component 'ArcBox-SQL VM' failed: $($_.Exception.Message)"
            Complete-DeploymentComponent -Name 'ArcBox-SQL VM' -Status Failed -Message $_.Exception.Message
        }
    }

    if (-not (Test-ComponentCompleted -Name 'ArcBox-SQL Arc onboarding')) {
        Start-DeploymentComponent -Name 'ArcBox-SQL Arc onboarding' -Message 'Installing the Azure Connected Machine agent on the SQL VM.'
        try {

        Write-Header 'Onboarding Arc-enabled servers'

        # Onboarding the nested VMs as Azure Arc-enabled servers
        Write-Output 'Onboarding the nested Windows VMs as Azure Arc-enabled servers'
        $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
        Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\installArcAgent.ps1 -accessToken $using:accessToken, -tenantId $Using:tenantId, -subscriptionId $Using:subscriptionId, -resourceGroup $Using:resourceGroup, -azureLocation $Using:azureLocation } -Credential $winCreds
        Write-Output 'Azure Arc client installation command completed on SQL VM.'
        Complete-DeploymentComponent -Name 'ArcBox-SQL Arc onboarding' -Message 'SQL VM Azure Connected Machine onboarding command completed.'
        } catch {
            Write-Warning "Component 'ArcBox-SQL Arc onboarding' failed: $($_.Exception.Message)"
            Complete-DeploymentComponent -Name 'ArcBox-SQL Arc onboarding' -Status Failed -Message $_.Exception.Message
        }
    }

    # Deploy the single Ubuntu nested VM and configure the two legacy app stacks.
    if ($Env:flavor -eq 'ITPro') {
        # Shared, deterministic values for the Ubuntu nested VM and its app stacks are defined here
        # (outside the per-component blocks) so re-runs that retry only failed components still have
        # every variable they need, even when the 'ArcBox-Ubuntu VM' component is skipped.
        $ubuntuVmName = "$namingPrefix-pgsql"
        # Default to the reserved address, but prefer whichever internal-subnet IP the VM actually
        # obtained so re-runs that skip VM creation still target the correct address (Ubuntu's
        # DUID-based DHCP client-id often means the MAC reservation for 10.10.1.102 is not honored
        # and it leases a pool address instead).
        $ubuntuVmIp = '10.10.1.102'
        try {
            $ubuntuDiscoveredIp = @(Get-VM -Name $ubuntuVmName -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty NetworkAdapters -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty IPAddresses -ErrorAction SilentlyContinue |
                Where-Object { $_ -match '^10\.10\.1\.\d+$' }) | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($ubuntuDiscoveredIp)) {
                $ubuntuVmIp = $ubuntuDiscoveredIp
            }
        } catch { }
        $nestedLinuxUsername = 'jumpstart'
        $nestedLinuxPassword = 'JS123!!'
        $sshDir = Join-Path -Path $Env:USERPROFILE -ChildPath '.ssh'
        $sshKeyPath = Join-Path -Path $sshDir -ChildPath 'id_rsa'

        # Track whether the Ubuntu VM is actually provisioned and reachable this run. The app-stack
        # components below depend on SSH to the VM, so they must be skipped (not hung on a connection
        # timeout) when the VM component did not complete. Seed it from the persisted status so a
        # re-run that only retries the app stacks still proceeds when the VM was created earlier.
        $ubuntuVmReady = Test-ComponentCompleted -Name 'ArcBox-Ubuntu VM'

        if (-not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu VM')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu VM' -Message 'Downloading Ubuntu VHD and creating the nested Ubuntu Hyper-V VM.'
            try {

            Write-Header 'Fetching Ubuntu VM'

            $ubuntuVmName = "$namingPrefix-pgsql"
            $ubuntuVhdPath = "${Env:ArcBoxVMDir}\$namingPrefix-pgsql.vhdx"
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

            $ubuntuVmMacAddressRaw = (Get-VMNetworkAdapter -VMName $ubuntuVmName -ErrorAction Stop | Select-Object -First 1 -ExpandProperty MacAddress)
            if ([string]::IsNullOrWhiteSpace($ubuntuVmMacAddressRaw)) {
                throw "Unable to determine MAC address for Ubuntu VM '$ubuntuVmName'. Cannot configure DHCP reservation."
            }
            Set-ArcBoxDhcpReservation -Name $ubuntuVmName -IPAddress $ubuntuVmIp -MacAddress $ubuntuVmMacAddressRaw
            if (Get-VM -Name $SQLvmName -ErrorAction SilentlyContinue) {
                $sqlVmMacAddress = (Get-VMNetworkAdapter -VMName $SQLvmName -ErrorAction Stop | Select-Object -First 1 -ExpandProperty MacAddress)
                Set-ArcBoxDhcpReservation -Name $SQLvmName -IPAddress $SQLvmIp -MacAddress $sqlVmMacAddress
            }

            # Configure automatic start & stop action for the nested Windows VM
            foreach ($nestedVm in Get-VM -Name $SQLvmName) {
                if ($nestedVm.State -eq 'Running') {
                    Stop-VM -Force -Name $nestedVm.Name
                }
                Set-VM -Name $nestedVm.Name -AutomaticStopAction ShutDown -AutomaticStartAction Start
                Start-VM -Name $nestedVm.Name
            }

            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds

            Write-Header 'Creating VM Credentials'
            # Hard-coded username and password for the nested Linux VM
            $nestedLinuxUsername = 'jumpstart'
            $nestedLinuxPassword = 'JS123!!'

            # Configuring SSH for accessing Linux VMs
            Write-Output 'Generating SSH key for accessing nested Linux VMs'

            $sshDir = Join-Path -Path $Env:USERPROFILE -ChildPath '.ssh'
            $sshKeyPath = Join-Path -Path $sshDir -ChildPath 'id_rsa'
            $null = New-Item -Path $sshDir -ItemType Directory -Force
            if (!(Test-Path $sshKeyPath)) {
                ssh-keygen -t rsa -N '' -f $sshKeyPath
            }

            # Automatically accept unseen keys but will refuse connections for changed or invalid hostkeys.
            $sshConfigPath = Join-Path -Path $sshDir -ChildPath 'config'
            if (!(Test-Path $sshConfigPath) -or -not (Select-String -Path $sshConfigPath -Pattern '^StrictHostKeyChecking=accept-new$' -Quiet)) {
                Add-Content -Path $sshConfigPath -Value 'StrictHostKeyChecking=accept-new'
            }

            Set-VM -Name $ubuntuVmName -AutomaticStopAction ShutDown -AutomaticStartAction Start

            if ((Get-VM -Name $ubuntuVmName).State -ne 'Running') {
                Start-VM -Name $ubuntuVmName
            }

            Wait-ArcBoxVmRunning -Name $ubuntuVmName

            # Ubuntu's default netplan/systemd-networkd sends a DUID-based DHCP client identifier
            # (RFC 4361), not its MAC, so the Hyper-V host's MAC-based reservation for 10.10.1.102 is
            # frequently not matched and the VM instead leases the first free pool address (e.g.
            # 10.10.1.100). Rather than assume the reserved address and time out on SSH, use whichever
            # 10.10.1.x address the VM actually obtained, reported over Hyper-V KVP (which works
            # without host-to-guest networking). KVP reports a moment after boot, so this polls.
            $ubuntuVmIp = Get-ArcBoxVmInternalIPv4 -Name $ubuntuVmName -SubnetPrefix '10.10.1.'
            Write-Host "Ubuntu VM is reachable at DHCP-assigned IPv4 $ubuntuVmIp."

            # The cloud-init seed that previously delivered the host's SSH public key was removed, and
            # the Hyper-V VMBus file-copy path is not serviced by this image (Copy-VMFile fails with
            # 0x80004005). Bootstrap the key once over password SSH so every key-based SSH/PowerShell
            # remoting call below works.
            Set-ArcBoxLinuxVmAuthorizedKey -IPAddress $ubuntuVmIp -PublicKeyPath "$sshKeyPath.pub" -UserName $nestedLinuxUsername -Password $nestedLinuxPassword

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
            $ubuntuVmReady = $true
            } catch {
                Write-Warning "Component 'ArcBox-Ubuntu VM' failed: $($_.Exception.Message)"
                try {
                    if ((Get-VM -Name $ubuntuVmName -ErrorAction SilentlyContinue).State -eq 'Off') {
                        Start-VM -Name $ubuntuVmName -ErrorAction SilentlyContinue
                    }
                } catch { }
                Complete-DeploymentComponent -Name 'ArcBox-Ubuntu VM' -Status Failed -Message $_.Exception.Message
            }
        }

        $arcBoxWebSqlSecret = 'ArcBoxWeb1!'
        $arcBoxWebPgSecret = 'ArcBoxWeb1!'
        $arcBoxWebPgUser = 'arcboxweb'
        $arcBoxWebPgDb = 'arcboxdemo'
        $arcBoxSqlDb = 'ArcBoxDemo'
        $arcBoxWebSqlUser = 'arcboxweb'

        if (-not (Test-ComponentCompleted -Name 'ArcBox-SQL website and database')) {
            Start-DeploymentComponent -Name 'ArcBox-SQL website and database' -Message 'Seeding the AdventureWorksLT SQL database and configuring IIS/ASP.NET on the SQL VM.'
            try {
            Write-Header 'Seeding AdventureWorksLT SQL Server and configuring IIS on SQL VM'
            Wait-ArcBoxWindowsVmReady -Name $SQLvmName -Credential $winCreds
            Copy-FileToWindowsVm -VMName $SQLvmName -Credential $winCreds -LocalPath "$Env:ArcBoxDir\Initialize-ArcBoxSqlDemo.ps1" -RemotePath "$nestedVMArcBoxDir\Initialize-ArcBoxSqlDemo.ps1"
            Copy-FileToWindowsVm -VMName $SQLvmName -Credential $winCreds -LocalPath "$Env:ArcBoxDir\Configure-IIS.ps1" -RemotePath "$nestedVMArcBoxDir\Configure-IIS.ps1"
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
            } catch {
                Write-Warning "Component 'ArcBox-SQL website and database' failed: $($_.Exception.Message)"
                Complete-DeploymentComponent -Name 'ArcBox-SQL website and database' -Status Failed -Message $_.Exception.Message
            }
        }

        if ($ubuntuVmReady -and -not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu website and database')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu website and database' -Message 'Installing the AdventureWorksLT PostgreSQL conversion and PHP storefront on Ubuntu.'
            try {
            Write-Header 'Installing PostgreSQL AdventureWorks storefront on Ubuntu VM'
            Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername

            # Copy the configuration script to the Ubuntu VM using scp with retries and CRLF
            # normalization so Windows line endings do not break the bash script.
            Copy-FileToLinuxVm -LocalPath "$Env:ArcBoxDir\Configure-Postgres.sh" -RemotePath "/home/$nestedLinuxUsername/Configure-Postgres.sh" -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -NormalizeLineEndings

            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ErrorAction Stop
            try {
                Invoke-Command -Session $ubuntuSession -ScriptBlock {
                    chmod +x "/home/$using:nestedLinuxUsername/Configure-Postgres.sh"
                } -ErrorAction Stop
                Invoke-ArcBoxLinuxScript -Session $ubuntuSession -Command "WEB_USER='$arcBoxWebPgUser' WEB_PASSWORD='$arcBoxWebPgSecret' WEB_DB='$arcBoxWebPgDb' ALLOW_CIDR='10.10.1.0/24' bash /home/$nestedLinuxUsername/Configure-Postgres.sh"
            } finally {
                Remove-PSSession $ubuntuSession -ErrorAction SilentlyContinue
            }
            Complete-DeploymentComponent -Name 'ArcBox-Ubuntu website and database' -Message "AdventureWorks PostgreSQL storefront is configured at http://$ubuntuVmIp/."
            
            $Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Ubuntu Website.lnk")
            $Shortcut.TargetPath = "http://$ubuntuVmIp/"
            $shortcut.Save()
            } catch {
                Write-Warning "Component 'ArcBox-Ubuntu website and database' failed: $($_.Exception.Message)"
                Complete-DeploymentComponent -Name 'ArcBox-Ubuntu website and database' -Status Failed -Message $_.Exception.Message
            }
        }

        if ($ubuntuVmReady -and -not (Test-ComponentCompleted -Name 'ArcBox-Ubuntu Arc onboarding')) {
            Start-DeploymentComponent -Name 'ArcBox-Ubuntu Arc onboarding' -Message 'Installing the Azure Connected Machine agent on the Ubuntu VM.'
            try {
            # Update Linux VM onboarding script connect to Azure Arc, get new token as it might have been expired by the time execution reached this line.
            $accessToken = ConvertFrom-SecureString ((Get-AzAccessToken -AsSecureString).Token) -AsPlainText
            (Get-Content -Path "$agentScript\installArcAgentUbuntu.sh" -Raw) -replace '\$accessToken', "'$accessToken'" -replace '\$resourceGroup', "'$resourceGroup'" -replace '\$tenantId', "'$Env:tenantId'" -replace '\$azureLocation', "'$Env:azureLocation'" -replace '\$subscriptionId', "'$subscriptionId'" | Set-Content -Path "$agentScript\installArcAgentModifiedUbuntu.sh"

            # Copy installation script to nested Linux VM using scp with retries and CRLF normalization
            Write-Output 'Transferring installation script to nested Linux VM...'
            Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
            Copy-FileToLinuxVm -LocalPath "$agentScript\installArcAgentModifiedUbuntu.sh" -RemotePath "/home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh" -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -NormalizeLineEndings

            Write-Header 'Onboarding Arc-enabled servers'

            Write-Output 'Onboarding the nested Linux VM as an Azure Arc-enabled server'
            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ErrorAction Stop
            try {
                Invoke-Command -Session $ubuntuSession -ScriptBlock {
                    chmod +x "/home/$using:nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
                } -ErrorAction Stop
                Invoke-ArcBoxLinuxScript -Session $ubuntuSession -Command "sudo sh /home/$nestedLinuxUsername/installArcAgentModifiedUbuntu.sh"
            } finally {
                Remove-PSSession $ubuntuSession -ErrorAction SilentlyContinue
            }
            Complete-DeploymentComponent -Name 'ArcBox-Ubuntu Arc onboarding' -Message 'Ubuntu VM Azure Connected Machine onboarding command completed.'
            } catch {
                Write-Warning "Component 'ArcBox-Ubuntu Arc onboarding' failed: $($_.Exception.Message)"
                Complete-DeploymentComponent -Name 'ArcBox-Ubuntu Arc onboarding' -Status Failed -Message $_.Exception.Message
            }
        }
        
        if (-not $ubuntuVmReady) {
            Write-Warning "Skipping Ubuntu app-stack and Arc onboarding components because the 'ArcBox-Ubuntu VM' component did not complete (the VM is not reachable over SSH). Re-run after the VM component succeeds, e.g. -ForceComponents 'ArcBox-Ubuntu VM'."
        }

        Write-Header 'Setting up Self-Signed Certificates'
        if (-not (Test-ComponentCompleted -Name 'Certificates Setup')) {
            Start-DeploymentComponent -Name 'Certificates Setup' -Message 'Generating and installing self-signed certificates'
            try {
            $cert = New-SelfSignedCertificate -DnsName "$SQLvmName","$ubuntuVmName" -CertStoreLocation Cert:\LocalMachine\My -KeyExportPolicy Exportable
            $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList Root, LocalMachine
            $rootStore.Open('ReadWrite')
            $rootStore.Add($cert)
            $rootStore.Close()
            
            $pwd = ConvertTo-SecureString -String "ArcBoxSSL123!" -Force -AsPlainText
            $pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pwd)
            $pfxBase64 = [Convert]::ToBase64String($pfxBytes)
            
            $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
            $certBase64 = [Convert]::ToBase64String($certBytes)

            Invoke-Command -VMName $SQLvmName -Credential $winCreds -ScriptBlock {
                $ErrorActionPreference = 'Stop'
                $certB64 = $using:certBase64
                $pfxB64 = $using:pfxBase64
                $bytes = [Convert]::FromBase64String($certB64)
                $pfxBytes = [Convert]::FromBase64String($pfxB64)
                
                $innerCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,$bytes)
                $rStore = New-Object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::Root, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
                $rStore.Open('ReadWrite')
                $rStore.Add($innerCert)
                $rStore.Close()

                $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]"PersistKeySet, MachineKeySet"
                $pfxCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxBytes, "ArcBoxSSL123!", $flags)
                $mStore = New-Object System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::My, [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
                $mStore.Open('ReadWrite')
                $mStore.Add($pfxCert)
                $mStore.Close()

                Import-Module WebAdministration
                if (-not (Test-Path 'IIS:\Sites\ArcBoxApp')) {
                    throw "IIS site 'ArcBoxApp' does not exist; cannot bind the HTTPS certificate. Ensure the 'ArcBox-SQL website and database' component completed first."
                }

                # Ensure the HTTPS site binding exists (idempotent).
                $bindingExists = Get-WebBinding -Name 'ArcBoxApp' -Port 443 -Protocol https -ErrorAction SilentlyContinue
                if (-not $bindingExists) {
                    New-WebBinding -Name 'ArcBoxApp' -IPAddress '*' -Port 443 -Protocol https
                }

                # Always (re)assign the certificate to the SSL binding so a re-run repairs a partial setup.
                $certItem = Get-ChildItem -Path "Cert:\LocalMachine\My\$($pfxCert.Thumbprint)"
                if (Test-Path 'IIS:\SslBindings\0.0.0.0!443') {
                    Remove-Item -Path 'IIS:\SslBindings\0.0.0.0!443' -Force
                }
                New-Item -Path 'IIS:\SslBindings\0.0.0.0!443' -Value $certItem -Force | Out-Null

                New-NetFirewallRule -DisplayName 'Allow HTTPS 443' -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue | Out-Null

                # Verify the SSL binding resolved to our certificate.
                $sslBinding = Get-Item -Path 'IIS:\SslBindings\0.0.0.0!443'
                if ($sslBinding.Thumbprint -ne $pfxCert.Thumbprint) {
                    throw "IIS HTTPS binding on 'ArcBoxApp' did not resolve to the expected certificate thumbprint."
                }
            }
            
            # Build a robust bash script to trust the host CA, extract the Apache key/cert from the
            # PFX, and enable SSL. The PFX produced by .NET uses legacy PKCS#12 encryption, so on
            # OpenSSL 3 (Ubuntu 22.04+) the '-legacy' flag is required or extraction fails silently.
            $apacheSslScript = @"
set -euo pipefail
CERT_B64='$certBase64'
PFX_B64='$pfxBase64'
PASSWORD='ArcBoxSSL123!'

printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "`$CERT_B64" | sudo tee /usr/local/share/ca-certificates/hyperv-host.crt >/dev/null
sudo update-ca-certificates

echo "`$PFX_B64" | base64 -d | sudo tee /tmp/cert.pfx >/dev/null

LEGACY=''
if openssl version | grep -qE 'OpenSSL 3'; then LEGACY='-legacy'; fi
sudo openssl pkcs12 `$LEGACY -in /tmp/cert.pfx -nocerts -nodes -passin pass:"`$PASSWORD" -out /etc/ssl/private/apache-selfsigned.key
sudo openssl pkcs12 `$LEGACY -in /tmp/cert.pfx -clcerts -nokeys -passin pass:"`$PASSWORD" -out /etc/ssl/certs/apache-selfsigned.crt
sudo rm -f /tmp/cert.pfx

sudo test -s /etc/ssl/private/apache-selfsigned.key
sudo test -s /etc/ssl/certs/apache-selfsigned.crt
sudo openssl x509 -in /etc/ssl/certs/apache-selfsigned.crt -noout
sudo chmod 600 /etc/ssl/private/apache-selfsigned.key

sudo a2enmod ssl
sudo a2ensite default-ssl
sudo sed -i 's/ssl-cert-snakeoil.pem/apache-selfsigned.crt/g' /etc/apache2/sites-available/default-ssl.conf
sudo sed -i 's/ssl-cert-snakeoil.key/apache-selfsigned.key/g' /etc/apache2/sites-available/default-ssl.conf
sudo apache2ctl configtest
sudo systemctl restart apache2
sudo systemctl is-active --quiet apache2
sudo ufw allow 'Apache Full' >/dev/null 2>&1 || true
"@

            $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ErrorAction Stop
            try {
                Invoke-ArcBoxLinuxScript -Session $ubuntuSession -Command $apacheSslScript
            } finally {
                Remove-PSSession $ubuntuSession -ErrorAction SilentlyContinue
            }

            # Verify HTTPS (port 443) is actually reachable on both VMs so this component only
            # reports success when SSL is genuinely serving on the SQL (IIS) and Ubuntu (Apache) VMs.
            Write-Header 'Verifying HTTPS connectivity to both VMs'
            foreach ($endpoint in @(
                    [pscustomobject]@{ Name = $SQLvmName; IPAddress = $SQLvmIp },
                    [pscustomobject]@{ Name = $ubuntuVmName; IPAddress = $ubuntuVmIp }
                )) {
                $reachable = $false
                for ($i = 0; $i -lt 12; $i++) {
                    if ((Test-NetConnection -ComputerName $endpoint.IPAddress -Port 443 -WarningAction SilentlyContinue).TcpTestSucceeded) {
                        $reachable = $true
                        break
                    }
                    Start-Sleep -Seconds 10
                }
                if (-not $reachable) {
                    throw "HTTPS (port 443) is not reachable on $($endpoint.Name) at $($endpoint.IPAddress)."
                }
                Write-Host "HTTPS endpoint reachable on $($endpoint.Name) ($($endpoint.IPAddress):443)."
            }

            Complete-DeploymentComponent -Name 'Certificates Setup' -Message 'Certificates configured and HTTPS verified on both VMs.'
            } catch {
                Write-Warning "Component 'Certificates Setup' failed: $($_.Exception.Message)"
                Complete-DeploymentComponent -Name 'Certificates Setup' -Status Failed -Message $_.Exception.Message
            }
        }

        if (-not (Test-ComponentCompleted -Name 'Time zone configuration')) {
            Start-DeploymentComponent -Name 'Time zone configuration' -Message 'Aligning the Hyper-V host and nested VMs to the template time zone.'
            try {
            if ([string]::IsNullOrWhiteSpace($autoShutdownTimezone)) {
                Write-Warning "No autoShutdownTimezone value was provided; skipping time zone configuration."
                Complete-DeploymentComponent -Name 'Time zone configuration' -Status Skipped -Message 'No time zone value supplied by the template.'
            } else {
                Write-Header "Configuring time zone '$autoShutdownTimezone' on host and nested VMs"

                # Host (Hyper-V / Client VM) - Windows time zone ID. Idempotent.
                Set-TimeZone -Id $autoShutdownTimezone

                # Nested SQL VM (Windows) via PowerShell Direct - same Windows time zone ID.
                Invoke-Command -VMName $SQLvmName -Credential $winCreds -ScriptBlock {
                    Set-TimeZone -Id $using:autoShutdownTimezone
                } -ErrorAction Stop

                # Nested Ubuntu VM (Linux) via SSH - timedatectl requires the IANA name.
                $ianaTimeZone = ConvertTo-IanaTimeZone -WindowsTimeZoneId $autoShutdownTimezone
                Wait-ArcBoxLinuxSshReady -IPAddress $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername
                $ubuntuSession = New-PSSession -HostName $ubuntuVmIp -KeyFilePath $sshKeyPath -UserName $nestedLinuxUsername -ErrorAction Stop
                try {
                    Invoke-ArcBoxLinuxScript -Session $ubuntuSession -Command "sudo timedatectl set-timezone '$ianaTimeZone'"
                } finally {
                    Remove-PSSession $ubuntuSession -ErrorAction SilentlyContinue
                }

                Complete-DeploymentComponent -Name 'Time zone configuration' -Message "Time zone set to '$autoShutdownTimezone' (Linux: '$ianaTimeZone') on host and both nested VMs."
            }
            } catch {
                Write-Warning "Component 'Time zone configuration' failed: $($_.Exception.Message)"
                Complete-DeploymentComponent -Name 'Time zone configuration' -Status Failed -Message $_.Exception.Message
            }
        }

        Write-Header "AdventureWorks SQL Server storefront reachable at https://$SQLvmName/"
        Write-Header "AdventureWorks PostgreSQL storefront reachable at https://$ubuntuVmName/"
    }

    if (-not (Test-ComponentCompleted -Name 'Re-enable auto-shutdown')) {
        Start-DeploymentComponent -Name 'Re-enable auto-shutdown' -Message 'Re-enabling the Azure VM auto-shutdown schedule disabled during automation.'
        try {
        if ($env:autoShutdownEnabled -eq 'true') {
            Write-Header 'Re-enabling Azure VM Auto-shutdown'

            # Bootstrap.ps1 temporarily disabled the DevTest Labs auto-shutdown schedule so it would
            # not stop the VM mid-deployment. Now that automation is complete, re-enable it so the
            # schedule configured by the template takes effect.
            $shutdownSchedule = Get-AzResource -ResourceType 'Microsoft.DevTestLab/schedules' -ResourceGroupName $env:resourceGroup -ErrorAction Stop | Where-Object { $_.Name -like "shutdown-computevm-*" } | Select-Object -First 1
            if ($null -eq $shutdownSchedule) {
                Write-Warning 'Auto-shutdown schedule resource was not found; nothing to re-enable.'
                Complete-DeploymentComponent -Name 'Re-enable auto-shutdown' -Status Skipped -Message 'Auto-shutdown schedule resource not found.'
            } else {
                $apiVersion = '2018-09-15'
                $Uri = "https://management.azure.com$($shutdownSchedule.ResourceId)?api-version=$apiVersion"
                $scheduleResponse = Invoke-AzRestMethod -Method GET -Uri $Uri
                $ScheduleSettings = $scheduleResponse.Content | ConvertFrom-Json
                $ScheduleSettings.properties.status = 'Enabled'
                $body = $ScheduleSettings | ConvertTo-Json -Depth 30
                $putResponse = Invoke-AzRestMethod -Method PUT -Uri $Uri -Payload $body
                if ($putResponse.StatusCode -ge 200 -and $putResponse.StatusCode -lt 300) {
                    Complete-DeploymentComponent -Name 'Re-enable auto-shutdown' -Message "Auto-shutdown schedule '$($shutdownSchedule.Name)' re-enabled."
                } else {
                    throw "Failed to re-enable auto-shutdown schedule. Status code: $($putResponse.StatusCode). Body: $($putResponse.Content)"
                }
            }
        } else {
            Write-Output 'Auto-shutdown is disabled by the template; nothing to re-enable.'
            Complete-DeploymentComponent -Name 'Re-enable auto-shutdown' -Status Skipped -Message 'Auto-shutdown is disabled by the template.'
        }
        } catch {
            Write-Warning "Component 'Re-enable auto-shutdown' failed: $($_.Exception.Message)"
            Complete-DeploymentComponent -Name 'Re-enable auto-shutdown' -Status Failed -Message $_.Exception.Message
        }
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