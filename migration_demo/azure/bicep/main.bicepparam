using 'main.bicep'

param tenantId = '<your tenant id>'

param windowsAdminUsername = 'arcdemo'

param passwordLength = 16

param windowsAdminPasswordSecretName = 'windowsAdminPassword'

param deployBastion = true

param vmAutologon = true

