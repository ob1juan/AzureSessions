[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

$ErrorActionPreference = 'Stop'

function Get-ArcBoxResourceId {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    if ($Resource.ResourceId) {
        return $Resource.ResourceId
    }

    return $Resource.Id
}

function Get-ArcBoxResourceDisplayName {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    if ($Resource.Name) {
        return $Resource.Name
    }

    return Get-ArcBoxResourceId -Resource $Resource
}

function Get-ArcBoxResourceDepth {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    return ($Resource.ResourceType -split '/').Count
}

function Get-ArcBoxDeletePriority {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    $resourceType = $Resource.ResourceType.ToLowerInvariant()

    switch -Regex ($resourceType) {
        'protecteditems|replicationmigrationitems' { return 0 }
        'protectioncontainermappings|networkmappings|backupProtectionIntent' { return 10 }
        'replicationextensions|fabricagents|runasaccounts' { return 20 }
        'protectioncontainers|replicationfabrics|hypervsites|serversites|vmwaresites|mastersites|importsites' { return 30 }
        'replicationpolicies|backuppolicies|backupstorageconfig|backupconfig' { return 40 }
        default { return 50 }
    }
}

function Invoke-ArcBoxCommandVariant {
    param(
        [Parameter(Mandatory = $true)]
        [string] $CommandName,

        [Parameter(Mandatory = $true)]
        [hashtable[]] $ParameterSets
    )

    $lastError = $null
    foreach ($parameters in $ParameterSets) {
        try {
            return & $CommandName @parameters -ErrorAction Stop
        }
        catch {
            $lastError = $_
        }
    }

    throw $lastError
}

function Get-ArcBoxResourceGroupResources {
    @(Get-AzResource -ResourceGroupName $ResourceGroupName -ExpandProperties -ErrorAction SilentlyContinue)
}

function Remove-ArcBoxResourceLocks {
    Write-Host "Removing locks in resource group '$ResourceGroupName'"

    $locks = @(Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)
    foreach ($resource in Get-ArcBoxResourceGroupResources) {
        $resourceId = Get-ArcBoxResourceId -Resource $resource
        try {
            $locks += @(Get-AzResourceLock -Scope $resourceId -ErrorAction SilentlyContinue)
        }
        catch {
            Write-Verbose "Unable to enumerate locks for '$resourceId': $($_.Exception.Message)"
        }
    }

    foreach ($lock in ($locks | Where-Object { $_.LockId } | Sort-Object -Property LockId -Unique)) {
        Write-Host "Removing lock '$($lock.Name)'"
        if ($PSCmdlet.ShouldProcess($lock.LockId, 'Remove-AzResourceLock')) {
            Remove-AzResourceLock -LockId $lock.LockId -Force
        }
    }
}

function Get-ArcBoxRecoveryServicesVaults {
    @(Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType 'Microsoft.RecoveryServices/vaults' -ErrorAction SilentlyContinue)
}

function Get-ArcBoxRecoveryServicesVaultObject {
    param([Parameter(Mandatory = $true)] [object] $Vault)

    if (-not (Get-Command Get-AzRecoveryServicesVault -ErrorAction SilentlyContinue)) {
        return $Vault
    }

    try {
        return Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $Vault.Name -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to load Recovery Services vault object '$($Vault.Name)': $($_.Exception.Message)"
        return $Vault
    }
}

function Disable-ArcBoxRecoveryServicesVaultSoftDelete {
    param([Parameter(Mandatory = $true)] [object] $Vault)

    $vaultId = Get-ArcBoxResourceId -Resource $Vault
    $vaultName = Get-ArcBoxResourceDisplayName -Resource $Vault
    Write-Host "Disabling soft delete for Recovery Services vault '$vaultName'"

    if (Get-Command Set-AzRecoveryServicesVaultProperty -ErrorAction SilentlyContinue) {
        $setVaultPropertyVariants = @(
            @{ VaultId = $vaultId; SoftDeleteFeatureState = 'Disable'; DisableHybridBackupSecurityFeature = $true },
            @{ VaultId = $vaultId; SoftDeleteFeatureState = 'Disable' },
            @{ VaultId = $vaultId; SoftDeleteFeatureState = 'Disabled'; DisableHybridBackupSecurityFeature = $true },
            @{ VaultId = $vaultId; SoftDeleteFeatureState = 'Disabled' }
        )

        if ($PSCmdlet.ShouldProcess($vaultName, 'Disable Recovery Services vault soft delete')) {
            try {
                Invoke-ArcBoxCommandVariant -CommandName 'Set-AzRecoveryServicesVaultProperty' -ParameterSets $setVaultPropertyVariants | Out-Null
                return
            }
            catch {
                Write-Warning "Set-AzRecoveryServicesVaultProperty could not disable soft delete for '$vaultName': $($_.Exception.Message)"
            }
        }
    }

    $payload = @{
        properties = @{
            securitySettings = @{
                softDeleteSettings = @{
                    softDeleteState = 'Disabled'
                    enhancedSecurityState = 'Disabled'
                }
            }
        }
    } | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($vaultName, 'Patch Recovery Services vault soft delete settings')) {
        Invoke-AzRestMethod -Method PATCH -Path "$vaultId?api-version=2024-10-01" -Payload $payload | Out-Null
    }
}

