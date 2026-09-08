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

@description('Location of the API Center service. Leave blank to use primary location, where API Center is available in that region.')
@allowed(['', 'australiaeast', 'canadacentral', 'centralindia', 'eastus', 'francecentral', 'swedencentral', 'uksouth', 'westeurope' ])
param apicLocation string = ''

@description('Tags to be applied to resources.')
param tags object = { 'azd-env-name': environmentName, 'SecurityControl': 'Ignore' }

//
// RESOURCE NAMES - Assign custom names to different provisioned services
//
@description('Name of the resource group. Leave blank to use default naming conventions.')
param resourceGroupName string

@description('Name of the APIM managed identity. Leave blank to use default naming conventions.')
param apimIdentityName string = ''

@description('Name of the Usage Logic App managed identity. Leave blank to use default naming conventions.')
param usageLogicAppIdentityName string = ''

@description('Name of the API Management service. Leave blank to use default naming conventions.')
param apimServiceName string = ''

@description('Name of the Log Analytics workspace. Leave blank to use default naming conventions.')
param logAnalyticsName string = ''

@description('Use an existing Log Analytics workspace instead of creating a new one.')
param useExistingLogAnalytics bool = false

@description('Name of the existing Log Analytics workspace (only used when useExistingLogAnalytics is true).')
param existingLogAnalyticsName string = ''

@description('Resource group containing the existing Log Analytics workspace (only used when useExistingLogAnalytics is true).')
param existingLogAnalyticsRG string = ''

@description('Subscription ID containing the existing Log Analytics workspace (only used when useExistingLogAnalytics is true). Leave blank to use the current subscription.')
param existingLogAnalyticsSubscriptionId string = ''

@description('Name of the Application Insights dashboard for APIM. Leave blank to use default naming conventions.')
param apimApplicationInsightsDashboardName string = ''

@description('Name of the Application Insights dashboard for Function/Logic App. Leave blank to use default naming conventions.')
param funcApplicationInsightsDashboardName string = ''

@description('Name of the Application Insights dashboard for Function/Logic App. Leave blank to use default naming conventions.')
param foundryApplicationInsightsDashboardName string = ''

@description('Name of the Application Insights for APIM resource. Leave blank to use default naming conventions.')
param apimApplicationInsightsName string = ''

@description('Name of the Application Insights for Function/Logic App resource. Leave blank to use default naming conventions.')
param funcApplicationInsightsName string = ''

@description('Name of the Application Insights for Function/Logic App resource. Leave blank to use default naming conventions.')
param foundryApplicationInsightsName string = ''

@description('Name of the Event Hub Namespace resource. Leave blank to use default naming conventions.')
param eventHubNamespaceName string = ''

@description('Name of the Cosmos DB account resource. Leave blank to use default naming conventions.')
param cosmosDbAccountName string = ''

@description('Name of the Logic App resource for usage processing. Leave blank to use default naming conventions.')
param usageProcessingLogicAppName string = ''

@description('Name of the Storage Account. Leave blank to use default naming conventions.')
param storageAccountName string = ''

@description('Name of the API Center service. Leave blank to use default naming conventions.')
param apicServiceName string = ''

@description('Name of the AI Foundry resource. Leave blank to use default naming conventions.')
param aiFoundryResourceName string = ''

@description('Name of the Azure Key Vault. Leave blank to use default naming conventions.')
param keyVaultName string = ''

@description('Name of the Azure Managed Redis resource. Leave blank to use default naming conventions.')
param redisCacheName string = ''

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

@description('Subnet name for Function/Logic App in the VNet. Leave blank to use default naming conventions.')
param functionAppSubnetName string = ''

@description('Subnet name for AI Foundry agent (network injection) workloads in the VNet. Leave blank to use default naming conventions. Required when foundryNetworkInjectionEnabled is true and useExistingVnet is true.')
param agentSubnetName string = ''


// NSG & route table names
@description('NSG name for API Management subnet. Leave blank to use default naming conventions.')
param apimNsgName string = ''

@description('NSG name for Private Endpoint subnet. Leave blank to use default naming conventions.')
param privateEndpointNsgName string = ''

@description('NSG name for Function App subnet. Leave blank to use default naming conventions.')
param functionAppNsgName string = ''

