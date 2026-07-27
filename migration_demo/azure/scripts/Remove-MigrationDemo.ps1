[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments)

    $output = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    if ([string]::IsNullOrWhiteSpace(($output -join ''))) {
        return $null
    }

    return $output | ConvertFrom-Json
}

function Invoke-AzCommand {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments)

    & az @Arguments --only-show-errors --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
}

function Get-MigrationDemoResources {
    @(Invoke-AzJson -Arguments @(
        'resource', 'list',
        '--resource-group', $ResourceGroupName,
        '--query', '[].{id:id,name:name,type:type,location:location}'
    ))
}

function Get-ResourceDepth {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    return ($Resource.type -split '/').Count
}

function Get-DeletePriority {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    switch -Regex ($Resource.type.ToLowerInvariant()) {
        'protecteditems|replicationmigrationitems' { return 0 }
        'protectioncontainermappings|networkmappings|backupprotectionintent' { return 10 }
        'replicationextensions|fabricagents|runasaccounts' { return 20 }
        'protectioncontainers|replicationfabrics|hypervsites|serversites|vmwaresites|mastersites|importsites' { return 30 }
        'replicationpolicies|backuppolicies|backupstorageconfig|backupconfig' { return 40 }
        default { return 50 }
    }
}

function Remove-MigrationDemoLocks {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Host "Removing locks in resource group '$ResourceGroupName'"
    $locks = @(Invoke-AzJson -Arguments @('lock', 'list', '--resource-group', $ResourceGroupName))

    foreach ($lock in $locks) {
        Write-Host "Removing lock '$($lock.name)'"
        if ($PSCmdlet.ShouldProcess($lock.id, 'az lock delete')) {
            Invoke-AzCommand -Arguments @('lock', 'delete', '--ids', $lock.id)
        }
    }
}

function Get-KeyVaultPurgeTargets {
    $activeVaults = @(Invoke-AzJson -Arguments @(
        'keyvault', 'list',
        '--resource-group', $ResourceGroupName,
        '--query', '[].{name:name,location:location}'
    ))
    $resourceGroupPath = "/resourceGroups/$ResourceGroupName/"
    $deletedVaults = @(Invoke-AzJson -Arguments @(
        'keyvault', 'list-deleted',
        '--query', '[].{name:name,location:properties.location,vaultId:properties.vaultId}'
    )) | Where-Object {
        $_.vaultId -and $_.vaultId.Contains($resourceGroupPath, [System.StringComparison]::OrdinalIgnoreCase)
    }

    @($activeVaults + $deletedVaults) | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.name
            Location = $_.location
        }
    } | Sort-Object Name, Location -Unique
}

function Remove-MigrationDemoKeyVaults {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $KeyVaults)

    foreach ($vault in $KeyVaults) {
        Write-Host "Deleting Key Vault '$($vault.Name)' before resource group removal"
        if ($PSCmdlet.ShouldProcess($vault.Name, 'az keyvault delete')) {
            try {
                Invoke-AzCommand -Arguments @(
                    'keyvault', 'delete',
                    '--name', $vault.Name,
                    '--resource-group', $ResourceGroupName
                )
            }
            catch {
                Write-Warning "Unable to delete Key Vault '$($vault.Name)': $($_.Exception.Message)"
            }
        }
    }
}

function Remove-DeletedKeyVaults {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $KeyVaults)

    foreach ($vault in $KeyVaults) {
        Write-Host "Purging soft-deleted Key Vault '$($vault.Name)' in '$($vault.Location)'"
        if ($PSCmdlet.ShouldProcess($vault.Name, 'az keyvault purge')) {
            try {
                Invoke-AzCommand -Arguments @(
                    'keyvault', 'purge',
                    '--name', $vault.Name,
                    '--location', $vault.Location,
                    '--no-wait'
                )
            }
            catch {
                Write-Warning "Unable to purge Key Vault '$($vault.Name)': $($_.Exception.Message)"
            }
        }
    }
}

function Get-RecoveryServicesVaults {
    @(Get-MigrationDemoResources |
        Where-Object { $_.type -eq 'Microsoft.RecoveryServices/vaults' })
}

function Disable-RecoveryServicesSoftDelete {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory = $true)] [object] $Vault)

    Write-Host "Disabling soft delete for Recovery Services vault '$($Vault.name)'"
    if (-not $PSCmdlet.ShouldProcess($Vault.name, 'az backup vault backup-properties set')) {
        return
    }

    try {
        Invoke-AzCommand -Arguments @(
            'backup', 'vault', 'backup-properties', 'set',
            '--name', $Vault.name,
            '--resource-group', $ResourceGroupName,
            '--soft-delete-feature-state', 'Disable',
            '--hybrid-backup-security-features', 'Disable'
        )
    }
    catch {
        Write-Warning "Azure CLI could not disable soft delete for '$($Vault.name)'; trying the REST API"
        $payload = @{
            properties = @{
                securitySettings = @{
                    softDeleteSettings = @{
                        softDeleteState      = 'Disabled'
                        enhancedSecurityState = 'Disabled'
                    }
                }
            }
        } | ConvertTo-Json -Depth 10 -Compress

        Invoke-AzCommand -Arguments @(
            'rest',
            '--method', 'patch',
            '--url', "$($Vault.id)?api-version=2024-10-01",
            '--body', $payload,
            '--headers', 'Content-Type=application/json'
        )
    }
}

