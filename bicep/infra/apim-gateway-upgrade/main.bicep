/**
 * @module apim-gateway-upgrade
 * @description Updates the configuration of an existing APIM instance provisioned by the main
 *              AI Hub Gateway Solution Accelerator. This deployment targets policy fragments,
 *              API definitions & policies, logging/diagnostics, and named values — without
 *              re-provisioning the APIM service or any surrounding infrastructure.
 *
 * Scope: Resource Group (the RG that already contains the APIM instance)
 *
 * Prerequisites:
 *   - APIM service already exists in the target resource group
 *   - Application Insights logger ('appinsights-logger') already exists on the APIM instance
 *   - Azure Monitor logger ('azuremonitor') already exists on the APIM instance — OR set
 *     deployAzureMonitorLogger=true to create it during the upgrade for legacy installs
 *   - User-assigned managed identity already exists (for backend auth)
 */

targetScope = 'resourceGroup'

// =====================================================================
//    CORE PARAMETERS
// =====================================================================

@description('Name of the existing API Management service to update')
param apimServiceName string

@description('Name of the existing user-assigned managed identity used by APIM for backend auth')
param managedIdentityName string

// =====================================================================
//    FEATURE FLAGS — control which configuration sections are applied
// =====================================================================

@description('Update policy fragments on the APIM instance')
param updatePolicyFragments bool = true

@description('Update the Universal LLM API definition and policy')
param updateUniversalLLMApi bool = true

@description('Update the Azure OpenAI API definition and policy')
param updateAzureOpenAIApi bool = true

@description('Update the OpenAI Realtime WebSocket API definition and policy')
param updateOpenAIRealtimeApi bool = false

@description('Update APIM-level Application Insights diagnostic configuration')
param updateAppInsightsDiagnostics bool = true

@description('Update APIM named values (auth, Entra, PII, Content Safety)')
param updateNamedValues bool = true

@description('Update LLM backend definitions')
param updateLLMBackends bool = true

@description('Update LLM backend pools')
param updateLLMBackendPools bool = true

@description('Update LLM policy fragments (set-backend-pools, set-backend-authorization, etc.)')
param updateLLMPolicyFragments bool = true

@description('Update the Unified AI Wildcard API definition, product, and policy')
param updateUnifiedAiApi bool = true

@description('Create or update the Release Version API (single GET operation returning release.json)')
param updateReleaseVersionApi bool = true

@description('Update JWT authentication named values (JWT-TenantId, JWT-AppRegistrationId, JWT-Issuer, JWT-OpenIdConfigUrl)')
param updateJwtNamedValues bool = true

@description('Update APIM Redis cache entity configuration')
param updateRedisCache bool = false

@description('Update APIM embeddings backend configuration')
param updateEmbeddingsBackend bool = false

// =====================================================================
//    FEATURE-SPECIFIC PARAMETERS
// =====================================================================

@description('Enable PII Anonymization policy fragments')
param enablePIIAnonymization bool = true

@description('Enable AI Model Inference policy fragments')
param enableAIModelInference bool = true

@description('Enable the Unified AI Wildcard API (3rd API alongside Azure OpenAI and Universal LLM)')
param enableUnifiedAiApi bool = true

@description('Enable JWT authentication support across all APIs (creates JWT named values and security-handler fragment)')
param enableJwtAuth bool = false

@description('JWT Tenant ID (required when enableJwtAuth is true)')
param jwtTenantId string = ''

@description('JWT App Registration Client ID (required when enableJwtAuth is true)')
param jwtAppRegistrationId string = ''

// =====================================================================
//    CLASSIC AI HUB GATEWAY (pre Citadel Governance Hub) — RESERVED
//    These settings are ONLY intended for classic AI Hub Gateway installs
//    provisioned before the Citadel Governance Hub release. Disabled by default.
// =====================================================================

@description('[Classic AI Hub Gateway ONLY] Provision a dedicated llm-usage-container in an EXISTING Cosmos DB account. Reserved for classic AI Hub Gateway installs prior to the Citadel Governance Hub release. Disabled by default.')
param enableClassicLlmUsageContainer bool = false

