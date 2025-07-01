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