function Set-ArcBoxRecoveryServicesContext {
    param([Parameter(Mandatory = $true)] [object] $Vault)

    if (Get-Command Set-AzRecoveryServicesVaultContext -ErrorAction SilentlyContinue) {
        try {
            Set-AzRecoveryServicesVaultContext -Vault $Vault -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Verbose "Unable to set backup vault context for '$($Vault.Name)': $($_.Exception.Message)"
        }
    }

    if (Get-Command Set-AzRecoveryServicesAsrVaultContext -ErrorAction SilentlyContinue) {
        try {
            Set-AzRecoveryServicesAsrVaultContext -Vault $Vault -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Verbose "Unable to set ASR vault context for '$($Vault.Name)': $($_.Exception.Message)"
        }
    }
}

function Get-ArcBoxBackupItems {
    param([Parameter(Mandatory = $true)] [string] $VaultId)

    if (-not (Get-Command Get-AzRecoveryServicesBackupItem -ErrorAction SilentlyContinue)) {
        return @()
    }

    $queries = @(
        @{ BackupManagementType = 'AzureVM'; WorkloadType = 'AzureVM' },
        @{ BackupManagementType = 'AzureStorage'; WorkloadType = 'AzureFiles' },
        @{ BackupManagementType = 'AzureWorkload'; WorkloadType = 'MSSQL' },
        @{ BackupManagementType = 'AzureWorkload'; WorkloadType = 'SAPHanaDatabase' },
        @{ BackupManagementType = 'MAB'; WorkloadType = 'FileFolder' },
        @{ BackupManagementType = 'AzureBackupServer'; WorkloadType = 'FileFolder' },
        @{ BackupManagementType = 'DPM'; WorkloadType = 'FileFolder' }
    )
    $deleteStates = @($null, 'NotDeleted', 'ToBeDeleted')
    $items = @()

    foreach ($query in $queries) {
        foreach ($deleteState in $deleteStates) {
            $parameters = @{}
            foreach ($key in $query.Keys) {
                $parameters[$key] = $query[$key]
            }

            if ($deleteState) {
                $parameters.DeleteState = $deleteState
            }

            $parameterSets = @(
                ($parameters + @{ VaultId = $VaultId }),
                $parameters
            )

            foreach ($parameterSet in $parameterSets) {
                try {
                    $items += @(Get-AzRecoveryServicesBackupItem @parameterSet -ErrorAction Stop)
                    break
                }
                catch {
                    Write-Verbose "Backup item query skipped: $($_.Exception.Message)"
                }
            }
        }
    }

    $seen = @{}
    foreach ($item in $items) {
        $key = if ($item.Id) { $item.Id } else { "$($item.ContainerName)/$($item.Name)" }
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $item
        }
    }
}

