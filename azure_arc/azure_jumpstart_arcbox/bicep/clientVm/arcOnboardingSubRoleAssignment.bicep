targetScope = 'subscription'

@description('Object ID of the client VM system-assigned managed identity that runs azcmagent connect for nested VMs.')
param principalId string

// Azure Connected Machine Onboarding (built-in). Grants Microsoft.HybridCompute/register/action
// at subscription scope, which azcmagent connect calls on every first machine in a sub.
var arcOnboardingRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b64e21ea-ac4e-4cdf-9dc9-5b892992bee7')

resource arcOnboardingAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, arcOnboardingRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: arcOnboardingRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
