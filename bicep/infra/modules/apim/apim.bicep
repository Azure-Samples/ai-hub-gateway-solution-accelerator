param name string
param location string = resourceGroup().location
param tags object = {}
param entraAuth bool = false

@minLength(1)
param publisherEmail string = 'noreply@microsoft.com'

@minLength(1)
param publisherName string = 'n/a'

param sku string = 'Developer'
var isV2SKU = sku == 'StandardV2' || sku == 'PremiumV2'
param skuCount int = 1
param applicationInsightsName string

param managedIdentityName string
param clientAppId string = ' '
param tenantId string = tenant().tenantId
param audience string = 'https://cognitiveservices.azure.com/.default'

@description('Name of the Key Vault used to store APIM-managed secrets (e.g. the Application Insights connection string consumed by the APIM logger). The vault must already exist and grant the APIM user-assigned managed identity the Key Vault Secrets User role.')
param keyVaultName string
param eventHubName string
param eventHubEndpoint string

param eventHubPIIName string
param eventHubPIIEndpoint string

param enableAzureAISearch bool = false
param aiSearchInstances array

param enableAIModelInference bool = true

param enableOpenAIRealtime bool = true

param enableDocumentIntelligence bool = false

param enablePIIAnonymization bool = true

param contentSafetyServiceUrl string
param aiLanguageServiceUrl string


// Networking
param apimNetworkType string = 'External'
param apimSubnetId string

param apimV2PrivateDnsZoneName string = 'privatelink.azure-api.net'
param apimV2PrivateEndpointName string
param dnsZoneRG string = ''
param dnsSubscriptionId string = ''
param privateEndpointSubnetId string
param usePrivateEndpoint bool = false
param apimV2PublicNetworkAccess bool = true

// New parameter: Direct DNS zone resource ID (preferred over dnsZoneRG/dnsSubscriptionId)
param dnsZoneResourceId string = ''



// MCP Samples (Weather API, Weather MCP, MS Learn MCP)
param isMCPSampleDeployed bool = false

/**
 * LLM Backend Configuration
 * This parameter defines all LLM backends and their supported models for dynamic routing.
 * Each backend can be:
 * - AI Foundry: Deployed Azure AI Foundry project with model deployments
 * - Azure OpenAI: Azure OpenAI service endpoints
 * - Other LLM providers: External LLM endpoints with appropriate authentication
 * 
 * Structure:
 * - backendId: Unique identifier for the backend (used in APIM backend resource name)
 * - backendType: Type of backend ('ai-foundry', 'azure-openai', 'aws-bedrock', 'aws-bedrock-mantle', 'gemini', 'gemini-openai', 'anthropic', 'external')
 * - endpoint: Base URL for the backend service
 * - authScheme: (Legacy) Authentication method ('managedIdentity', 'apiKey', 'token') — superseded by authType
 * - authType: (Optional) 'managed-identity' | 'aws-sigv4' | 'api-key-bearer' | 'api-key-header' | 'api-key-gemini' | 'api-key-anthropic' | 'none'.
 *             When omitted, it is derived from backendType (ai-foundry/azure-openai → managed-identity).
 * - authConfig: (Optional) { namedValueKey: 'apim-named-value', keyVaultSecretUri?: '...', secretValue?: '...' } for api-key-* auth types
 * - supportedModels: Array of model objects with:
 *     - name: Model name (required)
 *     - sku: (Optional) SKU name for deployment (default: 'Standard')
 *     - capacity: (Optional) Capacity/TPM quota (default: 100)
 *     - modelFormat: (Optional) Model format identifier (default: 'OpenAI')
 *     - modelVersion: (Optional) Version of the model (default: '1')
 *     - retirementDate: (Optional) Retirement date in YYYY-MM-DD format
 *     - apiVersion: (Optional) API version for OpenAI-type requests (default: '2024-02-15-preview')
 *     - timeout: (Optional) Request timeout in seconds (default: 120)
 *     - inferenceApiVersion: (Optional) API version for inference-type requests
 * - priority: (Optional) Priority for load balancing (1-5, default 1)
 * - weight: (Optional) Weight for load balancing (1-1000, default 1)
 */
