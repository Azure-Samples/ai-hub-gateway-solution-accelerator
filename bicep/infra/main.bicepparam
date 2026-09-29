using './main.bicep'

// ============================================================================
// BASIC PARAMETERS
// ============================================================================
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param apicLocation = readEnvironmentVariable('APIC_LOCATION', 'swedencentral')
param tags = {
  'azd-env-name': readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
  SecurityControl: 'Ignore'
}

// ============================================================================
// RESOURCE NAMES - Assign custom names to different provisioned services
// ============================================================================
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', '')
param apimIdentityName = readEnvironmentVariable('APIM_IDENTITY_NAME', '')
param usageLogicAppIdentityName = readEnvironmentVariable('USAGE_LOGIC_APP_IDENTITY_NAME', '')
param apimServiceName = readEnvironmentVariable('APIM_SERVICE_NAME', '')
param logAnalyticsName = readEnvironmentVariable('LOG_ANALYTICS_NAME', '')
param apimApplicationInsightsDashboardName = readEnvironmentVariable('APIM_APP_INSIGHTS_DASHBOARD_NAME', '')
param funcApplicationInsightsDashboardName = readEnvironmentVariable('FUNC_APP_INSIGHTS_DASHBOARD_NAME', '')
param foundryApplicationInsightsDashboardName = readEnvironmentVariable('FOUNDRY_APP_INSIGHTS_DASHBOARD_NAME', '')
param apimApplicationInsightsName = readEnvironmentVariable('APIM_APP_INSIGHTS_NAME', '')
param funcApplicationInsightsName = readEnvironmentVariable('FUNC_APP_INSIGHTS_NAME', '')
param foundryApplicationInsightsName = readEnvironmentVariable('FOUNDRY_APP_INSIGHTS_NAME', '')
param eventHubNamespaceName = readEnvironmentVariable('EVENTHUB_NAMESPACE_NAME', '')
param cosmosDbAccountName = readEnvironmentVariable('COSMOS_DB_ACCOUNT_NAME', '')
param usageProcessingLogicAppName = readEnvironmentVariable('USAGE_PROCESSING_LOGIC_APP_NAME', '')
param storageAccountName = readEnvironmentVariable('STORAGE_ACCOUNT_NAME', '')
param apicServiceName = readEnvironmentVariable('APIC_SERVICE_NAME', '')
param aiFoundryResourceName = readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
param keyVaultName = readEnvironmentVariable('KEY_VAULT_NAME', '')
param redisCacheName = readEnvironmentVariable('REDIS_CACHE_NAME', '')

// ============================================================================
// MONITORING - Log Analytics configuration
// ============================================================================
param useExistingLogAnalytics = bool(readEnvironmentVariable('USE_EXISTING_LOG_ANALYTICS', 'false'))
param existingLogAnalyticsName = readEnvironmentVariable('EXISTING_LOG_ANALYTICS_NAME', '')
param existingLogAnalyticsRG = readEnvironmentVariable('EXISTING_LOG_ANALYTICS_RG', '')
param existingLogAnalyticsSubscriptionId = readEnvironmentVariable('EXISTING_LOG_ANALYTICS_SUBSCRIPTION_ID', '')

// ============================================================================
// NETWORKING PARAMETERS - Network configuration and access controls
// ============================================================================
param vnetName = readEnvironmentVariable('VNET_NAME', '')
param useExistingVnet = bool(readEnvironmentVariable('USE_EXISTING_VNET', 'false'))
param existingVnetRG = readEnvironmentVariable('EXISTING_VNET_RG', '')

// Subnet names
param apimSubnetName = readEnvironmentVariable('APIM_SUBNET_NAME', '')
param privateEndpointSubnetName = readEnvironmentVariable('PRIVATE_ENDPOINT_SUBNET_NAME', '')
param functionAppSubnetName = readEnvironmentVariable('FUNCTION_APP_SUBNET_NAME', '')
param agentSubnetName = readEnvironmentVariable('AGENT_SUBNET_NAME', '')

// NSG & route table names
param apimNsgName = readEnvironmentVariable('APIM_NSG_NAME', '')
param privateEndpointNsgName = readEnvironmentVariable('PRIVATE_ENDPOINT_NSG_NAME', '')
param functionAppNsgName = readEnvironmentVariable('FUNCTION_APP_NSG_NAME', '')
param agentSubnetNsgName = readEnvironmentVariable('AGENT_SUBNET_NSG_NAME', '')
param apimRouteTableName = readEnvironmentVariable('APIM_ROUTE_TABLE_NAME', '')

