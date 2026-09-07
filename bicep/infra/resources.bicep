targetScope = 'resourceGroup'

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
// Generate a unique token for resources
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Transform aiFoundryModelsConfig to include the actual aiservice names based on aiserviceIndex
var transformedAiFoundryModelsConfig = [for model in aiFoundryModelsConfig: union(model, {
  aiservice: contains(model, 'aiserviceIndex') 
    ? (!empty(aiFoundryInstances[model.aiserviceIndex].name) 
        ? aiFoundryInstances[model.aiserviceIndex].name 
        : 'aif-${resourceToken}-${model.aiserviceIndex}')
    : ''
})]

// Group models by aiserviceIndex for backend configuration
// Each model now includes full metadata: name, sku, capacity, modelFormat, modelVersion, retirementDate
var modelsGroupedByInstance = [for (instance, i) in aiFoundryInstances: {
  instanceIndex: i
  models: filter(map(aiFoundryModelsConfig, model => contains(model, 'aiserviceIndex') && model.aiserviceIndex == i ? union({
    name: model.name
    sku: model.sku
    capacity: model.capacity
    modelFormat: model.publisher
    modelVersion: model.version
    retirementDate: model.?retirementDate ?? ''
  }, !empty(model.?apiVersion) ? { apiVersion: model.apiVersion } : {},
     !empty(model.?inferenceApiVersion) ? { inferenceApiVersion: model.inferenceApiVersion } : {},
     contains(model, 'timeout') ? { timeout: model.timeout } : {}
  ) : {}), m => !empty(m))
}]

/**
 * LLM Backend Configuration Array
 * 
 * Defines all LLM backends that APIM will route requests to. This enables:
 * - Multi-model support across different LLM providers
 * - Load balancing and failover for the same model across multiple backends
 * - Flexible authentication schemes per backend
 * 
 * Each backend object should have:
 * - backendId: Unique identifier (used in APIM backend resource name)
 * - backendType: 'ai-foundry' | 'azure-openai' | 'aws-bedrock' | 'aws-bedrock-mantle' | 'gemini' | 'gemini-openai' | 'anthropic' | 'external'
 * - endpoint: Base URL of the LLM service
 * - authScheme: (Legacy) 'managedIdentity' | 'apiKey' | 'token' — superseded by authType
 * - authType: (Optional) 'managed-identity' | 'aws-sigv4' | 'api-key-bearer' | 'api-key-header' | 'api-key-gemini' | 'api-key-anthropic' | 'none'.
 *             When omitted, it is derived from backendType (ai-foundry/azure-openai → managed-identity), matching the llm-backend-onboarding module.
 * - authConfig: (Optional) { namedValueKey, keyVaultSecretUri?, secretValue? } for api-key-* auth types
 * - supportedModels: Array of model objects with:
 *     - name: Model name (required)
 *     - sku: SKU name for deployment (default: 'Standard')
 *     - capacity: Capacity/TPM quota (default: 100)
 *     - modelFormat: Model format identifier, e.g., 'OpenAI', 'DeepSeek', 'Microsoft' (default: 'OpenAI')
 *     - modelVersion: Version of the model (default: '1')
 *     - retirementDate: (Optional) Retirement date for the model in YYYY-MM-DD format
 *     - apiVersion: (Optional) API version for OpenAI-type requests (default: '2024-02-15-preview')
 *     - timeout: (Optional) Request timeout in seconds (default: 120)
 *     - inferenceApiVersion: (Optional) API version for inference-type requests
 * - priority: (Optional) 1-5, default 1 (lower = higher priority)
 * - weight: (Optional) 1-1000, default 100 (higher = more traffic)
 * 
 * This configuration is now dynamically generated from aiFoundryInstances and aiFoundryModelsConfig as part of the deployment.
 * If you wish to onboard existing LLM backends, you can extend the llmBackendConfig variable with additional backend objects.

 var llmBackendConfig array = [
  // AI Foundry Instance 0 - Location: location (parameter)
  // Models: gpt-4o-mini, gpt-4o, gpt-4.1, DeepSeek-R1, Phi-4
  {
    backendId: 'aif-REPLACE-0'
    backendType: 'ai-foundry'
    endpoint: 'https://aif-REPLACE-0.services.ai.azure.com/models'
    authType: 'managed-identity'
    supportedModels: [
      { name: 'gpt-4o-mini', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2024-07-18', retirementDate: '2026-09-30' }
      { name: 'gpt-4o', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2024-11-20', retirementDate: '2026-09-30' }
      { name: 'gpt-4.1', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2025-04-14', retirementDate: '2026-10-14', apiVersion: '2025-04-01-preview', timeout: 180 }
      { name: 'DeepSeek-R1', sku: 'GlobalStandard', capacity: 1, modelFormat: 'DeepSeek', modelVersion: '1', retirementDate: '2099-12-30', inferenceApiVersion: '2024-05-01-preview' }
      { name: 'Phi-4', sku: 'GlobalStandard', capacity: 1, modelFormat: 'Microsoft', modelVersion: '3', retirementDate: '2099-12-30', inferenceApiVersion: '2024-05-01-preview' }
    ]
    priority: 1
    weight: 100
  }
  // AI Foundry Instance 1 - Location: eastus2
  // Models: gpt-5, DeepSeek-R1
  {
    backendId: 'aif-REPLACE-1'
    backendType: 'ai-foundry'
    endpoint: 'https://aif-REPLACE-1.services.ai.azure.com/models'
    authType: 'managed-identity'
    supportedModels: [
      { name: 'gpt-5', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2025-08-07', retirementDate: '2027-02-05' }
      { name: 'DeepSeek-R1', sku: 'GlobalStandard', capacity: 1, modelFormat: 'DeepSeek', modelVersion: '1', retirementDate: '2099-12-30', inferenceApiVersion: '2024-05-01-preview' }
    ]
    priority: 1
    weight: 100
  }
]

 */