@description('NSG name for AI Foundry agent (network injection) subnet. Leave blank to use default naming conventions.')
param agentSubnetNsgName string = ''

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

@description('AI Foundry agent (network injection) subnet address range. Used only when a new VNet is provisioned and foundryNetworkInjectionEnabled is true. Subnet is delegated to Microsoft.App/environments.')
param agentSubnetPrefix string = '10.170.0.192/26'

@description('Enable AI Foundry network injection by attaching the Foundry account to the agent subnet (delegated to Microsoft.App/environments). Defaults to FALSE. IMPORTANT: virtual network injection is only supported as part of the full Foundry Standard Agent setup (bring-your-own Azure Storage + Azure AI Search + Azure Cosmos DB plus an explicit project capabilityHost). This accelerator provisions the Foundry account as a gateway backend using Microsoft-managed agent resources, which is incompatible with injection - enabling it causes the agent capability host (aml_aiagentservice) to fail with "Invalid vnet resource ID provided, or the virtual network could not be found". Only enable this once the full BYO Standard Agent setup has been added. When useExistingVnet is true the agentSubnetName must reference an existing subnet with the required Microsoft.App/environments delegation.')
param foundryNetworkInjectionEnabled bool = false

// DNS ZONE PARAMETERS - DNS zone configuration for private endpoints (for use with existing VNet)
@description('Resource group containing the DNS zones (only used with existing VNet when existingPrivateDnsZones is not provided - LEGACY).')
param dnsZoneRG string = ''

@description('Subscription ID containing the DNS zones (only used with existing VNet when existingPrivateDnsZones is not provided - LEGACY).')
param dnsSubscriptionId string = ''

@description('Existing Private DNS Zone resource IDs for BYO network scenarios. Each property should contain the full resource ID of the DNS zone. When provided, these take precedence over dnsZoneRG/dnsSubscriptionId.')
param existingPrivateDnsZones object = {
  // Example format:
  // openai: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
  // keyVault: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
  // monitor: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.monitor.azure.com'
  // eventHub: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net'
  // cosmosDb: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
  // storageBlob: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
  // storageFile: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net'
  // storageTable: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net'
  // storageQueue: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net'
  // cognitiveServices: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
  // apimGateway: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.azure-api.net'
  // aiServices: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
  // redis: '/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.redis.azure.net'
}

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

@description('API Management V2 private endpoint name. Leave blank to use default naming conventions.')
param apimV2PrivateEndpointName string = ''

@description('AI Foundry private endpoint base name. Leave blank to use default naming conventions.')
param aiFoundryPrivateEndpointName string = ''

@description('Key Vault private endpoint name. Leave blank to use default naming conventions.')
param keyVaultPrivateEndpointName string = ''

@description('Azure Managed Redis private endpoint name. Leave blank to use default naming conventions.')
param redisPrivateEndpointName string = ''

@description('Logic App private endpoint name. Leave blank to use default naming conventions.')
param logicAppPrivateEndpointName string = ''

// Services network access configuration

@description('Network type for API Management service. Applies only to Premium and Developer SKUs.')
@allowed([ 'External', 'Internal' ])
param apimNetworkType string = 'External'

@description('Use private endpoint for API Management service. Applies only to StandardV2 and PremiumV2 SKUs.')
param apimV2UsePrivateEndpoint bool = true

@description('API Management service external network access. When false, APIM must have private endpoint.')
param apimV2PublicNetworkAccess bool = true

@description('Create a private endpoint for the Logic App. Existing VNets require existingPrivateDnsZones.logicApp or dnsZoneRG for privatelink.azurewebsites.net, with DNS links or forwarding configured.')
param logicAppUsePrivateEndpoint bool = false

@description('Allow public network access to the Logic App. When false, website and SCM access require a working private endpoint and private DNS; workflow publishing must run from a connected network.')
param logicAppPublicNetworkAccess bool = true

@description('Cosmos DB public network access.')
@allowed([ 'Enabled', 'Disabled' ])
param cosmosDbPublicAccess string = 'Disabled'

@description('Event Hub public network access. Needed to be Enabled when using APIM v2 SKUs during provisioning')
@allowed([ 'Enabled', 'Disabled' ]) 
param eventHubNetworkAccess string = 'Enabled'

