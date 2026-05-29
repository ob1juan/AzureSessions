targetScope = 'subscription'

// Pre-register Arc-related resource providers once per subscription.
// This is idempotent and prevents first-use register/action failures during azcmagent connect.
resource hybridComputeProvider 'Microsoft.Resources/subscriptions/providers@2021-04-01' = {
  name: '${subscription().subscriptionId}/Microsoft.HybridCompute'
}

resource guestConfigurationProvider 'Microsoft.Resources/subscriptions/providers@2021-04-01' = {
  name: '${subscription().subscriptionId}/Microsoft.GuestConfiguration'
}

resource hybridConnectivityProvider 'Microsoft.Resources/subscriptions/providers@2021-04-01' = {
  name: '${subscription().subscriptionId}/Microsoft.HybridConnectivity'
}

resource azureArcDataProvider 'Microsoft.Resources/subscriptions/providers@2021-04-01' = {
  name: '${subscription().subscriptionId}/Microsoft.AzureArcData'
}