// Dynamically generate LLM backend configuration from AI Foundry instances and models
var llmBackendConfig = [for (instance, i) in aiFoundryInstances: {
  backendId: !empty(instance.name) ? '${instance.name}-${i}' : 'aif-${resourceToken}-${i}'
  backendType: 'ai-foundry'
  endpoint: 'https://${!empty(instance.name) ? instance.name : 'aif-${resourceToken}-${i}'}.cognitiveservices.azure.com/'
  authType: 'managed-identity'
  supportedModels: modelsGroupedByInstance[i].models
  priority: 1
  weight: 100
}]

var primaryFoundryName = !empty(aiFoundryInstances[0].name) ? aiFoundryInstances[0].name : 'aif-${resourceToken}-0'
// Primary Foundry endpoint - serves APIM AI Gateway as both:
//   1. Backend URL for `content-safety-backend` (Content Safety API)
//   2. Named-value `piiServiceUrl` (Language Service / PII detection API)
// Both APIs are exposed on the AI Services account base endpoint.
var primaryFoundryEndpoint = 'https://${primaryFoundryName}.cognitiveservices.azure.com/'
var primaryFoundryEmbeddingsBackendUrl = '${primaryFoundryEndpoint}openai/deployments/${primaryFoundryEmbeddingModelName}/embeddings'

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
var aiServicesDnsZoneName = 'privatelink.services.ai.azure.com'
var redisPrivateDnsZoneName = 'privatelink.redis.azure.net'
var logicAppPrivateDnsZoneName = 'privatelink.azurewebsites.net'

// AI Foundry requires 3 DNS zones for full private endpoint support
var aiFoundryDnsZoneNames = [
  aiCogntiveServicesDnsZoneName     // privatelink.cognitiveservices.azure.com
  openAiPrivateDnsZoneName          // privatelink.openai.azure.com
  aiServicesDnsZoneName             // privatelink.services.ai.azure.com
]

