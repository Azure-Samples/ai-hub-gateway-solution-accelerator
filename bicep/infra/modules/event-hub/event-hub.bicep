param name string
param location string = resourceGroup().location
param sku string = 'Standard'
param capacity int = 1
param tags object = {}
param eventHubName string = 'ai-usage'

param isPIIEnabled bool = true
param eventHubNamePII string = 'pii-usage'

// Private networking parameters
param eventHubPrivateEndpointName string
param vNetName string
param privateEndpointSubnetName string
param eventHubDnsZoneName string
param publicNetworkAccess string = 'Enabled'

// Use existing network/dns zone
param dnsZoneRG string
param dnsSubscriptionId string
param vNetRG string

// Optional: Network rule sets for additional security
// param ipRules array = []
// param virtualNetworkRules array = []
// param defaultAction string = 'Deny'

// Disaster recovery parameters
param zoneRedundant bool = true
param disasterRecoveryConfig object = {}

// Performance and retention parameters
param messageRetentionInDays int = 7
param autoInflateEnabled bool = true
param maximumThroughputUnits int = 20
param kafkaEnabled bool = false

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2025-05-01-preview' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    tier: sku
    capacity: capacity
  }
  properties: {
    isAutoInflateEnabled: autoInflateEnabled
    maximumThroughputUnits: maximumThroughputUnits
    publicNetworkAccess: publicNetworkAccess
    zoneRedundant: zoneRedundant
    kafkaEnabled: kafkaEnabled
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2025-05-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: 4
    status: 'Active'
  }
}

resource eventHubPII 'Microsoft.EventHub/namespaces/eventhubs@2025-05-01-preview' = if (isPIIEnabled) {
  parent: eventHubNamespace
  name: eventHubNamePII
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: 2
    status: 'Active'
  }
}

// Consider adding a consumer group for each consumer application
resource defaultConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: '$Default'
  parent: eventHub
}

resource aiUsageConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: 'aiUsageIngestion'
  parent: eventHub
}

resource defaultPIIConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (isPIIEnabled) {
  name: '$Default'
  parent: eventHubPII
}

resource piiUsageConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (isPIIEnabled) {
  name: 'piiUsageIngestion'
  parent: eventHubPII
}

// Private endpoint for secure connectivity
module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${eventHubName}-pe'
  params: {
    groupIds: [
      'namespace'
    ]
    dnsZoneName: eventHubDnsZoneName
    name: eventHubPrivateEndpointName
    privateLinkServiceId: eventHubNamespace.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: subnet.id
    dnsSubId: dnsSubscriptionId
    tags: tags
  }
}

// Optional: Add disaster recovery configuration if needed
resource disasterRecovery 'Microsoft.EventHub/namespaces/disasterRecoveryConfigs@2024-01-01' = if (!empty(disasterRecoveryConfig)) {
  name: 'default'
  parent: eventHubNamespace
  properties: disasterRecoveryConfig
}

output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = 'ai-usage'
output eventHubEndpoint string = eventHubNamespace.properties.serviceBusEndpoint
output eventHubPIIName string = isPIIEnabled ? 'pii-usage' : ''
output eventHubResourceId string = eventHubNamespace.id
