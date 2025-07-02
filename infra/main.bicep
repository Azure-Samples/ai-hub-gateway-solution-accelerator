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

// AI Hub Gateway
module aiHubGateway 'ai-hub-gateway.bicep' = {
  name: 'aiHubGateway'
  params: {
    location: location
    tags: tags
    vnetId: landingZoneResources.outputs.vnetId
    logAnalyticsId: landingZoneResources.outputs.logAnalyticsId
  }
}

// Outputs
output vnetId string = landingZoneResources.outputs.vnetId
output keyVaultId string = landingZoneResources.outputs.keyVaultId
output logAnalyticsId string = landingZoneResources.outputs.logAnalyticsId
output openAIEndpoint string = aiServices.outputs.openAIEndpoint
output apiManagementGatewayUrl string = aiHubGateway.outputs.apiManagementGatewayUrl