// Extract existing DNS zone resource IDs from the parameter (for BYO network scenarios)
// These are used when useExistingVnet is true and existingPrivateDnsZones is provided
var existingKeyVaultDnsZoneId = existingPrivateDnsZones.?keyVault ?? ''
var existingMonitorDnsZoneId = existingPrivateDnsZones.?monitor ?? ''
var existingEventHubDnsZoneId = existingPrivateDnsZones.?eventHub ?? ''
var existingCosmosDbDnsZoneId = existingPrivateDnsZones.?cosmosDb ?? ''
var existingStorageBlobDnsZoneId = existingPrivateDnsZones.?storageBlob ?? ''
var existingStorageFileDnsZoneId = existingPrivateDnsZones.?storageFile ?? ''
var existingStorageTableDnsZoneId = existingPrivateDnsZones.?storageTable ?? ''
var existingStorageQueueDnsZoneId = existingPrivateDnsZones.?storageQueue ?? ''
var existingCognitiveServicesDnsZoneId = existingPrivateDnsZones.?cognitiveServices ?? ''
var existingApimGatewayDnsZoneId = existingPrivateDnsZones.?apimGateway ?? ''
var existingAiServicesDnsZoneId = existingPrivateDnsZones.?aiServices ?? ''
var existingOpenAiDnsZoneId = existingPrivateDnsZones.?openai ?? ''
var existingRedisDnsZoneId = existingPrivateDnsZones.?redis ?? ''
var existingLogicAppDnsZoneId = existingPrivateDnsZones.?logicApp ?? ''

var createLogicAppDnsZone = logicAppUsePrivateEndpoint && !useExistingVnet && empty(existingLogicAppDnsZoneId) && empty(dnsZoneRG)
var logicAppPrivateDnsZoneResourceId = !empty(existingLogicAppDnsZoneId) ? existingLogicAppDnsZoneId : (!empty(dnsZoneRG) ? resourceId(!empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId, dnsZoneRG, 'Microsoft.Network/privateDnsZones', logicAppPrivateDnsZoneName) : (createLogicAppDnsZone ? resourceId('Microsoft.Network/privateDnsZones', logicAppPrivateDnsZoneName) : ''))

// Existing DNS zone resource IDs for AI Foundry (for BYO network scenarios)
var aiFoundryDnsZoneResourceIds = union(
  !empty(existingCognitiveServicesDnsZoneId) ? [existingCognitiveServicesDnsZoneId] : [],
  !empty(existingOpenAiDnsZoneId) ? [existingOpenAiDnsZoneId] : [],
  !empty(existingAiServicesDnsZoneId) ? [existingAiServicesDnsZoneId] : []
)

// Determine if we're using explicit DNS zone resource IDs (new approach) vs legacy RG/Subscription lookup
#disable-next-line no-unused-vars
var useExplicitDnsZoneIds = !empty(existingCosmosDbDnsZoneId) || !empty(existingEventHubDnsZoneId) || !empty(existingStorageBlobDnsZoneId)

// Base DNS zones (always included)
var baseDnsZoneNames = [
  openAiPrivateDnsZoneName
  aiCogntiveServicesDnsZoneName
  keyVaultPrivateDnsZoneName
  eventHubPrivateDnsZoneName 
  cosmosDbPrivateDnsZoneName
  storageBlobPrivateDnsZoneName
  storageFilePrivateDnsZoneName
  storageTablePrivateDnsZoneName
  storageQueuePrivateDnsZoneName
  apimV2SkuDnsZoneName
  aiServicesDnsZoneName
  redisPrivateDnsZoneName
]

// Only include optional DNS zones when their private connectivity is enabled
var privateDnsZoneNames = concat(
  baseDnsZoneNames,
  useAzureMonitorPrivateLinkScope ? [monitorPrivateDnsZoneName] : [],
  createLogicAppDnsZone ? [logicAppPrivateDnsZoneName] : []
)

