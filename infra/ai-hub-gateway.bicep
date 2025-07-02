param location string
param tags object
param vnetId string
param keyVaultId string
param logAnalyticsId string
param storageAccountId string

// Get existing VNet reference



resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: split(vnetId, '/')[8]
}

// API Management Subnet
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' = {
  parent: vnet
  name: 'apim-subnet'
  properties: {
    addressPrefix: '192.168.10.64/26'
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
      }
    ]
  }
}

// API Management
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: 'aihub-apim-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: 'admin@contoso.com'
    publisherName: 'AI Hub Gateway'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: 'aihub-eventhub-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
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
  name: 'aihub-appinsights'
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
  name: 'aihub-adf-${uniqueString(resourceGroup().id)}'
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
