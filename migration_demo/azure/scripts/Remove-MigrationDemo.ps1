[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'DeleteResourceGroup')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'DeleteResourceGroup')]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true, ParameterSetName = 'PurgeSubscription')]
    [switch] $PurgeOnly,

    [string] $PimJustification = 'Activate Owner to remove migration demo resources',

    # Defaults to US regions for the active cloud when not specified
    [string[]] $Locations = @()
)

$ErrorActionPreference = 'Stop'
$ownerRoleDefinitionGuid = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

function Get-AzCliFailureMessage {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [object[]] $Output
    )

    $details = (@($Output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($details -match 'InteractionRequired|TokenCreatedWithOutdatedPolicies') {
        return @"
Azure CLI authentication must be refreshed because the tenant's Conditional Access policies changed.
Run 'az logout', then 'az login', select the original subscription with 'az account set --subscription <subscription-id>', and rerun this script.
Azure CLI details: $details
"@
    }

    if ([string]::IsNullOrWhiteSpace($details)) {
        return "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    return "Azure CLI command failed: az $($Arguments -join ' ')$([Environment]::NewLine)$details"
}

function Invoke-AzJson {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments)

    $azCommand = if ($env:OS -eq 'Windows_NT' -and (Get-Command azps.ps1 -ErrorAction SilentlyContinue)) {
        (Get-Command azps.ps1).Source
    }
    else {
        'az'
    }

    $output = @(& $azCommand @Arguments --only-show-errors --output json 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw (Get-AzCliFailureMessage -Arguments $Arguments -Output $output)
    }

    if ([string]::IsNullOrWhiteSpace(($output -join ''))) {
        return $null
    }

    return $output | ConvertFrom-Json
}

function Invoke-AzCommand {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments)

    $azCommand = if ($env:OS -eq 'Windows_NT' -and (Get-Command azps.ps1 -ErrorAction SilentlyContinue)) {
        (Get-Command azps.ps1).Source
    }
    else {
        'az'
    }

    $output = @(& $azCommand @Arguments --only-show-errors --output none 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw (Get-AzCliFailureMessage -Arguments $Arguments -Output $output)
    }
}

function Get-SignedInPrincipal {
    param([Parameter(Mandatory = $true)] [object] $Account)

    $arguments = @(
        'ad', 'signed-in-user', 'show',
        '--query', '{id:id,displayName:displayName,userPrincipalName:userPrincipalName}'
    )

    try {
        return Invoke-AzJson -Arguments $arguments
    }
    catch {
        if ($_.Exception.Message -notmatch 'InteractionRequired|TokenCreatedWithOutdatedPolicies') {
            throw
        }

        Write-Host 'Azure CLI authentication is stale. Starting interactive sign-in to refresh Conditional Access claims.'
        Invoke-AzCommand -Arguments @(
            'login',
            '--tenant', $Account.tenantId,
            '--scope', 'https://graph.microsoft.com//.default'
        )
        Invoke-AzCommand -Arguments @('account', 'set', '--subscription', $Account.id)
        return Invoke-AzJson -Arguments $arguments
    }
}

function Test-SubscriptionOwner {
    param(
        [Parameter(Mandatory = $true)] [string] $SubscriptionId,
        [Parameter(Mandatory = $true)] [string] $PrincipalId
    )

    $subscriptionScope = "/subscriptions/$SubscriptionId"
    $assignments = @(Invoke-AzJson -Arguments @(
        'role', 'assignment', 'list',
        '--assignee-object-id', $PrincipalId,
        '--scope', $subscriptionScope,
        '--include-groups',
        '--include-inherited',
        '--fill-principal-name', 'false'
    ))

    return @($assignments | Where-Object {
        $_.roleDefinitionName -eq 'Owner' -or
        ($_.roleDefinitionId -and $_.roleDefinitionId.EndsWith("/$ownerRoleDefinitionGuid", [System.StringComparison]::OrdinalIgnoreCase))
    }).Count -gt 0
}

