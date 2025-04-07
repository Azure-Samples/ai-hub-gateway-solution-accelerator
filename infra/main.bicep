targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (filtered on available regions for Azure Open AI Service).')
//@allowed([ 'uaenorth', 'sothafricanorth', 'westeurope', 'southcentralus', 'australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth' ])
@allowed([  'westeurope', 'francecentral', 'swedencentral', 'switzerlandnorth'])
param location string

//Leave blank to use default naming conventions

@description('Name of the resource group. Leave blank to use default naming conventions.')
param resourceGroupName string = ''

@description('Name of the identity. Leave blank to use default naming conventions.')
param identityName string = ''

@description('Name of the API Management service. Leave blank to use default naming conventions.')
param apimServiceName string = ''

@description('Network type for API Management service. Leave blank to use default naming conventions.')
@allowed([ 'External', 'Internal' ])
param apimNetworkType string = 'External'

@description('API Management service SKU. Due to networking constraints, only Developer and Premium are supported.')
@allowed([ 'Developer', 'Premium' ])
param apimSku string // = 'Developer'

@description('API Management service SKU units.')
param apimSkuUnits int = 1

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

@description('Flag to create Azure Function App. Turn it on only if you need it.')
param provisionFunctionApp bool = false

@description('Name of the Function App resource. Leave blank to use default naming conventions.')
param usageProcessingFunctionAppName string = ''

@description('Name of the Function App resource. Leave blank to use default naming conventions.')
param storageAccountName string = ''

@description('Name of the Storage Account file share used by Azure Function')
param functionContentShareName string = 'usage-function-content'

@description('Name of the Storage Account file share used by Azure Function')
param logicContentShareName string = 'usage-logic-content'

@description('Provision stream analytics job, turn it on only if you need it. Azure Function App will be provisioned to process usage data from Event Hub.')
param provisionStreamAnalytics bool = false

@description('This is to use Azure Monitor Private Link Scope for Log Analytics and Application Insights. If exsiting vnet is used, this should not be enabled')
param useAzureMonitorPrivateLinkScope bool = !useExistingVnet

//Networking - VNet

// ONLY for using existing VNet, set useExistingVnet to true and provide the existing VNet details
param useExistingVnet bool = false
param existingVnetRG string = ''
param vnetName string = ''
param apimSubnetName string = ''
param privateEndpointSubnetName string = ''
param functionAppSubnetName string = ''

// ONLY for existing VNet - Existing Private DNS zones mapping
param dnsZoneRG string = ''
param dnsSubscriptionId string = ''

// Networking - NSG naming (leave blank to use default naming conventions)
param apimNsgName string = ''
param privateEndpointNsgName string = ''
param functionAppNsgName string = ''

// Networking - Address Space
param vnetAddressPrefix string = '10.170.0.0/24'
param apimSubnetPrefix string = '10.170.0.0/26'
param privateEndpointSubnetPrefix string = '10.170.0.64/26'
param functionAppSubnetPrefix string = '10.170.0.128/26'



var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var eventHubPrivateDnsZoneName = 'privatelink.servicebus.windows.net'
var cosmosDbPrivateDnsZoneName = 'privatelink.documents.azure.com'
var storageBlobPrivateDnsZoneName = 'privatelink.blob.core.windows.net'
var storageFilePrivateDnsZoneName = 'privatelink.file.core.windows.net'
var storageTablePrivateDnsZoneName = 'privatelink.table.core.windows.net'
var storageQueuePrivateDnsZoneName = 'privatelink.queue.core.windows.net'

var privateDnsZoneNames = [
  openAiPrivateDnsZoneName
  keyVaultPrivateDnsZoneName
  monitorPrivateDnsZoneName
  eventHubPrivateDnsZoneName 
  cosmosDbPrivateDnsZoneName
  storageBlobPrivateDnsZoneName
  storageFilePrivateDnsZoneName
  storageTablePrivateDnsZoneName
  storageQueuePrivateDnsZoneName
]

