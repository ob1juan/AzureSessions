@description('Your Microsoft Entra tenant Id')
param tenantId string = tenant().tenantId

@description('Length for generated passwords that are stored in Key Vault')
@minValue(12)
param passwordLength int = 16

@description('Secret name in Key Vault for the Windows admin password')
param windowsAdminPasswordSecretName string = 'windowsAdminPassword'

@description('Secret name in Key Vault for the container registry password')
param registryPasswordSecretName string = 'registryPassword'

@description('Username for Windows account')
param windowsAdminUsername string

@description('Enable automatic logon into ArcBox Virtual Machine')
param vmAutologon bool = true

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

@description('Name for your log analytics workspace')
param logAnalyticsWorkspaceName string = 'ArcBox-la'

@description('SQL Server edition to deploy. Valid values are: \'Developer\', \'Standard\', \'Enterprise\'')
@allowed([
  'Developer'
  'Standard'
  'Enterprise'
])
param sqlServerEdition string = 'Developer'

@description('Target GitHub account')
param githubAccount string = 'ob1juan'

@description('Target GitHub repository name (under githubAccount)')
param githubRepo string = 'AzureSessions'

@description('Path inside the repo to azure_jumpstart_arcbox (no leading slash, trailing slash required)')
param githubRepoPath string = 'azure_arc/azure_jumpstart_arcbox/'

@description('Target GitHub branch')
param githubBranch string = 'main'

@description('Choice to deploy Bastion to connect to the client VM')
param deployBastion bool = true

@description('Bastion host Sku name. The Developer SKU is currently supported in a limited number of regions: https://learn.microsoft.com/azure/bastion/quickstart-developer-sku')
@allowed([
  'Basic'
  'Standard'
  'Developer'
])
param bastionSku string = 'Basic'

@description('User github account where they have forked https://github.com/Azure/jumpstart-apps')
param githubUser string = 'Azure'

@description('Active directory domain services domain name')
param addsDomainName string = 'jumpstart.local'

@description('Random GUID for cluster names')
param guid string = substring(newGuid(),0,4)

var location = resourceGroup().location

@description('The custom location RPO ID. This parameter is only needed when deploying the DataOps flavor.')
param customLocationRPOID string = newGuid()

@description('Use this parameter to enable or disable debug mode for the automation scripts on the client VM, effectively configuring PowerShell ErrorActionPreference to Break. Intended for use when troubleshooting automation scripts. Default is false.')
param debugEnabled bool = false

@description('Tags to assign for all ArcBox resources')
param resourceTags object = {
  Solution: 'jumpstart_arcbox_itpro'
}

@description('Name of the NAT Gateway')
param natGatewayName string = '${namingPrefix}-NatGateway'

@maxLength(7)
@description('The naming prefix for the nested virtual machines and all Azure resources deployed. The maximum length for the naming prefix is 7 characters,example: `ArcBox-Win2k19`')
param namingPrefix string = 'ArcBox'

param autoShutdownEnabled bool = true
param autoShutdownTime string = '1800' // The time for auto-shutdown in HHmm format (24-hour clock)
@description('Timezone for the auto-shutdown schedule. Uses Windows timezone IDs as accepted by Azure DevTest Labs.')
@allowed([
  'UTC'
  'Hawaiian Standard Time'
  'Alaskan Standard Time'
  'Pacific Standard Time'
  'Mountain Standard Time'
  'Central Standard Time'
  'Eastern Standard Time'
  'Atlantic Standard Time'
  'E. South America Standard Time'
  'Argentina Standard Time'
  'Greenwich Standard Time'
  'GMT Standard Time'
  'W. Europe Standard Time'
  'Central Europe Standard Time'
  'Romance Standard Time'
  'South Africa Standard Time'
  'E. Africa Standard Time'
  'Arabian Standard Time'
  'Russian Standard Time'
  'India Standard Time'
  'China Standard Time'
  'Singapore Standard Time'
  'Tokyo Standard Time'
  'AUS Eastern Standard Time'
  'New Zealand Standard Time'
])
param autoShutdownTimezone string = 'Central Standard Time'
param autoShutdownEmailRecipient string = ''

@description('Option to enable spot pricing for the ArcBox Client VM')
param enableAzureSpotPricing bool = false

@description('The availability zone for the Virtual Machine, public IP, and data disk for the ArcBox client VM')
@allowed([
  '1'
  '2'
  '3'
])
param zones string = '1'