function Assert-SubscriptionOwner {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)] [object] $Account,
        [Parameter(Mandatory = $true)] [string] $Justification
    )

    $principal = Get-SignedInPrincipal -Account $Account
    if (-not $principal.id) {
        throw 'Unable to determine the signed-in user object ID. PIM Owner activation requires an interactive user identity.'
    }

    if (Test-SubscriptionOwner -SubscriptionId $Account.id -PrincipalId $principal.id) {
        Write-Host "Subscription Owner access confirmed for '$($principal.userPrincipalName)'."
        return
    }

    $subscriptionScope = "/subscriptions/$($Account.id)"
    $eligibilityResponse = Invoke-AzJson -Arguments @(
        'rest',
        '--method', 'get',
        '--url', "https://management.azure.com$subscriptionScope/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&%24filter=asTarget()"
    )
    $ownerEligibility = @($eligibilityResponse.value | Where-Object {
        $_.properties.expandedProperties.roleDefinition.displayName -eq 'Owner' -or
        ($_.properties.roleDefinitionId -and
            $_.properties.roleDefinitionId.EndsWith("/$ownerRoleDefinitionGuid", [System.StringComparison]::OrdinalIgnoreCase))
    })

    if ($ownerEligibility.Count -eq 0) {
        throw "The signed-in user is not an Owner and has no eligible PIM Owner assignment for subscription '$($Account.name)' ($($Account.id))."
    }

    Write-Host 'Eligible PIM Owner assignments:'
    $ownerEligibility | ForEach-Object {
        [pscustomobject]@{
            Scope     = $_.properties.scope
            StartDate = $_.properties.startDateTime
            EndDate   = $_.properties.endDateTime
            Status    = $_.properties.status
        }
    } | Format-Table -AutoSize | Out-Host

    $eligibility = $ownerEligibility | Select-Object -First 1
    $activationScope = $eligibility.properties.scope
    $ownerRoleDefinitionId = if ($activationScope -like '/providers/Microsoft.Management/managementGroups/*') {
        "/providers/Microsoft.Authorization/roleDefinitions/$ownerRoleDefinitionGuid"
    }
    else {
        "$activationScope/providers/Microsoft.Authorization/roleDefinitions/$ownerRoleDefinitionGuid"
    }
    if (-not $PSCmdlet.ShouldProcess($activationScope, 'Activate eligible PIM Owner role for one hour')) {
        if ($WhatIfPreference) {
            Write-Host 'Owner activation skipped because WhatIf is enabled.'
            return
        }
        throw 'Owner activation was cancelled.'
    }

    $requestId = [guid]::NewGuid().ToString()
    $requestUrl = "https://management.azure.com$activationScope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$requestId`?api-version=2020-10-01"
    $requestBody = @{
        properties = @{
            principalId                    = $principal.id
            roleDefinitionId                = $ownerRoleDefinitionId
            requestType                     = 'SelfActivate'
            linkedRoleEligibilityScheduleId = $eligibility.properties.roleEligibilityScheduleId
            justification                   = $Justification
            ticketInfo                      = @{
                ticketNumber = ''
                ticketSystem = ''
            }
            scheduleInfo                    = @{
                startDateTime = [DateTimeOffset]::UtcNow.ToString('o')
                expiration    = @{
                    type     = 'AfterDuration'
                    duration = 'PT8H'
                }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Host "Activating PIM Owner for '$($principal.userPrincipalName)' on subscription '$($Account.name)'"
    $activation = Invoke-AzJson -Arguments @(
        'rest',
        '--method', 'put',
        '--url', $requestUrl,
        '--body', $requestBody,
        '--headers', 'Content-Type=application/json'
    )

    for ($attempt = 1; $attempt -le 120; $attempt++) {
        $status = $activation.properties.status
        if ($status -in @('Denied', 'Failed', 'Canceled', 'Revoked', 'TimedOut', 'PendingApproval')) {
            throw "PIM Owner activation request '$requestId' cannot complete automatically. Status: '$status'."
        }
        if ($status -in @('Granted', 'Provisioned') -and
            (Test-SubscriptionOwner -SubscriptionId $Account.id -PrincipalId $principal.id)) {
            Write-Host 'PIM Owner activation is effective.'
            return
        }

        Start-Sleep -Seconds 5
        $activation = Invoke-AzJson -Arguments @(
            'rest',
            '--method', 'get',
            '--url', $requestUrl
        )
    }

    throw "PIM Owner activation request '$requestId' did not become effective within 10 minutes. Last status: '$($activation.properties.status)'."
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
    param([switch] $DeletedOnly)

    $activeVaults = @()
    if (-not $DeletedOnly) {
        $activeVaults = @(Invoke-AzJson -Arguments @(
            'keyvault', 'list',
            '--resource-group', $ResourceGroupName,
            '--query', '[].{name:name,location:location}'
        ))
    }

    $deletedVaults = @(Invoke-AzJson -Arguments @(
        'keyvault', 'list-deleted',
        '--query', '[].{name:name,location:properties.location,vaultId:properties.vaultId}'
    ))

    @($activeVaults) | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.name
            Location = $_.location
            ResourceGroup = $ResourceGroupName
            State    = 'Active'
        }
    }
    @($deletedVaults) | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.name
            Location = $_.location
            ResourceGroup = if ($_.vaultId -match '/resourceGroups/([^/]+)') { $Matches[1] } else { 'Unknown' }
            State    = 'SoftDeleted'
        }
    }
}