// You can add more OpenAI instances by adding more objects to the openAiInstances object
// Then update the apim policy xml to include the new instances
@description('Object containing OpenAI instances. You can add more instances by adding more objects to this parameter.')
param openAiInstances object = {
  openAi1: {
    name: 'openai1'
    location: 'swedencentral'
    priority: 1
    weight: 100
    deployments: [
      {
        name: 'chat'
        model: {
          format: 'OpenAI'
          name: 'gpt-4o-mini'
          version: '2024-07-18'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
        
      }
      {
        name: 'embedding'
        model: {
          format: 'OpenAI'
          name: 'text-embedding-3-large'
          version: '1'
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
          version: '2024-11-20'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
  openAi2: {
    name: 'openai2'
    location: 'francecentral'
    priority: 2
    weight: 50
    deployments: [
      {
        name: 'chat'
        model: {
          format: 'OpenAI'
          name: 'gpt-4o-mini'
          version: '2024-07-18'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
        
      }
      {
        name: 'embedding'
        model: {
          format: 'OpenAI'
          name: 'text-embedding-3-large'
          version: '1'
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
          version: '2024-11-20'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
  openAi3: {
    name: 'openai3'
    location: 'spaincentral'
    priority: 2
    weight: 50
    deployments: [
      {
        name: 'chat'
        model: {
          format: 'OpenAI'
          name: 'gpt-4o-mini'
          version: '2024-07-18'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
        
      }
      {
        name: 'embedding'
        model: {
          format: 'OpenAI'
          name: 'text-embedding-3-large'
          version: '1'
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
          version: '2024-11-20'
        }
        sku: {
          name: 'DataZoneStandard'
          capacity: deploymentCapacity
        }
      }
    ]
  }
}


param enableAzureAISearch bool = false

@description('Object containing AI Search existing instances. You can add more instances by adding more objects to this parameter.')
param aiSearchInstances array = [
  {
    name: 'ai-search-swn'
    url: 'https://REPLACE1.search.windows.net/'
    description: 'AI Search Instance 1'
  }
  {
    name: 'ai-search-sec'
    url: 'https://REPLACE2.search.windows.net/'
    description: 'AI Search Instance 2'
  }
]

// OpenAI settings
@description('SKU name for OpenAI.')
param openAiSkuName string = 'S0'

@description('The OpenAI endpoints capacity (in thousands of tokens per minute)')
param deploymentCapacity int = 20

@description('Tags to be applied to resources.')
param tags object = { 'azd-env-name': environmentName }

@description('Should Entra ID validation be enabled')
param entraAuth bool = false
param entraTenantId string = ''
param entraClientId string = ''
param entraAudience string = '' 

param usageProcessingLogicAppName string = ''

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

module dnsDeployment './modules/networking/dns.bicep' = [for privateDnsZoneName in privateDnsZoneNames: if(!useExistingVnet) {
  name: 'dns-deployment-${privateDnsZoneName}'
  scope: resourceGroup
  params: {
    name: privateDnsZoneName
  }
}]

module vnet './modules/networking/vnet.bicep' = if(!useExistingVnet) {
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
    vnetAddressPrefix: vnetAddressPrefix
    apimSubnetAddressPrefix: apimSubnetPrefix
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetPrefix
    functionAppSubnetAddressPrefix: functionAppSubnetPrefix
    location: location
    tags: tags
    privateDnsZoneNames: privateDnsZoneNames
    apimRouteTableName: 'rt-apim-${resourceToken}'
  }
  dependsOn: [
    dnsDeployment
  ]
}

module vnetExisting './modules/networking/vnet-existing.bicep' = if(useExistingVnet) {
  name: 'vnetExisting'
  scope: resourceGroup
  params: {
    name: vnetName
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : 'snet-apim'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : 'snet-private-endpoint'
    functionAppSubnetName: !empty(functionAppSubnetName) ? functionAppSubnetName : 'snet-functionapp'
    vnetRG: existingVnetRG
  }
  dependsOn: [
    dnsDeployment
  ]
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
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    applicationInsightsDnsZoneName: monitorPrivateDnsZoneName
    createDashboard: createAppInsightsDashboard
    dnsZoneRG: !empty(dnsZoneRG) ? dnsZoneRG : resourceGroup.name
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    usePrivateLinkScope: useAzureMonitorPrivateLinkScope
  }
 
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
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetLocation: useExistingVnet ? vnetExisting.outputs.location : vnet.outputs.location
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    openAiPrivateEndpointName: '${config.value.name}-pe-${resourceToken}'
    publicNetworkAccess: openAIExternalNetworkAccess
    openAiDnsZoneName: openAiPrivateDnsZoneName
    sku: {
      name: openAiSkuName
    }
    deploymentCapacity: deploymentCapacity
    deployments: config.value.deployments
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !empty(dnsZoneRG) ? dnsZoneRG : resourceGroup.name
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }

}]

module eventHub './modules/event-hub/event-hub.bicep' = {
  name: 'event-hub'
  scope: resourceGroup
  params: {
    name: !empty(eventHubNamespaceName) ? eventHubNamespaceName : '${abbrs.eventHubNamespaces}${resourceToken}'
    location: location
    tags: tags
    eventHubPrivateEndpointName: 'eh-pe-${resourceToken}'
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    eventHubDnsZoneName: eventHubPrivateDnsZoneName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !empty(dnsZoneRG) ? dnsZoneRG : resourceGroup.name
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
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
    openAiInstances: map(items(openAiInstances), item => {
      name: item.value.name
      location: item.value.location
      priority: item.value.priority
      weight: contains(item.value, 'weight') ? item.value.weight : null
      deployments: item.value.deployments
    })
   
    openAiUris: [for i in range(0, length(openAiInstances)): openAis[i].outputs.openAiEndpointUri]
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    entraAuth: entraAuth
    clientAppId: entraAuth ? entraClientId : null 
    tenantId: entraAuth ? entraTenantId : null
    audience: entraAuth ? entraAudience : null
    eventHubName: eventHub.outputs.eventHubName
    eventHubEndpoint: eventHub.outputs.eventHubEndpoint
    apimSubnetId: useExistingVnet ? vnetExisting.outputs.apimSubnetId : vnet.outputs.apimSubnetId
    apimNetworkType: apimNetworkType
    enableAzureAISearch: enableAzureAISearch
    aiSearchInstances: aiSearchInstances
    sku: apimSku
    skuCount: apimSkuUnits
  }
  
}

module cosmosDb './modules/cosmos-db/cosmos-db.bicep' = {
  name: 'cosmos-db'
  scope: resourceGroup
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    cosmosDnsZoneName: cosmosDbPrivateDnsZoneName
    cosmosPrivateEndpointName: '${abbrs.documentDBDatabaseAccounts}pe-${resourceToken}'
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !empty(dnsZoneRG) ? dnsZoneRG : resourceGroup.name
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
 
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
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    storageBlobDnsZoneName: storageBlobPrivateDnsZoneName
    storageFileDnsZoneName: storageFilePrivateDnsZoneName
    storageTableDnsZoneName: storageTablePrivateDnsZoneName
    storageQueueDnsZoneName: storageQueuePrivateDnsZoneName
    storageBlobPrivateEndpointName: '${abbrs.storageStorageAccounts}blob-pe-${resourceToken}'
    storageFilePrivateEndpointName: '${abbrs.storageStorageAccounts}file-pe-${resourceToken}'
    storageTablePrivateEndpointName: '${abbrs.storageStorageAccounts}table-pe-${resourceToken}'
    storageQueuePrivateEndpointName: '${abbrs.storageStorageAccounts}queue-pe-${resourceToken}'
    functionContentShareName: functionContentShareName
    logicContentShareName: logicContentShareName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !empty(dnsZoneRG) ? dnsZoneRG : resourceGroup.name
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
  
}

module functionApp './modules/functionapp/functionapp.bicep' = if(provisionFunctionApp) {
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
    functionAppSubnetId: useExistingVnet ? vnetExisting.outputs.functionAppSubnetId : vnet.outputs.functionAppSubnetId
    functionContentShareName: functionContentShareName
  }
  
}

module logicApp './modules/logicapp/logicapp.bicep' = {
  name: 'usageLogicApp'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logicAppName: !empty(usageProcessingLogicAppName) ? usageProcessingLogicAppName : '${abbrs.logicWorkflows}usage-${resourceToken}'
    azdserviceName: 'usageProcessingLogicApp'   
    storageAccountName: storageAccount.outputs.storageAccountName
    applicationInsightsName: monitoring.outputs.funcApplicationInsightsName
    skuFamily: 'WS'
    skuName: 'WS1'
    skuCapaicty: 1
    skuSize: 'WS1'
    skuTier: 'WorkflowStandard'
    isReserved: false
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    eventHubName: eventHub.outputs.eventHubName
    eventHubNamespaceName: eventHub.outputs.eventHubNamespaceName
    cosmosDBDatabaseName: cosmosDb.outputs.cosmosDbDatabaseName
    cosmosDBContainerConfigName: cosmosDb.outputs.cosmosDbStreamingExportConfigContainerName
    cosmosDBContainerUsageName: cosmosDb.outputs.cosmosDbContainerName
    apimAppInsightsName: monitoring.outputs.applicationInsightsName
    functionAppSubnetId: useExistingVnet ? vnetExisting.outputs.functionAppSubnetId : vnet.outputs.functionAppSubnetId
    fileShareName: logicContentShareName
  }
  
}

output APIM_NAME string = apim.outputs.apimName
output APIM_AOI_PATH string = apim.outputs.apimOpenaiApiPath
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
output extendedOpenAiInstances array = apim.outputs.extendedOpenAiInstances

output eventHubName string = eventHub.outputs.eventHubName
output eventHubNamespaceName string = eventHub.outputs.eventHubNamespaceName
output eventHubEndpoint string = eventHub.outputs.eventHubEndpoint