@description('Name of the EXISTING Cosmos DB account (in the SAME resource group as the APIM instance) in which to provision the llm-usage-container. Required when enableClassicLlmUsageContainer is true.')
param classicCosmosDbAccountName string = ''

@description('Name of the EXISTING Cosmos DB SQL database in which to provision the llm-usage-container.')
param classicCosmosDbDatabaseName string = 'ai-usage-db'

@description('Throughput (RU/s) for the classic llm-usage-container.')
@minValue(400)
@maxValue(1000000)
param classicLlmUsageContainerThroughput int = 400

// =====================================================================
//    API PATH PREFIXES (legacy coexistence)
// =====================================================================

@description('''Optional path prefix for the Azure OpenAI API. Default '' deploys at /openai. Set to e.g.
'v2' to deploy at /v2/openai so a legacy /openai API can coexist (Option 2 in the README). The
frontend prefix is stripped dynamically by policies (context.Api.Path), so it never conflicts with
policy fragments or backend routing.''')
param azureOpenAIApiPathPrefix string = ''

@description('''Optional path prefix for the Universal LLM API. Default '' deploys at /models. Set to e.g.
'v2' to deploy at /v2/models so a legacy /models API can coexist (Option 2 in the README). The
frontend prefix is stripped dynamically by policies (context.Api.Path), so it never conflicts with
policy fragments or backend routing.''')
param universalLLMApiPathPrefix string = ''

// =====================================================================
//    AZURE MONITOR LOGGER (legacy installs missing it)
// =====================================================================

@description('Create the azuremonitor logger as part of the upgrade (for legacy installs that never provisioned it). When false, the logger is assumed to already exist.')
param deployAzureMonitorLogger bool = false

@description('Resource ID of an EXISTING Log Analytics workspace to wire to APIM diagnostic settings when deployAzureMonitorLogger is true. No workspace is provisioned. Leave empty to create only the logger without diagnostic settings.')
param logAnalyticsWorkspaceResourceId string = ''

// =====================================================================
//    NAMED VALUE PARAMETERS
// =====================================================================

@description('URL of the Azure AI Language service (used for PII)')
param aiLanguageServiceUrl string = ''

@description('URL of the Azure Content Safety service')
param contentSafetyServiceUrl string = ''

// =====================================================================
//    LLM BACKEND CONFIGURATION
// =====================================================================

@description('''Configuration array for LLM backends supporting multiple providers and models.
Each backend object: { backendId, backendType, endpoint, supportedModels[], priority?, weight?,
authType? ('managed-identity' | 'aws-sigv4' | 'api-key-bearer' | 'api-key-header' | 'api-key-gemini' | 'api-key-anthropic' | 'none'),
authConfig? ({ namedValueKey, keyVaultSecretUri?, secretValue? }) }.
When authType is omitted it is derived from backendType (ai-foundry/azure-openai → managed-identity),
matching the llm-backend-onboarding module. The legacy `authScheme` field is still tolerated but superseded by authType.''')
param llmBackendConfig array = []

@description('Anthropic API version sent in the anthropic-version header for Anthropic backends (Messages API). Stored as the `anthropic-version` named value referenced by the backend credentials.header.')
param anthropicVersion string = '2023-06-01'

// =====================================================================
//    REDIS CACHE & EMBEDDINGS CONFIGURATION
// =====================================================================

@description('Enable APIM cache configuration backed by Azure Managed Redis')
param enableRedisCache bool = false

@secure()
@description('Runtime connection string to the Azure Managed Redis instance (used for APIM caches)')
param redisCacheConnectionString string = ''

@description('APIM cache entity name for the Redis-backed cache')
param apimRedisCacheName string = 'redis-cache'

@description('Enable an APIM backend that targets the AI Foundry embeddings endpoint')
param enableEmbeddingsBackend bool = false

@description('URL for the AI Foundry embeddings endpoint')
param embeddingsBackendUrl string = ''

