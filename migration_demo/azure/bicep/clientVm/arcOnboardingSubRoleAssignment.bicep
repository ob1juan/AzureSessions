targetScope = 'subscription'

@description('Object ID of the client VM system-assigned managed identity that runs azcmagent connect for nested VMs.')
param principalId string

// Azure Connected Machine Onboarding (built-in role b64e21ea-ac4e-4cdf-9dc9-5b892992bee7).
// Grants the MI permission to create Microsoft.HybridCompute/machines records at subscription scope.
var arcOnboardingRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b64e21ea-ac4e-4cdf-9dc9-5b892992bee7')

// Owner is required because the logon script registers Arc-related resource providers before onboarding nested VMs.
var ownerRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')

resource arcOnboardingAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, arcOnboardingRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: arcOnboardingRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

resource ownerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, ownerRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: ownerRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
