param location string
param tags object
param vnetId string
param logAnalyticsId string

// Naming convention variables
var shortUniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Get existing VNet reference
resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: split(vnetId, '/')[8]
}

// API Management Subnet
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' = {
  parent: vnet
  name: 'apim-subnet'
  properties: {
    addressPrefix: '10.0.3.0/24'
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
      }
    ]
  }
}

// API Management
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: 'pdddevapim${shortUniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    publisherEmail: 'eduardo.arias@vertexinc.com'
    publisherName: 'Vertex Inc.'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: 'pdddeveh${shortUniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: false
  }
}

// Event Hub for AI Usage Metrics
resource aiUsageEventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: 'ai-usage-metrics'
  properties: {
    messageRetentionInDays: 1
    partitionCount: 2
  }
}

// Application Insights for Hub Performance Monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'pdddevai${shortUniqueSuffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Data Factory for Usage Processing
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: 'pdddevadf${shortUniqueSuffix}'
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Outputs
output apiManagementId string = apiManagement.id
output apiManagementGatewayUrl string = apiManagement.properties.gatewayUrl
output eventHubNamespaceId string = eventHubNamespace.id
output appInsightsId string = appInsights.id
output dataFactoryId string = dataFactory.id
