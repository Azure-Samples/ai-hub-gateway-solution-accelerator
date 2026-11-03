/*
 * @module llm-policy-fragments
 * @description Generates APIM policy fragments with backend pool configurations
 * 
 * This module creates policy fragments that contain the dynamically generated
 * backend pool configurations based on the LLM backend setup. These fragments
 * are used by the Universal LLM API policy to route requests appropriately.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('Policy fragment configuration from backend pools module')
param policyFragmentConfig object

@description('User-assigned managed identity client ID for authentication')
param managedIdentityClientId string

@description('LLM backend configuration with model metadata for available models response')
param llmBackendConfig array = []

@description('AWS access key ID for Amazon Bedrock authentication (required when using aws-bedrock backends)')
@secure()
param awsAccessKey string = 'NA'

@description('AWS secret access key for Amazon Bedrock authentication (required when using aws-bedrock backends)')
@secure()
param awsSecretKey string = 'NA'

@description('AWS region for Amazon Bedrock (e.g., us-east-1)')
param awsRegion string = 'NA'

@description('Model alias definitions for grouping models under a single alias name')
param modelAliases array = []

@description('Key Vault name for storing backend credentials (reserved for future use)')
#disable-next-line no-unused-params
param keyVaultName string = ''

// --- Backend contract reporting inputs (surfaced by the Release Version API GET /version/backend-contract) ---

@description('APIM target coordinates reported in the backend contract. Defaults to this module deployment scope and service name.')
param apimTarget object = {
  subscriptionId: subscription().subscriptionId
  resourceGroupName: resourceGroup().name
  name: apimServiceName
}

@description('Whether the backend circuit breaker is enabled (reported in the backend contract).')
param configureCircuitBreaker bool = true

@description('Default circuit breaker settings reported in the backend contract.')
param circuitBreakerDefaults object = {
  failureCount: 3
  failureInterval: 'PT5M'
  tripDuration: 'PT1M'
  acceptRetryAfter: true
  errorReasons: [ 'Server errors' ]
  statusCodeRanges: [
    { min: 429, max: 429 }
    { min: 500, max: 503 }
  ]
}

@description('Whether backend-pool session affinity is enabled (reported in the backend contract).')
param configureSessionAffinity bool = true

@description('Default session affinity settings reported in the backend contract.')
param sessionAffinityDefaults object = {
  cookieName: 'ai-gateway-affinity'
  source: 'Cookie'
}

// ------------------
//    VARIABLES
// ------------------

// Combine backend pools and direct backends for unified routing
var allPools = union(policyFragmentConfig.backendPools, policyFragmentConfig.directBackends)

// Generate C# code for each backend pool with unique variable names. The
// `authConfigNamedValue` field is informational only — the actual auth
// header is configured natively on the APIM Backend resource (see
// `credentials.header` in `llm-backends.bicep`), so the runtime policy
// never has to resolve a named-value-key string back to its secret.
var backendPoolsArray = [for (pool, index) in allPools: replace(replace(replace(replace(replace(replace('// Pool: POOLNAME (Type: POOLTYPE, Auth: AUTHTYPE)\nvar pool_INDEX = new JObject()\n{\n    { "poolName", "POOLNAME" },\n    { "poolType", "POOLTYPE" },\n    { "authType", "AUTHTYPE" },\n    { "authConfigNamedValue", "AUTHCONFIGNAMEDVALUE" },\n    { "supportedModels", new JArray(MODELS) }\n};\nbackendPools.Add(pool_INDEX);', 'POOLNAME', pool.poolName), 'POOLTYPE', pool.poolType), 'AUTHTYPE', pool.?authType ?? ''), 'AUTHCONFIGNAMEDVALUE', pool.?authConfigNamedValue ?? ''), 'INDEX', string(index)), 'MODELS', join(map(pool.supportedModels, (model) => '"${model}"'), ', '))]

var backendPoolsBaseCode = join(backendPoolsArray, '\n')

// ============================================================================
// MODEL ALIASES — virtual backend pools
// ============================================================================
// Each alias becomes a "virtual pool" entry inside the `backendPools` JArray
// consumed by `set-target-backend-pool`. Members carry the **resolved**
// poolName / poolType / authType / authConfigNamedValue at deploy time so
// the runtime can fall back across providers (and across api surfaces) on
// 429/5xx without re-walking the model→pool map.
//
// Shape rendered into the JArray (per alias):
//   {
//     "poolName": "alias:<aliasName>",
//     "poolType": "alias",
//     "isAlias":  true,
//     "aliasName": "<aliasName>",
//     "strategy": "priority" | "weighted",
//     "supportedModels": ["<aliasName>"],   // so the existing model→pool match path
//                                            // also locates the alias entry.
//     "members": [
//       {
//         "model":  "<real-model-name>",
//         "weight": <int>,                   // 1 for priority strategy; configured weight for weighted
//         "pools":  [
//           { "poolName": "...", "poolType": "...", "authType": "...", "authConfigNamedValue": "..." },
//           ...                                // multiple entries when the same model is hosted by
//                                              // both a native pool (e.g. `gemini`) and an OpenAI-compat
//                                              // pool (e.g. `gemini-openai`). Runtime picks the first one
//                                              // whose poolType matches the inbound api-type's
//                                              // compatible-pool-types filter.
//         ]
//       }
//     ]
//   }
// ============================================================================

// JObject literal (string) for ONE underlying pool that hosts a given alias member model.
// Indexed by [aliasIndex][memberIndex] = comma-separated list of JObject literals.
// Bicep does not allow nested `for` inside a variable declaration, so the inner per-model
// iteration uses `map(...)` (a function call) instead of a nested for-comprehension.
var aliasMemberPoolsLiterals = [for aIdx in range(0, length(modelAliases)): map(
  modelAliases[aIdx].models,
  model => join(map(filter(allPools, pool => contains(pool.supportedModels, model)), p =>
    'new JObject() { { "poolName", "${p.poolName}" }, { "poolType", "${p.poolType}" }, { "authType", "${p.?authType ?? ''}" }, { "authConfigNamedValue", "${p.?authConfigNamedValue ?? ''}" } }'
  ), ', ')
)]

// `aliasMembers_<aIdx>.Add(...)` statements — one per member.
var aliasMemberAddCodes = [for aIdx in range(0, length(modelAliases)): join(
  map(range(0, length(modelAliases[aIdx].models)), mIdx =>
    'aliasMembers_${aIdx}.Add(new JObject() { { "model", "${modelAliases[aIdx].models[mIdx]}" }, { "weight", ${contains(modelAliases[aIdx], 'weights') ? modelAliases[aIdx].weights[mIdx] : 1} }, { "pools", new JArray() { ${aliasMemberPoolsLiterals[aIdx][mIdx]} } } });'
  ),
  '\n'
)]

// Per-alias C# block that builds the alias virtual pool and pushes it onto `backendPools`.
// Note: the for-expression body must stay on a single line — Bicep does not allow a newline
// between the `:` and a string-literal body.
var aliasPoolBlocks = [for i in range(0, length(modelAliases)): '// Alias pool: ${modelAliases[i].name} (strategy: ${modelAliases[i].?strategy ?? 'priority'})\nvar aliasMembers_${i} = new JArray();\n${aliasMemberAddCodes[i]}\nvar aliasPool_${i} = new JObject()\n{\n    { "poolName", "alias:${modelAliases[i].name}" },\n    { "poolType", "alias" },\n    { "isAlias", true },\n    { "aliasName", "${modelAliases[i].name}" },\n    { "strategy", "${modelAliases[i].?strategy ?? 'priority'}" },\n    { "supportedModels", new JArray("${modelAliases[i].name}") },\n    { "members", aliasMembers_${i} }\n};\nbackendPools.Add(aliasPool_${i});']

var aliasPoolsCode = empty(modelAliases) ? '' : join(aliasPoolBlocks, '\n\n')

var backendPoolsCode = empty(aliasPoolsCode) ? backendPoolsBaseCode : '${backendPoolsBaseCode}\n\n// ===== Model alias virtual pools (resolve to underlying real-model pools at runtime) =====\n${aliasPoolsCode}'

// Load policy fragment templates
var setBackendPoolsFragmentTemplate = loadTextContent('./policies/frag-set-backend-pools.xml')
var setBackendAuthorizationFragmentXml = loadTextContent('./policies/frag-set-backend-authorization.xml')
var setTargetBackendPoolFragmentXml = loadTextContent('./policies/frag-set-target-backend-pool.xml')
var setLlmRequestedModelFragmentXml = loadTextContent('./policies/frag-set-llm-requested-model.xml')
var setLlmUsageFragmentXml = loadTextContent('./policies/frag-set-llm-usage.xml')
var getAvailableModelsFragmentTemplate = loadTextContent('./policies/frag-get-available-models.xml')

// Inject generated backend pools code into template
var updatedSetBackendPoolsFragmentXml = replace(setBackendPoolsFragmentTemplate, '//{backendPoolsCode}', backendPoolsCode)

// Generate model deployments code using reduce to flatten models from all backends
// Each backend generates code for all its supported models (now with per-model metadata)
// supportedModels is now an array of objects: { name, sku?, capacity?, modelFormat?, modelVersion?, retirementDate? }
var modelDeploymentsCodeResult = reduce(llmBackendConfig, { code: '', index: 0 }, (acc, config) => 
  reduce(config.supportedModels, acc, (modelAcc, model) => {
    code: '${modelAcc.code}\n// Model: ${model.name} from backend: ${config.backendId}\nvar deployment_${modelAcc.index} = new JObject()\n{\n    { "id", "${config.backendId}" },\n    { "type", "${config.backendType}" },\n    { "name", "${model.name}" },\n    { "sku", new JObject() { { "name", "${model.?sku ?? 'Standard'}" }, { "capacity", ${model.?capacity ?? 100} } } },\n    { "properties", new JObject() {\n        { "model", new JObject() { { "format", "${model.?modelFormat ?? 'OpenAI'}" }, { "name", "${model.name}" }, { "version", "${model.?modelVersion ?? '1'}" } } },\n        { "capabilities", new JObject() { ${config.backendType == 'azure-decision' ? '{ "systemone", "true" }' : '{ "chatCompletion", "true" }'}${contains(model.?operations ?? json('[]'), 'decisions') ? ', { "decisions", "true" }' : ''} } },\n        { "provisioningState", "Succeeded" }${!empty(model.?retirementDate) ? ',\n        { "retirementDate", "${model.retirementDate}" }' : ''}\n    }}\n};\nmodelDeployments.Add(deployment_${modelAcc.index});'
    index: modelAcc.index + 1
  })
)

var modelDeploymentsCode = modelDeploymentsCodeResult.code

// Generate JObject entries for each configured alias so they appear in the
// `get-available-models` (and `/deployments`) discovery responses alongside real
// model deployments. Each alias entry includes a `description` field under
// `capabilities` describing the underlying real models and routing strategy —
// clients can introspect what an alias maps to without leaving the gateway.
// `validate-model-access` (and the discovery-level `allowedModels` filter) match
// on `name`, so adding the alias here automatically extends RBAC to aliases.
var aliasModelsCsv = [for i in range(0, length(modelAliases)): join(modelAliases[i].models, ', ')]
var aliasStrategyText = [for i in range(0, length(modelAliases)): modelAliases[i].?strategy ?? 'priority']
var aliasWeightsSuffix = [for i in range(0, length(modelAliases)): contains(modelAliases[i], 'weights') ? '; weights: ${join(map(modelAliases[i].weights, w => string(w)), ', ')}' : '']
var aliasDescriptions = [for i in range(0, length(modelAliases)): 'Alias for: ${aliasModelsCsv[i]} (strategy: ${aliasStrategyText[i]}${aliasWeightsSuffix[i]})']
var aliasDeploymentEntries = [for i in range(0, length(modelAliases)): '\n// Alias: ${modelAliases[i].name}\nvar aliasDeployment_${i} = new JObject()\n{\n    { "id", "alias" },\n    { "type", "alias" },\n    { "name", "${modelAliases[i].name}" },\n    { "sku", new JObject() { { "name", "Standard" }, { "capacity", 100 } } },\n    { "properties", new JObject() {\n        { "model", new JObject() { { "format", "Alias" }, { "name", "${modelAliases[i].name}" }, { "version", "1" } } },\n        { "capabilities", new JObject() { { "chatCompletion", "true" }, { "description", "${aliasDescriptions[i]}" } } },\n        { "provisioningState", "Succeeded" }\n    }}\n};\nmodelDeployments.Add(aliasDeployment_${i});']
var aliasDeploymentsCode = join(aliasDeploymentEntries, '\n')

// Append alias entries after real model deployments — they share the same JArray
// and downstream filtering (allowedModels) treats them identically.
var modelDeploymentsCodeWithAliases = '${modelDeploymentsCode}${aliasDeploymentsCode}'

// Inject generated model deployments code into available models template
var updatedGetAvailableModelsFragmentXml = replace(getAvailableModelsFragmentTemplate, '//{modelDeploymentsCode}', modelDeploymentsCodeWithAliases)

// Generate metadata-config fragment for the Unified AI API
// Maps each model to its backend pool/direct backend + apiVersion + timeout + inferenceApiVersion
var metadataModelsResult = reduce(llmBackendConfig, { code: '', seenModels: [] }, (acc, config) =>
  reduce(config.supportedModels, acc, (modelAcc, model) => {
    code: contains(modelAcc.seenModels, model.name) ? modelAcc.code : '${modelAcc.code}${length(modelAcc.seenModels) > 0 ? ',\n' : ''}\t\t\t\'${model.name}\': {\n\t\t\t\t\'backend\': \'${reduce(allPools, '', (poolAcc, pool) => contains(pool.supportedModels, model.name) ? pool.poolName : poolAcc)}\',\n\t\t\t\t\'apiVersion\': \'${model.?apiVersion ?? '2024-02-15-preview'}\',\n\t\t\t\t\'timeout\': ${model.?timeout ?? 120}${!empty(model.?inferenceApiVersion) ? ',\n\t\t\t\t\'inferenceApiVersion\': \'${model.inferenceApiVersion}\'' : ''}${!empty(model.?modelPath) ? ',\n\t\t\t\t\'modelPath\': \'${model.modelPath}\'' : ''}\n\t\t\t}'
    seenModels: contains(modelAcc.seenModels, model.name) ? modelAcc.seenModels : union(modelAcc.seenModels, [model.name])
  })
)
var metadataModelsCode = metadataModelsResult.code
var metadataConfigFragmentXml = loadTextContent('./policies/frag-metadata-config.xml')
var updatedMetadataConfigStep1 = replace(metadataConfigFragmentXml, '//{modelsConfigCode}', metadataModelsCode)

// Generate model aliases code from modelAliases parameter.
// Used inside the metadata-config JSON (parsed and cached by central-cache-manager).
// Built with map+join to keep string interpolation simple (Bicep limits on nested `${}`).
var modelAliasesEntries = map(modelAliases, alias => '\t\t\t\'${alias.name}\': {\n\t\t\t\t\'models\': [${join(map(alias.models, m => '\'${m}\''), ', ')}],\n\t\t\t\t\'strategy\': \'${alias.?strategy ?? 'priority'}\'${contains(alias, 'weights') ? ',\n\t\t\t\t\'weights\': WEIGHTS_PLACEHOLDER' : ''}\n\t\t\t}')
var aliasWeightArrays = map(modelAliases, alias => contains(alias, 'weights') ? '[${join(map(alias.weights, w => string(w)), ', ')}]' : '')
var modelAliasesEntriesWithWeights = [for i in range(0, length(modelAliases)): replace(modelAliasesEntries[i], 'WEIGHTS_PLACEHOLDER', aliasWeightArrays[i])]
var modelAliasesCode = join(modelAliasesEntriesWithWeights, ',\n')
var updatedMetadataConfigFragmentXml = replace(updatedMetadataConfigStep1, '//{modelAliasesCode}', modelAliasesCode)

// Generate inline-aliases C# code for the resolve-model-alias fragment.
// As of the alias-as-virtual-pool refactor, alias **resolution** (alias-name → real
// model + target pool) is performed by `frag-set-target-backend-pool.xml` directly
// against the alias entries injected into the `backendPools` JArray above. The
// resolve-model-alias fragment is now only responsible for the JSON body / URL
// rewrite that runs AFTER set-target-backend-pool has set `is-alias`,
// `original-model-alias`, and the resolved `requestedModel`. The inline-aliases
// JObject is therefore no longer needed at runtime — we still emit a stub so the
// fragment template stays valid.
var inlineAliasesCode = ''
var resolveModelAliasFragmentTemplate = loadTextContent('./policies/frag-resolve-model-alias.xml')
var updatedResolveModelAliasFragmentXml = replace(resolveModelAliasFragmentTemplate, '//{inlineAliasesCode}', inlineAliasesCode)

// Backend Contract fragment
// Returns the active LLM backend routing contract as static JSON. The contract is a detailed
// projection of the effective onboarding configuration: APIM target, full llmBackendConfig
// (with per-model metadata), circuit breaker configuration, session affinity configuration,
// model aliases, and the derived backend pools. Refreshed on every LLM onboarding run so the
// Release Version API `GET /version/backend-contract` operation reflects the live configuration.
// Any `authConfig.secretValue` is redacted; endpoints and Key Vault references are preserved.
var releaseManifest = loadJsonContent('../../../../release.json')
var backendContractVersion = releaseManifest['backend-contract-version']
var masterVersion = releaseManifest['master-version']

// Redact inline secret values from each backend's authConfig (Key Vault refs / named values are kept).
var backendContractBackends = map(llmBackendConfig, backend => contains(backend, 'authConfig')
  ? union(backend, {
      authConfig: contains(backend.authConfig, 'secretValue')
        ? union(backend.authConfig, { secretValue: '***redacted***' })
        : backend.authConfig
    })
  : backend)

// Full, detailed backend contract object. string() serializes it to compact valid JSON.
var backendContractObject = {
  masterVersion: masterVersion
  backendContractVersion: backendContractVersion
  apim: apimTarget
  circuitBreaker: {
    enabled: configureCircuitBreaker
    defaults: circuitBreakerDefaults
  }
  sessionAffinity: {
    enabled: configureSessionAffinity
    defaults: sessionAffinityDefaults
  }
  modelAliases: modelAliases
  backends: backendContractBackends
  pools: allPools
}

var backendContractJson = string(backendContractObject)

// XML-escape the JSON so it embeds safely as literal text inside the fragment's <set-body>.
// (& must be escaped first.) APIM un-escapes the entities when returning the body.
var backendContractJsonEscaped = replace(replace(replace(backendContractJson, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')

var backendContractFragmentXml = replace(loadTextContent('./policies/frag-backend-contract.xml'), '//{backendContractJson}', backendContractJsonEscaped)

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

// Named value for managed identity client ID
resource uamiClientIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'uami-client-id'
  parent: apimService
  properties: {
    displayName: 'uami-client-id'
    value: managedIdentityClientId
    secret: false
  }
}

// Named values for AWS Bedrock authentication
// Always created with safe defaults so the policy fragment compiles even when no aws-bedrock backends are configured.
// When aws-bedrock backends are present, the caller must supply real credentials via parameters.
resource awsAccessKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'aws-access-key'
  parent: apimService
  properties: {
    displayName: 'aws-access-key'
    value: !empty(awsAccessKey) ? awsAccessKey : 'NOT_CONFIGURED'
    secret: true
  }
}

resource awsSecretKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'aws-secret-key'
  parent: apimService
  properties: {
    displayName: 'aws-secret-key'
    value: !empty(awsSecretKey) ? awsSecretKey : 'NOT_CONFIGURED'
    secret: true
  }
}

resource awsRegionNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: 'aws-region'
  parent: apimService
  properties: {
    displayName: 'aws-region'
    value: !empty(awsRegion) ? awsRegion : 'NOT_CONFIGURED'
    secret: false
  }
}

// Named value for Anthropic API version header (anthropic-version) is created
// by the `llm-backends` module (Step 1 in main.bicep) so that the api-key-anthropic
// backend's `credentials.header` reference to `{{anthropic-version}}` resolves at
// backend create time. Do not re-declare it here.

// Per-backend named values for `credentials.header` are now created by the
// `llm-backends` module (which runs as Step 1 in main.bicep) so they exist
// before the backend resources reference them. This module no longer needs to
// declare them.

// Policy Fragment: Set Backend Pools
resource setBackendPoolsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-pools'
  parent: apimService
  properties: {
    description: 'Dynamically generated backend pool configurations for LLM routing'
    format: 'rawxml'
    value: updatedSetBackendPoolsFragmentXml
  }
}

// Policy Fragment: Set Backend Authorization
resource setBackendAuthorizationFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-authorization'
  parent: apimService
  dependsOn: [
    awsAccessKeyNamedValue
    awsSecretKeyNamedValue
    awsRegionNamedValue
  ]
  properties: {
    description: 'Authentication and routing configuration for different LLM backend types'
    format: 'rawxml'
    value: setBackendAuthorizationFragmentXml
  }
}

// Policy Fragment: Set Target Backend Pool
resource setTargetBackendPoolFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-target-backend-pool'
  parent: apimService
  properties: {
    description: 'Determines the target backend pool for LLM requests'
    format: 'rawxml'
    value: setTargetBackendPoolFragmentXml
  }
}

// Policy Fragment: Set LLM Requested Model
resource setLlmRequestedModelFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-llm-requested-model'
  parent: apimService
  properties: {
    description: 'Extracts the requested model from deployment-id (Azure OpenAI) or request body (Inference)'
    format: 'rawxml'
    value: setLlmRequestedModelFragmentXml
  }
}

// Policy Fragment: Set LLM Usage
resource setLlmUsageFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-llm-usage'
  parent: apimService
  properties: {
    description: 'Collects usage metrics for LLM requests'
    format: 'rawxml'
    value: setLlmUsageFragmentXml
  }
}

// Policy Fragment: Get Available Models
resource getAvailableModelsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'get-available-models'
  parent: apimService
  properties: {
    description: 'Returns a JSON response listing all available model deployments with their capabilities'
    format: 'rawxml'
    value: updatedGetAvailableModelsFragmentXml
  }
}

// Policy Fragment: Validate Model Access
// Restricts access to specific models based on the allowedModels variable
resource validateModelAccessFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'validate-model-access'
  parent: apimService
  properties: {
    description: 'Validates that the requested model is in the allowed models list for the product'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-validate-model-access.xml')
  }
}

// Policy Fragment: Responses API ID Security (inbound)
// Enforces per-subscription ownership of OpenAI Responses API response_id values
// and hydrates routing for GET/DELETE operations on /responses/{id}.
resource responsesIdSecurityFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'responses-id-security'
  parent: apimService
  properties: {
    description: 'Inbound: validates response_id ownership and hydrates routing for /responses operations'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-responses-id-security.xml')
  }
}

// Policy Fragment: Responses API ID Cache Store (outbound)
// Records response_id → "<subscriptionId>|<requestedModel>|<userId>" in APIM cache
// after a successful POST /responses, enabling subsequent ownership checks.
resource responsesIdCacheStoreFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'responses-id-cache-store'
  parent: apimService
  properties: {
    description: 'Outbound: caches response_id ownership for newly created Responses API objects'
    format: 'rawxml'
    value: loadTextContent('./policies/frag-responses-id-cache-store.xml')
  }
}

// Policy Fragment: Metadata Configuration
// Provides centralized configuration for the Unified AI API with dynamically generated model mappings
resource metadataConfigFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'metadata-config'
  parent: apimService
  properties: {
    description: 'Dynamically generated metadata configuration for Unified AI API routing'
    format: 'rawxml'
    value: updatedMetadataConfigFragmentXml
  }
}

// Policy Fragment: Resolve Model Alias
// Resolves a client-facing alias (e.g. "adv-gpt") to a real underlying model based on
// 'priority' or 'weighted' strategy. Shared by Azure OpenAI, Universal LLM, and Unified AI APIs.
// Inline alias map is generated at deploy time from the modelAliases parameter; falls back
// to config-model-aliases (cached metadata-config) when invoked from the Unified AI policy.
resource resolveModelAliasFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'resolve-model-alias'
  parent: apimService
  properties: {
    description: 'Resolves model alias names to actual underlying models with priority/weighted strategy'
    format: 'rawxml'
    value: updatedResolveModelAliasFragmentXml
  }
}

// Policy Fragment: Backend Contract
// Returns the active LLM backend routing contract (version + pools + backends) as JSON.
// Consumed by the Release Version API `GET /version/backend-contract` operation. Refreshed on
// every LLM onboarding run so the endpoint always reflects the live routing contract.
resource backendContractFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'backend-contract'
  parent: apimService
  properties: {
    description: 'Returns the active LLM backend routing contract (version, pools, backends) deployed on this gateway'
    format: 'rawxml'
    value: backendContractFragmentXml
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Name of the set-backend-pools fragment')
output setBackendPoolsFragmentName string = setBackendPoolsFragment.name

@description('Name of the set-backend-authorization fragment')
output setBackendAuthorizationFragmentName string = setBackendAuthorizationFragment.name

@description('Name of the set-target-backend-pool fragment')
output setTargetBackendPoolFragmentName string = setTargetBackendPoolFragment.name

@description('Name of the get-available-models fragment')
output getAvailableModelsFragmentName string = getAvailableModelsFragment.name

@description('Name of the validate-model-access fragment')
output validateModelAccessFragmentName string = validateModelAccessFragment.name

@description('Name of the metadata-config fragment')
output metadataConfigFragmentName string = metadataConfigFragment.name

@description('Name of the resolve-model-alias fragment')
output resolveModelAliasFragmentName string = resolveModelAliasFragment.name

@description('Name of the responses-id-security fragment')
output responsesIdSecurityFragmentName string = responsesIdSecurityFragment.name

@description('Name of the responses-id-cache-store fragment')
output responsesIdCacheStoreFragmentName string = responsesIdCacheStoreFragment.name

@description('Name of the backend-contract fragment')
output backendContractFragmentName string = backendContractFragment.name

@description('Generated backend pools configuration code')
output backendPoolsCode string = backendPoolsCode
