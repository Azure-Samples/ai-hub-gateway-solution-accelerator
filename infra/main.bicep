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

@description('Network type for API Management service. Leave blank to use default naming conventions.')
@allowed([ 'None', 'External', 'Internal' ])
param apimNetworkType string = 'External'

@description('Azure OpenAI service public access')
@allowed([ 'Enabled', 'Disabled' ])
param openAIExternalNetworkAccess string = 'Disabled'

@description('Name of the Log Analytics workspace. Leave blank to use default naming conventions.')
param logAnalyticsName string = ''

@description('Create Application Insights dashboard. Turn it on only if you need it.')
param createAppInsightsDashboard bool = false

@description('Name of the Application Insights dashboard. Leave blank to use default naming conventions.')
param applicationInsightsDashboardName string = ''

@description('Name of the Application Insights dashboard. Leave blank to use default naming conventions.')
param funcAplicationInsightsDashboardName string = ''

@description('Name of the Application Insights for APIM resource. Leave blank to use default naming conventions.')
param applicationInsightsName string = ''

@description('Name of the Application Insights for Function App resource. Leave blank to use default naming conventions.')
param funcApplicationInsightsName string = ''

@description('Name of the Event Hub Namespace resource. Leave blank to use default naming conventions.')
param eventHubNamespaceName string = ''

@description('Name of the Cosmos Db account resource. Leave blank to use default naming conventions.')
param cosmosDbAccountName string = ''

@description('Name of the Stream Analytics resource. Leave blank to use default naming conventions.')
param streamAnalyticsJobName string = ''

@description('Name of the Function App resource. Leave blank to use default naming conventions.')
param usageProcessingFunctionAppName string = ''

@description('Name of the Function App resource. Leave blank to use default naming conventions.')
param storageAccountName string = ''

@description('Provision stream analytics job, turn it on only if you need it. Azure Function App will be provisioned to process usage data from Event Hub.')
param provisionStreamAnalytics bool = false

//Networking - VNet
param bringYourOwnVnet bool = true
param vnetName string = ''
param apimSubnetName string = ''
param privateEndpointSubnetName string = ''
param functionAppSubnetName string = ''

param bringYourOwnNsg bool = false
param apimNsgName string = ''
param privateEndpointNsgName string = ''
param functionAppNsgName string = ''

// param appGatewaySubnetName string = ''
// param appGatewayNsgName string = ''
// param appGatewayPublicIpName string = ''

// Networking - Address Space
param vnetAddressPrefix string = '10.170.0.0/24'
param apimSubnetPrefix string = '10.170.0.0/26'
param privateEndpointSubnetPrefix string = '10.170.0.64/26'
param functionAppSubnetPrefix string = '10.170.0.128/26'

// Networking - Private DNS
var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var eventHubPrivateDnsZoneName = 'privatelink.servicebus.windows.net'
var cosmosDbPrivateDnsZoneName = 'privatelink.documents.azure.com'
var storageBlobPrivateDnsZoneName = 'privatelink.blob.core.windows.net'
var storageFilePrivateDnsZoneName = 'privatelink.file.core.windows.net'
var privateDnsZoneNames = [
  openAiPrivateDnsZoneName
  keyVaultPrivateDnsZoneName
  monitorPrivateDnsZoneName
  eventHubPrivateDnsZoneName 
  cosmosDbPrivateDnsZoneName
  storageBlobPrivateDnsZoneName
  storageFilePrivateDnsZoneName
]

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
param deploymentCapacity int = 20

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

module dnsDeployment './modules/networking/dns.bicep' = [for privateDnsZoneName in privateDnsZoneNames: {
  name: 'dns-deployment-${privateDnsZoneName}'
  scope: resourceGroup
  params: {
    name: privateDnsZoneName
  }
}]