function Show-DestructiveResourceInventory {
    param(
        [object[]] $KeyVaults,
        [object[]] $StorageAccounts,
        [object[]] $RecoveryServicesVaults
    )

    $inventory = @(
        foreach ($vault in $KeyVaults) {
            [pscustomobject]@{
                ResourceType = 'Key Vault'
                Name         = $vault.Name
                ResourceGroup = $vault.ResourceGroup
                Location     = $vault.Location
                Action       = if ($vault.State -eq 'Active') { 'Delete and purge' } else { 'Purge' }
            }
        }
        foreach ($storageAccount in $StorageAccounts) {
            [pscustomobject]@{
                ResourceType = 'Storage Account'
                Name         = $storageAccount.name
                ResourceGroup = $ResourceGroupName
                Location     = $storageAccount.location
                Action       = 'Delete with resource group'
            }
        }
        foreach ($vault in $RecoveryServicesVaults) {
            [pscustomobject]@{
                ResourceType = 'Recovery Services Vault'
                Name         = $vault.Name
                ResourceGroup = $ResourceGroupName
                Location     = $vault.Location
                Action       = if ($vault.State -eq 'SoftDeleted') { 'Restore and permanently delete' } else { 'Permanently delete' }
            }
        }
    )

    if ($inventory.Count -eq 0) {
        Write-Host 'No Key Vaults, Recovery Services vaults, or Storage Accounts found for deletion or purge.'
        return
    }

    Write-Host 'Resources scheduled for deletion or purge:'
    $inventory | Sort-Object ResourceType, ResourceGroup, Name, Location -Unique | Format-Table -AutoSize | Out-Host
}

function Confirm-DestructiveResourceAction {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [string] $Description)

    if ($WhatIfPreference) {
        return $true
    }

    return $PSCmdlet.ShouldContinue(
        $Description,
        'Confirm permanent resource deletion'
    )
}

function Remove-MigrationDemoKeyVaults {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $KeyVaults)

    foreach ($vault in ($KeyVaults | Where-Object { $_.State -eq 'Active' })) {
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
                    '--location', $vault.Location
                )
            }
            catch {
                throw "Unable to purge Key Vault '$($vault.Name)': $($_.Exception.Message)"
            }
        }
    }
}

function Get-RecoveryServicesVaults {
    @(Get-MigrationDemoResources |
        Where-Object { $_.type -eq 'Microsoft.RecoveryServices/vaults' })
}

