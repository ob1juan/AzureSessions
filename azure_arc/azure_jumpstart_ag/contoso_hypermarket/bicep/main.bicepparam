using 'main.bicep'

param tenantId = ''
param windowsAdminUsername = 'agora'
param windowsAdminPassword = az.getSecret('<subscription-id>', '<resource-group-name>', '<key-vault-name>', '<secret-name>')
param deployBastion = false
param customLocationRPOID = ''
param sshRSAPublicKey = ''
param fabricCapacityAdmin = ''
