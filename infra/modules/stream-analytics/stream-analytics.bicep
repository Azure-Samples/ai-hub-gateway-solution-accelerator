param jobName string
param location string = resourceGroup().location
param tags object = {}
param eventHubNamespace string
param eventHubName string
param cosmosDbAccountName string
param cosmosDbDatabaseName string
param cosmosDbContainerName string
param managedIdentityName string


resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: jobName
  location: location
  tags: union(tags, { 'azd-service-name': jobName })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'StandardV2'
    }
    eventsOutOfOrderPolicy: 'Adjust'
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderMaxDelayInSeconds: 5
    compatibilityLevel: '1.2'
    inputs: [
      {
        name: 'input'
        properties: {
          type: 'Stream'
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
            }
          }
          datasource: {
            type: 'Microsoft.EventHub/EventHub'
            properties: {
              authenticationMode: 'Msi'
              eventHubName: eventHubName
              serviceBusNamespace: eventHubNamespace
            }
          }
        }
      }
    ]
    outputs: [
      {
        name: 'output'
        properties: {
          datasource: {
            type: 'Microsoft.Storage/DocumentDB'
            properties: {
              accountId: cosmosDbAccountName
              database: cosmosDbDatabaseName
              collectionNamePattern: cosmosDbContainerName
              authenticationMode: 'Msi'
              documentId: 'id'
              partitionKey: 'productName'
            }
          }
        }
      }
    ]
    transformation: {
      name: 'transformation'
      properties: {
        query: 'SELECT * INTO [output] FROM [input]'
        streamingUnits: 3
      }
    }
  }
}

output asaId string = streamAnalyticsJob.id
