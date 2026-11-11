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
param isAPIMV2SKU bool
param tags object = {}

@description('Enable provisioning of the AI Foundry agent network injection subnet (delegated to Microsoft.App/environments).')
param enableAgentSubnet bool = true

@description('Name of the AI Foundry agent (network injection) subnet.')
param agentSubnetName string = 'snet-agents'

@description('NSG name for the AI Foundry agent (network injection) subnet.')
param agentSubnetNsgName string = 'nsg-agents'

@description('Address prefix for the AI Foundry agent (network injection) subnet. Must not overlap other subnets.')
param agentSubnetAddressPrefix string = '10.170.0.192/26'

// Set to true to enable service endpoints for APIM subnet
param enableServiceEndpointsForAPIM bool = true

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

resource agentNsg 'Microsoft.Network/networkSecurityGroups@2020-07-01' = if (enableAgentSubnet) {
  name: agentSubnetNsgName
  location: location
  tags: union(tags, { 'azd-service-name': agentSubnetNsgName })
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

// Omitting the parent subnets property preserves subnets managed outside this template.
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2026-01-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }

  resource apimSubnet 'subnets' = {
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
        {
          service: 'Microsoft.CognitiveServices'
        }
      ] : []
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      delegations: isAPIMV2SKU ? [
        {
          name: 'Microsoft.Web/serverFarms'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ] : []
    }
  }

  resource privateEndpointSubnet 'subnets' = {
    name: privateEndpointSubnetName
    properties: {
      addressPrefix: privateEndpointSubnetAddressPrefix
      networkSecurityGroup: privateEndpointNsg.id == '' ? null : {
        id: privateEndpointNsg.id
      }
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      serviceEndpoints: [
        {
          service: 'Microsoft.CognitiveServices'
        }
      ]
    }
    // Serialize subnet writes to avoid concurrent updates to the same VNet.
    dependsOn: [
      virtualNetwork::apimSubnet
    ]
  }

  resource functionAppSubnet 'subnets' = {
    name: functionAppSubnetName
    properties: {
      addressPrefix: functionAppSubnetAddressPrefix
      networkSecurityGroup: functionAppNsg.id == '' ? null : {
        id: functionAppNsg.id
      }
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      serviceEndpoints: [
        {
          service: 'Microsoft.CognitiveServices'
        }
      ]
      delegations: [
        {
          name: 'Microsoft.Web/serverFarms'
          properties: {
            serviceName: 'Microsoft.Web/serverFarms'
          }
        }
      ]
    }
    dependsOn: [
      virtualNetwork::privateEndpointSubnet
    ]
  }

  resource agentSubnet 'subnets' = if (enableAgentSubnet) {
    name: agentSubnetName
    properties: {
      addressPrefix: agentSubnetAddressPrefix
      networkSecurityGroup: {
        id: agentNsg.id
      }
      privateEndpointNetworkPolicies: 'Enabled'
      privateLinkServiceNetworkPolicies: 'Enabled'
      delegations: [
        {
          name: 'Microsoft.app/environments'
          properties: {
            serviceName: 'Microsoft.App/environments'
          }
        }
      ]
    }
    dependsOn: [
      virtualNetwork::functionAppSubnet
    ]
  }
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: '${privateDnsZoneName}/privateDnsZoneLink'
  location: 'global'
  tags: tags
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
output agentSubnetName string = enableAgentSubnet ? virtualNetwork::agentSubnet.name : ''
output agentSubnetId string = enableAgentSubnet ? virtualNetwork::agentSubnet.id : ''
output location string = virtualNetwork.location
output vnetRG string = resourceGroup().name
