using 'main.bicep'

param tenantId = '<your tenant id>'

param location = 'centralus'

param windowsAdminUsername = 'arcdemo'

param passwordLength = 16

param windowsAdminPasswordSecretName = 'windowsAdminPassword'

param registryPasswordSecretName = 'registryPassword'

param logAnalyticsWorkspaceName = '<your unique Log Analytics workspace name>'

param deployBastion = true

param vmAutologon = true

param resourceTags = {} // Add tags as needed