function Wait-ArcBoxBackupJob {
    param([object] $Job)

    if (-not $Job -or -not (Get-Command Wait-AzRecoveryServicesBackupJob -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        Wait-AzRecoveryServicesBackupJob -Job $Job -Timeout 3600 -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose "Unable to wait for backup job '$($Job.JobId)': $($_.Exception.Message)"
    }
}

function Disable-ArcBoxBackupItems {
    param([Parameter(Mandatory = $true)] [string] $VaultId)

    if (-not (Get-Command Disable-AzRecoveryServicesBackupProtection -ErrorAction SilentlyContinue)) {
        return
    }

    foreach ($item in Get-ArcBoxBackupItems -VaultId $VaultId) {
        $itemName = if ($item.FriendlyName) { $item.FriendlyName } else { $item.Name }

        if ($item.DeleteState -eq 'ToBeDeleted' -and (Get-Command Undo-AzRecoveryServicesBackupItemDeletion -ErrorAction SilentlyContinue)) {
            Write-Host "Rehydrating soft-deleted backup item '$itemName' before permanent removal"
            if ($PSCmdlet.ShouldProcess($itemName, 'Undo soft-deleted backup item')) {
                try {
                    Undo-AzRecoveryServicesBackupItemDeletion -Item $item -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Unable to undo soft deletion for backup item '$itemName': $($_.Exception.Message)"
                }
            }
        }

        Write-Host "Disabling backup protection for '$itemName' and removing recovery points"
        if ($PSCmdlet.ShouldProcess($itemName, 'Disable backup protection and remove recovery points')) {
            try {
                $job = Invoke-ArcBoxCommandVariant -CommandName 'Disable-AzRecoveryServicesBackupProtection' -ParameterSets @(
                    @{ Item = $item; RemoveRecoveryPoints = $true; Force = $true },
                    @{ Item = $item; RemoveRecoveryPoints = $true }
                )
                Wait-ArcBoxBackupJob -Job $job
            }
            catch {
                Write-Warning "Unable to disable backup protection for '$itemName': $($_.Exception.Message)"
            }
        }
    }
}

function Wait-ArcBoxAsrJob {
    param([object] $Job)

    if (-not $Job -or -not (Get-Command Wait-AzRecoveryServicesAsrJob -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        Wait-AzRecoveryServicesAsrJob -Job $Job -TimeoutInSeconds 3600 -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Verbose "Unable to wait for ASR job '$($Job.Name)': $($_.Exception.Message)"
    }
}

function Disable-ArcBoxAsrProtectedItems {
    if (-not (Get-Command Get-AzRecoveryServicesAsrFabric -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-AzRecoveryServicesAsrProtectionContainer -ErrorAction SilentlyContinue) -or
        -not (Get-Command Get-AzRecoveryServicesAsrReplicationProtectedItem -ErrorAction SilentlyContinue) -or
        -not (Get-Command Remove-AzRecoveryServicesAsrReplicationProtectedItem -ErrorAction SilentlyContinue)) {
        return
    }

    foreach ($fabric in @(Get-AzRecoveryServicesAsrFabric -ErrorAction SilentlyContinue)) {
        foreach ($container in @(Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric -ErrorAction SilentlyContinue)) {
            foreach ($item in @(Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container -ErrorAction SilentlyContinue)) {
                $itemName = if ($item.FriendlyName) { $item.FriendlyName } else { $item.Name }
                Write-Host "Disabling ASR replication protected item '$itemName'"

                if ($PSCmdlet.ShouldProcess($itemName, 'Disable ASR replication protected item')) {
                    try {
                        $job = Invoke-ArcBoxCommandVariant -CommandName 'Remove-AzRecoveryServicesAsrReplicationProtectedItem' -ParameterSets @(
                            @{ ReplicationProtectedItem = $item; WaitForCompletion = $true },
                            @{ InputObject = $item; WaitForCompletion = $true },
                            @{ ReplicationProtectedItem = $item; Force = $true },
                            @{ InputObject = $item; Force = $true },
                            @{ ReplicationProtectedItem = $item },
                            @{ InputObject = $item }
                        )
                        Wait-ArcBoxAsrJob -Job $job
                    }
                    catch {
                        Write-Warning "Unable to disable ASR replication protected item '$itemName': $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}

function Test-ArcBoxAzureMigrateResource {
    param([Parameter(Mandatory = $true)] [object] $Resource)

    $resourceType = $Resource.ResourceType
    $isAzureMigrateProvider = $resourceType -like 'Microsoft.Migrate/*' -or
        $resourceType -like 'Microsoft.OffAzure/*' -or
        $resourceType -like 'Microsoft.DataReplication/*' -or
        $resourceType -like 'Microsoft.RecoveryServices/vaults/*'

    if (-not $isAzureMigrateProvider) {
        return $false
    }

    if ((Get-ArcBoxResourceDepth -Resource $Resource) -le 2) {
        return $false
    }

    $readOnlySuffixes = @('/operationResults', '/jobs', '/events', '/recoveryPoints', '/privateLinkResources')
    foreach ($suffix in $readOnlySuffixes) {
        if ($resourceType -like "*$suffix") {
            return $false
        }
    }

    return $true
}

function Remove-ArcBoxAzureMigrateChildResources {
    $resources = Get-ArcBoxResourceGroupResources |
        Where-Object { Test-ArcBoxAzureMigrateResource -Resource $_ } |
        Sort-Object @{ Expression = { Get-ArcBoxDeletePriority -Resource $_ }; Ascending = $true }, @{ Expression = { Get-ArcBoxResourceDepth -Resource $_ }; Descending = $true }

    foreach ($resource in $resources) {
        $resourceId = Get-ArcBoxResourceId -Resource $resource
        Write-Host "Removing Azure Migrate child resource '$resourceId'"

        if ($PSCmdlet.ShouldProcess($resourceId, 'Remove Azure Migrate child resource')) {
            try {
                Remove-AzResource -ResourceId $resourceId -Force -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Warning "Unable to remove Azure Migrate child resource '$resourceId': $($_.Exception.Message)"
            }
        }
    }
}

Write-Host "Preparing to delete resource group '$ResourceGroupName'"

if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to delete."
    return
}

Remove-ArcBoxResourceLocks

foreach ($vault in Get-ArcBoxRecoveryServicesVaults) {
    $vaultObject = Get-ArcBoxRecoveryServicesVaultObject -Vault $vault
    $vaultId = Get-ArcBoxResourceId -Resource $vault

    Disable-ArcBoxRecoveryServicesVaultSoftDelete -Vault $vault
    Set-ArcBoxRecoveryServicesContext -Vault $vaultObject
    Disable-ArcBoxBackupItems -VaultId $vaultId
    Disable-ArcBoxAsrProtectedItems
}

Remove-ArcBoxAzureMigrateChildResources
Remove-ArcBoxResourceLocks

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Remove-AzResourceGroup')) {
    Write-Host "Deleting resource group '$ResourceGroupName'"
    Remove-AzResourceGroup -Name $ResourceGroupName -Force
}