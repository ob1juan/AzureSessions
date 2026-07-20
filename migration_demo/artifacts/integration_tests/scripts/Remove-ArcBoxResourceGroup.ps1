[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

$ErrorActionPreference = 'Stop'

Write-Host "Preparing to delete resource group '$ResourceGroupName'"

$locks = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
foreach ($lock in $locks) {
    Write-Host "Removing lock '$($lock.Name)'"
    if ($PSCmdlet.ShouldProcess($lock.Name, 'Remove-AzResourceLock')) {
        Remove-AzResourceLock -LockId $lock.LockId -Force
    }
}

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Remove-AzResourceGroup')) {
    Write-Host "Deleting resource group '$ResourceGroupName'"
    Remove-AzResourceGroup -Name $ResourceGroupName -Force
}