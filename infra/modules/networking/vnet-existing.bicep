param name string
param location string = resourceGroup().location
param useExistingSubnets bool
param vnetRG string
param apimSubnetName string
param apimNsgName string
param privateEndpointSubnetName string
param privateEndpointNsgName string
param functionAppSubnetName string
param functionAppNsgName string
param apimRouteTableName string
param privateDnsZoneNames array
param apimSubnetAddressPrefix string
param privateEndpointSubnetAddressPrefix string
param functionAppSubnetAddressPrefix string
param tags object = {}

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = if(!useExistingSubnets) {
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

resource privateEndpointNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = if(!useExistingSubnets) {
  name: privateEndpointNsgName
  location: location
  tags: union(tags, { 'azd-service-name': privateEndpointNsgName })
  properties: {
    securityRules: []
  }
}

resource functionAppNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = if(!useExistingSubnets) {
  name: functionAppNsgName
  location: location
  tags: union(tags, { 'azd-service-name': functionAppNsgName })
  properties: {
    securityRules: []
  }
}

resource apimRouteTable 'Microsoft.Network/routeTables@2023-11-01' = if(!useExistingSubnets) {
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

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: name
  scope: resourceGroup(vnetRG)
}

module apimSubnet './subnet.bicep' = {
  name: apimSubnetName
  params: {
    vnetName: virtualNetwork.name
    name: apimSubnetName
    vnetRG: vnetRG
    properties: {
      addressPrefix: apimSubnetAddressPrefix
      networkSecurityGroup: apimNsg.id == '' ? null : {
        id: apimNsg.id 
      }
      routeTable: apimRouteTable.id == '' ? null : {
        id: apimRouteTable.id
      }
    }
  }
}

module privateEndpointSubnet './subnet.bicep' = {
  name: privateEndpointSubnetName
  params: {
    vnetName: virtualNetwork.name
    name: privateEndpointSubnetName
    vnetRG: vnetRG
    properties: {
      addressPrefix: privateEndpointSubnetAddressPrefix
      networkSecurityGroup: privateEndpointNsg.id == '' ? null : {
        id: privateEndpointNsg.id 
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
    }
  }
}

module functionAppSubnet './subnet.bicep' = {
  name: functionAppSubnetName
  params: {
    vnetName: virtualNetwork.name
    name: functionAppSubnetName
    vnetRG: vnetRG
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
output apimSubnetName string = apimSubnet.name
output apimSubnetId string = '${virtualNetwork.id}/subnets/${apimSubnetName}'
output privateEndpointSubnetName string = privateEndpointSubnet.name
output privateEndpointSubnetId string = '${virtualNetwork.id}/subnets/${privateEndpointSubnetName}'
output functionAppSubnetName string = functionAppSubnet.name
output functionAppSubnetId string = '${virtualNetwork.id}/subnets/${functionAppSubnetName}'
output location string = virtualNetwork.location
output vnetRG string = vnetRG