module dnsDeployment './modules/networking/dns.bicep' = [for privateDnsZoneName in privateDnsZoneNames: if(!useExistingVnet) {
  name: 'dns-deployment-${privateDnsZoneName}'
  params: {
    name: privateDnsZoneName
    tags: tags
  }
}]

module vnet './modules/networking/vnet.bicep' = if(!useExistingVnet) {
  name: 'vnet'
  params: {
    name: !empty(vnetName) ? vnetName : 'vnet-${resourceToken}'
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : 'snet-apim'
    apimNsgName: !empty(apimNsgName) ? apimNsgName : 'nsg-apim-${resourceToken}'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : 'snet-private-endpoint'
    privateEndpointNsgName: !empty(privateEndpointNsgName) ? privateEndpointNsgName : 'nsg-pe-${resourceToken}'
    functionAppSubnetName: !empty(functionAppSubnetName) ? functionAppSubnetName : 'snet-functionapp'
    functionAppNsgName: !empty(functionAppNsgName) ? functionAppNsgName : 'nsg-functionapp-${resourceToken}'
    enableAgentSubnet: foundryNetworkInjectionEnabled
    agentSubnetName: !empty(agentSubnetName) ? agentSubnetName : 'snet-agents'
    agentSubnetNsgName: !empty(agentSubnetNsgName) ? agentSubnetNsgName : 'nsg-agents-${resourceToken}'
    agentSubnetAddressPrefix: agentSubnetPrefix
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
  params: {
    name: vnetName
    apimSubnetName: !empty(apimSubnetName) ? apimSubnetName : 'snet-apim'
    privateEndpointSubnetName: !empty(privateEndpointSubnetName) ? privateEndpointSubnetName : 'snet-private-endpoint'
    functionAppSubnetName: !empty(functionAppSubnetName) ? functionAppSubnetName : 'snet-functionapp'
    agentSubnetName: foundryNetworkInjectionEnabled ? agentSubnetName : ''
    vnetRG: existingVnetRG
  }
  dependsOn: [
    dnsDeployment
  ]
}

module apimManagedIdentity './modules/security/managed-identity-apim.bicep' = {
  name: 'apim-managed-identity'
  params: {
    name: !empty(apimIdentityName) ? apimIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}apim-${resourceToken}'
    location: location
    tags: tags
  }
}

// The usage managed identity is created early (no dependency on Cosmos DB) so its principal has
// time to replicate in AAD before the Cosmos SQL role assignment runs (see usageCosmosSqlRole).
module usageManagedIdentity './modules/security/managed-identity-usage.bicep' = {
  name: 'logicapp-usage-managed-identity'
  params: {
    name: !empty(usageLogicAppIdentityName) ? usageLogicAppIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}logicapp-${resourceToken}'
    location: location
    tags: tags
  }
}

module monitoring './modules/monitor/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    useExistingLogAnalytics: useExistingLogAnalytics
    existingLogAnalyticsName: existingLogAnalyticsName
    existingLogAnalyticsRG: existingLogAnalyticsRG
    existingLogAnalyticsSubscriptionId: !empty(existingLogAnalyticsSubscriptionId) ? existingLogAnalyticsSubscriptionId : subscription().subscriptionId
    apimApplicationInsightsName: !empty(apimApplicationInsightsName) ? apimApplicationInsightsName : '${abbrs.insightsComponents}apim-${resourceToken}'
    apimApplicationInsightsDashboardName: !empty(apimApplicationInsightsDashboardName) ? apimApplicationInsightsDashboardName : '${abbrs.portalDashboards}apim-${resourceToken}'
    functionApplicationInsightsName: !empty(funcApplicationInsightsName) ? funcApplicationInsightsName : '${abbrs.insightsComponents}func-${resourceToken}'
    functionApplicationInsightsDashboardName: !empty(funcApplicationInsightsDashboardName) ? funcApplicationInsightsDashboardName : '${abbrs.portalDashboards}func-${resourceToken}'
    foundryApplicationInsightsName: !empty(foundryApplicationInsightsName) ? foundryApplicationInsightsName : '${abbrs.insightsComponents}aif-${resourceToken}'
    foundryApplicationInsightsDashboardName: !empty(foundryApplicationInsightsDashboardName) ? foundryApplicationInsightsDashboardName : '${abbrs.portalDashboards}aif-${resourceToken}'
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    applicationInsightsDnsZoneName: monitorPrivateDnsZoneName
    createDashboard: createAppInsightsDashboards
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingMonitorDnsZoneId
    usePrivateLinkScope: useAzureMonitorPrivateLinkScope
  }
}

