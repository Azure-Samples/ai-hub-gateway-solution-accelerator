targetScope = 'subscription'

//
// BASIC PARAMETERS
//
@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (filtered on available regions for Azure Open AI Service).')
@allowed([ 'uaenorth', 'southafricanorth', 'westeurope', 'southcentralus', 'australiaeast', 'canadaeast', 'eastus', 'eastus2', 'francecentral', 'japaneast', 'northcentralus', 'swedencentral', 'switzerlandnorth', 'uksouth' ])
param location string

@description('Tags to be applied to resources.')
param tags object = { 'azd-env-name': environmentName, 'SecurityControl': 'Ignore' }

//
// RESOURCE NAMES - Assign custom names to different provisioned services
//
@description('Name of the resource group. Leave blank to use default naming conventions.')
param resourceGroupName string

@description('Name of the managed identity. Leave blank to use default naming conventions.')
param identityName string = ''

@description('Name of the API Management service. Leave blank to use default naming conventions.')
param apimServiceName string = ''

@description('Name of the Log Analytics workspace. Leave blank to use default naming conventions.')
param logAnalyticsName string = ''

@description('Name of the Application Insights dashboard for APIM. Leave blank to use default naming conventions.')
param applicationInsightsDashboardName string = ''

@description('Name of the Application Insights dashboard for Function/Logic App. Leave blank to use default naming conventions.')
param funcAplicationInsightsDashboardName string = ''

@description('Name of the Application Insights dashboard for Function/Logic App. Leave blank to use default naming conventions.')
param foundryApplicationInsightsDashboardName string = ''

@description('Name of the Application Insights for APIM resource. Leave blank to use default naming conventions.')
param applicationInsightsName string = ''

@description('Name of the Application Insights for Function/Logic App resource. Leave blank to use default naming conventions.')
param funcApplicationInsightsName string = ''

@description('Name of the Application Insights for Function/Logic App resource. Leave blank to use default naming conventions.')
param foundryApplicationInsightsName string = ''

@description('Name of the Event Hub Namespace resource. Leave blank to use default naming conventions.')
param eventHubNamespaceName string = ''

@description('Name of the Cosmos DB account resource. Leave blank to use default naming conventions.')
param cosmosDbAccountName string = ''

@description('Name of the Function App resource for usage processing. Leave blank to use default naming conventions.')
param usageProcessingFunctionAppName string = ''

@description('Name of the Logic App resource for usage processing. Leave blank to use default naming conventions.')
param usageProcessingLogicAppName string = ''

@description('Name of the Storage Account. Leave blank to use default naming conventions.')
param storageAccountName string = ''

@description('Name of the Azure Language service. Leave blank to use default naming conventions.')
param languageServiceName string = ''

@description('Name of the Azure Content Safety service. Leave blank to use default naming conventions.')
param aiContentSafetyName string = ''

@description('Name of the API Center service. Leave blank to use default naming conventions.')
param apicServiceName string = ''

@description('Name of the AI Foundry resource. Leave blank to use default naming conventions.')
param aiFoundryResourceName string = ''

//
// NETWORKING PARAMETERS - Network configuration and access controls
//

@description('Name of the Virtual Network. Leave blank to use default naming conventions.')
param vnetName string = ''

@description('Use an existing Virtual Network instead of creating a new one.')
param useExistingVnet bool = false

@description('Resource group containing the existing VNet (only used when useExistingVnet is true).')
param existingVnetRG string = ''

// Subnet names
@description('Subnet name for API Management in the VNet. Leave blank to use default naming conventions.')
param apimSubnetName string = ''

@description('Subnet name for Private Endpoints in the VNet. Leave blank to use default naming conventions.')
param privateEndpointSubnetName string = ''

@description('Subnet name for Function App in the VNet. Leave blank to use default naming conventions.')
param functionAppSubnetName string = ''


// NSG & route table names
@description('NSG name for API Management subnet. Leave blank to use default naming conventions.')
param apimNsgName string = ''

@description('NSG name for Private Endpoint subnet. Leave blank to use default naming conventions.')
param privateEndpointNsgName string = ''

