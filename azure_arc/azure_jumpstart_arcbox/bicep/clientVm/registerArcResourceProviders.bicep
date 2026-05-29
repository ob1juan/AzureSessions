targetScope = 'subscription'

// Pre-register Arc-related resource providers once per subscription.
// This is idempotent and prevents first-use register/action failures during azcmagent connect.
resource hybridComputeProvider 'Microsoft.Resources/providers@2021-04-01' = {
  name: 'Microsoft.HybridCompute'
}

resource guestConfigurationProvider 'Microsoft.Resources/providers@2021-04-01' = {
  name: 'Microsoft.GuestConfiguration'
}

resource hybridConnectivityProvider 'Microsoft.Resources/providers@2021-04-01' = {
  name: 'Microsoft.HybridConnectivity'
}

resource azureArcDataProvider 'Microsoft.Resources/providers@2021-04-01' = {
  name: 'Microsoft.AzureArcData'
}
