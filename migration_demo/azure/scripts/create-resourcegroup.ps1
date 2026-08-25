[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string] $Subscription,

    [Parameter(Mandatory = $true)]
    [string] $Location,

    [string] $PimJustification = 'Activate Owner to create an Azure resource group'
)

$ErrorActionPreference = 'Stop'
$ownerRoleDefinitionGuid = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
$policyAssignmentsToExclude = @(
    '/providers/microsoft.management/managementgroups/c2a60037-2356-452a-aa29-853c795d20f6/providers/microsoft.authorization/policyassignments/mcapsgovdenypolicies'
    '/providers/microsoft.management/managementgroups/republic-landingzones/providers/microsoft.authorization/policyassignments/enforce-gr-keyvault'
)

function Get-AzCliFailureMessage {
    param(
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [object[]] $Output
    )

    $details = (@($Output) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($details -match 'InteractionRequired|TokenCreatedWithOutdatedPolicies') {
        return @"
Azure CLI authentication must be refreshed because the tenant's Conditional Access policies changed.
Run 'az logout', then 'az login', and rerun this script.
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

    $output = @(& az @Arguments --only-show-errors --output json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (Get-AzCliFailureMessage -Arguments $Arguments -Output $output)
    }

    if ([string]::IsNullOrWhiteSpace(($output -join ''))) {
        return $null
    }

    return $output | ConvertFrom-Json
}

function Invoke-AzCommand {
    param([Parameter(Mandatory = $true)] [string[]] $Arguments)

    $output = @(& az @Arguments --only-show-errors --output none 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (Get-AzCliFailureMessage -Arguments $Arguments -Output $output)
    }
}

function Get-SignedInPrincipal {
    Invoke-AzJson -Arguments @(
        'ad', 'signed-in-user', 'show',
        '--query', '{id:id,displayName:displayName,userPrincipalName:userPrincipalName}'
    )
}

function Test-SubscriptionOwner {
    param(
        [Parameter(Mandatory = $true)] [string] $SubscriptionId,
        [Parameter(Mandatory = $true)] [string] $PrincipalId
    )

    $assignments = @(Invoke-AzJson -Arguments @(
        'role', 'assignment', 'list',
        '--assignee-object-id', $PrincipalId,
        '--scope', "/subscriptions/$SubscriptionId",
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
    param(
        [Parameter(Mandatory = $true)] [object] $Account,
        [Parameter(Mandatory = $true)] [string] $Justification
    )

    $principal = Get-SignedInPrincipal
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

    $eligibility = $ownerEligibility | Select-Object -First 1
    $activationScope = $eligibility.properties.scope
    $ownerRoleDefinitionId = if ($activationScope -like '/providers/Microsoft.Management/managementGroups/*') {
        "/providers/Microsoft.Authorization/roleDefinitions/$ownerRoleDefinitionGuid"
    }
    else {
        "$activationScope/providers/Microsoft.Authorization/roleDefinitions/$ownerRoleDefinitionGuid"
    }

    if (-not $PSCmdlet.ShouldProcess($activationScope, 'Activate eligible PIM Owner role for one hour')) {
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
            scheduleInfo                    = @{
                startDateTime = [DateTimeOffset]::UtcNow.ToString('o')
                expiration    = @{
                    type     = 'AfterDuration'
                    duration = 'PT1H'
                }
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Host "Activating PIM Owner for '$($principal.userPrincipalName)' on subscription '$($Account.name)'."
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

function New-PolicyExemption {
    param(
        [Parameter(Mandatory = $true)] [string] $ResourceGroupId,
        [Parameter(Mandatory = $true)] [string] $PolicyAssignmentId
    )

    $policyAssignmentName = $PolicyAssignmentId.Split('/')[-1]
    $exemptionName = "$policyAssignmentName-exemption"
    $exemptionUrl = "https://management.azure.com$ResourceGroupId/providers/Microsoft.Authorization/policyExemptions/$exemptionName`?api-version=2022-07-01-preview"
    $exemptionBody = @{
        properties = @{
            displayName        = "Exclude $policyAssignmentName for $ResourceGroupName"
            description        = "Resource group exemption created by create-resourcegroup.ps1"
            exemptionCategory  = 'Waiver'
            policyAssignmentId = $PolicyAssignmentId
        }
    } | ConvertTo-Json -Depth 10 -Compress

    if ($PSCmdlet.ShouldProcess($PolicyAssignmentId, "Create policy exemption '$exemptionName'")) {
        Invoke-AzJson -Arguments @(
            'rest',
            '--method', 'put',
            '--url', $exemptionUrl,
            '--body', $exemptionBody,
            '--headers', 'Content-Type=application/json'
        ) | Out-Null
        Write-Host "Policy exemption '$exemptionName' created."
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required but was not found in PATH.'
}

Invoke-AzCommand -Arguments @('account', 'set', '--subscription', $Subscription)
$account = Invoke-AzJson -Arguments @(
    'account', 'show',
    '--query', '{id:id,name:name,tenantId:tenantId,user:user}'
)
Assert-SubscriptionOwner -Account $account -Justification $PimJustification

if (-not $PSCmdlet.ShouldProcess("$ResourceGroupName in $($account.name)", "Create resource group in $Location with SecurityControl:Ignore tag")) {
    return
}

$resourceGroup = Invoke-AzJson -Arguments @(
    'group', 'create',
    '--name', $ResourceGroupName,
    '--location', $Location,
    '--subscription', $account.id,
    '--tags', 'SecurityControl=Ignore',
    '--query', '{id:id,name:name,location:location,tags:tags}'
)
Write-Host "Resource group '$($resourceGroup.name)' is ready in '$($resourceGroup.location)'."

foreach ($policyAssignmentId in $policyAssignmentsToExclude) {
    New-PolicyExemption -ResourceGroupId $resourceGroup.id -PolicyAssignmentId $policyAssignmentId
}

Write-Host "Resource group '$ResourceGroupName' created with the requested tag and policy exemptions."