function Disable-RecoveryServicesBackupItems {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory = $true)] [object] $Vault)

    try {
        $items = @(Invoke-AzJson -Arguments @(
            'backup', 'item', 'list',
            '--resource-group', $ResourceGroupName,
            '--vault-name', $Vault.name
        ))
    }
    catch {
        Write-Warning "Unable to enumerate backup items in '$($Vault.name)': $($_.Exception.Message)"
        return
    }

    foreach ($item in $items) {
        $itemName = if ($item.properties.friendlyName) { $item.properties.friendlyName } else { $item.name }
        Write-Host "Disabling backup protection for '$itemName' and deleting recovery points"

        if ($PSCmdlet.ShouldProcess($item.id, 'az backup protection disable')) {
            try {
                Invoke-AzCommand -Arguments @(
                    'backup', 'protection', 'disable',
                    '--ids', $item.id,
                    '--delete-backup-data', 'true',
                    '--yes'
                )
            }
            catch {
                Write-Warning "Unable to disable backup protection for '$itemName': $($_.Exception.Message)"
            }
        }
    }
}

function Test-AzureMigrateChildResource {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    $isMigrationResource = $Resource.type -like 'Microsoft.Migrate/*' -or
        $Resource.type -like 'Microsoft.OffAzure/*' -or
        $Resource.type -like 'Microsoft.DataReplication/*' -or
        $Resource.type -like 'Microsoft.RecoveryServices/vaults/*'

    if (-not $isMigrationResource -or (Get-ResourceDepth -Resource $Resource) -le 2) {
        return $false
    }

    $readOnlySuffixes = @('/operationResults', '/jobs', '/events', '/recoveryPoints', '/privateLinkResources')
    foreach ($suffix in $readOnlySuffixes) {
        if ($Resource.type.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

function Remove-AzureMigrateChildResources {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $resources = Get-MigrationDemoResources |
        Where-Object { Test-AzureMigrateChildResource -Resource $_ } |
        Sort-Object @{ Expression = { Get-DeletePriority -Resource $_ }; Ascending = $true },
                    @{ Expression = { Get-ResourceDepth -Resource $_ }; Descending = $true }

    foreach ($resource in $resources) {
        Write-Host "Removing Azure Migrate child resource '$($resource.id)'"
        if ($PSCmdlet.ShouldProcess($resource.id, 'az resource delete')) {
            try {
                Invoke-AzCommand -Arguments @('resource', 'delete', '--ids', $resource.id)
            }
            catch {
                Write-Warning "Unable to remove '$($resource.id)': $($_.Exception.Message)"
            }
        }
    }
}

function Remove-RecoveryServicesVaults {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $Vaults)

    foreach ($vault in @($Vaults)) {
        Write-Host "Deleting Recovery Services vault '$($vault.name)'"
        if ($PSCmdlet.ShouldProcess($vault.id, 'az resource delete')) {
            try {
                Invoke-AzCommand -Arguments @('resource', 'delete', '--ids', $vault.id)
            }
            catch {
                Write-Warning "Unable to delete Recovery Services vault '$($vault.name)': $($_.Exception.Message)"
            }
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required but was not found in PATH.'
}

Invoke-AzJson -Arguments @('account', 'show') | Out-Null

$resourceGroupExists = & az group exists --name $ResourceGroupName --only-show-errors --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine whether resource group '$ResourceGroupName' exists."
}

if ($resourceGroupExists -ne 'true') {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to delete."
    return
}

Write-Host "Preparing to delete resource group '$ResourceGroupName'"
Remove-MigrationDemoLocks

$keyVaultPurgeTargets = Get-KeyVaultPurgeTargets
$recoveryServicesVaults = Get-RecoveryServicesVaults

foreach ($vault in $recoveryServicesVaults) {
    Disable-RecoveryServicesSoftDelete -Vault $vault
    Disable-RecoveryServicesBackupItems -Vault $vault
    Disable-RecoveryServicesSoftDelete -Vault $vault
}

Remove-AzureMigrateChildResources
Remove-RecoveryServicesVaults -Vaults $recoveryServicesVaults
Remove-MigrationDemoKeyVaults -KeyVaults $keyVaultPurgeTargets
Remove-DeletedKeyVaults -KeyVaults $keyVaultPurgeTargets
Remove-MigrationDemoLocks

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'az group delete')) {
    Write-Host "Deleting resource group '$ResourceGroupName'"
    Invoke-AzCommand -Arguments @(
        'group', 'delete',
        '--name', $ResourceGroupName,
        '--yes'
    )
}

Remove-DeletedKeyVaults -KeyVaults $keyVaultPurgeTargets