var templateBaseUrl = 'https://raw.githubusercontent.com/${githubAccount}/${githubRepo}/${githubBranch}/${githubRepoPath}'
var aksArcDataClusterName = '${namingPrefix}-AKS-Data-${guid}'
var aksDrArcDataClusterName = '${namingPrefix}-AKS-DR-Data-${guid}'
var k3sArcDataClusterName = '${namingPrefix}-K3s-Data-${guid}'
var k3sArcClusterName = '${namingPrefix}-K3s-${guid}'
var k3sClusterNodesCount = 3 // Number of nodes to deploy in the K3s cluster
var randomSeed = uniqueString(resourceGroup().id, deployment().name, guid)
var generatedWindowsAdminPassword = 'Aa1!${substring(base64('${randomSeed}-windows'), 0, passwordLength - 4)}'
var generatedRegistryPassword = 'Bb2!${substring(base64('${randomSeed}-registry'), 0, passwordLength - 4)}'
var flavor = 'ITPro'
var customerUsageAttributionDeploymentName = (flavor == 'DevOps' ? '390d1642-349e-43c5-845e-8c7cc0972f22' : flavor == 'DataOps' ? 'a8caf3c1-0980-4e23-8c52-27e5d424dbbd' : 'c4a26bed-72cb-415d-91a3-e2577c7c92f5')

module clientVmDeployment 'clientVm/clientVm.bicep' = {
  name: 'clientVmDeployment'
  params: {
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: generatedWindowsAdminPassword
    tenantId: tenantId
    workspaceName: logAnalyticsWorkspaceName
    stagingStorageAccountName: toLower(stagingStorageAccountDeployment.outputs.storageAccountName)
    templateBaseUrl: templateBaseUrl
    flavor: flavor
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    deployBastion: deployBastion
    githubBranch: githubBranch
    githubUser: githubUser
    location: location
    k3sArcDataClusterName : k3sArcDataClusterName
    k3sArcClusterName : k3sArcClusterName
    aksArcClusterName : aksArcDataClusterName
    aksdrArcClusterName : aksDrArcDataClusterName
    vmAutologon: vmAutologon
    rdpPort: rdpPort
    addsDomainName: addsDomainName
    customLocationRPOID: customLocationRPOID
    namingPrefix: namingPrefix
    debugEnabled: debugEnabled
    autoShutdownEnabled: autoShutdownEnabled
    autoShutdownTime: autoShutdownTime
    autoShutdownTimezone: autoShutdownTimezone
    autoShutdownEmailRecipient: empty(autoShutdownEmailRecipient) ? null : autoShutdownEmailRecipient
    sqlServerEdition: sqlServerEdition
    zones: zones
    enableAzureSpotPricing: enableAzureSpotPricing
  }
  dependsOn: [
    updateVNetDNSServers
  ]
}

module stagingStorageAccountDeployment 'mgmt/mgmtStagingStorage.bicep' = {
  name: 'stagingStorageAccountDeployment'
  params: {
    location: location
    namingPrefix: namingPrefix
  }
}

module mgmtArtifactsAndPolicyDeployment 'mgmt/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifactsAndPolicyDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    flavor: flavor
    deployBastion: deployBastion
    bastionSku: bastionSku
    location: location
    resourceTags: resourceTags
    namingPrefix: namingPrefix
    windowsAdminPassword: generatedWindowsAdminPassword
    windowsAdminPasswordSecretName: windowsAdminPasswordSecretName
    registryPassword: generatedRegistryPassword
    registryPasswordSecretName: registryPasswordSecretName
    natGatewayName: natGatewayName
  }
}

module addsVmDeployment 'mgmt/addsVm.bicep' = if (flavor == 'DataOps'){
  name: 'addsVmDeployment'
  params: {
    windowsAdminUsername : windowsAdminUsername
    windowsAdminPassword : generatedWindowsAdminPassword
    addsDomainName: addsDomainName
    deployBastion: deployBastion
    templateBaseUrl: templateBaseUrl
    azureLocation: location
    namingPrefix: namingPrefix
  }
  dependsOn: [
    mgmtArtifactsAndPolicyDeployment
  ]
}

module updateVNetDNSServers 'mgmt/mgmtArtifacts.bicep' = if (flavor == 'DataOps'){
  name: 'updateVNetDNSServers'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    flavor: flavor
    deployBastion: deployBastion
    location: location
    dnsServers: [
    '10.16.2.100'
    '168.63.129.16'
    ]
    namingPrefix: namingPrefix
  }
  dependsOn: [
    addsVmDeployment
    mgmtArtifactsAndPolicyDeployment
  ]
}

module customerUsageAttribution 'mgmt/customerUsageAttribution.bicep' = {
  name: 'pid-${customerUsageAttributionDeploymentName}'
  params: {
  }
}

// Grant the client VM's managed identity the built-in Azure Connected Machine Onboarding role
// at subscription scope so azcmagent connect (used to onboard the nested SQL/Linux VMs) can
// perform Microsoft.HybridCompute/register/action.
module arcOnboardingSubRoleAssignment 'clientVm/arcOnboardingSubRoleAssignment.bicep' = {
  name: 'arcOnboardingSubRoleAssignment'
  scope: subscription()
  params: {
    principalId: clientVmDeployment.outputs.vmPrincipalId
  }
}

output clientVmLogonUserName string = flavor == 'DataOps' ? '${windowsAdminUsername}@${addsDomainName}' : ''
output centralKeyVaultId string = mgmtArtifactsAndPolicyDeployment.outputs.keyVaultId
output centralKeyVaultName string = mgmtArtifactsAndPolicyDeployment.outputs.keyVaultName