@description('Configuration array for LLM backends supporting multiple providers and models')
param llmBackendConfig array = []

@description('Enable APIM cache configuration backed by Azure Managed Redis')
param enableRedisCache bool = false

@secure()
@description('Runtime connection string to the Azure Managed Redis instance (used for APIM caches).')
param redisCacheConnectionString string = ''

@description('Resource ID of the Azure Managed Redis instance (optional, used for traceability)')
param redisCacheResourceId string = ''

@description('APIM cache entity name for the Redis-backed cache')
param apimRedisCacheName string = 'redis-cache'

@description('Azure Monitor diagnostic log settings for inference APIs (frontend/backend request/response headers & body bytes, and LLM log settings).')
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

@description('Application Insights diagnostic log settings for inference APIs (headers to capture and body bytes).')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

@description('Enable an APIM backend that targets the AI Foundry embeddings endpoint')
param enableEmbeddingsBackend bool = false

@description('Enable the Unified AI Wildcard API (3rd API alongside Azure OpenAI and Universal LLM)')
param enableUnifiedAiApi bool = true

@description('Enable JWT authentication support across all APIs (creates JWT named values and security-handler fragment)')
param enableJwtAuth bool = false

@description('JWT Tenant ID (required when enableJwtAuth is true and not using Entra module)')
param jwtTenantId string = ''

@description('JWT App Registration Client ID (required when enableJwtAuth is true and not using Entra module)')
param jwtAppRegistrationId string = ''

@description('URL for the AI Foundry embeddings endpoint (should be /models/embeddings on the primary Foundry resource)')
param embeddingsBackendUrl string = ''

@description('APIM backend ID for the embeddings backend')
param embeddingsBackendId string = 'foundry-embeddings'

var apimPublicNetworkAccess = apimV2PublicNetworkAccess ? 'Enabled' : 'Disabled'

var openAiApiUamiNamedValue = 'uami-client-id'
var openAiApiEntraNamedValue = 'entra-auth'
var openAiApiClientNamedValue = 'client-id'
var openAiApiTenantNamedValue = 'tenant-id'
var openAiApiAudienceNamedValue = 'audience'

var apiManagementMinApiVersion = '2021-08-01'
var apiManagementMinApiVersionV2 = '2024-05-01'

