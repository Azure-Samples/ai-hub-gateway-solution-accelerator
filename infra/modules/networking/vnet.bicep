param name string
param location string = resourceGroup().location
param apimSubnetName string
param apimNsgName string
param privateEndpointSubnetName string
param privateEndpointNsgName string
param functionAppSubnetName string
param functionAppNsgName string
param apimRouteTableName string
param privateDnsZoneNames array
param vnetAddressPrefix string
param apimSubnetAddressPrefix string
param privateEndpointSubnetAddressPrefix string
param functionAppSubnetAddressPrefix string
param tags object = {}

// Set to true to enable service endpoints for APIM subnet
param enableServiceEndpointsForAPIM bool = false

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
            sourceAddressPrefix: 'VirtualNetwork'
            destinationAddressPrefix: 'Storage'
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
            sourceAddressPrefix: 'VirtualNetwork'
            destinationAddressPrefix: 'Sql'
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
            sourceAddressPrefix: 'VirtualNetwork'
            destinationAddressPrefix: 'AzureKeyVault'
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
            sourceAddressPrefix: 'VirtualNetwork'
            destinationAddressPrefix: 'AzureMonitor'
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

resource apimRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: apimRouteTableName
  location: location
  tags: union(tags, { 'azd-service-name': apimRouteTableName })
  properties: {
    routes: [
      {
        name: 'apim-management'
        properties: {
          addressPrefix: 'ApiManagement'
          nextHopType: 'Internet'
        }
      }
      // Add additional routes as required
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetAddressPrefix
          networkSecurityGroup: apimNsg.id == '' ? null : {
            id: apimNsg.id 
          }
          routeTable: {
            id: apimRouteTable.id
          }
          serviceEndpoints: enableServiceEndpointsForAPIM ? [
            {
              service: 'Microsoft.AzureActiveDirectory'
            }
            {
              service: 'Microsoft.EventHub'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.ServiceBus'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          networkSecurityGroup: privateEndpointNsg.id == '' ? null : {
            id: privateEndpointNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: functionAppSubnetName
        properties: {
          addressPrefix: functionAppSubnetAddressPrefix
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

output virtualNetworkId string = virtualNetwork.id
output vnetName string = virtualNetwork.name
output apimSubnetName string = virtualNetwork::apimSubnet.name
output apimSubnetId string = virtualNetwork::apimSubnet.id
output privateEndpointSubnetName string = virtualNetwork::privateEndpointSubnet.name
output privateEndpointSubnetId string = virtualNetwork::privateEndpointSubnet.id
output functionAppSubnetName string = virtualNetwork::functionAppSubnet.name
output functionAppSubnetId string = virtualNetwork::functionAppSubnet.id
output location string = virtualNetwork.location
output vnetRG string = resourceGroup().name
