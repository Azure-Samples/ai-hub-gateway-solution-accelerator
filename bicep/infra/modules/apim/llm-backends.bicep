/**
 * @module llm-backends
 * @description Creates APIM backends for LLM services (AI Foundry, Azure OpenAI, Amazon Bedrock, and other providers)
 * 
 * This module dynamically creates backend resources based on the provided configuration array.
 * Each backend represents an LLM endpoint that can serve one or more model deployments.
 * 
 * Supported backend types:
 * - ai-foundry: Azure AI Foundry projects with model deployments
 * - azure-openai: Azure OpenAI Service endpoints
 * - aws-bedrock: Amazon Bedrock native (Converse + InvokeModel) endpoints. Default auth is AWS SigV4;
 *                set `authType: 'api-key-bearer'` to use a long-lived Bedrock API key (Bearer token).
 * - aws-bedrock-mantle: Amazon Bedrock OpenAI-compatible endpoint with Bearer token
 * - gemini: GCP Gemini native endpoints (/v1beta/models/...:generateContent) with x-goog-api-key
 * - gemini-openai: GCP Gemini OpenAI-compatible endpoints (/v1beta/openai/...) with Bearer token
 * - anthropic: Anthropic Claude direct endpoints (native Messages API) with x-api-key + anthropic-version
 * - external: Other LLM providers (OpenAI, etc.)
 * - azure-decision: Microsoft Decision-1 SystemOne on a Foundry services root
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('User-assigned managed identity client ID for authentication')
param managedIdentityClientId string

@description('Configuration array for LLM backends')
@metadata({
  example: [
    {
      backendId: 'ai-foundry-gpt4'
      backendType: 'ai-foundry'
      endpoint: 'https://my-foundry-project.eastus.inference.ml.azure.com'
      authType: 'managed-identity'
      supportedModels: [
        { name: 'gpt-4', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '0613' }
        { name: 'gpt-4-turbo', sku: 'GlobalStandard', capacity: 100, modelFormat: 'OpenAI', modelVersion: '1106' }
      ]
      priority: 1
      weight: 100
    }
    {
      backendId: 'azure-openai-eastus'
      backendType: 'azure-openai'
      endpoint: 'https://my-openai-eastus.openai.azure.com'
      authType: 'managed-identity'
      supportedModels: [
        { name: 'gpt-35-turbo', sku: 'Standard', capacity: 120, modelFormat: 'OpenAI', modelVersion: '0613' }
        { name: 'text-embedding-ada-002', sku: 'Standard', capacity: 120, modelFormat: 'OpenAI', modelVersion: '2' }
      ]
      priority: 1
      weight: 100
    }
  ]
})
param llmBackendConfig array

@description('Whether to configure circuit breaker for backends')
param configureCircuitBreaker bool = true

@description('Tags to apply to resources')
// Retained for interface compatibility with callers; APIM backends do not support tags.
#disable-next-line no-unused-params
param tags object = {}

@description('Anthropic API version sent in the anthropic-version header for Anthropic backends (Messages API). Stored as the `anthropic-version` named value referenced by the backend credentials.header.')
param anthropicVersion string = '2023-06-01'

// ------------------
//    VARIABLES
// ------------------

/**
 * Resolve effective authType + named-value key per backend up front so the
 * resource body stays readable. The same precedence used by the policy
 * fragments (and the day-2 llm-backend-onboarding module) applies here:
 *   explicit `authType` > backendType-derived default > `managed-identity`
 *
 * The legacy `authScheme` field is no longer read directly — `ai-foundry` and
 * `azure-openai` backends resolve to `managed-identity` via the default below,
 * which preserves the previous behaviour for the auto-generated config.
 */
var enrichedBackendConfig = [for config in llmBackendConfig: {
  raw: config
  effectiveAuthType: config.?authType ?? (config.backendType == 'aws-bedrock' ? 'aws-sigv4' : config.backendType == 'external' ? 'none' : config.backendType == 'aws-bedrock-mantle' || config.backendType == 'gemini-openai' ? 'api-key-bearer' : config.backendType == 'gemini' ? 'api-key-gemini' : config.backendType == 'anthropic' ? 'api-key-anthropic' : 'managed-identity')
  authNamedValueKey: config.?authConfig.?namedValueKey ?? ''
}]

// Deduplicate per-backend authConfigs by namedValueKey so we create exactly one
// APIM named value per unique key. Multiple backends MAY share the same key.
// ARM rejects duplicate resource declarations, so we collapse to a unique map
// and re-emit as an array.
var backendAuthConfigs = filter(llmBackendConfig, config => !empty(config.?authConfig.?namedValueKey ?? ''))
var uniqueAuthConfigsMap = reduce(backendAuthConfigs, {}, (acc, config) => contains(acc, config.authConfig.namedValueKey)
  ? acc
  : union(acc, { '${config.authConfig.namedValueKey}': config.authConfig }))
var uniqueAuthConfigs = map(items(uniqueAuthConfigsMap), item => item.value)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

