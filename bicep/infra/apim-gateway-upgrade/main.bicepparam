using './main.bicep'

// =====================================================================
//    CORE — Identify the existing APIM instance and managed identity
// =====================================================================

param apimServiceName = '<your-apim-service-name>'
param managedIdentityName = '<your-managed-identity-name>'

// =====================================================================
//    POLICY FRAGMENTS
// =====================================================================

param updatePolicyFragments = true
param enablePIIAnonymization = true
param enableAIModelInference = true

// =====================================================================
//    NAMED VALUES (PII, Content Safety)
// =====================================================================

param updateNamedValues = true
param aiLanguageServiceUrl = ''
param contentSafetyServiceUrl = ''

// =====================================================================
//    JWT AUTHENTICATION NAMED VALUES
//    Required when enableJwtAuth = true
// =====================================================================

param updateJwtNamedValues = true
param enableJwtAuth = false
param jwtTenantId = ''
param jwtAppRegistrationId = ''

// =====================================================================
//    CLASSIC AI HUB GATEWAY (pre Citadel Governance Hub) — RESERVED
//    ONLY for classic AI Hub Gateway installs provisioned before the
//    Citadel Governance Hub release. Disabled by default.
//    When enabled, provisions an llm-usage-container (/productName) in an
//    EXISTING Cosmos DB account (in the SAME resource group as the APIM
//    instance) referenced by its account name.
// =====================================================================

param enableClassicLlmUsageContainer = false
param classicCosmosDbAccountName = ''
param classicCosmosDbDatabaseName = 'ai-usage-db'
param classicLlmUsageContainerThroughput = 400

// =====================================================================
//    LLM BACKENDS, POOLS & DYNAMIC POLICY FRAGMENTS
//    Define all LLM backends and their supported models.
//    Uncomment and configure the array below to match your environment.
// =====================================================================

param updateLLMBackends = true
param updateLLMBackendPools = true
param updateLLMPolicyFragments = true

// Anthropic API version sent in the anthropic-version header for `anthropic` backends.
param anthropicVersion = '2023-06-01'

param llmBackendConfig = [
  // Example reflecting the current AI Foundry-based implementation (two backends, each
  // exposing multiple model deployments). Tip: copy the live value from your environment
  // with `azd env get-value LLM_BACKEND_CONFIG` and paste it here (converted to Bicep object syntax).
  //
  // Authentication: prefer `authType` over the legacy `authScheme`. When omitted, authType is
  // derived from backendType (ai-foundry/azure-openai → managed-identity), consistent with the
  // llm-backend-onboarding package. For api-key backends add an `authConfig` object, e.g.:
  //   authType: 'api-key-bearer'
  //   authConfig: { namedValueKey: 'my-provider-key', keyVaultSecretUri: 'https://kv.vault.azure.net/secrets/my-provider-key' }
  // {
  //   backendId: 'aif-REPLACE-0'
  //   backendType: 'ai-foundry'
  //   endpoint: 'https://aif-REPLACE-0.cognitiveservices.azure.com/'
  //   authType: 'managed-identity'
  //   priority: 1
  //   weight: 100
  //   supportedModels: [
  //     { name: 'gpt-4.1', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2025-04-14', apiVersion: '2025-04-01-preview', retirementDate: '2026-10-14', timeout: 180 }
  //     { name: 'DeepSeek-R1', sku: 'GlobalStandard', capacity: 1, modelFormat: 'DeepSeek', modelVersion: '1', inferenceApiVersion: '2024-05-01-preview', retirementDate: '2099-12-30' }
  //     { name: 'text-embedding-3-large', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '1', retirementDate: '2027-04-14' }
  //     { name: 'Mistral-Large-3', sku: 'GlobalStandard', capacity: 100, modelFormat: 'Mistral AI', modelVersion: '1', retirementDate: '2099-12-30' }
  //     { name: 'gpt-5.4-mini', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2026-03-17', retirementDate: '2026-09-30' }
  //     { name: 'Phi-4', sku: 'GlobalStandard', capacity: 1, modelFormat: 'Microsoft', modelVersion: '7', apiVersion: '2025-04-01-preview', retirementDate: '2099-10-14', timeout: 180 }
  //   ]
  // }
  // {
  //   backendId: 'aif-REPLACE-1'
  //   backendType: 'ai-foundry'
  //   endpoint: 'https://aif-REPLACE-1.cognitiveservices.azure.com/'
  //   authType: 'managed-identity'
  //   priority: 1
  //   weight: 100
  //   supportedModels: [
  //     { name: 'Phi-4', sku: 'GlobalStandard', capacity: 1, modelFormat: 'Microsoft', modelVersion: '7', apiVersion: '2025-04-01-preview', retirementDate: '2099-10-14', timeout: 180 }
  //     { name: 'gpt-5.4-mini', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2026-03-17', retirementDate: '2026-09-30' }
  //     { name: 'gpt-5.2', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '2025-12-11', retirementDate: '2027-02-05' }
  //     { name: 'DeepSeek-R1', sku: 'GlobalStandard', capacity: 1, modelFormat: 'DeepSeek', modelVersion: '1', inferenceApiVersion: '2024-05-01-preview', retirementDate: '2099-12-30' }
  //     { name: 'text-embedding-3-large', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '1', retirementDate: '2027-04-14' }
  //   ]
  // }
]

// =====================================================================
//    INFERENCE APIs — Universal LLM & Azure OpenAI
// =====================================================================

param updateUniversalLLMApi = true
param updateAzureOpenAIApi = true

// API path prefixes for legacy coexistence. Leave '' to deploy at /openai and /models.
// Set (e.g. 'v2') to deploy the new APIs at /v2/openai and /v2/models so legacy APIs can stay live.
param azureOpenAIApiPathPrefix = ''
param universalLLMApiPathPrefix = ''

// =====================================================================
//    UNIFIED AI WILDCARD API
// =====================================================================

param updateUnifiedAiApi = true
param enableUnifiedAiApi = true

// =====================================================================
//    OPENAI REALTIME WEBSOCKET API
// =====================================================================

param updateOpenAIRealtimeApi = false

// =====================================================================
//    REDIS CACHE & EMBEDDINGS BACKEND
//    Required when updateRedisCache or updateEmbeddingsBackend = true
// =====================================================================

param updateRedisCache = false
param enableRedisCache = false
param redisCacheConnectionString = ''

param updateEmbeddingsBackend = false
param enableEmbeddingsBackend = false
param embeddingsBackendUrl = ''

// =====================================================================
//    LOGGING / DIAGNOSTICS SETTINGS
//    Customize what is captured in Application Insights and Azure Monitor.
// =====================================================================

param updateAppInsightsDiagnostics = true

// Azure Monitor logger — for legacy installs that never provisioned it. Set deployAzureMonitorLogger
// = true to create the 'azuremonitor' logger, and provide an EXISTING Log Analytics workspace resource
// ID to wire APIM diagnostic settings to it (no workspace is provisioned).
param deployAzureMonitorLogger = false
param logAnalyticsWorkspaceResourceId = ''


param azureMonitorLogSettings = {
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
    requests:  { messages: 'all', maxSizeInBytes: 0 } // maxSizeInBytes is 262144 bytes (256 KB)
    responses: { messages: 'all', maxSizeInBytes: 0 } // maxSizeInBytes is 262144 bytes (256 KB)
  }
}

param appInsightsLogSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}