// Add this variable near the top with other variables
// var apimZones = sku == 'Premium' && skuCount > 1 ? ['1','2','3'] : []
// Replace the existing apimZones variable
var apimZones = (sku == 'Premium' && skuCount > 1) ? (skuCount == 2 ? ['1','2'] : ['1','2','3']) : []

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    capacity: (sku == 'Consumption') ? 0 : ((sku == 'Developer') ? 1 : skuCount)
  }
  identity: {
    // Enable BOTH system-assigned and user-assigned managed identities.
    // - User-assigned: pre-existing identity used by APIM policies (federated to backends, etc.)
    // - System-assigned: required by APIM to resolve named-value Key Vault references.
    //   When a named value is created with a `keyVault.secretIdentifier`, APIM uses its
    //   primary identity (system-assigned by default) to fetch the secret. Without it,
    //   provisioning a Key-Vault-backed named value fails with an authorization error.
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: isV2SKU ? 'External' : apimNetworkType
    publicNetworkAccess: isV2SKU ? apimPublicNetworkAccess : 'Enabled'
    virtualNetworkConfiguration: apimNetworkType != 'None' || isV2SKU ? {
      subnetResourceId: apimSubnetId
    } : null
    apiVersionConstraint: {
      minApiVersion: isV2SKU? apiManagementMinApiVersionV2 : apiManagementMinApiVersion
    }
    // Custom properties are not supported for Consumption SKU
    customProperties: sku == 'Consumption' ? {} : {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
  zones: apimZones
}

module privateEndpoint '../networking/private-endpoint.bicep' = if (isV2SKU && usePrivateEndpoint) {
  name: '${name}-pe'
  params: {
    groupIds: [
      'Gateway'
    ]
    dnsZoneName: apimV2PrivateDnsZoneName
    name: apimV2PrivateEndpointName
    privateLinkServiceId: apimService.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: privateEndpointSubnetId
    dnsSubId: dnsSubscriptionId
    dnsZoneResourceId: dnsZoneResourceId
  }
}

module apimAiSearchIndexApi './api.bicep' = if (enableAzureAISearch) {
  name: 'azure-ai-search-index-api'
  params: {
    serviceName: apimService.name
    apiName: 'azure-ai-search-index-api'
    path: 'search'
    apiRevision: '1'
    apiDisplayName: 'Azure AI Search Index API (index services)'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./ai-search-api/ai-search-index-2024-07-01-api-spec.json')
    apiDescription: 'Azure AI Search Index Client APIs'
    policyDocument: loadTextContent('./policies/ai-search-index-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimOpenAIRealTimetApi './api.bicep' = if (enableOpenAIRealtime) {
  name: 'openai-realtime-ws-api'
  params: {
    serviceName: apimService.name
    apiName: 'openai-realtime-ws-api'
    path: 'openai/realtime'
    apiRevision: '1'
    apiDisplayName: 'Azure OpenAI Realtime API'
    subscriptionRequired: entraAuth ? false : true
    subscriptionKeyName: 'api-key'
    openApiSpecification: 'NA'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion.'
    policyDocument: loadTextContent('./policies/openai-realtime-policy.xml')
    enableAPIDeployment: true
    serviceUrl: 'wss://to-be-replaced-by-policy'
    apiType: 'websocket'
    apiProtocols: ['wss']
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimDocumentIntelligenceLegacy './api.bicep' = if (enableDocumentIntelligence) {
  name: 'document-intelligence-api-legacy'
  params: {
    serviceName: apimService.name
    apiName: 'document-intelligence-api-legacy'
    path: 'formrecognizer'
    apiRevision: '1'
    apiDisplayName: 'Document Intelligence API (Legacy)'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'Ocp-Apim-Subscription-Key'
    openApiSpecification: loadTextContent('./doc-intel-api/document-intelligence-2024-11-30-compressed.openapi.yaml')
    apiDescription: 'Uses (/formrecognizer) url path. Extracts content, layout, and structured data from documents.'
    policyDocument: loadTextContent('./policies/doc-intelligence-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

module apimDocumentIntelligence './api.bicep' = if (enableDocumentIntelligence) {
  name: 'document-intelligence-api'
  params: {
    serviceName: apimService.name
    apiName: 'document-intelligence-api'
    path: 'documentintelligence'
    apiRevision: '1'
    apiDisplayName: 'Document Intelligence API'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'Ocp-Apim-Subscription-Key'
    openApiSpecification: loadTextContent('./doc-intel-api/document-intelligence-2024-11-30-compressed.openapi.yaml')
    apiDescription: 'Uses (/documentintelligence) url path. Extracts content, layout, and structured data from documents.'
    policyDocument: loadTextContent('./policies/doc-intelligence-api-policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
    policyFragments
  ]
}

/**
 * Dynamic LLM Backend Creation
 * Creates individual backends for each LLM endpoint defined in llmBackendConfig
 * Supports AI Foundry, Azure OpenAI, and external LLM providers
 */
module llmBackends './llm-backends.bicep' = {
  name: 'llm-backends'
  params: {
    apimServiceName: apimService.name
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
    configureCircuitBreaker: true
    tags: tags
  }
}

/**
 * Dynamic Backend Pool Creation
 * Groups backends by supported models to enable load balancing and failover
 * Only creates pools for models supported by multiple backends
 */
module llmBackendPools './llm-backend-pools.bicep' = {
  name: 'llm-backend-pools'
  params: {
    apimServiceName: apimService.name
    backendDetails: llmBackends.outputs.backendDetails
    tags: tags
  }
}

/**
 * Dynamic LLM Policy Fragments
 * Generates policy fragments with backend pool configurations for routing logic
 * Updates set-backend-pools and set-backend-authorization fragments dynamically
 * Also generates get-available-models fragment with model metadata
 */
module llmPolicyFragments './llm-policy-fragments.bicep' =  {
  name: 'llm-policy-fragments'
  params: {
    apimServiceName: apimService.name
    policyFragmentConfig: llmBackendPools.outputs.policyFragmentConfig
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
    // Backend contract reporting (surfaced via GET /version/backend-contract). The primary
    // deployment enables the circuit breaker; session affinity and model aliases are features
    // of the LLM onboarding submodule, so they are reported as inactive here until onboarding runs.
    apimTarget: {
      subscriptionId: subscription().subscriptionId
      resourceGroupName: resourceGroup().name
      name: apimService.name
    }
    configureCircuitBreaker: true
    configureSessionAffinity: false
  }
}

resource redisCache 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = if (enableRedisCache) {
  name: apimRedisCacheName
  parent: apimService
  properties: {
    connectionString: redisCacheConnectionString
    useFromLocation: 'default'
    description: 'Azure Managed Redis cache for APIM Semantic Cache'
  }
}

resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (enableEmbeddingsBackend) {
  name: embeddingsBackendId
  parent: apimService
  properties: {
    description: 'AI Foundry embeddings backend'
    url: embeddingsBackendUrl
    protocol: 'http'
    credentials: {
      managedIdentity: {
        clientId: managedIdentity.properties.clientId
        resource: 'https://cognitiveservices.azure.com'
      }
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

module apiUniversalLLM './inference-api.bicep' = {
  name: 'universal-llm-api'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'universal-llm-api'
    inferenceAPIPath: ''
    inferenceAPIType: 'OpenAIV1'
    inferenceAPIDisplayName: 'Universal LLM API'
    inferenceAPIDescription: 'Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: entraAuth ? false:true
    apimLoggerId: apimAzMonitorLogger.id
    policyXml: loadTextContent('./policies/universal-llm-api-policy-v2.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
  ]
}

module apimOpenaiApi './inference-api.bicep' = {
  name: 'azure-openai-api'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'azure-openai-api'
    inferenceAPIPath: ''
    inferenceAPIType: 'AzureOpenAI'
    inferenceAPIDisplayName: 'Azure OpenAI (Legacy)'
    inferenceAPIDescription: 'Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: entraAuth ? false:true
    apimLoggerId: apimAzMonitorLogger.id
    policyXml: loadTextContent('./policies/azure-open-ai-api-policy.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
    // Serialize OpenAPI import with the Universal LLM API. Both specs declare the
    // same global operation tags (Chat, Embeddings, Audio, Images, Files, Models,
    // Threads, Vector Stores, etc.). APIM creates these tags at service scope during
    // import; running the two imports in parallel makes both try to CREATE the same
    // tag simultaneously, causing the transient "Tag with the same name already
    // exists" (ValidationError). Import tolerates pre-existing tags (hence retries
    // succeed), so forcing sequential import guarantees a clean first-run.
    apiUniversalLLM
  ]
}

////// Unified AI Wildcard API /////////////

module apiUnifiedAI './unified-ai-api.bicep' = if (enableUnifiedAiApi) {
  name: 'unified-ai-api'
  params: {
    apiManagementName: apimService.name
    enabled: enableUnifiedAiApi
    apimLoggerId: apimAzMonitorLogger.id
    azureMonitorLogSettings: azureMonitorLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
  ]
}

////// Release Version API /////////////
// Lightweight API exposing a single GET operation that returns the accelerator
// release manifest (release.json) as static JSON content via a mock response.
module apiReleaseVersion './version-api.bicep' = {
  name: 'release-version-api'
  params: {
    apiManagementName: apimService.name
  }
  dependsOn: [
    // The backend-contract operation includes the dynamically generated
    // 'backend-contract' policy fragment, which must exist first.
    llmPolicyFragments
  ]
}

////// JWT Authentication Named Values /////////////
// These named values support JWT authentication across all APIs (Azure OpenAI,
// Universal LLM, and Unified AI). The security-handler fragment is included in all
// API policies and references these named values via {{...}} syntax.
// When enableJwtAuth is false, placeholders are used so deployment passes.
// JWT enforcement is controlled per-product via the 'jwtRequired' context variable
// set in each Access Contract's product policy.

var jwtTenantIdValue = !empty(jwtTenantId) ? jwtTenantId : subscription().tenantId
var jwtAppRegIdValue = !empty(jwtAppRegistrationId) ? jwtAppRegistrationId : 'not-configured'

resource jwtTenantIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'JWT-TenantId'
  parent: apimService
  properties: {
    displayName: 'JWT-TenantId'
    value: enableJwtAuth ? jwtTenantIdValue : 'not-configured'
  }
}

resource jwtAppRegistrationIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'JWT-AppRegistrationId'
  parent: apimService
  properties: {
    displayName: 'JWT-AppRegistrationId'
    value: enableJwtAuth ? jwtAppRegIdValue : 'not-configured'
  }
}

resource jwtIssuerNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'JWT-Issuer'
  parent: apimService
  properties: {
    displayName: 'JWT-Issuer'
    value: enableJwtAuth ? '${environment().authentication.loginEndpoint}${jwtTenantIdValue}/v2.0' : 'not-configured'
  }
}

resource jwtOpenIdConfigUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'JWT-OpenIdConfigUrl'
  parent: apimService
  properties: {
    displayName: 'JWT-OpenIdConfigUrl'
    value: enableJwtAuth ? '${environment().authentication.loginEndpoint}${jwtTenantIdValue}/v2.0/.well-known/openid-configuration' : 'not-configured'
  }
}

////// AI Foundry Integration Requirements /////////////

// Typed resource reference for the Universal LLM API (created by module above)
resource universalLLMApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: 'universal-llm-api'
  parent: apimService
  dependsOn: [
    apiUniversalLLM
  ]
}

resource universalLlmDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployments'
  parent: universalLLMApi
}

resource universalLlmDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployment-by-name'
  parent: universalLLMApi
}

resource universalLlmListModelsOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'listModels'
  parent: universalLLMApi
}

resource universalLlmRetrieveModelOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'retrieveModel'
  parent: universalLLMApi
}

resource openAIApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: 'azure-openai-api'
  parent: apimService
  dependsOn: [
    apimOpenaiApi
  ]
}

resource openAIDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployments'
  parent: openAIApi
}

resource openAIDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = {
  name: 'deployment-by-name'
  parent: openAIApi
}

resource universalLlmDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource universalLlmDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

resource universalLlmListModelsOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmListModelsOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource universalLlmRetrieveModelOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: universalLlmRetrieveModelOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

resource openAIDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: openAIDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployments-policy.xml')
  }
}

