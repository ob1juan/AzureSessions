@description('Azure region for the managed database services.')
param location string = resourceGroup().location

@description('Short prefix used to name the managed database resources.')
param namingPrefix string

@description('Administrator login shared by the demo Azure SQL and PostgreSQL servers.')
param administratorLogin string

@description('Administrator password shared by the demo Azure SQL and PostgreSQL servers.')
@secure()
param administratorLoginPassword string

@description('Use the Azure SQL Database serverless free offer. A subscription can have one free database.')
param useAzureSqlFreeLimit bool = true

var uniqueSuffix = uniqueString(resourceGroup().id, namingPrefix)
var sqlServerName = toLower('sql-${namingPrefix}-${uniqueSuffix}')
var postgresqlServerName = toLower('pg-${namingPrefix}-${uniqueSuffix}')

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: 'AdventureWorks'
  location: location
  sku: useAzureSqlFreeLimit
    ? {
        name: 'GP_S_Gen5_1'
        tier: 'GeneralPurpose'
        family: 'Gen5'
        capacity: 1
      }
    : {
        name: 'Basic'
        tier: 'Basic'
        capacity: 5
      }
  properties: useAzureSqlFreeLimit
    ? {
        autoPauseDelay: 60
        minCapacity: json('0.5')
        maxSizeBytes: 34359738368
        requestedBackupStorageRedundancy: 'Local'
        useFreeLimit: true
        freeLimitExhaustionBehavior: 'AutoPause'
        zoneRedundant: false
      }
    : {
        maxSizeBytes: 2147483648
        requestedBackupStorageRedundancy: 'Local'
        zoneRedundant: false
      }
}

resource sqlAllowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresqlServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: '16'
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    storage: {
      autoGrow: 'Disabled'
      storageSizeGB: 32
      type: 'Premium_LRS'
    }
  }
}

resource postgresqlDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2022-12-01' = {
  parent: postgresqlServer
  name: 'adventureworks'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource postgresqlAllowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2022-12-01' = {
  parent: postgresqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output sqlServerName string = sqlServer.name
output sqlDatabaseName string = sqlDatabase.name
output sqlServerFqdn string = '${sqlServer.name}${environment().suffixes.sqlServerHostname}'
output postgresqlServerName string = postgresqlServer.name
output postgresqlDatabaseName string = postgresqlDatabase.name
output postgresqlServerFqdn string = '${postgresqlServer.name}.postgres.database.azure.com'
