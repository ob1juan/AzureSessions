@description('Your Microsoft Entra tenant Id')
param tenantId string = tenant().tenantId

@description('Length for generated passwords that are stored in Key Vault')
@minValue(12)
param passwordLength int = 16

@description('Secret name in Key Vault for the Windows admin password')
param windowsAdminPasswordSecretName string = 'windowsAdminPassword'

@description('Username for Windows account')
param windowsAdminUsername string

@description('Enable automatic logon into ArcBox Virtual Machine')
param vmAutologon bool = true

@description('Override default RDP port using this parameter. Default is 3389. No changes will be made to the client VM.')
param rdpPort string = '3389'

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

@description('Path inside the repo to the migration demo root (no leading slash, trailing slash required)')
param githubRepoPath string = 'migration_demo/'

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

@description('Seed suffix used for deterministic generated credentials')
param guid string = substring(uniqueString(resourceGroup().id), 0, 4)

var location = resourceGroup().location

@description('Use this parameter to enable or disable debug mode for the automation scripts on the client VM, effectively configuring PowerShell ErrorActionPreference to Break. Intended for use when troubleshooting automation scripts. Default is false.')
param debugEnabled bool = false

@description('Name of the NAT Gateway')
param natGatewayName string = '${namingPrefix}-NatGateway'

@maxLength(7)
@description('The naming prefix for the nested virtual machines and all Azure resources deployed. The maximum length for the naming prefix is 7 characters, example: `MigDem-Win2k19`')
param namingPrefix string = 'MigDem'

@minLength(3)
@maxLength(24)
@description('Azure Migrate project resource name. Azure Migrate allows only letters, numbers, and hyphens, so the default uses `Migration-Test` as the resource-safe form of `Migration Test`.')
param migrateProjectName string = 'Migration-Test'

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
var randomSeed = uniqueString(resourceGroup().id, guid)
var generatedWindowsAdminPassword = 'Aa1!${substring(base64('${randomSeed}-windows'), 0, passwordLength - 4)}'
var flavor = 'ITPro'
var customerUsageAttributionDeploymentName = 'c4a26bed-72cb-415d-91a3-e2577c7c92f5'
var migrateUtilityStorageAccountName = 'mig${uniqueString(resourceGroup().id, migrateProjectName)}'
var migrateModernizeProjectName = 'azmig${uniqueString(resourceGroup().id, migrateProjectName)}'
var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var storageBlobDataContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource migrateUtilityStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: migrateUtilityStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: migrateProjectName
  location: location
  properties: {
    publicNetworkAccess: 'Enabled'
    utilityStorageAccountId: migrateUtilityStorageAccount.id
  }
}

// The migrateProject resource on its own creates an empty project: its read-only `registeredTools`
// property is populated by registering solution child resources, which the portal normally creates
// behind the scenes. Without these solutions the Azure Migrate tools (Discovery and assessment,
// Migration and modernization) never appear and discovered/assessment data has nowhere to land,
// which is why the project looks half-configured. These three Server* solutions mirror what the
// portal registers for a new server-migration project.
resource serverDiscoverySolution 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  parent: migrateProject
  name: 'Servers-Discovery-ServerDiscovery'
  properties: {
    tool: 'ServerDiscovery'
    purpose: 'Discovery'
    goal: 'Servers'
    status: 'Active'
  }
}

resource serverAssessmentSolution 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  parent: migrateProject
  name: 'Servers-Assessment-ServerAssessment'
  properties: {
    tool: 'ServerAssessment'
    purpose: 'Assessment'
    goal: 'Servers'
    status: 'Active'
  }
}

resource serverMigrationSolution 'Microsoft.Migrate/migrateProjects/solutions@2018-09-01-preview' = {
  parent: migrateProject
  name: 'Servers-Migration-ServerMigration'
  properties: {
    tool: 'ServerMigration'
    purpose: 'Migration'
    goal: 'Servers'
    status: 'Active'
  }
}