module vnet './modules/networking/vnet.bicep' = {
  name: 'vnet'
  scope: resourceGroup
  params: {
    name: !empty(vnetName) ? vnetName : 'vnet-${resourceToken}'
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : 'snet-apim'
    apimNsgName: !empty(apimNsgName) ? apimNsgName : 'nsg-apim-${resourceToken}'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : 'snet-private-endpoint'
    privateEndpointNsgName: !empty(privateEndpointNsgName) ? privateEndpointNsgName : 'nsg-pe-${resourceToken}'
    functionAppSubnetName: !empty(functionAppSubnetName) ? functionAppSubnetName : 'snet-functionapp'
    functionAppNsgName: !empty(functionAppNsgName) ? functionAppNsgName : 'nsg-functionapp-${resourceToken}'
    // appGatewaySubnetName: !empty(appGatewaySubnetName) ? appGatewaySubnetName : 'snet-appgateway'
    // appGatewayNsgName: !empty(appGatewayNsgName) ? appGatewayNsgName : 'nsg-appgateway-${resourceToken}'
    // appGatewayPIPName: !empty(appGatewayPublicIpName) ? appGatewayPublicIpName : 'pip-appgateway-${resourceToken}'
    vnetAddressPrefix: vnetAddressPrefix
    apimSubnetAddressPrefix: apimSubnetPrefix
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetPrefix
    functionAppSubnetAddressPrefix: functionAppSubnetPrefix
    location: location
    tags: tags
    privateDnsZoneNames: privateDnsZoneNames
    apimRouteTableName: 'rt-apim-${resourceToken}'
  }
}

module apimManagedIdentity './modules/security/managed-identity-apim.bicep' = {
  name: 'apim-managed-identity'
  scope: resourceGroup
  params: {
    name: !empty(identityName) ? identityName : '${abbrs.managedIdentityUserAssignedIdentities}apim-${resourceToken}'
    location: location
    tags: tags
  }
}

module usageManagedIdentity './modules/security/managed-identity-stream-analytics.bicep' = {
  name: 'usage-managed-identity'
  scope: resourceGroup
  params: {
    name: !empty(identityName) ? identityName : '${abbrs.managedIdentityUserAssignedIdentities}usage-${resourceToken}'
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
    apimApplicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}apim-${resourceToken}'
    apimApplicationInsightsDashboardName: !empty(applicationInsightsDashboardName) ? applicationInsightsDashboardName : '${abbrs.portalDashboards}apim-${resourceToken}'
    functionApplicationInsightsName: !empty(funcApplicationInsightsName) ? funcApplicationInsightsName : '${abbrs.insightsComponents}func-${resourceToken}'
    functionApplicationInsightsDashboardName: !empty(funcAplicationInsightsDashboardName) ? funcAplicationInsightsDashboardName : '${abbrs.portalDashboards}func-${resourceToken}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    applicationInsightsDnsZoneName: monitorPrivateDnsZoneName
    createDashboard: createAppInsightsDashboard
  }
  dependsOn: [
    vnet
  ]
}

@batchSize(1)
module openAis 'modules/ai/cognitiveservices.bicep' = [for (config, i) in items(openAiInstances): {
  name: '${config.value.name}-${resourceToken}'
  scope: resourceGroup
  params: {
    name: '${config.value.name}-${resourceToken}'
    location: config.value.location
    tags: tags
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    vNetName: vnet.outputs.vnetName
    vNetLocation: vnet.outputs.location
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    openAiPrivateEndpointName: '${config.value.name}-pe-${resourceToken}'
    publicNetworkAccess: openAIExternalNetworkAccess
    openAiDnsZoneName: openAiPrivateDnsZoneName
    sku: {
      name: openAiSkuName
    }
    deploymentCapacity: deploymentCapacity
    deployments: config.value.deployments
  }
  dependsOn: [
    vnet
    apimManagedIdentity
  ]
}]