function Get-DeletedRecoveryServicesVaults {
    $matchingVaults = [System.Collections.Generic.List[object]]::new()
    foreach ($location in $Locations) {
        try {
            $deletedVaults = @(Invoke-AzJson -Arguments @(
                'backup', 'deleted-vault', 'list',
                '--location', $location
            ))
        }
        catch {
            if (($_.Exception.Message -match 'NoRegisteredProviderFound' -and
                    $_.Exception.Message -match 'locations/deletedVaults') -or
                $_.Exception.Message -match "invalid status 'Bad Request'") {
                Write-Verbose "Skipping location '$location' because Recovery Services deleted vaults are not supported there."
                continue
            }

            throw
        }

        foreach ($vault in $deletedVaults) {
            $vaultId = @(
                $vault.properties.vaultId
                $vault.properties.originalResourceId
                $vault.properties.resourceId
            ) | Where-Object { $_ } | Select-Object -First 1
            $originalResourceGroup = $vault.properties.resourceGroupName
            if (-not $originalResourceGroup -and $vaultId -match '/resourceGroups/([^/]+)') {
                $originalResourceGroup = $Matches[1]
            }

            if ($originalResourceGroup -eq $ResourceGroupName) {
                $matchingVaults.Add([pscustomobject]@{
                    Name            = if ($vault.properties.vaultName) { $vault.properties.vaultName } else { $vault.name }
                    Location        = if ($vault.location) { $vault.location } else { $location }
                    Id              = $vault.id
                    OriginalVaultId = $vaultId
                    DeletionTime    = $vault.properties.vaultDeletionTime
                    State           = 'SoftDeleted'
                })
            }
        }
    }

    @($matchingVaults |
        Group-Object OriginalVaultId |
        ForEach-Object { $_.Group | Sort-Object DeletionTime -Descending | Select-Object -First 1 })
}

function Restore-DeletedRecoveryServicesVaults {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]] $Vaults)

    foreach ($vault in $Vaults) {
        Write-Host "Restoring soft-deleted Recovery Services vault '$($vault.Name)' before permanent deletion"
        if ($PSCmdlet.ShouldProcess($vault.Id, 'az backup deleted-vault undelete')) {
            for ($attempt = 1; $attempt -le 30; $attempt++) {
                try {
                    Invoke-AzCommand -Arguments @(
                        'backup', 'deleted-vault', 'undelete',
                        '--ids', $vault.Id
                    )
                    break
                }
                catch {
                    if ($_.Exception.Message -notmatch 'UserErrorDeletedVaultUndeleteConflictingVaultPresent' -or $attempt -eq 30) {
                        throw "Unable to restore soft-deleted Recovery Services vault '$($vault.Name)' for permanent deletion: $($_.Exception.Message)"
                    }

                    Write-Host "Waiting for the deleted active vault name to become available (attempt $attempt of 30)"
                    Start-Sleep -Seconds 10
                }
            }
        }
    }
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

    foreach ($vault in @($Vaults | Where-Object { $null -ne $_ })) {
        Write-Host "Deleting Recovery Services vault '$($vault.name)'"
        if ($PSCmdlet.ShouldProcess($vault.id, 'az resource delete')) {
            try {
                Invoke-AzCommand -Arguments @('resource', 'delete', '--ids', $vault.id)
                Invoke-AzCommand -Arguments @('resource', 'wait', '--deleted', '--ids', $vault.id)
            }
            catch {
                if ($_.Exception.Message -match '\(ResourceNotFound\)') {
                    Write-Host "Recovery Services vault '$($vault.name)' is already deleted."
                    continue
                }

                throw "Unable to permanently delete Recovery Services vault '$($vault.name)': $($_.Exception.Message)"
            }
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required but was not found in PATH.'
}

if ($Locations.Count -eq 0) {
    $cloudName = & az cloud show --query name --output tsv --only-show-errors 2>&1
    $Locations = if ($cloudName -eq 'AzureUSGovernment') {
        @('usgovvirginia', 'usgovarizona', 'usgovtexas', 'usdodeast', 'usdodcentral')
    } else {
        @('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus', 'northcentralus', 'southcentralus', 'westcentralus')
    }
}

$account = Invoke-AzJson -Arguments @(
    'account', 'show',
    '--query', '{id:id,name:name,tenantId:tenantId,user:user}'
)
Assert-SubscriptionOwner -Account $account -Justification $PimJustification

if ($PurgeOnly) {
    Write-Host 'Searching the current subscription for soft-deleted Key Vaults'
    $keyVaultPurgeTargets = @(Get-KeyVaultPurgeTargets -DeletedOnly)
    Show-DestructiveResourceInventory -KeyVaults $keyVaultPurgeTargets -StorageAccounts @() -RecoveryServicesVaults @()
    if ($keyVaultPurgeTargets.Count -eq 0) {
        Write-Host 'No soft-deleted Key Vaults found in the current subscription.'
        return
    }

    if (-not (Confirm-DestructiveResourceAction -Description "Permanently purge all $($keyVaultPurgeTargets.Count) listed soft-deleted Key Vaults from the current subscription?")) {
        Write-Host 'Purge cancelled.'
        return
    }

    Remove-DeletedKeyVaults -KeyVaults $keyVaultPurgeTargets
    return
}

$resourceGroupExists = & az group exists --name $ResourceGroupName --only-show-errors --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine whether resource group '$ResourceGroupName' exists."
}

