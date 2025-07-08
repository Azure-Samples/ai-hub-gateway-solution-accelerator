param location string = 'eastus2'

// Common tags
var tags = {
  Environment: 'Development'
  Project: 'AI-Hub-Gateway'
  Owner: 'Vertex-Inc'
}

// Landing Zone Resources
module landingZoneResources 'Landingzone.bicep' = {
  name: 'landingZoneResources'
  params: {
    location: location
    tags: tags
  }
}

// AI Services
module aiServices 'ai-services.bicep' = {
  name: 'aiServices'
  params: {
    location: location
    tags: tags
    vnetId: landingZoneResources.outputs.vnetId
    keyVaultId: landingZoneResources.outputs.keyVaultId
  }
}

// Backend Systems
module backendSystems 'backend-systems.bicep' = {
  name: 'backendSystems'
  params: {
    location: location
    tags: tags
  }
}

// Managed Identity for APIM
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'aihub-identity-${substring(uniqueString(resourceGroup().id), 0, 6)}'
  location: location
  tags: tags
}

// Event Hub Data Sender role assignment for APIM
resource eventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'f526a384-b230-433a-b45c-95f59c4a2dec')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec') // Azure Event Hubs Data Sender
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// AI Hub Gateway - Full APIM with Policy Fragments
module aiHubGateway 'modules/apim/apim.bicep' = {
  name: 'aiHubGateway'
  params: {
    name: 'aihub-apim-${substring(uniqueString(resourceGroup().id), 0, 6)}'
    location: location
    tags: tags
    publisherEmail: 'eduardo.arias@vertexinc.com'
    publisherName: 'Vertex Inc.'
    sku: 'Developer'
    applicationInsightsName: 'aihub-appinsights'
    openAiUris: [
      aiServices.outputs.openAIEndpoint
    ]
    managedIdentityName: managedIdentity.name
    eventHubName: 'ai-usage-metrics'
    eventHubEndpoint: 'https://aihub-eventhub-dlcm7h5j57xdm.servicebus.windows.net/'
    apimNetworkType: 'Internal'
    apimSubnetId: '${landingZoneResources.outputs.vnetId}/subnets/apim-subnet'
    enableAzureAISearch: false
    aiSearchInstances: []
  }
}

// Outputs
output vnetId string = landingZoneResources.outputs.vnetId
output keyVaultId string = landingZoneResources.outputs.keyVaultId
output logAnalyticsId string = landingZoneResources.outputs.logAnalyticsId
output openAIEndpoint string = aiServices.outputs.openAIEndpoint
output apiManagementGatewayUrl string = aiHubGateway.outputs.apimGatewayUrl