@description('AI Foundry external network access.')
@allowed([ 'Enabled', 'Disabled' ])
param aiFoundryExternalNetworkAccess string = 'Disabled'

@description('Key Vault external network access.')
@allowed([ 'Enabled', 'Disabled' ])
param keyVaultExternalNetworkAccess string = 'Disabled'

@description('Azure Managed Redis public network access. When Disabled, private endpoint is the exclusive access method.')
@allowed([ 'Enabled', 'Disabled' ])
param redisPublicNetworkAccess string = 'Disabled'

@description('Use Azure Monitor Private Link Scope for Log Analytics and Application Insights.')
param useAzureMonitorPrivateLinkScope bool = false

//
// FEATURE FLAGS - Deploy specific capabilities
//
@description('Create Application Insights dashboards.')
param createAppInsightsDashboards bool = false

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

@description('Enable Microsoft Entra ID authentication for API Management.')
param entraAuth bool = true

@description('Enable API Center for API governance and discovery.')
param enableAPICenter bool = true

@description('Enable Azure Managed Redis (AMR). When true (default), the Redis resource and APIM cache integration are provisioned.')
param enableManagedRedis bool = true

@description('Azure Monitor diagnostic log settings for inference APIs. Controls frontend/backend request/response headers, body bytes, and LLM-specific log settings.')
param azureMonitorLogSettings object = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

@description('Application Insights diagnostic log settings for inference APIs. Controls which headers are captured and body byte limits.')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

//
// COMPUTE SKU & SIZE - SKUs and capacity settings for services
//
@description('API Management service SKU. Only Developer and Premium are supported.')
@allowed([ 'Developer', 'Premium', 'StandardV2', 'PremiumV2' ])
param apimSku string = 'Developer'

@description('API Management service SKU units.')
param apimSkuUnits int = 1

@description('Event Hub capacity units.')
param eventHubCapacityUnits int = 1

@description('Cosmos DB throughput in Request Units (RUs).')
param cosmosDbRUs int = 400

@description('Logic Apps SKU capacity units.')
param logicAppsSkuCapacityUnits int = 1

@description('SKU for the API Center service.')
@allowed(['Free', 'Standard'])
param apicSku string = 'Free'

@description('SKU for the Key Vault service.')
@allowed(['standard', 'premium'])
param keyVaultSkuName string = 'standard'

@description('Redis Enterprise / Azure Managed Redis SKU name. Allowed values align to Microsoft.Cache/redisEnterprise@2025-07-01.')
@allowed([
  'Enterprise_E1'
  'Enterprise_E5'
  'Enterprise_E10'
  'Enterprise_E20'
  'Enterprise_E50'
  'Enterprise_E100'
  'Enterprise_E200'
  'Enterprise_E400'
  'EnterpriseFlash_F300'
  'EnterpriseFlash_F700'
  'EnterpriseFlash_F1500'
  'Balanced_B0'
  'Balanced_B1'
  'Balanced_B3'
  'Balanced_B5'
  'Balanced_B10'
  'Balanced_B20'
  'Balanced_B50'
  'Balanced_B100'
  'Balanced_B150'
  'Balanced_B250'
  'Balanced_B350'
  'Balanced_B500'
  'Balanced_B700'
  'Balanced_B1000'
  'MemoryOptimized_M10'
  'MemoryOptimized_M20'
  'MemoryOptimized_M50'
  'MemoryOptimized_M100'
  'MemoryOptimized_M150'
  'MemoryOptimized_M250'
  'MemoryOptimized_M350'
  'MemoryOptimized_M500'
  'MemoryOptimized_M700'
  'MemoryOptimized_M1000'
  'MemoryOptimized_M1500'
  'MemoryOptimized_M2000'
  'ComputeOptimized_X3'
  'ComputeOptimized_X5'
  'ComputeOptimized_X10'
  'ComputeOptimized_X20'
  'ComputeOptimized_X50'
  'ComputeOptimized_X100'
  'ComputeOptimized_X150'
  'ComputeOptimized_X250'
  'ComputeOptimized_X350'
  'ComputeOptimized_X500'
  'ComputeOptimized_X700'
  'FlashOptimized_A250'
  'FlashOptimized_A500'
  'FlashOptimized_A700'
  'FlashOptimized_A1000'
  'FlashOptimized_A1500'
  'FlashOptimized_A2000'
  'FlashOptimized_A4500'
])
param redisSkuName string = 'Balanced_B10'

