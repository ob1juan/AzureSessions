@description('Azure region for the Virtual WAN resources.')
param location string

@maxLength(7)
@description('Naming prefix shared by the migration demo resources.')
param namingPrefix string

@description('Resource ID of the Azure VNet that contains the Hyper-V host VM.')
param connectedVnetId string

@description('Public IP address used by the nested Ubuntu VPN endpoint through the Hyper-V host NAT.')
param vpnSitePublicIp string

@secure()
@description('Pre-shared key used by the Azure Virtual WAN site-to-site VPN connection.')
param vpnSharedKey string

@description('Address prefix of the Azure VNet connected to the virtual hub.')
param azureVnetAddressPrefix string

@description('Address prefix of the private Hyper-V network advertised by the VPN site.')
param hyperVNetworkAddressPrefix string

@description('Non-overlapping address prefix assigned to the Virtual WAN hub.')
param virtualHubAddressPrefix string = '10.20.0.0/23'

var virtualWanName = '${namingPrefix}-vWAN'
var virtualHubName = '${namingPrefix}-vHub'
var firewallPolicyName = '${namingPrefix}-vHub-FirewallPolicy'
var firewallName = '${namingPrefix}-vHub-Firewall'
var vpnGatewayName = '${namingPrefix}-vHub-VpnGateway'
var vpnSiteName = '${namingPrefix}-HyperV-Site'
var vpnSiteLinkName = '${namingPrefix}-HyperV-Link'

resource virtualWan 'Microsoft.Network/virtualWans@2024-05-01' = {
  name: virtualWanName
  location: location
  properties: {
    allowBranchToBranchTraffic: true
    allowVnetToVnetTraffic: true
    disableVpnEncryption: false
    type: 'Standard'
  }
}

resource virtualHub 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: virtualHubName
  location: location
  properties: {
    addressPrefix: virtualHubAddressPrefix
    hubRoutingPreference: 'VpnGateway'
    sku: 'Standard'
    virtualWan: {
      id: virtualWan.id
    }
  }
}

resource hubVnetConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: virtualHub
  name: '${namingPrefix}-VNet-Connection'
  properties: {
    allowHubToRemoteVnetTransit: true
    allowRemoteVnetToUseHubVnetGateways: true
    enableInternetSecurity: false
    remoteVirtualNetwork: {
      id: connectedVnetId
    }
  }
  dependsOn: [
    routingIntent
  ]
}

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: firewallPolicyName
  location: location
  properties: {
    dnsSettings: {
      enableProxy: false
    }
    sku: {
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
  }
}

resource firewallRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: firewallPolicy
  name: 'HybridPrivateTraffic'
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'AllowHyperVAndAzure'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'AzureToHyperV'
            ruleType: 'NetworkRule'
            sourceAddresses: [
              azureVnetAddressPrefix
            ]
            destinationAddresses: [
              hyperVNetworkAddressPrefix
            ]
            destinationPorts: [
              '*'
            ]
            ipProtocols: [
              'Any'
            ]
          }
          {
            name: 'HyperVToAzure'
            ruleType: 'NetworkRule'
            sourceAddresses: [
              hyperVNetworkAddressPrefix
            ]
            destinationAddresses: [
              azureVnetAddressPrefix
            ]
            destinationPorts: [
              '*'
            ]
            ipProtocols: [
              'Any'
            ]
          }
        ]
      }
    ]
  }
}

resource hubFirewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: firewallName
  location: location
  properties: {
    firewallPolicy: {
      id: firewallPolicy.id
    }
    hubIPAddresses: {
      publicIPs: {
        count: 1
      }
    }
    sku: {
      name: 'AZFW_Hub'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
    virtualHub: {
      id: virtualHub.id
    }
  }
  dependsOn: [
    firewallRuleCollectionGroup
  ]
}

resource routingIntent 'Microsoft.Network/virtualHubs/routingIntent@2024-05-01' = {
  parent: virtualHub
  name: 'routingIntent'
  properties: {
    routingPolicies: [
      {
        name: 'PrivateTrafficPolicy'
        destinations: [
          'PrivateTraffic'
        ]
        nextHop: hubFirewall.id
      }
    ]
  }
}

resource vpnGateway 'Microsoft.Network/vpnGateways@2024-05-01' = {
  name: vpnGatewayName
  location: location
  properties: {
    virtualHub: {
      id: virtualHub.id
    }
    vpnGatewayScaleUnit: 1
  }
  dependsOn: [
    routingIntent
  ]
}

resource vpnSite 'Microsoft.Network/vpnSites@2024-05-01' = {
  name: vpnSiteName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hyperVNetworkAddressPrefix
      ]
    }
    deviceProperties: {
      deviceModel: 'strongSwan'
      deviceVendor: 'Ubuntu'
      linkSpeedInMbps: 100
    }
    virtualWan: {
      id: virtualWan.id
    }
    vpnSiteLinks: [
      {
        name: vpnSiteLinkName
        properties: {
          ipAddress: vpnSitePublicIp
          linkProperties: {
            linkProviderName: 'Nested Hyper-V lab'
            linkSpeedInMbps: 100
          }
        }
      }
    ]
  }
}

resource vpnConnection 'Microsoft.Network/vpnGateways/vpnConnections@2024-05-01' = {
  parent: vpnGateway
  name: '${namingPrefix}-HyperV-Connection'
  properties: {
    enableInternetSecurity: false
    remoteVpnSite: {
      id: vpnSite.id
    }
    vpnLinkConnections: [
      {
        name: '${vpnSiteLinkName}-Connection'
        properties: {
          connectionBandwidth: 100
          dpdTimeoutSeconds: 45
          enableBgp: false
          ipsecPolicies: [
            {
              dhGroup: 'DHGroup14'
              ikeEncryption: 'AES256'
              ikeIntegrity: 'SHA256'
              ipsecEncryption: 'AES256'
              ipsecIntegrity: 'SHA256'
              pfsGroup: 'PFS14'
              saDataSizeKilobytes: 102400000
              saLifeTimeSeconds: 27000
            }
          ]
          sharedKey: vpnSharedKey
          usePolicyBasedTrafficSelectors: false
          vpnConnectionProtocolType: 'IKEv2'
          vpnLinkConnectionMode: 'Default'
          vpnSiteLink: {
            id: '${vpnSite.id}/vpnSiteLinks/${vpnSiteLinkName}'
          }
        }
      }
    ]
  }
}

output virtualWanId string = virtualWan.id
output virtualHubId string = virtualHub.id
output hubVnetConnectionId string = hubVnetConnection.id
output firewallId string = hubFirewall.id
output vpnGatewayId string = vpnGateway.id
output vpnGatewayPublicIp string = vpnGateway.properties.ipConfigurations[0].publicIpAddress
output vpnSiteId string = vpnSite.id
output vpnConnectionId string = vpnConnection.id
