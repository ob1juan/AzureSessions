<#
.SYNOPSIS
Opens an authenticated shell or runs a command on an ArcBox nested VM from the Hyper-V host.

.EXAMPLE
.\Connect-ArcBoxVm.ps1 -Target Windows

.EXAMPLE
.\Connect-ArcBoxVm.ps1 -Target Linux

.EXAMPLE
.\Connect-ArcBoxVm.ps1 -Target Windows -Command 'Get-Website'

.EXAMPLE
.\Connect-ArcBoxVm.ps1 -Target Linux -Command 'sudo systemctl status apache2'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Windows', 'Linux', 'SQL', 'PostgreSQL')]
    [string]$Target,

    [Parameter(Position = 1)]
    [string]$Command
)

$ErrorActionPreference = 'Stop'

function Resolve-ArcBoxVmName {
    param([Parameter(Mandatory = $true)][string]$Suffix)

    $expectedName = if ([string]::IsNullOrWhiteSpace($env:namingPrefix)) { $null } else { "$($env:namingPrefix)-$Suffix" }
    if ($expectedName -and (Get-VM -Name $expectedName -ErrorAction SilentlyContinue)) {
        return $expectedName
    }

    $matches = @(Get-VM -ErrorAction Stop | Where-Object { $_.Name -like "*-$Suffix" })
    if ($matches.Count -ne 1) {
        throw "Unable to identify one ArcBox '*-$Suffix' VM. Found $($matches.Count). Set the namingPrefix environment variable or remove ambiguous VMs."
    }

    return $matches[0].Name
}

function Resolve-ArcBoxVmIPv4 {
    param([Parameter(Mandatory = $true)][string]$Name)

    $ipAddress = @(Get-VMNetworkAdapter -VMName $Name -ErrorAction Stop |
        Select-Object -ExpandProperty IPAddresses |
        Where-Object { $_ -match '^10\.10\.1\.\d+$' }) |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($ipAddress)) {
        throw "VM '$Name' has not reported an IPv4 address on the ArcBox 10.10.1.0/24 network."
    }

    return $ipAddress
}

if ($Target -in @('Windows', 'SQL')) {
    $vmName = Resolve-ArcBoxVmName -Suffix 'SQL'
    $securePassword = ConvertTo-SecureString 'JS123!!' -AsPlainText -Force
    $credential = [pscredential]::new('Administrator', $securePassword)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-Host "Opening PowerShell Direct session to $vmName as Administrator."
        Enter-PSSession -VMName $vmName -Credential $credential
    } else {
        Invoke-Command -VMName $vmName -Credential $credential -ScriptBlock ([scriptblock]::Create($Command))
    }
    return
}

$linuxVmName = Resolve-ArcBoxVmName -Suffix 'pgsql'
$linuxVmIp = Resolve-ArcBoxVmIPv4 -Name $linuxVmName
$keyFilePath = Join-Path $env:USERPROFILE '.ssh\id_rsa'
if (-not (Test-Path -Path $keyFilePath)) {
    throw "SSH private key not found: $keyFilePath"
}

$sshArguments = @(
    '-i', $keyFilePath,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=accept-new'
)
if (-not [string]::IsNullOrWhiteSpace($Command)) {
    $sshArguments += @('-o', 'BatchMode=yes')
}
$sshArguments += "jumpstart@$linuxVmIp"

if ([string]::IsNullOrWhiteSpace($Command)) {
    Write-Host "Opening SSH session to $linuxVmName ($linuxVmIp) as jumpstart."
    & ssh @sshArguments
} else {
    & ssh @sshArguments $Command
}

if ($LASTEXITCODE -ne 0) {
    throw "SSH exited with code $LASTEXITCODE."
}