@description('Redis Enterprise cluster capacity. Only used for Enterprise_* and EnterpriseFlash_* SKUs. Valid values are (2, 4, 6, ...) for Enterprise SKUs and (3, 9, 15, ...) for EnterpriseFlash SKUs.')
param redisSkuCapacity int = 2

@description('Minimum TLS version for Redis connections.')
param redisMinimumTlsVersion string = '1.2'

@description('High availability / zone redundancy for Azure Managed Redis. Enabled (default) replicates data across availability zones. Set to Disabled if cluster creation intermittently fails with "CreateFailed" due to zonal capacity constraints in the selected region (reduces the availability SLA).')
@allowed([ 'Enabled', 'Disabled' ])
param redisHighAvailability string = 'Enabled'

//
// ACCELERATOR SPECIFIC PARAMETERS - Additional parameters for the solution (should not be modified without careful consideration)
//

@description('Name of the Storage Account file share for Logic App content.')
param logicContentShareName string = 'usage-logic-content'

//
// Governance Hub AI Backends
//

@description('AI Search instances configuration - add more instances by adding to this array.')
param aiSearchInstances array = [
  // {
  //   name: 'ai-search-01'
  //   url: 'https://REPLACE1.search.windows.net/'
  //   description: 'AI Search Instance 1'
  // }
  // {
  //   name: 'ai-search-02'
  //   url: 'https://REPLACE2.search.windows.net/'
  //   description: 'AI Search Instance 2'
  // }
]

@description('AI Foundry instances configuration array. The first element (index 0) is the **primary** Foundry resource. The primary Foundry powers the APIM AI Gateway content safety and PII processing capabilities (via the AI Services unified endpoint) AND can also host LLM model deployments. Add more entries to deploy additional Foundry resources in different regions for additional LLM capacity / regional routing. All entries can host LLM deployments declared in aiFoundryModelsConfig. Each entry may optionally set `networkInjectionEnabled: true|false` to opt the specific Foundry resource into (or out of) agent network injection (delegated to Microsoft.App/environments). Per-instance values only take effect when the global `foundryNetworkInjectionEnabled` flag is also true. Note: agent subnet is regional - only enable injection for instances in the same region as the VNet, and only when the full Foundry Standard Agent BYO setup (Storage + AI Search + Cosmos DB + capabilityHost) is in place.')
param aiFoundryInstances array = [
  {
    name: !empty(aiFoundryResourceName) ? aiFoundryResourceName : ''
    location: location
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
    networkInjectionEnabled: false
  }
  {
    name: !empty(aiFoundryResourceName) ? aiFoundryResourceName : ''
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
    networkInjectionEnabled: false
  }
]

@description('AI Foundry model deployments configuration - configure model deployments for Foundry instances.')
@metadata({
  example: '''
  Each model object should have:
  - name: Model name (required) - e.g., 'gpt-4o', 'DeepSeek-R1'
  - publisher: Publisher/format identifier, e.g., 'OpenAI', 'DeepSeek', 'Microsoft' (used as modelFormat in backend config)
  - version: Version of the model
  - sku: SKU name for the deployment, e.g., 'GlobalStandard', 'Standard'
  - capacity: Capacity/TPM quota
  - retirementDate: (Optional) Retirement date for the model in YYYY-MM-DD format
  - apiVersion: (Optional) API version for OpenAI-type backend requests (default: '2024-02-15-preview')
  - timeout: (Optional) Request timeout in seconds (default: 120)
  - inferenceApiVersion: (Optional) API version for inference-type requests (e.g., '2024-05-01-preview' for non-OpenAI models)
  - aiserviceIndex: (Optional) Index of the AI Foundry instance to deploy to. Leave empty to deploy to all instances
  '''
})
// Leaving 'aiserviceIndex' empty or omitted means this model deployment will be created for all AI Foundry resources in 'aiFoundryInstances', 
// Adding 'aiserviceIndex' with a numeric value (0, 1, etc.) means that the model will be deployed only to that specific instance by index
// The aiservice field will be automatically populated based on aiserviceIndex and the generated foundry resource names
param aiFoundryModelsConfig array = [
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2026-09-30'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2026-09-30'
    aiserviceIndex: 0
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-30'
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4'
    publisher: 'Microsoft'
    version: '3'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-30'
    aiserviceIndex: 0
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-04-14'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5'
    publisher: 'OpenAI'
    version: '2025-08-07'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-02-05'
    aiserviceIndex: 1
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-12-30'
    aiserviceIndex: 1
  }
  {
    name: 'text-embedding-3-large'
    publisher: 'OpenAI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-04-14'
    aiserviceIndex: 1
  }
]

