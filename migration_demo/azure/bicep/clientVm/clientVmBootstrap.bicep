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

param spnAuthority string = environment().authentication.loginEndpoint

@description('Your Microsoft Entra tenant Id')
param tenantId string
param azdataUsername string

param acceptEula string
param registryUsername string

param arcDcName string
param mssqlmiName string

@description('Name of PostgreSQL server group')
param postgresName string

@description('Number of PostgreSQL worker nodes')
param postgresWorkerNodeCount int

@description('Size of data volumes in MB')
param postgresDatasize int

@description('Choose how PostgreSQL service is accessed through Kubernetes networking interface')
param postgresServiceType string

@description('Name for the staging storage account using to hold kubeconfig. This value is passed into the template as an output from mgmtStagingStorage.json')
param stagingStorageAccountName string

@description('Name for the environment Azure Log Analytics workspace')
param workspaceName string

@description('The base URL used for accessing artifacts and automation artifacts.')
param templateBaseUrl string

@description('Tags to assign for all ArcBox resources')
param resourceTags object

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

@description('User github account where they have forked https://github.com/Azure/jumpstart-apps')
param githubUser string

@description('Git branch to use from the forked repo https://github.com/Azure/jumpstart-apps')
param githubBranch string

@description('The name of the K3s cluster')
param k3sArcClusterName string

@description('The name of the Cluster API workload cluster to be connected as an Azure Arc-enabled Kubernetes cluster')
param k3sArcDataClusterName string

@description('The name of the AKS cluster')
param aksArcClusterName string

@description('The name of the AKS DR cluster')
param aksdrArcClusterName string

@description('Domain name for the jumpstart environment')
param addsDomainName string

@description('The custom location RPO ID. This parameter is only needed when deploying the DataOps flavor.')
param customLocationRPOID string

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
      commandToExecute: 'powershell.exe -ExecutionPolicy Bypass -File Bootstrap.ps1 -adminUsername ${windowsAdminUsername} -tenantId ${tenantId} -spnAuthority ${spnAuthority} -subscriptionId ${subscription().subscriptionId} -resourceGroup ${resourceGroup().name} -azdataUsername ${azdataUsername} -acceptEula ${acceptEula} -registryUsername ${registryUsername} -arcDcName ${arcDcName} -azureLocation ${location} -mssqlmiName ${mssqlmiName} -POSTGRES_NAME ${postgresName} -POSTGRES_WORKER_NODE_COUNT ${postgresWorkerNodeCount} -POSTGRES_DATASIZE ${postgresDatasize} -POSTGRES_SERVICE_TYPE ${postgresServiceType} -stagingStorageAccountName ${stagingStorageAccountName} -workspaceName ${workspaceName} -templateBaseUrl ${templateBaseUrl} -flavor ${flavor} -k3sArcDataClusterName ${k3sArcDataClusterName} -k3sArcClusterName ${k3sArcClusterName} -aksArcClusterName ${aksArcClusterName} -aksdrArcClusterName ${aksdrArcClusterName} -githubUser ${githubUser} -githubBranch ${githubBranch} -vmAutologon ${vmAutologon} -rdpPort ${rdpPort} -addsDomainName ${addsDomainName} -customLocationRPOID ${customLocationRPOID} -resourceTags ${resourceTags} -namingPrefix ${namingPrefix} -debugEnabled ${debugEnabled} -sqlServerEdition ${sqlServerEdition} -autoShutdownEnabled ${autoShutdownEnabled}'
    }
  }
}
