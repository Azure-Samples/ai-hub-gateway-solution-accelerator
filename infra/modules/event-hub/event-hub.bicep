param name string
param location string = resourceGroup().location
param sku string = 'Standard'
param capacity int = 1
param tags object = {}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-01-01-preview' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-01-01-preview' = {
  name: 'ai-usage'
  parent: eventHubNamespace
  properties: {
    messageRetentionInDays: 7
    partitionCount: 2
    status: 'Active'
  }
}

output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output eventHubEndpoint string = eventHubNamespace.properties.serviceBusEndpoint
