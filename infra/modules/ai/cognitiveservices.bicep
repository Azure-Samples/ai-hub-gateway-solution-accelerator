param name string
param location string = resourceGroup().location
param tags object = {}
param managedIdentityName string = ''
param deployments array = []
param kind string = 'OpenAI'
param sku object = {
  name: 'S0'
}
param deploymentCapacity int = 1

// Networking
param publicNetworkAccess string = 'Disabled'
param openAiPrivateEndpointName string
param vNetName string
param vNetLocation string
param privateEndpointSubnetName string
param openAiDnsZoneName string

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource account 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
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
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
  sku: sku
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in deployments: {
  parent: account
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

module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${account.name}-privateEndpoint'
  params: {
    groupIds: [
      'account'
    ]
    dnsZoneName: openAiDnsZoneName
    name: openAiPrivateEndpointName
    subnetName: privateEndpointSubnetName
    privateLinkServiceId: account.id
    vNetName: vNetName
    location: vNetLocation
  }
}

output openAiName string = account.name
output openAiEndpointUri string = '${account.properties.endpoint}openai/'