resource openAIDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = {
  name: 'policy'
  parent: openAIDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

//////////// End of AI Foundry Integration Requirements /////////////

resource aiSearchBackends 'Microsoft.ApiManagement/service/backends@2022-08-01' = [for (aiSearchInstance, i) in aiSearchInstances: if(enableAzureAISearch) {
  name: aiSearchInstance.name
  parent: apimService
  properties: {
    description: aiSearchInstance.description
    url: aiSearchInstance.url
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  name: 'content-safety-backend'
  parent: apimService
  properties: {
    description: 'Content Safety Service Backend'
    url: contentSafetyServiceUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    credentials: {
      managedIdentity: {
        clientId: managedIdentity.properties.clientId
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

resource apimOpenaiApiUamiNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiUamiNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiUamiNamedValue
    secret: true
    value: managedIdentity.properties.clientId
  }
}

resource apiopenAiApiEntraNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiEntraNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiEntraNamedValue
    secret: false
    value: entraAuth
  }
}
resource apiopenAiApiClientNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiClientNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiClientNamedValue
    secret: true
    value: !empty(clientAppId) ? clientAppId : 'not-configured'
  }
}
resource apiopenAiApiTenantNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiTenantNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiTenantNamedValue
    secret: true
    value: !empty(tenantId) ? tenantId : tenant().tenantId
  }
}
resource apimOpenaiApiAudienceNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: openAiApiAudienceNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiAudienceNamedValue
    secret: true
    value: !empty(audience) ? audience : 'https://cognitiveservices.azure.com/.default'
  }
}