module keyVault './modules/keyvault/keyvault.bicep' = {
  name: 'key-vault'
  params: {
    keyVaultName: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    skuName: keyVaultSkuName
    publicNetworkAccess: keyVaultExternalNetworkAccess
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    keyVaultPrivateEndpointName: !empty(keyVaultPrivateEndpointName) ? keyVaultPrivateEndpointName : '${abbrs.keyVaultVaults}pe-${resourceToken}'
    keyVaultDnsZoneName: keyVaultPrivateDnsZoneName
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingKeyVaultDnsZoneId
    apimPrincipalId: apimManagedIdentity.outputs.managedIdentityPrincipalId
  }
}

// AI Foundry deployment.
// The first element of `aiFoundryInstances` is the **primary** Foundry resource. Its endpoint is
// reused by APIM as the backend for content safety and as the named-value URL for PII / language
// processing (both APIs are exposed on the unified AI Services endpoint of the account).
// Additional entries in `aiFoundryInstances` simply provide more regional Foundry resources that
// can host LLM model deployments declared in `aiFoundryModelsConfig`.
module foundry 'modules/foundry/foundry.bicep' = {
  name: 'ai-foundry'
  params: {
    aiServicesConfig: aiFoundryInstances
    modelsConfig: transformedAiFoundryModelsConfig
    lawId: monitoring.outputs.logAnalyticsWorkspaceId
    apimPrincipalId: apimManagedIdentity.outputs.managedIdentityPrincipalId
    foundryProjectName: 'citadel-governance-project'
    appInsightsInstrumentationKey: monitoring.outputs.foundryApplicationInsightsInstrumentationKey
    appInsightsId: monitoring.outputs.foundryApplicationInsightsId
    publicNetworkAccess: aiFoundryExternalNetworkAccess
    disableKeyAuth: false
    resourceToken: resourceToken
    tags: tags
    // Networking parameters for private endpoints
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    vNetLocation: useExistingVnet ? vnetExisting.outputs.location : vnet.outputs.location
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    aiFoundryPrivateEndpointBaseName: !empty(aiFoundryPrivateEndpointName) ? aiFoundryPrivateEndpointName : '${abbrs.cognitiveServicesAccounts}foundry-pe-${resourceToken}'
    aiServicesDnsZoneNames: aiFoundryDnsZoneNames
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceIds: aiFoundryDnsZoneResourceIds
    networkInjectionEnabled: foundryNetworkInjectionEnabled
    agentSubnetName: foundryNetworkInjectionEnabled ? (useExistingVnet ? vnetExisting.outputs.agentSubnetName : vnet.outputs.agentSubnetName) : ''
    // Key Vault connection parameters
    keyVaultId: keyVault.outputs.keyVaultId
    keyVaultUri: keyVault.outputs.keyVaultUri
  }
}

module eventHub './modules/event-hub/event-hub.bicep' = {
  name: 'event-hub'
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
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingEventHubDnsZoneId
    capacity: eventHubCapacityUnits
  }
}