@description('APIM backend ID for the embeddings backend')
param embeddingsBackendId string = 'foundry-embeddings'

// =====================================================================
//    LOGGING / DIAGNOSTICS PARAMETERS
// =====================================================================

@description('Azure Monitor diagnostic log settings for inference APIs')
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

@description('Application Insights diagnostic log settings for inference APIs')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

// =====================================================================
//    EXISTING RESOURCE REFERENCES
// =====================================================================

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimServiceName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}

// Reference existing loggers (assumed already provisioned)
resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2024-05-01' existing = {
  name: 'appinsights-logger'
  parent: apimService
}

resource azMonitorLoggerNew 'Microsoft.ApiManagement/service/loggers@2024-10-01-preview' = if (deployAzureMonitorLogger) {
  parent: apimService
  name: 'azuremonitor'
  properties: {
    loggerType: 'azureMonitor'
    isBuffered: false
    description: 'Azure Monitor logger for Log Analytics'
  }
}

// Route APIM diagnostics to an existing Log Analytics workspace (no workspace is provisioned).
resource apimAzMonitorDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployAzureMonitorLogger && !empty(logAnalyticsWorkspaceResourceId)) {
  name: 'apim-azuremonitor-diagnostics'
  scope: apimService
  properties: {
    workspaceId: logAnalyticsWorkspaceResourceId
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// Resolve the logger id without an `existing` reference (which would clash with the conditional
// create above and trigger "defined multiple times"). When the logger is created, this string id
// matches it; otherwise it references the pre-provisioned logger.
var azMonitorLoggerId = resourceId('Microsoft.ApiManagement/service/loggers', apimServiceName, 'azuremonitor')

// =====================================================================
//    NAMED VALUES
// =====================================================================

resource uamiNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = if (updateNamedValues) {
  name: 'uami-client-id'
  parent: apimService
  properties: {
    displayName: 'uami-client-id'
    secret: true
    value: managedIdentity.properties.clientId
  }
}

resource piiServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = if (updateNamedValues && enablePIIAnonymization) {
  name: 'piiServiceUrl'
  parent: apimService
  properties: {
    displayName: 'piiServiceUrl'
    secret: false
    value: aiLanguageServiceUrl
  }
}

resource piiServiceKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = if (updateNamedValues && enablePIIAnonymization) {
  name: 'piiServiceKey'
  parent: apimService
  properties: {
    displayName: 'piiServiceKey'
    secret: true
    value: 'replace-with-language-service-key-if-needed'
  }
}

resource contentSafetyServiceUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = if (updateNamedValues) {
  name: 'contentSafetyServiceUrl'
  parent: apimService
  properties: {
    displayName: 'contentSafetyServiceUrl'
    secret: false
    value: contentSafetyServiceUrl
  }
}

// =====================================================================
//    CONTENT SAFETY BACKEND
// =====================================================================

resource contentSafetyBackend 'Microsoft.ApiManagement/service/backends@2024-05-01' = if (updateNamedValues && !empty(contentSafetyServiceUrl)) {
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
      // 'managedIdentity' is a valid runtime credential for APIM backends but is not yet
      // modeled in the BackendCredentialsContract Bicep type, so BCP037 is suppressed here.
      #disable-next-line BCP037
      managedIdentity: {
        clientId: managedIdentity.properties.clientId
        resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}

// =====================================================================
//    JWT AUTHENTICATION NAMED VALUES
// =====================================================================

var jwtTenantIdValue = !empty(jwtTenantId) ? jwtTenantId : subscription().tenantId
var jwtAppRegIdValue = !empty(jwtAppRegistrationId) ? jwtAppRegistrationId : 'not-configured'

resource jwtTenantIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (updateJwtNamedValues) {
  name: 'JWT-TenantId'
  parent: apimService
  properties: {
    displayName: 'JWT-TenantId'
    value: enableJwtAuth ? jwtTenantIdValue : 'not-configured'
  }
}

resource jwtAppRegistrationIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (updateJwtNamedValues) {
  name: 'JWT-AppRegistrationId'
  parent: apimService
  properties: {
    displayName: 'JWT-AppRegistrationId'
    value: enableJwtAuth ? jwtAppRegIdValue : 'not-configured'
  }
}

resource jwtIssuerNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (updateJwtNamedValues) {
  name: 'JWT-Issuer'
  parent: apimService
  properties: {
    displayName: 'JWT-Issuer'
    value: enableJwtAuth ? '${environment().authentication.loginEndpoint}${jwtTenantIdValue}/v2.0' : 'not-configured'
  }
}

resource jwtOpenIdConfigUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (updateJwtNamedValues) {
  name: 'JWT-OpenIdConfigUrl'
  parent: apimService
  properties: {
    displayName: 'JWT-OpenIdConfigUrl'
    value: enableJwtAuth ? '${environment().authentication.loginEndpoint}${jwtTenantIdValue}/v2.0/.well-known/openid-configuration' : 'not-configured'
  }
}

// =====================================================================
//    REDIS CACHE & EMBEDDINGS BACKEND
// =====================================================================

resource redisCache 'Microsoft.ApiManagement/service/caches@2024-06-01-preview' = if (updateRedisCache && enableRedisCache) {
  name: apimRedisCacheName
  parent: apimService
  properties: {
    connectionString: redisCacheConnectionString
    useFromLocation: 'default'
    description: 'Azure Managed Redis cache for APIM Semantic Cache'
  }
}

resource embeddingsBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if (updateEmbeddingsBackend && enableEmbeddingsBackend) {
  name: embeddingsBackendId
  parent: apimService
  properties: {
    description: 'AI Foundry embeddings backend'
    url: embeddingsBackendUrl
    protocol: 'http'
    credentials: {
      // 'managedIdentity' is a valid runtime credential for APIM backends but is not yet
      // modeled in the BackendCredentialsContract Bicep type, so BCP037 is suppressed here.
      #disable-next-line BCP037
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

// =====================================================================
//    POLICY FRAGMENTS (static — from policy-fragments.bicep)
// =====================================================================

module policyFragments '../modules/apim/policy-fragments.bicep' = if (updatePolicyFragments) {
  name: 'apim-policy-fragments-upgrade'
  params: {
    apimServiceName: apimService.name
    enablePIIAnonymization: enablePIIAnonymization
    enableAIModelInference: enableAIModelInference
    enableUnifiedAiApi: enableUnifiedAiApi
  }
  dependsOn: [
    piiServiceUrlNamedValue
    piiServiceKeyNamedValue
    jwtTenantIdNamedValue
    jwtAppRegistrationIdNamedValue
    jwtIssuerNamedValue
    jwtOpenIdConfigUrlNamedValue
  ]
}

// =====================================================================
//    LLM BACKENDS, POOLS & DYNAMIC POLICY FRAGMENTS
// =====================================================================

module llmBackends '../modules/apim/llm-backends.bicep' = if (updateLLMBackends) {
  name: 'llm-backends-upgrade'
  params: {
    apimServiceName: apimService.name
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
    configureCircuitBreaker: true
    anthropicVersion: anthropicVersion
  }
}

module llmBackendPools '../modules/apim/llm-backend-pools.bicep' = if (updateLLMBackendPools && updateLLMBackends) {
  name: 'llm-backend-pools-upgrade'
  params: {
    apimServiceName: apimService.name
    // llmBackends is guaranteed to be deployed because this module's condition includes
    // updateLLMBackends, so the output access is safe; suppress the null-safety warning.
    #disable-next-line BCP318
    backendDetails: llmBackends.outputs.backendDetails
  }
}

module llmPolicyFragments '../modules/apim/llm-policy-fragments.bicep' = if (updateLLMPolicyFragments && updateLLMBackendPools && updateLLMBackends) {
  name: 'llm-policy-fragments-upgrade'
  params: {
    apimServiceName: apimService.name
    // llmBackendPools is guaranteed to be deployed because this module's condition includes
    // updateLLMBackendPools, so the output access is safe; suppress the null-safety warning.
    #disable-next-line BCP318
    policyFragmentConfig: llmBackendPools.outputs.policyFragmentConfig
    managedIdentityClientId: managedIdentity.properties.clientId
    llmBackendConfig: llmBackendConfig
  }
}

// =====================================================================
//    APIs — Inference APIs (Universal LLM & Azure OpenAI)
// =====================================================================

module apiUniversalLLM '../modules/apim/inference-api.bicep' = if (updateUniversalLLMApi) {
  name: 'universal-llm-api-upgrade'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'universal-llm-api'
    inferenceAPIPath: universalLLMApiPathPrefix
    inferenceAPIType: 'OpenAIV1'
    inferenceAPIDisplayName: 'Universal LLM API'
    inferenceAPIDescription: 'Universal LLM API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: true
    apimLoggerId: azMonitorLoggerId
    policyXml: loadTextContent('../modules/apim/policies/universal-llm-api-policy-v2.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
    azMonitorLoggerNew
  ]
}

module apimOpenaiApi '../modules/apim/inference-api.bicep' = if (updateAzureOpenAIApi) {
  name: 'azure-openai-api-upgrade'
  params: {
    apiManagementName: apimService.name
    inferenceAPIName: 'azure-openai-api'
    inferenceAPIPath: azureOpenAIApiPathPrefix
    inferenceAPIType: 'AzureOpenAI'
    inferenceAPIDisplayName: 'Azure OpenAI API'
    inferenceAPIDescription: 'Azure OpenAI API to route requests to different LLM providers including Azure OpenAI, AI Foundry and 3rd party models.'
    allowSubscriptionKey: true
    apimLoggerId: azMonitorLoggerId
    policyXml: loadTextContent('../modules/apim/policies/azure-open-ai-api-policy.xml')
    azureMonitorLogSettings: azureMonitorLogSettings
    appInsightsLogSettings: appInsightsLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
    azMonitorLoggerNew
  ]
}

// =====================================================================
//    APIs — Unified AI Wildcard API
// =====================================================================

module apiUnifiedAI '../modules/apim/unified-ai-api.bicep' = if (updateUnifiedAiApi) {
  name: 'unified-ai-api-upgrade'
  params: {
    apiManagementName: apimService.name
    enabled: enableUnifiedAiApi
    apimLoggerId: azMonitorLoggerId
    azureMonitorLogSettings: azureMonitorLogSettings
  }
  dependsOn: [
    policyFragments
    llmBackends
    llmBackendPools
    llmPolicyFragments
    azMonitorLoggerNew
  ]
}

// =====================================================================
//    APIs — Release Version API
// =====================================================================

// Lightweight API exposing a single GET operation that returns the accelerator
// release manifest (release.json) as static JSON content via a mock response.
module apiReleaseVersion '../modules/apim/version-api.bicep' = if (updateReleaseVersionApi) {
  name: 'release-version-api-upgrade'
  params: {
    apiManagementName: apimService.name
  }
  dependsOn: [
    // The backend-contract operation includes the dynamically generated
    // 'backend-contract' policy fragment. When fragments are being updated in
    // the same run, ensure they are created/updated first.
    llmPolicyFragments
  ]
}

// =====================================================================
//    APIs — AI Foundry Deployment Operations (operation-level policies)
// =====================================================================

// Universal LLM API operation policies
resource universalLLMApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = if (updateUniversalLLMApi) {
  name: 'universal-llm-api'
  parent: apimService
  dependsOn: [
    apiUniversalLLM
  ]
}

resource universalLlmDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateUniversalLLMApi) {
  name: 'deployments'
  parent: universalLLMApi
}

resource universalLlmDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateUniversalLLMApi) {
  name: 'deployment-by-name'
  parent: universalLLMApi
}

resource universalLlmListModelsOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateUniversalLLMApi) {
  name: 'listModels'
  parent: universalLLMApi
}

resource universalLlmRetrieveModelOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateUniversalLLMApi) {
  name: 'retrieveModel'
  parent: universalLLMApi
}

resource universalLlmDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateUniversalLLMApi) {
  name: 'policy'
  parent: universalLlmDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployments-policy.xml')
  }
}