module eventHub './modules/event-hub/event-hub.bicep' = {
  name: 'event-hub'
  scope: resourceGroup
  params: {
    name: !empty(eventHubNamespaceName) ? eventHubNamespaceName : '${abbrs.eventHubNamespaces}${resourceToken}'
    location: location
    tags: tags
    eventHubPrivateEndpointName: 'eh-pe-${resourceToken}'
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    eventHubDnsZoneName: eventHubPrivateDnsZoneName
  }
  dependsOn: [
    vnet
  ]
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
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    entraAuth: entraAuth
    clientAppId: entraAuth ? entraClientId : null 
    tenantId: entraAuth ? entraTenantId : null
    audience: entraAuth ? entraAudience : null
    eventHubName: eventHub.outputs.eventHubName
    eventHubEndpoint: eventHub.outputs.eventHubEndpoint
    apimSubnetId: vnet.outputs.apimSubnetId
    apimNetworkType: apimNetworkType
  }
  dependsOn: [
    vnet
    apimManagedIdentity
    eventHub
  ]
}

module cosmosDb './modules/cosmos-db/cosmos-db.bicep' = {
  name: 'cosmos-db'
  scope: resourceGroup
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
    vNetName: vnet.outputs.vnetName
    cosmosDnsZoneName: cosmosDbPrivateDnsZoneName
    cosmosPrivateEndpointName: '${abbrs.documentDBDatabaseAccounts}pe-${resourceToken}'
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
  }
  dependsOn: [
    vnet
  ]
}

module streamAnalyticsJob './modules/stream-analytics/stream-analytics.bicep' = if(provisionStreamAnalytics) {
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
    managedIdentityName: usageManagedIdentity.outputs.managedIdentityName
  }
}

module storageAccount './modules/functionapp/storageaccount.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    storageAccountName: !empty(storageAccountName) ? storageAccountName : 'funcusage${resourceToken}'
    functionAppManagedIdentityName: usageManagedIdentity.outputs.managedIdentityName
    vNetName: vnet.outputs.vnetName
    privateEndpointSubnetName: vnet.outputs.privateEndpointSubnetName
    storageBlobDnsZoneName: storageBlobPrivateDnsZoneName
    storageFileDnsZoneName: storageFilePrivateDnsZoneName
    storageBlobPrivateEndpointName: '${abbrs.storageStorageAccounts}blob-pe-${resourceToken}'
    storageFilePrivateEndpointName: '${abbrs.storageStorageAccounts}file-pe-${resourceToken}'
    functionSubnetId: vnet.outputs.functionAppSubnetId
  }
  dependsOn: [
    vnet
  ]
}

module functionApp './modules/functionapp/functionapp.bicep' = {
  name: 'usageFunctionApp'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    functionAppName: !empty(usageProcessingFunctionAppName) ? usageProcessingFunctionAppName : '${abbrs.webSitesFunctions}usage-${resourceToken}'
    azdserviceName: 'usageProcessingFunctionApp'   
    storageAccountName: storageAccount.outputs.storageAccountName
    functionAppIdentityName: usageManagedIdentity.outputs.managedIdentityName
    applicationInsightsName: monitoring.outputs.funcApplicationInsightsName
    eventHubNamespaceName: eventHub.outputs.eventHubNamespaceName
    eventHubName: eventHub.outputs.eventHubName
    cosmosDBEndpoint: cosmosDb.outputs.cosmosDbEndpoint
    cosmosDatabaseName: cosmosDb.outputs.cosmosDbDatabaseName
    cosmosContainerName: cosmosDb.outputs.cosmosDbContainerName
    vnetName: vnet.outputs.vnetName
    functionAppSubnetId: vnet.outputs.functionAppSubnetId
  }
  dependsOn: [
    vnet
    storageAccount
    usageManagedIdentity
    monitoring
    eventHub
    cosmosDb
  ]
}

output APIM_NAME string = apim.outputs.apimName
output APIM_AOI_PATH string = apim.outputs.apimOpenaiApiPath
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
