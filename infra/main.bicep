param location string = 'eastus2'
param tags object = {
  Product: 'AI Foundation'
  Owner: 'eduardo.arias@vertexinc.com'
  Environment: 'POC'
}

// Deploy all landing zone resources into the existing resource group via module
module landingZoneResources 'landingzone.bicep' = {
  name: 'landingZoneResources'
  params: {
    location: location
    tags: tags
  }
}

// Deploy AI Hub Gateway components
module aiHubGateway 'ai-hub-gateway.bicep' = {
  name: 'aiHubGateway'
  params: {
    location: location
    tags: tags
    vnetId: landingZoneResources.outputs.vnetId
    keyVaultId: landingZoneResources.outputs.keyVaultId
    logAnalyticsId: landingZoneResources.outputs.logAnalyticsId
    storageAccountId: landingZoneResources.outputs.storageAccountId
  }
  dependsOn: [
    landingZoneResources
  ]
}

// Deploy AI Services
module aiServices 'ai-services.bicep' = {
  name: 'aiServices'
  params: {
    location: location
    tags: tags
    vnetId: landingZoneResources.outputs.vnetId
    keyVaultId: landingZoneResources.outputs.keyVaultId
  }
  dependsOn: [
    landingZoneResources
  ]
}

// Deploy Backend Systems (AKS, App Services, etc.)
module backendSystems 'backend-systems.bicep' = {
  name: 'backendSystems'
  params: {
    location: location
    tags: tags
    vnetId: landingZoneResources.outputs.vnetId
    logAnalyticsId: landingZoneResources.outputs.logAnalyticsId
  }
  dependsOn: [
    landingZoneResources
  ]
}