// VNet address space and subnet prefixes
param vnetAddressPrefix = readEnvironmentVariable('VNET_ADDRESS_PREFIX', '10.170.0.0/24')
param apimSubnetPrefix = readEnvironmentVariable('APIM_SUBNET_PREFIX', '10.170.0.0/26')
param privateEndpointSubnetPrefix = readEnvironmentVariable('PRIVATE_ENDPOINT_SUBNET_PREFIX', '10.170.0.64/26')
param functionAppSubnetPrefix = readEnvironmentVariable('FUNCTION_APP_SUBNET_PREFIX', '10.170.0.128/26')
param agentSubnetPrefix = readEnvironmentVariable('AGENT_SUBNET_PREFIX', '10.170.0.192/26')

// DNS Zone parameters (legacy approach - single subscription/RG)
param dnsZoneRG = readEnvironmentVariable('DNS_ZONE_RG', '')
param dnsSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID', '')

// Existing Private DNS Zones (BYO approach - specify resource IDs per DNS zone type)
// Use this when you have existing Private DNS Zones in different subscriptions/resource groups
// Leave empty strings to use the legacy dnsZoneRG/dnsSubscriptionId approach
param existingPrivateDnsZones = {
  openai: readEnvironmentVariable('EXISTING_DNS_ZONE_OPENAI', '')              // privatelink.openai.azure.com
  keyVault: readEnvironmentVariable('EXISTING_DNS_ZONE_KEYVAULT', '')          // privatelink.vaultcore.azure.net
  monitor: readEnvironmentVariable('EXISTING_DNS_ZONE_MONITOR', '')            // privatelink.monitor.azure.com
  eventHub: readEnvironmentVariable('EXISTING_DNS_ZONE_EVENTHUB', '')          // privatelink.servicebus.windows.net
  cosmosDb: readEnvironmentVariable('EXISTING_DNS_ZONE_COSMOSDB', '')          // privatelink.documents.azure.com
  storageBlob: readEnvironmentVariable('EXISTING_DNS_ZONE_STORAGE_BLOB', '')   // privatelink.blob.core.windows.net
  storageFile: readEnvironmentVariable('EXISTING_DNS_ZONE_STORAGE_FILE', '')   // privatelink.file.core.windows.net
  storageTable: readEnvironmentVariable('EXISTING_DNS_ZONE_STORAGE_TABLE', '') // privatelink.table.core.windows.net
  storageQueue: readEnvironmentVariable('EXISTING_DNS_ZONE_STORAGE_QUEUE', '') // privatelink.queue.core.windows.net
  cognitiveServices: readEnvironmentVariable('EXISTING_DNS_ZONE_COGNITIVE', '') // privatelink.cognitiveservices.azure.com
  apimGateway: readEnvironmentVariable('EXISTING_DNS_ZONE_APIM', '')           // privatelink.azure-api.net
  aiServices: readEnvironmentVariable('EXISTING_DNS_ZONE_AI_SERVICES', '')     // privatelink.services.azure.com
  redis: readEnvironmentVariable('EXISTING_DNS_ZONE_REDIS', '')                // privatelink.redis.azure.net
  logicApp: readEnvironmentVariable('EXISTING_DNS_ZONE_LOGIC_APP', '')
}

// Private Endpoint names
param storageBlobPrivateEndpointName = readEnvironmentVariable('STORAGE_BLOB_PE_NAME', '')
param storageFilePrivateEndpointName = readEnvironmentVariable('STORAGE_FILE_PE_NAME', '')
param storageTablePrivateEndpointName = readEnvironmentVariable('STORAGE_TABLE_PE_NAME', '')
param storageQueuePrivateEndpointName = readEnvironmentVariable('STORAGE_QUEUE_PE_NAME', '')
param cosmosDbPrivateEndpointName = readEnvironmentVariable('COSMOS_DB_PE_NAME', '')
param eventHubPrivateEndpointName = readEnvironmentVariable('EVENTHUB_PE_NAME', '')
param apimV2PrivateEndpointName = readEnvironmentVariable('APIM_V2_PE_NAME', '')
param aiFoundryPrivateEndpointName = readEnvironmentVariable('AI_FOUNDRY_PE_NAME', '')
param keyVaultPrivateEndpointName = readEnvironmentVariable('KEY_VAULT_PE_NAME', '')
param redisPrivateEndpointName = readEnvironmentVariable('REDIS_PE_NAME', '')
param logicAppPrivateEndpointName = readEnvironmentVariable('LOGIC_APP_PE_NAME', '')