@description('NSG name for Function App subnet. Leave blank to use default naming conventions.')
param functionAppNsgName string = ''

@description('Route Table name for API Management subnet. Leave blank to use default naming conventions.')
param apimRouteTableName string = ''

// VNet address space and subnet prefixes
@description('Virtual Network address space.')
param vnetAddressPrefix string = '10.170.0.0/24'

@description('API Management subnet address range.')
param apimSubnetPrefix string = '10.170.0.0/26'

@description('Private Endpoint subnet address range.')
param privateEndpointSubnetPrefix string = '10.170.0.64/26'

@description('Function App subnet address range.')
param functionAppSubnetPrefix string = '10.170.0.128/26'

// DNS ZONE PARAMETERS - DNS zone configuration for private endpoints (for use with existing VNet)
@description('Resource group containing the DNS zones (only used with existing VNet).')
param dnsZoneRG string = ''

@description('Subscription ID containing the DNS zones (only used with existing VNet).')
param dnsSubscriptionId string = ''

// PRIVATE ENDPOINTS - Names for private endpoints for various services
@description('Storage Blob private endpoint name. Leave blank to use default naming conventions.')
param storageBlobPrivateEndpointName string = ''

@description('Storage File private endpoint name. Leave blank to use default naming conventions.')
param storageFilePrivateEndpointName string = ''

@description('Storage Table private endpoint name. Leave blank to use default naming conventions.')
param storageTablePrivateEndpointName string = ''

@description('Storage Queue private endpoint name. Leave blank to use default naming conventions.')
param storageQueuePrivateEndpointName string = ''

@description('Cosmos DB private endpoint name. Leave blank to use default naming conventions.')
param cosmosDbPrivateEndpointName string = ''

@description('Event Hub private endpoint name. Leave blank to use default naming conventions.')
param eventHubPrivateEndpointName string = ''

@description('Azure OpenAI private endpoint name. Leave blank to use default naming conventions.')
param openAiPrivateEndpointName string = ''

@description('Name of the Azure Language service private endpoint. Leave blank to use default naming conventions.')
param languageServicePrivateEndpointName string = ''

@description('Name of the Azure Content Safety service private endpoint. Leave blank to use default naming conventions.')
param aiContentSafetyPrivateEndpointName string = ''

@description('API Management V2 private endpoint name. Leave blank to use default naming conventions.')
param apimV2PrivateEndpointName string = ''

// Services network access configuration

@description('Network type for API Management service. Applies only to Premium and Developer SKUs.')
@allowed([ 'External', 'Internal' ])
param apimNetworkType string = 'External'

@description('Use private endpoint for API Management service. Applies only to StandardV2 and PremiumV2 SKUs.')
param apimV2UsePrivateEndpoint bool = true

@description('API Management service external network access. When false, APIM must have private endpoint.')
param apimV2PublicNetworkAccess bool = true

@description('Azure OpenAI service public network access.')
@allowed([ 'Enabled', 'Disabled' ])
param openAIExternalNetworkAccess string = 'Disabled'

@description('Cosmos DB public network access.')
@allowed([ 'Enabled', 'Disabled' ])
param cosmosDbPublicAccess string = 'Disabled'

@description('Event Hub public network access.')
@allowed([ 'Enabled', 'Disabled' ]) 
param eventHubNetworkAccess string = 'Enabled'

@description('Azure Language service external network access.')
@allowed([ 'Enabled', 'Disabled' ])
param languageServiceExternalNetworkAccess string = 'Disabled'

@description('Azure Content Safety external network access.')
@allowed([ 'Enabled', 'Disabled' ])
param aiContentSafetyExternalNetworkAccess string = 'Disabled'

@description('Use Azure Monitor Private Link Scope for Log Analytics and Application Insights.')
param useAzureMonitorPrivateLinkScope bool = !useExistingVnet

//
// FEATURE FLAGS - Deploy specific capabilities
//
@description('Create Application Insights dashboard.')
param createAppInsightsDashboard bool = false

@description('Deploy Azure Function App for processing usage data.')
param provisionFunctionApp bool = false

@description('Enable AI Model Inference in API Management.')
param enableAIModelInference bool = true