resource piiServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'piiServiceUrl'
  parent: apimService
  properties: {
    displayName: 'piiServiceUrl'
    secret: false
    value: aiLanguageServiceUrl
  }
}

resource piiServiceKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'piiServiceKey'
  parent: apimService
  properties: {
    displayName: 'piiServiceKey'
    secret: true
    value: 'replace-with-language-service-key-if-needed'
  }
}

resource contentSafetyServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: 'contentSafetyServiceUrl'
  parent: apimService
  properties: {
    displayName: 'contentSafetyServiceUrl'
    secret: false
    value: contentSafetyServiceUrl
  }
}

// Policy Fragments Module
module policyFragments './policy-fragments.bicep' = {
  name: 'apim-policy-fragments'
  params: {
    apimServiceName: apimService.name
    enablePIIAnonymization: enablePIIAnonymization
    enableAIModelInference: enableAIModelInference
    enableUnifiedAiApi: enableUnifiedAiApi
  }
  dependsOn: [
    apiopenAiApiClientNamedValue
    apiopenAiApiEntraNamedValue
    apimOpenaiApiAudienceNamedValue
    apiopenAiApiTenantNamedValue
    ehUsageLogger
    ehPIIUsageLogger
    piiServiceUrlNamedValue
    piiServiceKeyNamedValue
    jwtTenantIdNamedValue
    jwtAppRegistrationIdNamedValue
    jwtIssuerNamedValue
    jwtOpenIdConfigUrlNamedValue
  ]
}

