targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (filtered on available regions for Azure Open AI Service).')
@allowed([ 'westeurope', 'southcentralus', 'australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth' ])
param location string

//Leave blank to use default naming conventions

@description('Name of the resource group. Leave blank to use default naming conventions.')
param resourceGroupName string = ''

@description('Name of the identity. Leave blank to use default naming conventions.')
param identityName string = ''

@description('Name of the API Management service. Leave blank to use default naming conventions.')
param apimServiceName string = ''

@description('Name of the Log Analytics workspace. Leave blank to use default naming conventions.')
param logAnalyticsName string = ''

@description('Name of the Application Insights dashboard. Leave blank to use default naming conventions.')
param applicationInsightsDashboardName string = ''

@description('Name of the Application Insights resource. Leave blank to use default naming conventions.')
param applicationInsightsName string = ''

@description('Name of the Event Hub Namespace resource. Leave blank to use default naming conventions.')
param eventHubNamespaceName string = ''

@description('Name of the Cosmos Db account resource. Leave blank to use default naming conventions.')
param cosmosDbAccountName string = ''

@description('Name of the Stream Analytics resource. Leave blank to use default naming conventions.')
param streamAnalyticsJobName string = ''


// You can add more OpenAI instances by adding more objects to the openAiInstances object
// Then update the apim policy xml to include the new instances
@description('Object containing OpenAI instances. You can add more instances by adding more objects to this parameter.')
param openAiInstances object = {
  openAi1: {
    name: 'openai1'
    location: 'eastus'
    deployments: [
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: chatGptModelVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: embeddingGptDeploymentName
        model: {
          format: 'OpenAI'
          name: embeddingGptModelName
          version: embeddingGptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: deploymentCapacity
        }
      }
      {
        name: 'gpt-4o'
        model: {
          format: 'OpenAI'
          name: 'gpt-4o'
          version: '2024-05-13'
        }
        sku: {
          name: 'GlobalStandard'
          capacity: deploymentCapacity
        }
      }
      {
        name: 'dall-e-3'
        location: 'eastus'
        model: {
          format: 'OpenAI'
          name: 'dall-e-3'
          version: '3.0'
        }
        sku: {
          name: 'Standard'
          capacity: 1
        }
      }
    ]
  }
  openAi2: {
    name: 'openai2'
    location: 'northcentralus'
    deployments: [
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: chatGptModelVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: embeddingGptDeploymentName
        model: {
          format: 'OpenAI'
          name: embeddingGptModelName
          version: embeddingGptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
  openAi3: {
    name: 'openai3'
    location: 'eastus2'
    deployments: [
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: chatGptModelVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: embeddingGptDeploymentName
        model: {
          format: 'OpenAI'
          name: embeddingGptModelName
          version: embeddingGptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
}

@description('SKU name for OpenAI.')
param openAiSkuName string = 'S0'

@description('Version of the Chat GPT model.')
param chatGptModelVersion string = '0613'

@description('Name of the Chat GPT deployment.')
param chatGptDeploymentName string = 'chat'

@description('Name of the Chat GPT model.')
param chatGptModelName string = 'gpt-35-turbo'

@description('Name of the embedding model.')
param embeddingGptModelName string = 'text-embedding-ada-002'

@description('Version of the embedding model.')
param embeddingGptModelVersion string = '2'

@description('Name of the embedding deployment.')
param embeddingGptDeploymentName string = 'embedding'

@description('The OpenAI endpoints capacity (in thousands of tokens per minute)')
param deploymentCapacity int = 30

@description('Tags to be applied to resources.')
param tags object = { 'azd-env-name': environmentName }

@description('Should Entra ID validation be enabled')
param entraAuth bool = false
param entraTenantId string = ''
param entraClientId string = ''
param entraAudience string = '' 


// Load abbreviations from JSON file
var abbrs = loadJsonContent('./abbreviations.json')
// Generate a unique token for resources
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))


// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module managedIdentity './modules/security/managed-identity-apim.bicep' = {
  name: 'managed-identity'
  scope: resourceGroup
  params: {
    name: !empty(identityName) ? identityName : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module streamAnalyticsManagedIdentity './modules/security/managed-identity-stream-analytics.bicep' = {
  name: 'stream-analytics-managed-identity'
  scope: resourceGroup
  params: {
    name: !empty(identityName) ? identityName : '${abbrs.managedIdentityUserAssignedIdentities}asa-${resourceToken}'
    location: location
    tags: tags
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
  }
}

module monitoring './modules/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}${resourceToken}'
  }
}

module openAis 'modules/ai/cognitiveservices.bicep' = [for (config, i) in items(openAiInstances): {
  name: '${config.value.name}-${resourceToken}'
  scope: resourceGroup
  params: {
    name: '${config.value.name}-${resourceToken}'
    location: config.value.location
    tags: tags
    managedIdentityName: managedIdentity.outputs.managedIdentityName
    sku: {
      name: openAiSkuName
    }
    deploymentCapacity: deploymentCapacity
    deployments: config.value.deployments
  }
}]

module eventHub './modules/event-hub/event-hub.bicep' = {
  name: 'event-hub'
  scope: resourceGroup
  params: {
    name: !empty(eventHubNamespaceName) ? eventHubNamespaceName : '${abbrs.eventHubNamespaces}${resourceToken}'
    location: location
    tags: tags
  }
}

module apim './modules/apim/apim.bicep' = {
  name: 'apim'
  scope: resourceGroup
  params: {
    name: !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    openAiUris: [for i in range(0, length(openAiInstances)): openAis[i].outputs.openAiEndpointUri]
    managedIdentityName: managedIdentity.outputs.managedIdentityName
    entraAuth: entraAuth
    clientAppId: entraAuth ? entraClientId : null 
    tenantId: entraAuth ? entraTenantId : null
    audience: entraAuth ? entraAudience : null
    eventHubName: eventHub.outputs.eventHubName
    eventHubEndpoint: eventHub.outputs.eventHubEndpoint
  }
}

module cosmosDb './modules/cosmos-db/cosmos-db.bicep' = {
  name: 'cosmos-db'
  scope: resourceGroup
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
  }
}

module streamAnalyticsJob './modules/stream-analytics/stream-analytics.bicep' = {
  name: 'stream-analytics-job'
  scope: resourceGroup
  params: {
    jobName: !empty(streamAnalyticsJobName) ? streamAnalyticsJobName : '${abbrs.streamAnalyticsCluster}${resourceToken}'
    location: location
    tags: tags
    eventHubNamespace: eventHub.outputs.eventHubNamespaceName
    eventHubName: eventHub.outputs.eventHubName
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    cosmosDbDatabaseName: cosmosDb.outputs.cosmosDbDatabaseName
    cosmosDbContainerName: cosmosDb.outputs.cosmosDbContainerName
    managedIdentityName: streamAnalyticsManagedIdentity.outputs.managedIdentityName
  }
}

output APIM_NAME string = apim.outputs.apimName
output APIM_AOI_PATH string = apim.outputs.apimOpenaiApiPath
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