@description('Enable Document Intelligence in API Management.')
param enableDocumentIntelligence bool = true

@description('Enable Azure AI Search integration.')
param enableAzureAISearch bool = true

@description('Enable PII redaction in AI Gateway')
param enableAIGatewayPiiRedaction bool = true

@description('Enable OpenAI realtime capabilities')
param enableOpenAIRealtime bool = true

@description('Enable AI Foundry integration.')
param enableAIFoundry bool = true

@description('Enable Microsoft Entra ID authentication for API Management.')
param entraAuth bool = false

@description('Enable API Center for API governance and discovery.')
param enableAPICenter bool = true

//
// COMPUTE SKU & SIZE - SKUs and capacity settings for services
//
@description('API Management service SKU. Only Developer and Premium are supported.')
@allowed([ 'Developer', 'Premium', 'StandardV2', 'PremiumV2' ])
param apimSku string = 'StandardV2'

@description('API Management service SKU units.')
param apimSkuUnits int = 1

@description('SKU name for OpenAI services.')
param openAiSkuName string = 'S0'

@description('OpenAI deployment capacity (in thousands of tokens per minute).')
param deploymentCapacity int = 20

@description('Event Hub capacity units.')
param eventHubCapacityUnits int = 1

@description('Cosmos DB throughput in Request Units (RUs).')
param cosmosDbRUs int = 400

@description('Logic Apps SKU capacity units.')
param logicAppsSkuCapacityUnits int = 1

@description('Azure Language service SKU name.')
param languageServiceSkuName string = 'S'

@description('Azure Content Safety service SKU name.')
param aiContentSafetySkuName string = 'S0'

@description('SKU for the API Center service.')
@allowed(['Free', 'Standard'])
param apicSku string = 'Free'

//
// ACCELERATOR SPECIFIC PARAMETERS - Additional parameters for the solution (should not be modified without careful consideration)
//
@description('Name of the Storage Account file share for Azure Function content.')
param functionContentShareName string = 'usage-function-content'

@description('Name of the Storage Account file share for Logic App content.')
param logicContentShareName string = 'usage-logic-content'

@description('OpenAI instances configuration - add more instances by modifying this object.')
param openAiInstances object = {}

@description('AI Search instances configuration - add more instances by adding to this array.')
param aiSearchInstances array = [
  {
    name: 'ai-search-01'
    url: 'https://REPLACE1.search.windows.net/'
    description: 'AI Search Instance 1'
  }
  {
    name: 'ai-search-02'
    url: 'https://REPLACE2.search.windows.net/'
    description: 'AI Search Instance 2'
  }
]

@description('AI Foundry services configuration - configure AI Foundry resources.')
param aiFoundryInstances array = [
  {
    name: !empty(aiFoundryResourceName) ? aiFoundryResourceName : ''
    location: location
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
    modelDeployments: [
      {
        name: 'gpt-4o-mini'
        publisher: 'OpenAI'
        version: '2024-07-18'
        sku: 'GlobalStandard'
        capacity: 100
      }
      {
        name: 'gpt-4o'
        publisher: 'OpenAI'
        version: '2024-11-20'
        sku: 'GlobalStandard'
        capacity: 100
      }
      {
        name: 'DeepSeek-R1'
        publisher: 'DeepSeek'
        version: '1'
        sku: 'GlobalStandard'
        capacity: 1
      }
      {
        name: 'Phi-4'
        publisher: 'Microsoft'
        version: '3'
        sku: 'GlobalStandard'
        capacity: 1
      }
    ]
  }
]

@description('AI Foundry model deployments configuration - configure model deployments for Foundry instances.')
// Leaving 'aiservice' empty means this model deployment will be created for all AI Foundry resources in 'aiFoundryInstances', 
// Adding 'aiservice' explicit value, means that the model will be deployed only to that instance (must exist in 'aiFoundryInstances' array)
param aiFoundryModelsConfig array = [
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiservice: ''
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiservice: ''
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiservice: ''
  }
  {
    name: 'Phi-4'
    publisher: 'Microsoft'
    version: '3'
    sku: 'GlobalStandard'
    capacity: 1
    aiservice: ''
  }
]

