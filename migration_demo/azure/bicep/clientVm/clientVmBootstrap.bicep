@description('The name of your Virtual Machine')
param vmName string

@description('Username for the Virtual Machine')
param windowsAdminUsername string

@description('Enable automatic logon into ArcBox Virtual Machine')
param vmAutologon bool

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Your Microsoft Entra tenant Id')
param tenantId string

@description('The base URL used for accessing artifacts and automation artifacts.')
param templateBaseUrl string

@description('The naming prefix for the nested virtual machines. Example: ArcBox-Win2k19')
param namingPrefix string

@description('The flavor of ArcBox to deploy. This migration demo supports ITPro only.')
@allowed([
  'ITPro'
])
param flavor string

@description('SQL Server edition to deploy. Valid values are: \'Developer\', \'Standard\', \'Enterprise\'')
@allowed([
  'Developer'
  'Standard'
  'Enterprise'
])
param sqlServerEdition string

@description('Use this parameter to enable or disable debug mode for the automation scripts on the client VM, effectively configuring PowerShell ErrorActionPreference to Break. Default is false.')
param debugEnabled bool

param autoShutdownEnabled bool

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource vmBootstrap 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'Bootstrap'
  location: location
  tags: {
    displayName: 'config-bootstrap'
  }
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      fileUris: [
        uri(templateBaseUrl, 'artifacts/Bootstrap.ps1')
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${windowsAdminUsername} -tenantId ${tenantId} -subscriptionId ${subscription().subscriptionId} -resourceGroup ${resourceGroup().name} -azureLocation ${location} -templateBaseUrl ${templateBaseUrl} -flavor ${flavor} -vmAutologon ${vmAutologon} -rdpPort ${rdpPort} -namingPrefix ${namingPrefix} -debugEnabled ${debugEnabled} -sqlServerEdition ${sqlServerEdition} -autoShutdownEnabled ${autoShutdownEnabled}'
    }
  }
}
