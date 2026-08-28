@description('The name of your Virtual Machine')
param vmName string

@description('Username for the Virtual Machine')
param windowsAdminUsername string

@description('Windows admin password as a base64-encoded string, decoded and stored in Key Vault by the bootstrap script over the private endpoint.')
@secure()
param windowsAdminPasswordBase64 string

@description('Managed database administrator username stored in Key Vault by Bootstrap.')
param managedDatabaseAdminUsername string

@description('Managed database administrator password as base64, decoded and stored in Key Vault by Bootstrap.')
@secure()
param managedDatabaseAdminPasswordBase64 string

@description('Azure SQL logical server fully qualified domain name.')
param azureSqlServerFqdn string

@description('Azure SQL database name.')
param azureSqlDatabaseName string

@description('Azure Database for PostgreSQL server fully qualified domain name.')
param azurePostgresqlServerFqdn string

@description('Azure Database for PostgreSQL database name.')
param azurePostgresqlDatabaseName string

@description('Site-to-site VPN pre-shared key encoded as base64 for safe command-line transport and Key Vault storage.')
@secure()
param vpnSharedKeyBase64 string

@description('Public IP address assigned to the Hyper-V host and used as the Virtual WAN VPN site endpoint.')
param vpnSitePublicIp string

@description('Public IP address of the first Azure Virtual WAN VPN gateway instance.')
param vpnGatewayPublicIp string

@description('Address prefix of the Azure VNet connected to the Virtual WAN hub.')
param azureVnetAddressPrefix string

@description('Address prefix of the private Hyper-V network advertised by the VPN site.')
param hyperVNetworkAddressPrefix string

@description('Reserved private IP address of the nested Ubuntu VPN gateway.')
param ubuntuVpnGatewayIp string

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

@description('The naming prefix for the nested virtual machines. Example: MigDem-Win2k19')
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

@description('Windows time zone ID (as accepted by Azure DevTest Labs and tzutil/Set-TimeZone) applied to the Hyper-V host and nested VMs. Example: \'Central Standard Time\'.')
param autoShutdownTimezone string

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
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${windowsAdminUsername} -windowsAdminPasswordBase64 ${windowsAdminPasswordBase64} -managedDatabaseAdminUsername ${managedDatabaseAdminUsername} -managedDatabaseAdminPasswordBase64 ${managedDatabaseAdminPasswordBase64} -azureSqlServerFqdn ${azureSqlServerFqdn} -azureSqlDatabaseName ${azureSqlDatabaseName} -azurePostgresqlServerFqdn ${azurePostgresqlServerFqdn} -azurePostgresqlDatabaseName ${azurePostgresqlDatabaseName} -vpnSharedKeyBase64 ${vpnSharedKeyBase64} -vpnSitePublicIp ${vpnSitePublicIp} -vpnGatewayPublicIp ${vpnGatewayPublicIp} -azureVnetAddressPrefix ${azureVnetAddressPrefix} -hyperVNetworkAddressPrefix ${hyperVNetworkAddressPrefix} -ubuntuVpnGatewayIp ${ubuntuVpnGatewayIp} -tenantId ${tenantId} -subscriptionId ${subscription().subscriptionId} -resourceGroup ${resourceGroup().name} -azureLocation ${location} -templateBaseUrl ${templateBaseUrl} -flavor ${flavor} -vmAutologon ${vmAutologon} -rdpPort ${rdpPort} -namingPrefix ${namingPrefix} -debugEnabled ${debugEnabled} -sqlServerEdition ${sqlServerEdition} -autoShutdownEnabled ${autoShutdownEnabled} -autoShutdownTimezone "${autoShutdownTimezone}"'
    }
  }
}