// Services network access configuration
param apimNetworkType = readEnvironmentVariable('APIM_NETWORK_TYPE', 'External')
param apimV2UsePrivateEndpoint = bool(readEnvironmentVariable('APIM_V2_USE_PRIVATE_ENDPOINT', 'true'))
param apimV2PublicNetworkAccess = bool(readEnvironmentVariable('APIM_V2_PUBLIC_NETWORK_ACCESS', 'true'))
param logicAppUsePrivateEndpoint = bool(readEnvironmentVariable('LOGIC_APP_USE_PRIVATE_ENDPOINT', 'false'))
param logicAppPublicNetworkAccess = bool(readEnvironmentVariable('LOGIC_APP_PUBLIC_NETWORK_ACCESS', 'true'))
param cosmosDbPublicAccess = readEnvironmentVariable('COSMOS_DB_PUBLIC_ACCESS', 'Disabled')
param eventHubNetworkAccess = readEnvironmentVariable('EVENTHUB_NETWORK_ACCESS', 'Enabled')
param aiFoundryExternalNetworkAccess = readEnvironmentVariable('AI_FOUNDRY_EXTERNAL_NETWORK_ACCESS', 'Disabled')
param keyVaultExternalNetworkAccess = readEnvironmentVariable('KEY_VAULT_EXTERNAL_NETWORK_ACCESS', 'Disabled')
param useAzureMonitorPrivateLinkScope = bool(readEnvironmentVariable('USE_AZURE_MONITOR_PRIVATE_LINK_SCOPE', 'false'))
param redisPublicNetworkAccess = readEnvironmentVariable('REDIS_PUBLIC_NETWORK_ACCESS', 'Disabled')

// ============================================================================
// FEATURE FLAGS - Deploy specific capabilities
// ============================================================================
param createAppInsightsDashboards = bool(readEnvironmentVariable('CREATE_DASHBOARDS', 'false'))
param enableAIModelInference = bool(readEnvironmentVariable('ENABLE_AI_MODEL_INFERENCE', 'true'))
param enableDocumentIntelligence = bool(readEnvironmentVariable('ENABLE_DOCUMENT_INTELLIGENCE', 'false'))
param enableAzureAISearch = bool(readEnvironmentVariable('ENABLE_AZURE_AI_SEARCH', 'false'))
param enableAIGatewayPiiRedaction = bool(readEnvironmentVariable('ENABLE_PII_REDACTION', 'true'))
param enableOpenAIRealtime = bool(readEnvironmentVariable('ENABLE_OPENAI_REALTIME', 'true'))
param entraAuth = bool(readEnvironmentVariable('AZURE_ENTRA_AUTH', 'false'))
param enableAPICenter = bool(readEnvironmentVariable('ENABLE_API_CENTER', 'false'))
param enableManagedRedis = bool(readEnvironmentVariable('ENABLE_MANAGED_REDIS', 'false'))
param enableUnifiedAiApi = bool(readEnvironmentVariable('ENABLE_UNIFIED_AI_API', 'true'))

// ============================================================================
// INFERENCE API DIAGNOSTIC LOG SETTINGS
// ============================================================================