// ----------------------------------------------------------------------------
// Application Insights logger credentials via Azure Key Vault
// ----------------------------------------------------------------------------
// Official guidance: https://learn.microsoft.com/azure/api-management/api-management-howto-app-insights
// Rather than embedding the Application Insights connection string directly in
// the APIM logger resource (which would surface it in deployment outputs and ARM
// history), we store it as a Key Vault secret and expose it via an APIM
// named value that references the secret. The named value is configured to use
// the APIM user-assigned managed identity (which already has Key Vault Secrets
// User on this vault — see `keyvault.bicep`) so the secret is resolved at
// runtime without static credentials. APIM auto-refreshes the cached value on a
// regular interval, so rotating the secret in Key Vault is picked up without
// redeploying the logger.

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Persist the Application Insights connection string as a Key Vault secret.
// Key Vault secret names cannot contain underscores; hyphenated names are used
// to match the convention applied elsewhere in this accelerator (e.g.
// `ENTRA-APP-CLIENT-SECRET`). The secret is unversioned so APIM picks up
// rotated values automatically.
var appInsightsConnectionStringSecretName = 'apim-appinsights-connection-string'

resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: appInsightsConnectionStringSecretName
  parent: keyVault
  properties: {
    value: applicationInsights.properties.ConnectionString
    contentType: 'text/plain'
  }
}

// APIM named value that resolves the secret from Key Vault. The token
// `{{appinsights-logger-credentials}}` can then be used anywhere an APIM
// resource accepts a named-value reference (logger credentials, policies, etc.).
// `secretIdentifier` is intentionally version-less so rotation is automatic.
var appInsightsLoggerCredentialsNamedValueName = 'appinsights-logger-credentials'

resource appInsightsLoggerCredentialsNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: appInsightsLoggerCredentialsNamedValueName
  parent: apimService
  properties: {
    displayName: appInsightsLoggerCredentialsNamedValueName
    secret: true
    keyVault: {
      // Use the APIM user-assigned managed identity for the Key Vault fetch.
      // The user-assigned identity is granted `Key Vault Secrets User` by
      // `keyvault.bicep` *before* APIM is provisioned, which guarantees that
      // the secret is reachable the moment this named value is created and
      // avoids the chicken-and-egg problem that the system-assigned identity
      // would have (its role assignment is created in `keyvault-apim-system-rbac.bicep`,
      // which runs *after* the APIM module).
      identityClientId: managedIdentity.properties.clientId
      secretIdentifier: '${keyVault.properties.vaultUri}secrets/${appInsightsConnectionStringSecretName}'
    }
  }
  dependsOn: [
    appInsightsConnectionStringSecret
  ]
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  name: 'appinsights-logger'
  parent: apimService
  properties: {
    credentials: {
      // Reference the APIM named value (which itself is backed by a Key Vault secret)
      // instead of embedding the Application Insights connection string directly in
      // the logger configuration. APIM resolves the {{...}} token at runtime by
      // fetching the secret from Key Vault using the user-assigned managed identity
      // declared on the named value.
      connectionString: '{{${appInsightsLoggerCredentialsNamedValueName}}}'
    }
    description: 'Application Insights logger for API observability (connection string resolved from Key Vault via named value)'
    isBuffered: false
    loggerType: 'applicationInsights'
    resourceId: applicationInsights.id
  }
  dependsOn: [
    appInsightsLoggerCredentialsNamedValue
  ]
}

