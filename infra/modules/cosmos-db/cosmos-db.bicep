@description('Azure Cosmos DB account name, max length 44 characters')
param accountName string

@description('Location for the Azure Cosmos DB account.')
param location string = resourceGroup().location

@description('The primary region for the Azure Cosmos DB account.')
param primaryRegion string = location

param tags object = {}

@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
@description('The default consistency level of the Cosmos DB account.')
param defaultConsistencyLevel string = 'Session'

@minValue(10)
@maxValue(2147483647)
@description('Max stale requests. Required for BoundedStaleness. Valid ranges, Single Region: 10 to 2147483647. Multi Region: 100000 to 2147483647.')
param maxStalenessPrefix int = 100000

@minValue(5)
@maxValue(86400)
@description('Max lag time (minutes). Required for BoundedStaleness. Valid ranges, Single Region: 5 to 84600. Multi Region: 300 to 86400.')
param maxIntervalInSeconds int = 300

@allowed([
  true
  false
])
@description('Enable system managed failover for regions')
param systemManagedFailover bool = true

@description('The name for the database')
param databaseName string = 'ai-usage-db'

@description('The name for the container')
param containerName string = 'ai-usage-container'

@description('The name for the container')
param pricingContainerName string = 'model-pricing'

@description('The name for the container')
param streamingExportConfigContainerName string = 'streaming-export-config'

@minValue(400)
@maxValue(1000000)
@description('The throughput for the container')
param throughput int = 400

var consistencyPolicy = {
  Eventual: {
    defaultConsistencyLevel: 'Eventual'
  }
  ConsistentPrefix: {
    defaultConsistencyLevel: 'ConsistentPrefix'
  }
  Session: {
    defaultConsistencyLevel: 'Session'
  }
  BoundedStaleness: {
    defaultConsistencyLevel: 'BoundedStaleness'
    maxStalenessPrefix: maxStalenessPrefix
    maxIntervalInSeconds: maxIntervalInSeconds
  }
  Strong: {
    defaultConsistencyLevel: 'Strong'
  }
}
var locations = [
  {
    locationName: primaryRegion
    failoverPriority: 0
    isZoneRedundant: false
  }
]

// Networking
param cosmosPrivateEndpointName string
param vNetName string
param privateEndpointSubnetName string
param cosmosDnsZoneName string
param publicAccess string = 'Disabled'

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

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = {
  name: toLower(accountName)
  location: location
  tags: union(tags, { 'azd-service-name': accountName })
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: consistencyPolicy[defaultConsistencyLevel]
    locations: locations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: systemManagedFailover
    disableKeyBasedMetadataWriteAccess: true
    publicNetworkAccess: publicAccess
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-02-15-preview' = {
  parent: account
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/productName'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: throughput
    }
  }
}

resource modelPricingContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
  parent: database
  name: pricingContainerName
  properties: {
    resource: {
      id: pricingContainerName
      partitionKey: {
        paths: [
          '/model'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: throughput
    }
  }
}

resource streamingExportConfigContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
  parent: database
  name: streamingExportConfigContainerName
  properties: {
    resource: {
      id: streamingExportConfigContainerName
      partitionKey: {
        paths: [
          '/type'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
    options: {
      throughput: throughput
    }
  }
}

module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${accountName}-privateEndpoint'
  params: {
    groupIds: [
      'sql'
    ]
    dnsZoneName: cosmosDnsZoneName
    name: cosmosPrivateEndpointName
    privateLinkServiceId: account.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: subnet.id
    dnsSubId: dnsSubscriptionId
  }
}

output location string = location
output cosmosDbAccountName string = account.name
output cosmosDbDatabaseName string = database.name
output cosmosDbContainerName string = container.name
output cosmosDbPricingContainerName string = modelPricingContainer.name
output cosmosDbStreamingExportConfigContainerName string = streamingExportConfigContainer.name
output resourceId string = database.id
output cosmosDbEndpoint string = 'https://${account.name}.documents.azure.com:443/'