if ($resourceGroupExists -ne 'true') {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Nothing to delete."
    return
}

Write-Host "Preparing to delete resource group '$ResourceGroupName'"
$keyVaultPurgeTargets = Get-KeyVaultPurgeTargets
$storageAccounts = @(Get-MigrationDemoResources | Where-Object { $_.type -eq 'Microsoft.Storage/storageAccounts' })
$recoveryServicesVaults = Get-RecoveryServicesVaults
$deletedRecoveryServicesVaults = @(Get-DeletedRecoveryServicesVaults)
$allRecoveryServicesVaults = @($recoveryServicesVaults) + @($deletedRecoveryServicesVaults)
Show-DestructiveResourceInventory -KeyVaults $keyVaultPurgeTargets -StorageAccounts $storageAccounts -RecoveryServicesVaults $allRecoveryServicesVaults

if (-not (Confirm-DestructiveResourceAction -Description "Permanently remove every listed Key Vault and Recovery Services vault before deleting resource group '$ResourceGroupName'?")) {
    Write-Host 'Deletion cancelled.'
    return
}

Remove-MigrationDemoLocks

foreach ($vault in $recoveryServicesVaults) {
    Disable-RecoveryServicesSoftDelete -Vault $vault
    Disable-RecoveryServicesBackupItems -Vault $vault
}

Remove-AzureMigrateChildResources
Remove-RecoveryServicesVaults -Vaults $recoveryServicesVaults

$pendingDeletedRecoveryServicesVaults = @($deletedRecoveryServicesVaults)
for ($cleanupPass = 1; $pendingDeletedRecoveryServicesVaults.Count -gt 0; $cleanupPass++) {
    if ($cleanupPass -gt 10) {
        throw "Recovery Services cleanup still found deleted vault records after 10 passes: $($pendingDeletedRecoveryServicesVaults.Name -join ', ')"
    }

    Write-Host "Recovery Services deleted-vault cleanup pass $cleanupPass"
    Restore-DeletedRecoveryServicesVaults -Vaults $pendingDeletedRecoveryServicesVaults
    $recoveryServicesVaults = Get-RecoveryServicesVaults

    foreach ($vault in $recoveryServicesVaults) {
        Disable-RecoveryServicesSoftDelete -Vault $vault
        Disable-RecoveryServicesBackupItems -Vault $vault
    }

    Remove-AzureMigrateChildResources
    Remove-RecoveryServicesVaults -Vaults $recoveryServicesVaults

    if ($WhatIfPreference) {
        break
    }

    $pendingDeletedRecoveryServicesVaults = @(Get-DeletedRecoveryServicesVaults)
}
Remove-MigrationDemoKeyVaults -KeyVaults $keyVaultPurgeTargets
$keyVaultPurgeTargets = @(Get-KeyVaultPurgeTargets -DeletedOnly)
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