resource apimAzMonitorLogger 'Microsoft.ApiManagement/service/loggers@2024-10-01-preview' = {
  parent: apimService
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: false // Set to false to ensure logs are sent immediately
    description: 'Azure Monitor logger for Log Analytics'
  }
}

resource apimAppInsights 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    loggerId: apimLogger.id
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
    }
  }
}

resource ehUsageLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  name: 'usage-eventhub-logger'
  parent: apimService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for OpenAI usage metrics'
    credentials: {
      name: eventHubName
      endpointAddress: replace(eventHubEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
}

resource ehPIIUsageLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = if (enablePIIAnonymization) {
  name: 'pii-usage-eventhub-logger'
  parent: apimService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for PII usage metrics and logs'
    credentials: {
      name: eventHubPIIName
      endpointAddress: replace(eventHubPIIEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
}

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apimService
  name: 'apimDiagnosticSettings'
  properties: {
    workspaceId: applicationInsights.properties.WorkspaceResourceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'AllLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Sample MCP resources
module weatherAPI './api.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-api'
  params: {
    serviceName: apimService.name
    apiName: 'weather-api'
    path: 'weather'
    apiRevision: '1'
    apiDisplayName: 'Weather API'
    subscriptionRequired: false
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./sample/weather/openapi.json')
    apiDescription: 'Weather API for getting dynamic weather information for a given location.'
    policyDocument: loadTextContent('./sample/weather/policy.xml')
    enableAPIDeployment: true
    enableAPIDiagnostics: false
  }
  dependsOn: [
  ]
}

module weatherMCP './mcp-from-api.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-mcp'
  params: {
    apimServiceName: apimService.name
    appInsightsLoggerName: 'appinsights-logger'
    apiName: 'weather-api'
    operationNames: ['get-weather']
    mcpPath: 'weather-mcp'
    mcpName: 'weather-mcp'
    mcpDisplayName: 'Weather MCP Development'
    mcpDescription: 'MCP server for weather data operations for given location (Development)'
  }
  dependsOn: [
    weatherAPI
    apimLogger
  ]
}

module microsoftLearnMCPServer 'mcp-existing.bicep' = if (isMCPSampleDeployed) {
  name: 'microsoftLearnMCPServer'
  params: {
    apimServiceName: apimService.name
    backendName: 'ms-learn-mcp-server'
    backendDescription: 'Microsoft Learn MCP Server'
    backendURL: 'https://learn.microsoft.com/api/mcp'
    mcpApiName: 'ms-learn-mcp'
    mcpDisplayName: 'Microsoft Learn MCP'
    mcpDescription: 'Microsoft Learn MCP Server'
    mcpPath: 'ms-learn-mcp'
    mcpPolicyXml: ''
  }
  dependsOn: [
    apimLogger
  ]
}

@description('The name of the deployed API Management service.')
output apimName string = apimService.name

@description('The path for the OpenAI API in the deployed API Management service.')
output apimOpenaiApiPath string = apimOpenaiApi.outputs.path

@description('Gateway URL for the deployed API Management resource.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

output apimIdentityClientId string = managedIdentity.properties.principalId

@description('Principal ID of the APIM system-assigned managed identity. Used to grant Key Vault access for named-value secret references.')
output apimSystemAssignedPrincipalId string = apimService.identity.principalId