@description('Microsoft Entra ID tenant ID for authentication (only used when entraAuth is true).')
param entraTenantId string = ''

@description('Microsoft Entra ID client ID for authentication (only used when entraAuth is true).')
param entraClientId string = ''

@description('Audience value for Microsoft Entra ID authentication (only used when entraAuth is true).')
param entraAudience string = '' 

// Load abbreviations from JSON file
var abbrs = loadJsonContent('./abbreviations.json')
// Generate a unique token for resources
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var openAiPrivateDnsZoneName = 'privatelink.openai.azure.com'
var keyVaultPrivateDnsZoneName = 'privatelink.vaultcore.azure.net'
var monitorPrivateDnsZoneName = 'privatelink.monitor.azure.com'
var eventHubPrivateDnsZoneName = 'privatelink.servicebus.windows.net'
var cosmosDbPrivateDnsZoneName = 'privatelink.documents.azure.com'
var storageBlobPrivateDnsZoneName = 'privatelink.blob.core.windows.net'
var storageFilePrivateDnsZoneName = 'privatelink.file.core.windows.net'
var storageTablePrivateDnsZoneName = 'privatelink.table.core.windows.net'
var storageQueuePrivateDnsZoneName = 'privatelink.queue.core.windows.net'
var aiCogntiveServicesDnsZoneName = 'privatelink.cognitiveservices.azure.com'
var apimV2SkuDnsZoneName = 'privatelink.azure-api.net'

var privateDnsZoneNames = [
  openAiPrivateDnsZoneName
  aiCogntiveServicesDnsZoneName
  keyVaultPrivateDnsZoneName
  monitorPrivateDnsZoneName
  eventHubPrivateDnsZoneName 
  cosmosDbPrivateDnsZoneName
  storageBlobPrivateDnsZoneName
  storageFilePrivateDnsZoneName
  storageTablePrivateDnsZoneName
  storageQueuePrivateDnsZoneName
  apimV2SkuDnsZoneName
]

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
    tags: tags
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
    isAPIMV2SKU: apimSku == 'StandardV2' || apimSku == 'PremiumV2'
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetPrefix
    functionAppSubnetAddressPrefix: functionAppSubnetPrefix
    location: location
    tags: tags
    privateDnsZoneNames: privateDnsZoneNames
    apimRouteTableName: !empty(apimRouteTableName) ? apimRouteTableName : 'rt-apim-${resourceToken}'
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

module usageManagedIdentity './modules/security/managed-identity-usage.bicep' = {
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
    foundryApplicationInsightsName: !empty(foundryApplicationInsightsName) ? foundryApplicationInsightsName : '${abbrs.insightsComponents}aif-${resourceToken}'
    foundryApplicationInsightsDashboardName: !empty(foundryApplicationInsightsDashboardName) ? foundryApplicationInsightsDashboardName : '${abbrs.portalDashboards}aif-${resourceToken}'
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    applicationInsightsDnsZoneName: monitorPrivateDnsZoneName
    createDashboard: createAppInsightsDashboard
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    usePrivateLinkScope: useAzureMonitorPrivateLinkScope
  }
  dependsOn: [
    vnet
    vnetExisting
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
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetLocation: useExistingVnet ? vnetExisting.outputs.location : vnet.outputs.location
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    aiPrivateEndpointName: !empty(openAiPrivateEndpointName) ? '${openAiPrivateEndpointName}-${i}' : '${abbrs.cognitiveServicesAccounts}openai-pe-${i}-${resourceToken}'
    publicNetworkAccess: openAIExternalNetworkAccess
    openAiDnsZoneName: openAiPrivateDnsZoneName
    sku: {
      name: openAiSkuName
    }
    deploymentCapacity: deploymentCapacity
    deployments: config.value.deployments
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
  dependsOn: [
    vnet
    vnetExisting
    apimManagedIdentity
  ]
}]