resource universalLlmDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateUniversalLLMApi) {
  name: 'policy'
  parent: universalLlmDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

resource universalLlmListModelsOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateUniversalLLMApi) {
  name: 'policy'
  parent: universalLlmListModelsOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployments-policy.xml')
  }
}

resource universalLlmRetrieveModelOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateUniversalLLMApi) {
  name: 'policy'
  parent: universalLlmRetrieveModelOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

// Azure OpenAI API operation policies
resource openAIApi 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = if (updateAzureOpenAIApi) {
  name: 'azure-openai-api'
  parent: apimService
  dependsOn: [
    apimOpenaiApi
  ]
}

resource openAIDeploymentOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateAzureOpenAIApi) {
  name: 'deployments'
  parent: openAIApi
}

resource openAIDeploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' existing = if (updateAzureOpenAIApi) {
  name: 'deployment-by-name'
  parent: openAIApi
}

resource openAIDeploymentOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateAzureOpenAIApi) {
  name: 'policy'
  parent: openAIDeploymentOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployments-policy.xml')
  }
}

resource openAIDeploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2022-08-01' = if (updateAzureOpenAIApi) {
  name: 'policy'
  parent: openAIDeploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('../modules/apim/policies/universal-llm-api-deployment-by-name-policy.xml')
  }
}

