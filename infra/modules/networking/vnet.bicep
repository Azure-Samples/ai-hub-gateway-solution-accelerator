param name string
param location string = resourceGroup().location
param appGatewaySubnetName string
param appGatewayNsgName string
param appGatewayPIPName string
param apimSubnetName string
param apimNsgName string
param privateEndpointSubnetName string
param privateEndpointNsgName string
param functionAppSubnetName string
param functionAppNsgName string
param privateDnsZoneNames array
param tags object = {}

resource appGatewayNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: appGatewayNsgName
  location: location
  tags: union(tags, { 'azd-service-name': appGatewayNsgName })
  properties: {
    securityRules: [
      {
        name: 'AllowPublicAccess'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '443'
            sourceAddressPrefix: 'Internet'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3000
            direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbes'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 3010
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 3020
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: apimNsgName
  location: location
  tags: union(tags, { 'azd-service-name': apimNsgName })
  properties: {
    securityRules: [
      {
        name: 'AllowPublicAccess' // Only External
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '443'
            sourceAddressPrefix: 'Internet'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3000
            direction: 'Inbound'
        }
      }
      {
        name: 'AllowAPIMManagement'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '3443'
            sourceAddressPrefix: 'ApiManagement'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3010
            direction: 'Inbound'
        }
      }
      {
        name: 'AllowAPIMLoadBalancer'
        properties: {
            protocol: '*'
            sourcePortRange: '*'
            destinationPortRange: '6390'
            sourceAddressPrefix: 'AzureLoadBalancer'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3020
            direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureTrafficManager' //Only External
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '443'
            sourceAddressPrefix: 'AzureTrafficManager'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3030
            direction: 'Inbound'
        }
      }
      {
        name: 'AllowStorage'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '443'
            sourceAddressPrefix: 'Storage'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3000
            direction: 'Outbound'
        }
      }
      {
        name: 'AllowSql'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '1433'
            sourceAddressPrefix: 'Sql'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3010
            direction: 'Outbound'
        }
      }
      {
        name: 'AllowKeyVault'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRange: '443'
            sourceAddressPrefix: 'AzureKeyVault'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3020
            direction: 'Outbound'
        }
      }
      {
        name: 'AllowMonitor'
        properties: {
            protocol: 'Tcp'
            sourcePortRange: '*'
            destinationPortRanges: ['1886', '443']
            sourceAddressPrefix: 'AzureMonitor'
            destinationAddressPrefix: 'VirtualNetwork'
            access: 'Allow'
            priority: 3030
            direction: 'Outbound'
        }
      }
    ]
  }
}

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: privateEndpointNsgName
  location: location
  tags: union(tags, { 'azd-service-name': privateEndpointNsgName })
  properties: {
    securityRules: []
  }
}

resource functionAppNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = {
  name: functionAppNsgName
  location: location
  tags: union(tags, { 'azd-service-name': functionAppNsgName })
  properties: {
    securityRules: []
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.170.0.0/16'
      ]
    }
    subnets: [
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: '10.170.0.0/24'
          networkSecurityGroup: appGatewayNsg.id == '' ? null : {
            id: appGatewayNsg.id 
          }
        }
      }
      {
        name: apimSubnetName
        properties: {
          addressPrefix: '10.170.1.0/24'
          networkSecurityGroup: apimNsg.id == '' ? null : {
            id: apimNsg.id 
          }
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.170.2.0/24'
          networkSecurityGroup: privateEndpointNsg.id == '' ? null : {
            id: privateEndpointNsg.id
          }
        }
      }
      {
        name: functionAppSubnetName
        properties: {
          addressPrefix: '10.170.3.0/24'
          networkSecurityGroup: functionAppNsg.id == '' ? null : {
            id: functionAppNsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'Microsoft.Web/serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }

  resource appGatewaySubnet 'subnets' existing = {
    name: appGatewaySubnetName
  }

  resource apimSubnet 'subnets' existing = {
    name: apimSubnetName
  }

  resource privateEndpointSubnet 'subnets' existing = {
    name: privateEndpointSubnetName
  }

  resource functionAppSubnet 'subnets' existing = {
    name: functionAppSubnetName
  }
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: '${privateDnsZoneName}/privateDnsZoneLink'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: virtualNetwork.id
    }
    registrationEnabled: false
  }
}]

// Public IP 
// resource pipAppGateway 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
//   name: appGatewayPIPName
//   location: location
//   sku: {
//     name: 'Standard'
//   }
//   properties: {
//     publicIPAddressVersion: 'IPv4'
//     publicIPAllocationMethod: 'Static'
//     dnsSettings: {
//       domainNameLabel: appGatewayPIPName
//     }
//   }
// }

output virtualNetworkId string = virtualNetwork.id
output vnetName string = virtualNetwork.name
output apimSubnetName string = virtualNetwork::apimSubnet.name
output apimSubnetId string = virtualNetwork::apimSubnet.id
output privateEndpointSubnetName string = virtualNetwork::privateEndpointSubnet.name
output privateEndpointSubnetId string = virtualNetwork::privateEndpointSubnet.id
output functionAppSubnetName string = virtualNetwork::functionAppSubnet.name
output functionAppSubnetId string = virtualNetwork::functionAppSubnet.id
output location string = virtualNetwork.location