module contentSafety 'modules/ai/cognitiveservices.bicep' = {
  name: 'ai-content-safety'
  scope: resourceGroup
  params: {
    name: !empty(aiContentSafetyName) ? aiContentSafetyName : '${abbrs.cognitiveServicesAccounts}consafety-${resourceToken}'
    location: location
    tags: tags
    kind: 'ContentSafety'
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetLocation: useExistingVnet ? vnetExisting.outputs.location : vnet.outputs.location
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    aiPrivateEndpointName: !empty(aiContentSafetyPrivateEndpointName) ? aiContentSafetyPrivateEndpointName : '${abbrs.cognitiveServicesAccounts}consafety-pe-${resourceToken}'
    publicNetworkAccess: aiContentSafetyExternalNetworkAccess
    openAiDnsZoneName: aiCogntiveServicesDnsZoneName
    sku: {
      name: aiContentSafetySkuName
    }
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
  dependsOn: [
    vnet
    vnetExisting
    apimManagedIdentity
  ]
}

module languageService 'modules/ai/cognitiveservices.bicep' = {
  name: 'ai-language-service'
  scope: resourceGroup
  params: {
    name: !empty(languageServiceName) ? languageServiceName : '${abbrs.cognitiveServicesAccounts}language-${resourceToken}'
    location: location
    tags: tags
    kind: 'TextAnalytics'
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetLocation: useExistingVnet ? vnetExisting.outputs.location : vnet.outputs.location
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    aiPrivateEndpointName: !empty(languageServicePrivateEndpointName) ? languageServicePrivateEndpointName : '${abbrs.cognitiveServicesAccounts}language-pe-${resourceToken}'
    publicNetworkAccess: languageServiceExternalNetworkAccess
    openAiDnsZoneName: aiCogntiveServicesDnsZoneName
    sku: {
      name: languageServiceSkuName
    }
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
  dependsOn: [
    vnet
    vnetExisting
    apimManagedIdentity
  ]
}

module foundry 'modules/foundry/foundry.bicep' = if(enableAIFoundry) {
  name: 'ai-foundry'
  scope: resourceGroup
  params: {
    aiServicesConfig: aiFoundryInstances
    modelsConfig: aiFoundryModelsConfig
    lawId: monitoring.outputs.logAnalyticsWorkspaceId
    apimPrincipalId: apimManagedIdentity.outputs.managedIdentityPrincipalId
    foundryProjectName: 'citadel-governance-project'
    appInsightsInstrumentationKey: monitoring.outputs.foundryApplicationInsightsInstrumentationKey
    appInsightsId: monitoring.outputs.foundryApplicationInsightsId
    publicNetworkAccess: 'Enabled'
    disableKeyAuth: false
    resourceToken: resourceToken
    tags: tags
  }
}

module eventHub './modules/event-hub/event-hub.bicep' = {
  name: 'event-hub'
  scope: resourceGroup
  params: {
    name: !empty(eventHubNamespaceName) ? eventHubNamespaceName : '${abbrs.eventHubNamespaces}${resourceToken}'
    location: location
    tags: tags
    eventHubPrivateEndpointName: !empty(eventHubPrivateEndpointName) ? eventHubPrivateEndpointName : '${abbrs.eventHubNamespaces}pe-${resourceToken}'
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    eventHubDnsZoneName: eventHubPrivateDnsZoneName
    publicNetworkAccess: eventHubNetworkAccess
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    capacity: eventHubCapacityUnits
  }
  dependsOn: [
    vnet
    vnetExisting
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
    eventHubPIIName: eventHub.outputs.eventHubPIIName
    eventHubPIIEndpoint: eventHub.outputs.eventHubEndpoint
    apimSubnetId: useExistingVnet ? vnetExisting.outputs.apimSubnetId : vnet.outputs.apimSubnetId
    aiLanguageServiceUrl: languageService.outputs.aiServiceEndpoint
    contentSafetyServiceUrl: contentSafety.outputs.aiServiceEndpoint
    apimNetworkType: apimNetworkType
    enablePIIAnonymization: enableAIGatewayPiiRedaction
    enableAIModelInference: enableAIModelInference
    enableDocumentIntelligence: enableDocumentIntelligence
    enableOpenAIRealtime: enableOpenAIRealtime
    enableAzureAISearch: enableAzureAISearch
    aiSearchInstances: aiSearchInstances
    sku: apimSku
    skuCount: apimSkuUnits
    usePrivateEndpoint: apimV2UsePrivateEndpoint
    apimV2PrivateEndpointName: !empty(apimV2PrivateEndpointName) ? apimV2PrivateEndpointName : '${abbrs.apiManagementService}pe-${resourceToken}'
    apimV2PublicNetworkAccess: apimV2PublicNetworkAccess
    privateEndpointSubnetId: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetId : vnet.outputs.privateEndpointSubnetId
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    isMCPSampleDeployed: true
    apiCenterServiceName: apiCenter.outputs.name
    apiCenterWorkspaceName: apiCenter.outputs.defaultWorkspaceName
  }
  dependsOn: [
    vnet
    vnetExisting
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
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    cosmosDnsZoneName: cosmosDbPrivateDnsZoneName
    cosmosPrivateEndpointName: !empty(cosmosDbPrivateEndpointName) ? cosmosDbPrivateEndpointName : '${abbrs.documentDBDatabaseAccounts}pe-${resourceToken}'
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    throughput: cosmosDbRUs
    publicAccess: cosmosDbPublicAccess
  }
  dependsOn: [
    vnet
    vnetExisting
  ]
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
    storageBlobPrivateEndpointName: !empty(storageBlobPrivateEndpointName) ? storageBlobPrivateEndpointName : '${abbrs.storageStorageAccounts}blob-pe-${resourceToken}'
    storageFilePrivateEndpointName: !empty(storageFilePrivateEndpointName) ? storageFilePrivateEndpointName : '${abbrs.storageStorageAccounts}file-pe-${resourceToken}'
    storageTablePrivateEndpointName: !empty(storageTablePrivateEndpointName) ? storageTablePrivateEndpointName : '${abbrs.storageStorageAccounts}table-pe-${resourceToken}'
    storageQueuePrivateEndpointName: !empty(storageQueuePrivateEndpointName) ? storageQueuePrivateEndpointName : '${abbrs.storageStorageAccounts}queue-pe-${resourceToken}'
    functionContentShareName: functionContentShareName
    logicContentShareName: logicContentShareName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup.name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
  }
  dependsOn: [
    vnet
    vnetExisting
  ]
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
  dependsOn: [
    vnet
    vnetExisting
    storageAccount
    usageManagedIdentity
    monitoring
    eventHub
    cosmosDb
  ]
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
    skuCapaicty: logicAppsSkuCapacityUnits
    skuSize: 'WS1'
    skuTier: 'WorkflowStandard'
    isReserved: false
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    eventHubName: eventHub.outputs.eventHubName
    eventHubNamespaceName: eventHub.outputs.eventHubNamespaceName
    cosmosDBDatabaseName: cosmosDb.outputs.cosmosDbDatabaseName
    cosmosDBContainerConfigName: cosmosDb.outputs.cosmosDbStreamingExportConfigContainerName
    cosmosDBContainerUsageName: cosmosDb.outputs.cosmosDbContainerName
    cosmosDBContainerPIIName: cosmosDb.outputs.cosmosDbPiiUsageContainerName
    eventHubPIIName: eventHub.outputs.eventHubPIIName
    apimAppInsightsName: monitoring.outputs.applicationInsightsName
    functionAppSubnetId: useExistingVnet ? vnetExisting.outputs.functionAppSubnetId : vnet.outputs.functionAppSubnetId
    fileShareName: logicContentShareName
  }
  dependsOn: [
    vnet
    vnetExisting
    storageAccount
    monitoring
    eventHub
    cosmosDb
  ]
}

module apiCenter './modules/apic/apic.bicep' = if(enableAPICenter) {
  name: 'api-center'
  scope: resourceGroup
  params: {
    apicServiceName: !empty(apicServiceName) ? apicServiceName : '${abbrs.apiCenterService}${resourceToken}'
    apicsku: apicSku
    location: 'swedencentral'
    tags: tags
  }
}

output APIM_NAME string = apim.outputs.apimName
output APIM_AOI_PATH string = apim.outputs.apimOpenaiApiPath
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
output AI_FOUNDRY_SERVICES array = enableAIFoundry ? foundry!.outputs.extendedAIServicesConfig : []
