targetScope = 'subscription'

@description('Object ID of the client VM system-assigned managed identity that runs azcmagent connect for nested VMs.')
param principalId string

// Azure Connected Machine Onboarding (built-in role b64e21ea-ac4e-4cdf-9dc9-5b892992bee7).
// Grants the MI permission to CREATE Microsoft.HybridCompute/machines records at subscription
// scope (machines/read, machines/write, settings/*, machines/addExtensions/action, etc.).
//
// NOTE: This role does NOT include Microsoft.HybridCompute/register/action — that's the
// resource-provider REGISTRATION action and must be performed once per subscription before
// the first Arc machine is created. This repo handles that in
// clientVm/registerArcResourceProviders.bicep.
var arcOnboardingRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b64e21ea-ac4e-4cdf-9dc9-5b892992bee7')

resource arcOnboardingAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, arcOnboardingRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: arcOnboardingRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}