// Azure Monitor diagnostic log settings for inference APIs
// Controls frontend/backend request/response headers, body bytes, and LLM-specific log settings.
// Max size in bytes for request/response bodies is 262144 bytes (256 KB).
param azureMonitorLogSettings = {
  frontend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request:  { headers: [], body: { bytes: 0 } }
    response: { headers: ['Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests'], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests:  { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

// Application Insights diagnostic log settings for inference APIs
// Controls which headers are captured and body byte limits (max 8192 bytes).
param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 8192 }
}

// ============================================================================
// COMPUTE SKU & SIZE - SKUs and capacity settings for services
// ============================================================================
param apimSku = readEnvironmentVariable('APIM_SKU', 'StandardV2')
param apimSkuUnits = int(readEnvironmentVariable('APIM_SKU_UNITS', '1'))
param eventHubCapacityUnits = int(readEnvironmentVariable('EVENTHUB_CAPACITY', '1'))
param cosmosDbRUs = int(readEnvironmentVariable('COSMOS_DB_RUS', '400'))
param logicAppsSkuCapacityUnits = int(readEnvironmentVariable('LOGIC_APPS_SKU_CAPACITY_UNITS', '1'))
param apicSku = readEnvironmentVariable('APIC_SKU', 'Free')
param keyVaultSkuName = readEnvironmentVariable('KEY_VAULT_SKU_NAME', 'standard')
param redisSkuName = readEnvironmentVariable('REDIS_SKU_NAME', 'Balanced_B1')
param redisSkuCapacity = int(readEnvironmentVariable('REDIS_SKU_CAPACITY', '1'))
param redisHighAvailability = readEnvironmentVariable('REDIS_HIGH_AVAILABILITY', 'Enabled')

// ============================================================================
// ACCELERATOR SPECIFIC PARAMETERS
// ============================================================================
param logicContentShareName = readEnvironmentVariable('LOGIC_CONTENT_SHARE_NAME', 'usage-logic-content')

// AI Search instances configuration - add more instances by adding to this array
// Example: [{name: 'ai-search-01', url: 'https://search1.search.windows.net/', description: 'AI Search 1'}]
param aiSearchInstances = []

// AI Foundry instances configuration array
// Per-instance `networkInjectionEnabled` opts the specific Foundry into (or out of)
// agent network injection. Omit it to inherit the global foundryNetworkInjectionEnabled flag.
// Agent subnet is regional - typically only enable injection for the instance in the VNet's region.
param aiFoundryInstances = [
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: readEnvironmentVariable('AZURE_LOCATION', 'eastus')
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
  {
    name: readEnvironmentVariable('AI_FOUNDRY_RESOURCE_NAME', '')
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]

// AI Foundry model deployments configuration
// Each model can optionally include metadata for the Unified AI API routing:
//   - apiVersion: API version for OpenAI-type requests (default: '2024-02-15-preview')
//   - timeout: Request timeout in seconds (default: 120)
//   - inferenceApiVersion: API version for inference-type requests (e.g., '2024-05-01-preview' for non-OpenAI models)
param aiFoundryModelsConfig = [
  {
    name: 'gpt-4.1'
    publisher: 'OpenAI'
    version: '2025-04-14'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2026-10-14'
    apiVersion: '2025-04-01-preview'
    timeout: 180
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5.2'
    publisher: 'OpenAI'
    version: '2025-12-11'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-02-05'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-image-1.5'
    publisher: 'OpenAI'
    version: '2025-12-16'
    sku: 'GlobalStandard'
    capacity: 2
    retirementDate: '2026-12-16'
    inferenceApiVersion: '2025-04-01-preview'
    apiVersion: '2025-04-01-preview'
    aiserviceIndex: 0
  }
  {
    name: 'MAI-Image-2.5-Flash'
    publisher: 'Microsoft'
    version: '2026-06-02'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2026-09-01'
    inferenceApiVersion: '2024-05-01-preview'
    aiserviceIndex: 0
  }
  {
    name: 'FLUX.2-pro'
    publisher: 'Black Forest Labs'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    retirementDate: '2099-09-01'
    inferenceApiVersion: '2024-05-01-preview'
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
    name: 'Mistral-Large-3'
    publisher: 'Mistral AI'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2099-12-30'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5.4-mini'
    publisher: 'OpenAI'
    version: '2026-03-17'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2026-09-30'
    aiserviceIndex: 0
  }
  {
    name: 'gpt-5.4-mini'
    publisher: 'OpenAI'
    version: '2026-03-17'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2026-09-30'
    aiserviceIndex: 1
  }
  {
    name: 'gpt-5.2'
    publisher: 'OpenAI'
    version: '2025-12-11'
    sku: 'GlobalStandard'
    capacity: 100
    retirementDate: '2027-02-05'
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

// Semantic caching APIM integration configurations
param primaryFoundryEmbeddingModelName = readEnvironmentVariable('PRIMARY_FOUNDRY_EMBEDDING_MODEL_NAME', 'text-embedding-3-large')

// ============================================================================
// ENTRA ID AUTHENTICATION
// ============================================================================
// Values are populated by the entra-id-setup script (bicep/infra/entra-id-setup/setup.ps1)
// which creates the App Registration and stores values as azd environment variables.
// For bring-your-own app registrations, set these values directly via 'azd env set'.
param entraTenantId = readEnvironmentVariable('AZURE_TENANT_ID', '')
param entraClientId = readEnvironmentVariable('AZURE_CLIENT_ID', '')
param entraAudience = readEnvironmentVariable('AZURE_AUDIENCE', '')
param entraClientSecret = readEnvironmentVariable('ENTRA_CLIENT_SECRET', '')