module managedRedis './modules/redis/redis.bicep' = if (enableManagedRedis) {
  name: 'managed-redis'
  params: {
    name: !empty(redisCacheName) ? redisCacheName : '${abbrs.cacheRedis}${resourceToken}'
    location: location
    tags: tags
    skuName: redisSkuName
    skuCapacity: redisSkuCapacity
    publicNetworkAccess: redisPublicNetworkAccess
    minimumTlsVersion: redisMinimumTlsVersion
    highAvailability: redisHighAvailability
    usePrivateEndpoint: true
    redisPrivateEndpointName: !empty(redisPrivateEndpointName) ? redisPrivateEndpointName : '${abbrs.cacheRedis}pe-${resourceToken}'
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    redisDnsZoneName: redisPrivateDnsZoneName
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingRedisDnsZoneId
  }
}

// ============================================================================
// ENTRA ID CONFIGURATION
// ============================================================================
// Entra ID App Registration is created independently by the entra-id-setup script
// (bicep/infra/entra-id-setup/setup.ps1) which stores values as azd environment
// variables. These values flow through main.bicepparam -> parameters here.
// For bring-your-own app registrations, set the values directly via azd env set.
// See: bicep/infra/entra-id-setup/README.md

var resolvedEntraTenantId = !empty(entraTenantId) ? entraTenantId : subscription().tenantId
var resolvedEntraClientId = !empty(entraClientId) ? entraClientId : 'not-configured'
var resolvedEntraAudience = !empty(entraAudience) ? entraAudience : (entraAuth ? 'api://${resolvedEntraClientId}' : 'https://cognitiveservices.azure.com/.default')

// Store client secret in Key Vault when provided via parameter (for BYOA scenarios
// where the secret isn't already in Key Vault from the entra-id-setup script)
module entraClientSecretKv './modules/keyvault/keyvault-secret.bicep' = if (entraAuth && !empty(entraClientSecret)) {
  name: 'entra-client-secret-kv'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    secretName: 'ENTRA-APP-CLIENT-SECRET'
    secretValue: entraClientSecret
  }
}

module apim './modules/apim/apim.bicep' = {
  name: 'apim'
  params: {
    name: !empty(apimServiceName) ? apimServiceName : '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.apimApplicationInsightsName
    managedIdentityName: apimManagedIdentity.outputs.managedIdentityName
    keyVaultName: keyVault.outputs.keyVaultName
    entraAuth: entraAuth
    clientAppId: resolvedEntraClientId
    tenantId: resolvedEntraTenantId
    audience: resolvedEntraAudience
    eventHubName: eventHub.outputs.eventHubName
    eventHubEndpoint: eventHub.outputs.eventHubEndpoint
    eventHubPIIName: eventHub.outputs.eventHubPIIName
    eventHubPIIEndpoint: eventHub.outputs.eventHubEndpoint
    apimSubnetId: useExistingVnet ? vnetExisting.outputs.apimSubnetId : vnet.outputs.apimSubnetId
    aiLanguageServiceUrl: primaryFoundryEndpoint
    contentSafetyServiceUrl: primaryFoundryEndpoint
    apimNetworkType: apimNetworkType
    enablePIIAnonymization: enableAIGatewayPiiRedaction
    enableAIModelInference: enableAIModelInference
    enableDocumentIntelligence: enableDocumentIntelligence
    enableOpenAIRealtime: enableOpenAIRealtime
    enableAzureAISearch: enableAzureAISearch
    aiSearchInstances: aiSearchInstances
    llmBackendConfig: llmBackendConfig
    enableRedisCache: enableManagedRedis
    redisCacheConnectionString: enableManagedRedis ? managedRedis.outputs.redisCacheConnectionString : ''
    redisCacheResourceId: enableManagedRedis ? managedRedis.outputs.redisResourceId : ''
    enableEmbeddingsBackend: enableManagedRedis
    embeddingsBackendUrl: enableManagedRedis ? primaryFoundryEmbeddingsBackendUrl : ''
    sku: apimSku
    skuCount: apimSkuUnits
    usePrivateEndpoint: apimV2UsePrivateEndpoint
    apimV2PrivateEndpointName: !empty(apimV2PrivateEndpointName) ? apimV2PrivateEndpointName : '${abbrs.apiManagementService}pe-${resourceToken}'
    apimV2PublicNetworkAccess: apimV2PublicNetworkAccess
    privateEndpointSubnetId: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetId : vnet.outputs.privateEndpointSubnetId
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingApimGatewayDnsZoneId
    isMCPSampleDeployed: false
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
    enableUnifiedAiApi: enableUnifiedAiApi
    enableJwtAuth: entraAuth
    jwtTenantId: resolvedEntraTenantId
    jwtAppRegistrationId: resolvedEntraClientId
  }
}