@description('Name of the text embedding model deployment in the primary Microsoft Foundry to be used for APIM semantic caching.')
param primaryFoundryEmbeddingModelName string = 'text-embedding-3-large'

@description('Microsoft Entra ID tenant ID for authentication (only used when entraAuth is true).')
param entraTenantId string = ''

@description('Microsoft Entra ID client ID for authentication (only used when entraAuth is true). If empty and entraAuth is true, an app registration will be auto-provisioned.')
param entraClientId string = ''

@description('Audience value for Microsoft Entra ID authentication (only used when entraAuth is true).')
param entraAudience string = ''

@secure()
@description('Entra ID client secret for the app registration (only used when entraAuth is true with a pre-existing app registration, i.e., entraClientId is provided). When auto-provisioning, the secret is stored in Key Vault automatically by the entra-id module.')
param entraClientSecret string = ''

@description('Enable the Unified AI Wildcard API (3rd API alongside Azure OpenAI and Universal LLM)')
param enableUnifiedAiApi bool = true

// Load abbreviations from JSON file
var abbrs = loadJsonContent('./abbreviations.json')

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module resources './resources.bicep' = {
  name: 'resources-${uniqueString(resourceGroup.name, deployment().name)}'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
    apicLocation: apicLocation
    tags: tags
    apimIdentityName: apimIdentityName
    usageLogicAppIdentityName: usageLogicAppIdentityName
    apimServiceName: apimServiceName
    logAnalyticsName: logAnalyticsName
    useExistingLogAnalytics: useExistingLogAnalytics
    existingLogAnalyticsName: existingLogAnalyticsName
    existingLogAnalyticsRG: existingLogAnalyticsRG
    existingLogAnalyticsSubscriptionId: existingLogAnalyticsSubscriptionId
    apimApplicationInsightsDashboardName: apimApplicationInsightsDashboardName
    funcApplicationInsightsDashboardName: funcApplicationInsightsDashboardName
    foundryApplicationInsightsDashboardName: foundryApplicationInsightsDashboardName
    apimApplicationInsightsName: apimApplicationInsightsName
    funcApplicationInsightsName: funcApplicationInsightsName
    foundryApplicationInsightsName: foundryApplicationInsightsName
    eventHubNamespaceName: eventHubNamespaceName
    cosmosDbAccountName: cosmosDbAccountName
    usageProcessingLogicAppName: usageProcessingLogicAppName
    storageAccountName: storageAccountName
    apicServiceName: apicServiceName
    aiFoundryResourceName: aiFoundryResourceName
    keyVaultName: keyVaultName
    redisCacheName: redisCacheName
    vnetName: vnetName
    useExistingVnet: useExistingVnet
    existingVnetRG: existingVnetRG
    apimSubnetName: apimSubnetName
    privateEndpointSubnetName: privateEndpointSubnetName
    functionAppSubnetName: functionAppSubnetName
    agentSubnetName: agentSubnetName
    apimNsgName: apimNsgName
    privateEndpointNsgName: privateEndpointNsgName
    functionAppNsgName: functionAppNsgName
    agentSubnetNsgName: agentSubnetNsgName
    apimRouteTableName: apimRouteTableName
    vnetAddressPrefix: vnetAddressPrefix
    apimSubnetPrefix: apimSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    functionAppSubnetPrefix: functionAppSubnetPrefix
    agentSubnetPrefix: agentSubnetPrefix
    foundryNetworkInjectionEnabled: foundryNetworkInjectionEnabled
    dnsZoneRG: dnsZoneRG
    dnsSubscriptionId: dnsSubscriptionId
    existingPrivateDnsZones: existingPrivateDnsZones
    storageBlobPrivateEndpointName: storageBlobPrivateEndpointName
    storageFilePrivateEndpointName: storageFilePrivateEndpointName
    storageTablePrivateEndpointName: storageTablePrivateEndpointName
    storageQueuePrivateEndpointName: storageQueuePrivateEndpointName
    cosmosDbPrivateEndpointName: cosmosDbPrivateEndpointName
    eventHubPrivateEndpointName: eventHubPrivateEndpointName
    apimV2PrivateEndpointName: apimV2PrivateEndpointName
    aiFoundryPrivateEndpointName: aiFoundryPrivateEndpointName
    keyVaultPrivateEndpointName: keyVaultPrivateEndpointName
    redisPrivateEndpointName: redisPrivateEndpointName
    logicAppPrivateEndpointName: logicAppPrivateEndpointName
    apimNetworkType: apimNetworkType
    apimV2UsePrivateEndpoint: apimV2UsePrivateEndpoint
    apimV2PublicNetworkAccess: apimV2PublicNetworkAccess
    logicAppUsePrivateEndpoint: logicAppUsePrivateEndpoint
    logicAppPublicNetworkAccess: logicAppPublicNetworkAccess
    cosmosDbPublicAccess: cosmosDbPublicAccess
    eventHubNetworkAccess: eventHubNetworkAccess
    aiFoundryExternalNetworkAccess: aiFoundryExternalNetworkAccess
    keyVaultExternalNetworkAccess: keyVaultExternalNetworkAccess
    redisPublicNetworkAccess: redisPublicNetworkAccess
    useAzureMonitorPrivateLinkScope: useAzureMonitorPrivateLinkScope
    createAppInsightsDashboards: createAppInsightsDashboards
    enableAIModelInference: enableAIModelInference
    enableDocumentIntelligence: enableDocumentIntelligence
    enableAzureAISearch: enableAzureAISearch
    enableAIGatewayPiiRedaction: enableAIGatewayPiiRedaction
    enableOpenAIRealtime: enableOpenAIRealtime
    entraAuth: entraAuth
    enableAPICenter: enableAPICenter
    enableManagedRedis: enableManagedRedis
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
    apimSku: apimSku
    apimSkuUnits: apimSkuUnits
    eventHubCapacityUnits: eventHubCapacityUnits
    cosmosDbRUs: cosmosDbRUs
    logicAppsSkuCapacityUnits: logicAppsSkuCapacityUnits
    apicSku: apicSku
    keyVaultSkuName: keyVaultSkuName
    redisSkuName: redisSkuName
    redisSkuCapacity: redisSkuCapacity
    redisMinimumTlsVersion: redisMinimumTlsVersion
    redisHighAvailability: redisHighAvailability
    logicContentShareName: logicContentShareName
    aiSearchInstances: aiSearchInstances
    aiFoundryInstances: aiFoundryInstances
    aiFoundryModelsConfig: aiFoundryModelsConfig
    primaryFoundryEmbeddingModelName: primaryFoundryEmbeddingModelName
    entraTenantId: entraTenantId
    entraClientId: entraClientId
    entraAudience: entraAudience
    entraClientSecret: entraClientSecret
    enableUnifiedAiApi: enableUnifiedAiApi
  }
}

output APIM_NAME string = resources.outputs.APIM_NAME
output APIM_AOI_PATH string = resources.outputs.APIM_AOI_PATH
output APIM_GATEWAY_URL string = resources.outputs.APIM_GATEWAY_URL
output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AI_FOUNDRY_SERVICES array = resources.outputs.AI_FOUNDRY_SERVICES
output LLM_BACKEND_CONFIG array = resources.outputs.LLM_BACKEND_CONFIG
output KEY_VAULT_NAME string = resources.outputs.KEY_VAULT_NAME
output KEY_VAULT_URI string = resources.outputs.KEY_VAULT_URI
output ENTRA_AUTH_ENABLED bool = resources.outputs.ENTRA_AUTH_ENABLED
output ENTRA_CLIENT_ID string = resources.outputs.ENTRA_CLIENT_ID
output ENTRA_TENANT_ID string = resources.outputs.ENTRA_TENANT_ID
output ENTRA_AUDIENCE string = resources.outputs.ENTRA_AUDIENCE
output COSMOS_DB_ACCOUNT_NAME string = resources.outputs.COSMOS_DB_ACCOUNT_NAME
output EVENT_HUB_NAME string = resources.outputs.EVENT_HUB_NAME