// =====================================================================
//    APIs — OpenAI Realtime WebSocket
// =====================================================================

module apimOpenAIRealtimeApi '../modules/apim/api.bicep' = if (updateOpenAIRealtimeApi) {
  name: 'openai-realtime-ws-api-upgrade'
  params: {
    serviceName: apimService.name
    apiName: 'openai-realtime-ws-api'
    path: 'openai/realtime'
    apiRevision: '1'
    apiDispalyName: 'Azure OpenAI Realtime API'
    subscriptionRequired: true
    subscriptionKeyName: 'api-key'
    openApiSpecification: 'NA'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion.'
    policyDocument: loadTextContent('../modules/apim/policies/openai-realtime-policy.xml')
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

// =====================================================================
//    LOGGING — Application Insights Diagnostics (APIM-level)
// =====================================================================

resource apimAppInsightsDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = if (updateAppInsightsDiagnostics) {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    loggerId: appInsightsLogger.id
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: appInsightsLogSettings.headers
        body: {
          bytes: appInsightsLogSettings.body.bytes
        }
      }
      response: {
        headers: appInsightsLogSettings.headers
        body: {
          bytes: appInsightsLogSettings.body.bytes
        }
      }
    }
    backend: {
      request: {
        headers: appInsightsLogSettings.headers
        body: {
          bytes: appInsightsLogSettings.body.bytes
        }
      }
      response: {
        headers: appInsightsLogSettings.headers
        body: {
          bytes: appInsightsLogSettings.body.bytes
        }
      }
    }
  }
}

// =====================================================================
//    CLASSIC AI HUB GATEWAY (pre Citadel Governance Hub) — RESERVED
//    Provision the llm-usage-container in an EXISTING Cosmos DB account.
// =====================================================================

module classicLlmUsageContainer 'services/classic-llm-usage-container.bicep' = if (enableClassicLlmUsageContainer && !empty(classicCosmosDbAccountName)) {
  name: 'classic-llm-usage-container'
  params: {
    cosmosDbAccountName: classicCosmosDbAccountName
    databaseName: classicCosmosDbDatabaseName
    throughput: classicLlmUsageContainerThroughput
  }
}

// =====================================================================
//    OUTPUTS
// =====================================================================

@description('Name of the updated APIM instance')
output apimName string = apimService.name

@description('Gateway URL of the APIM instance')
output apimGatewayUrl string = apimService.properties.gatewayUrl