// Grant the APIM SYSTEM-assigned managed identity (created by the apim module) read access
// to Key Vault secrets and certificates. APIM uses its system-assigned identity to resolve
// named-value Key Vault references, so this is required before any Key-Vault-backed named
// value can be provisioned.
module keyVaultApimSystemRbac './modules/keyvault/keyvault-apim-system-rbac.bicep' = {
  name: 'kv-apim-system-rbac'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    apimSystemAssignedPrincipalId: apim.outputs.apimSystemAssignedPrincipalId
  }
}

module cosmosDb './modules/cosmos-db/cosmos-db.bicep' = {
  name: 'cosmos-db'
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: tags
    vNetName: useExistingVnet ? vnetExisting.outputs.vnetName : vnet.outputs.vnetName
    cosmosDnsZoneName: cosmosDbPrivateDnsZoneName
    cosmosPrivateEndpointName: !empty(cosmosDbPrivateEndpointName) ? cosmosDbPrivateEndpointName : '${abbrs.documentDBDatabaseAccounts}pe-${resourceToken}'
    privateEndpointSubnetName: useExistingVnet ? vnetExisting.outputs.privateEndpointSubnetName : vnet.outputs.privateEndpointSubnetName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    dnsZoneResourceId: existingCosmosDbDnsZoneId
    throughput: cosmosDbRUs
    publicAccess: cosmosDbPublicAccess
  }
}

// Grant the usage managed identity the Cosmos DB native data-contributor role. This is split into
// its own deployment (after both Cosmos DB and the managed identity exist) so the identity's
// principal has replicated in AAD, avoiding the transient "principal ID was not found in the AAD
// tenant" error that Cosmos DB raises when validating a freshly created principal.
module usageCosmosSqlRole './modules/cosmos-db/cosmos-sql-role-assignment.bicep' = {
  name: 'logicapp-usage-cosmos-sql-role'
  params: {
    cosmosDbAccountName: cosmosDb.outputs.cosmosDbAccountName
    principalId: usageManagedIdentity.outputs.managedIdentityPrincipalId
  }
}

module storageAccount './modules/functionapp/storageaccount.bicep' = {
  name: 'storage'
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
    logicContentShareName: logicContentShareName
    vNetRG: useExistingVnet ? vnetExisting.outputs.vnetRG : vnet.outputs.vnetRG
    dnsZoneRG: !useExistingVnet ? resourceGroup().name : dnsZoneRG
    dnsSubscriptionId: !empty(dnsSubscriptionId) ? dnsSubscriptionId : subscription().subscriptionId
    storageBlobDnsZoneResourceId: existingStorageBlobDnsZoneId
    storageFileDnsZoneResourceId: existingStorageFileDnsZoneId
    storageTableDnsZoneResourceId: existingStorageTableDnsZoneId
    storageQueueDnsZoneResourceId: existingStorageQueueDnsZoneId
  }
}