// Per-backend named values for the secrets referenced from `credentials.header`.
// MUST be created BEFORE the `llmBackends` resource because APIM validates the
// `{{namedValueKey}}` tokens at backend create/update time and rejects the
// request with `Property '<key>' not found.` if the named value doesn't exist
// yet. When `keyVaultSecretUri` is supplied, the named value is created as a
// Key Vault reference (rotatable, auditable); otherwise the inline `secretValue`
// is stored directly (testing-only path).
resource backendApiKeyNamedValues 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = [for cfg in uniqueAuthConfigs: {
  name: cfg.namedValueKey
  parent: apimService
  properties: {
    displayName: cfg.namedValueKey
    secret: true
    keyVault: !empty(cfg.?keyVaultSecretUri ?? '') ? {
      secretIdentifier: cfg.keyVaultSecretUri
    } : null
    value: empty(cfg.?keyVaultSecretUri ?? '') ? (cfg.?secretValue ?? 'NOT_CONFIGURED') : null
  }
}]

// `anthropic-version` named value for Anthropic backends. Always created with a
// sensible default so the resource is unconditional and the dependsOn below
// stays static (avoids `if(...)` on a non-collection symbolic resource).
resource anthropicVersionNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'anthropic-version'
  parent: apimService
  properties: {
    displayName: 'anthropic-version'
    value: !empty(anthropicVersion) ? anthropicVersion : '2023-06-01'
    secret: false
  }
}

/**
 * Create individual backends for each LLM endpoint
 * Each backend represents a single LLM service endpoint with its configuration.
 *
 * API-key auth is configured **natively on the backend resource** via
 * `credentials.header`. APIM substitutes `{{namedValueKey}}` tokens when the
 * backend is created/updated, so the secret never appears in policy expressions.
 *
 * IMPORTANT: APIM only substitutes a `{{namedValueKey}}` token when the *entire*
 * header value is the bare token (not inside a concatenated string), so the
 * stored secret must contain the **complete header value**:
 *   api-key-bearer    → Authorization: <secret>   ← secret = "Bearer sk-abc..."
 *   api-key-header    → api-key: <secret>          ← secret = "sk-abc..."
 *   api-key-gemini    → x-goog-api-key: <secret>   ← secret = "sk-abc..."
 *   api-key-anthropic → x-api-key: <secret>        ← secret = "sk-abc..."
 */
resource llmBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for (entry, i) in enrichedBackendConfig: {
  name: entry.raw.backendId
  parent: apimService
  // Named-value references inside `credentials.header` are string templates, so
  // Bicep can't infer the dependency on `backendApiKeyNamedValues`. Declare it
  // explicitly to avoid the "Property '<key>' not found." validation error.
  dependsOn: [
    backendApiKeyNamedValues
    anthropicVersionNamedValue
  ]
  properties: {
    description: 'LLM Backend: ${entry.raw.backendType} - ${entry.raw.backendId} - Supports models: ${join(map(entry.raw.supportedModels, m => m.name), ', ')}'
    url: entry.raw.endpoint
    protocol: 'http'

    // Circuit breaker configuration for resilience
    circuitBreaker: configureCircuitBreaker ? {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT5M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
              {
                min: 500
                max: 503
              }
            ]
          }
          name: '${entry.raw.backendId}-breaker-rule'
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    } : null

    // Backend authorization configuration
    // managed-identity: native APIM backend auth via credentials.managedIdentity
    // api-key-*: native static header resolved from the named value at create time
    // aws-sigv4 / none: no native credential — handled by policy fragments / no auth
    credentials: {
      #disable-next-line BCP037
      managedIdentity: entry.effectiveAuthType == 'managed-identity' ? {
        clientId: managedIdentityClientId
        resource: 'https://cognitiveservices.azure.com'
      } : null
      // Static headers — APIM resolves `{{namedValueKey}}` to the named value's
      // secret (or Key Vault reference) at create/update time.
      header: entry.effectiveAuthType == 'managed-identity' ? {
        'x-ms-client-id': [managedIdentityClientId]
      } : entry.effectiveAuthType == 'api-key-bearer' ? {
        Authorization: ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-header' ? {
        'api-key': ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-gemini' ? {
        'x-goog-api-key': ['{{${entry.authNamedValueKey}}}']
      } : entry.effectiveAuthType == 'api-key-anthropic' ? {
        'x-api-key': ['{{${entry.authNamedValueKey}}}']
        'anthropic-version': ['{{anthropic-version}}']
      } : {}
    }

    // TLS configuration for secure communication
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

// ------------------
//    OUTPUTS
// ------------------

@description('Array of created backend IDs')
output backendIds array = [for (config, i) in llmBackendConfig: llmBackends[i].name]

@description('Array of backend configurations with resource IDs')
output backendDetails array = [for (config, i) in llmBackendConfig: {
  backendId: config.backendId
  backendType: config.backendType
  authType: config.?authType ?? ''
  authConfigNamedValue: config.?authConfig.?namedValueKey ?? ''
  resourceId: llmBackends[i].id
  supportedModels: config.supportedModels
  priority: config.?priority ?? 1
  weight: config.?weight ?? 100
}]