resource migrateModernizeProject 'Microsoft.Migrate/modernizeProjects@2022-05-01-preview' = {
  name: migrateModernizeProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    migrationConfiguration: {
      keyVaultResourceId: mgmtArtifactsAndPolicyDeployment.outputs.keyVaultId
      migrationSolutionResourceId: serverMigrationSolution.id
      storageAccountResourceId: migrateUtilityStorageAccount.id
    }
  }
}

resource migrateModernizeProjectStorageContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: sys.guid(migrateUtilityStorageAccount.id, migrateModernizeProject.id, contributorRoleDefinitionId)
  scope: migrateUtilityStorageAccount
  properties: {
    principalId: migrateModernizeProject.identity.principalId
    roleDefinitionId: contributorRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

resource migrateModernizeProjectStorageBlobContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: sys.guid(migrateUtilityStorageAccount.id, migrateModernizeProject.id, storageBlobDataContributorRoleDefinitionId)
  scope: migrateUtilityStorageAccount
  properties: {
    principalId: migrateModernizeProject.identity.principalId
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

module clientVmDeployment 'clientVm/clientVm.bicep' = {
  name: 'clientVmDeployment'
  params: {
    windowsAdminUsername: windowsAdminUsername
    windowsAdminPassword: generatedWindowsAdminPassword
    subnetId: mgmtArtifactsAndPolicyDeployment.outputs.subnetId
    deployBastion: deployBastion
    location: location
    namingPrefix: namingPrefix
    autoShutdownEnabled: autoShutdownEnabled
    autoShutdownTime: autoShutdownTime
    autoShutdownTimezone: autoShutdownTimezone
    autoShutdownEmailRecipient: empty(autoShutdownEmailRecipient) ? null : autoShutdownEmailRecipient
    zones: zones
    enableAzureSpotPricing: enableAzureSpotPricing
  }
}

module mgmtArtifactsAndPolicyDeployment 'mgmt/mgmtArtifacts.bicep' = {
  name: 'mgmtArtifactsAndPolicyDeployment'
  params: {
    flavor: flavor
    deployBastion: deployBastion
    bastionSku: bastionSku
    location: location
    namingPrefix: namingPrefix
    windowsAdminPassword: generatedWindowsAdminPassword
    windowsAdminPasswordSecretName: windowsAdminPasswordSecretName
    natGatewayName: natGatewayName
  }
}

module customerUsageAttribution 'mgmt/customerUsageAttribution.bicep' = {
  name: 'pid-${customerUsageAttributionDeploymentName}'
  params: {
  }
}

// Grant the client VM's managed identity subscription permissions before Bootstrap starts.
module arcOnboardingSubRoleAssignment 'clientVm/arcOnboardingSubRoleAssignment.bicep' = {
  name: 'arcOnboardingSubRoleAssignment'
  scope: subscription()
  params: {
    principalId: clientVmDeployment.outputs.vmPrincipalId
  }
}

module clientVmBootstrapDeployment 'clientVm/clientVmBootstrap.bicep' = {
  name: 'clientVmBootstrapDeployment'
  dependsOn: [
    clientVmDeployment
    arcOnboardingSubRoleAssignment
  ]
  params: {
    vmName: '${namingPrefix}-Host'
    windowsAdminUsername: windowsAdminUsername
    tenantId: tenantId
    templateBaseUrl: templateBaseUrl
    flavor: flavor
    location: location
    vmAutologon: vmAutologon
    rdpPort: rdpPort
    namingPrefix: namingPrefix
    debugEnabled: debugEnabled
    autoShutdownEnabled: autoShutdownEnabled
    autoShutdownTimezone: autoShutdownTimezone
    sqlServerEdition: sqlServerEdition
  }
}

output clientVmLogonUserName string = ''
output centralKeyVaultId string = mgmtArtifactsAndPolicyDeployment.outputs.keyVaultId
output centralKeyVaultName string = mgmtArtifactsAndPolicyDeployment.outputs.keyVaultName
output azureMigrateProjectId string = migrateProject.id
output azureMigrateProjectName string = migrateProject.name