module logicApp './modules/logicapp/logicapp.bicep' = {
  name: 'usageLogicApp'
  params: {
    location: location
    tags: tags
    logicAppName: !empty(usageProcessingLogicAppName) ? usageProcessingLogicAppName : '${abbrs.logicWorkflows}usage-${resourceToken}'
    azdserviceName: 'usageProcessingLogicApp'   
    storageAccountName: storageAccount.outputs.storageAccountName
    applicationInsightsName: monitoring.outputs.funcApplicationInsightsName
    skuFamily: 'WS'
    skuName: 'WS1'
    skuCapacity: logicAppsSkuCapacityUnits
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
    cosmosDBContainerLLMUsageName: cosmosDb.outputs.cosmosDbLLMUsageContainerName
    cosmosDBContainerMCPUsageName: cosmosDb.outputs.cosmosDbMcpUsageContainerName
    cosmosDBContainerAgentUsageName: cosmosDb.outputs.cosmosDbAgentUsageContainerName
    eventHubPIIName: eventHub.outputs.eventHubPIIName
    apimAppInsightsName: monitoring.outputs.apimApplicationInsightsName
    functionAppSubnetId: useExistingVnet ? vnetExisting.outputs.functionAppSubnetId : vnet.outputs.functionAppSubnetId
    logicAppUsePrivateEndpoint: logicAppUsePrivateEndpoint
    logicAppPublicNetworkAccess: logicAppPublicNetworkAccess
    logicAppPrivateEndpointName: !empty(logicAppPrivateEndpointName) ? logicAppPrivateEndpointName : '${abbrs.logicWorkflows}pe-${resourceToken}'
    privateEndpointSubnetId: useExistingVnet ? vnetExisting!.outputs.privateEndpointSubnetId : vnet!.outputs.privateEndpointSubnetId
    dnsZoneResourceId: logicAppPrivateDnsZoneResourceId
    fileShareName: logicContentShareName
  }
}

module apiCenter './modules/apic/apic.bicep' = if(enableAPICenter) {
  name: 'api-center'
  params: {
    apicServiceName: !empty(apicServiceName) ? apicServiceName : '${abbrs.apiCenterService}${resourceToken}'
    apicsku: apicSku
    location: !empty(apicLocation) ? apicLocation : location
    tags: tags
  }
}

module apiCenterOnboarding './modules/apim/api-center-onboarding-all.bicep' = if(enableAPICenter) {
  name: 'api-center-onboarding'
  params: {
    apiCenterServiceName: enableAPICenter ? apiCenter.outputs.name : ''
    apiCenterWorkspaceName: enableAPICenter ? apiCenter.outputs.defaultWorkspaceName : 'default'
    apimGatewayUrl: apim.outputs.apimGatewayUrl
    isMCPSampleDeployed: true
    enableAzureAISearch: enableAzureAISearch
    enableAIModelInference: enableAIModelInference
    enableOpenAIRealtime: enableOpenAIRealtime
    enableDocumentIntelligence: enableDocumentIntelligence
  }
  dependsOn: [
    apim
    apiCenter
  ]
}

// Grant AI Foundry resources access to Key Vault (deployed after both Key Vault and Foundry)
module keyVaultFoundryRbac './modules/keyvault/keyvault-rbac.bicep' = {
  name: 'key-vault-foundry-rbac'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    aiFoundryPrincipalIds: foundry.outputs.aiFoundryPrincipalIds
  }
  dependsOn: [
    keyVault
    foundry
  ]
}

output APIM_NAME string = apim.outputs.apimName
output APIM_AOI_PATH string = apim.outputs.apimOpenaiApiPath
output APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AI_FOUNDRY_SERVICES array = foundry.outputs.extendedAIServicesConfig
output LLM_BACKEND_CONFIG array = llmBackendConfig
output KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output KEY_VAULT_URI string = keyVault.outputs.keyVaultUri
output ENTRA_AUTH_ENABLED bool = entraAuth
output ENTRA_CLIENT_ID string = resolvedEntraClientId
output ENTRA_TENANT_ID string = resolvedEntraTenantId
output ENTRA_AUDIENCE string = resolvedEntraAudience
output COSMOS_DB_ACCOUNT_NAME string = cosmosDb.outputs.cosmosDbAccountName
output EVENT_HUB_NAME string = eventHub.outputs.eventHubName
