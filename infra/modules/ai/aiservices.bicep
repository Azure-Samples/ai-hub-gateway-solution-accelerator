param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityName string = ''
param deployments array = []
param kind string = 'AIServices'
param sku object = {
  name: 'S0'
}
param deploymentCapacity int = 1

// Networking
param publicNetworkAccess string = 'Disabled'
param aiServicesPrivateEndpointName string
param vNetName string
param vNetLocation string
param privateEndpointSubnetName string
param aiCognitiveServicesDnsZoneName string

// Use existing network/dns zone
param dnsZoneRG string
param dnsSubscriptionId string
param vNetRG string
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource aiServicesAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  kind: kind
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    customSubDomainName: toLower(name)
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
  sku: sku
}

@batchSize(1)
resource aiServicesDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in deployments: {
  parent: aiServicesAccount
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: contains(deployment, 'raiPolicyName') ? deployment.raiPolicyName : null
  }
  sku: contains(deployment, 'sku') ? deployment.sku : {
    name: 'Standard'
    capacity: deploymentCapacity
  }
}]

module aiServicesPrivateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${aiServicesAccount.name}-privateEndpoint'
  params: {
    groupIds: [
      'account'
    ]
    dnsZoneName: aiCognitiveServicesDnsZoneName
    name: aiServicesPrivateEndpointName
    privateLinkServiceId: aiServicesAccount.id
    location: vNetLocation
    privateEndpointSubnetId: subnet.id
    dnsZoneRG: dnsZoneRG
    dnsSubId: dnsSubscriptionId
  }
  dependsOn: [
    aiServicesDeployment
  ]
}

output aiServicesName string = aiServicesAccount.name
output aiServicesEndpoint string = replace(aiServicesAccount.properties.endpoint, '.cognitiveservices.azure.com/', '.services.ai.azure.com/models/')
