/*
===========================================
Foundry APIM Connection Module
===========================================

Creates an APIM connection in an existing Azure AI Foundry project.
This enables Foundry agents to access AI models through the APIM gateway.

AUTHENTICATION MODES (authType):
- 'ProjectManagedIdentity' (DEFAULT): the Foundry project's managed identity acquires an Entra ID
  token for `managedIdentityAudience` (default https://cognitiveservices.azure.com) and sends it as
  a Bearer token. The APIM subscription key is ALSO sent as the `api-key` custom header so the
  gateway can validate the APIM subscription (api-key) AND the JWT (Bearer). The access contract's
  product policy must enable JWT validation for this audience (jwtRequired + jwtAudience).
- 'ApiKey' (backward compatible): only the APIM subscription key is used, stored in `credentials.key`
  and sent via the default `api-key` header. Reproduces the original behavior exactly.

REFERENCES:
- https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/ai-gateway
  (see "Configure managed identity authentication for API Management")
*/

// ============================================================================
// REQUIRED PARAMETERS
// ============================================================================

@description('Name of the AI Foundry account (Cognitive Services account)')
param aiFoundryAccountName string

@description('Name of the AI Foundry project')
param aiFoundryProjectName string

@description('Name for the APIM connection')
param connectionName string

@description('Target URL for the APIM connection (gateway + API path)')
param targetUrl string

@description('APIM subscription key for API access')
@secure()
param apimSubscriptionKey string

// ============================================================================
// OPTIONAL PARAMETERS
// ============================================================================

@allowed(['ApiKey', 'ProjectManagedIdentity'])
@description('Authentication type. "ProjectManagedIdentity" (default in the access contract) uses the Foundry project managed identity for a Bearer token AND sends the APIM subscription key as the "api-key" custom header. "ApiKey" stores the subscription key in credentials.key (original behavior).')
param authType string = 'ApiKey'

@description('Audience (resource) the Foundry project managed identity requests a token for when authType is ProjectManagedIdentity. The access contract product policy must validate the JWT against this same value.')
param managedIdentityAudience string = 'https://cognitiveservices.azure.com'

@allowed(['ApiManagement', 'ModelGateway'])
@description('Foundry connection category. Use ModelGateway for portal-compatible model gateway connections.')
param connectionCategory string = 'ApiManagement'

@description('Share connection to all project users')
param isSharedToAll bool = false

@allowed(['true', 'false'])
@description('Whether deployment name is in URL path (true) or request body (false)')
param deploymentInPath string = 'false'

@description('API version for inference calls. Leave empty for APIM defaults.')
param inferenceAPIVersion string = ''

@description('API version for deployment discovery calls. Leave empty for APIM defaults.')
param deploymentAPIVersion string = ''

@description('Static model list (optional - use this OR dynamic discovery)')
param staticModels array = []

@description('Endpoint for listing models. Leave empty for APIM defaults.')
param listModelsEndpoint string = ''

@description('Endpoint for getting model details. Leave empty for APIM defaults.')
param getModelEndpoint string = ''

@allowed(['', 'AzureOpenAI', 'OpenAI'])
@description('Provider format for model discovery responses')
param deploymentProvider string = ''

@description('Custom headers to include in requests')
param customHeaders object = {}

@description('Custom authentication configuration')
param authConfig object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// When using the project managed identity, the APIM subscription key is delivered as the
// "api-key" custom header (in addition to the Bearer token), so it is merged into customHeaders.
var isManagedIdentity = authType == 'ProjectManagedIdentity'
var effectiveCustomHeaders = isManagedIdentity ? union(customHeaders, { 'api-key': apimSubscriptionKey }) : customHeaders

// Validation flags
var hasStaticModels = length(staticModels) > 0
var hasCustomDiscovery = !empty(listModelsEndpoint) && !empty(getModelEndpoint) && !empty(deploymentProvider)
var hasCustomHeaders = !empty(effectiveCustomHeaders)
var hasAuthConfig = !empty(authConfig)
var hasInferenceAPIVersion = !empty(inferenceAPIVersion)
var hasDeploymentAPIVersion = !empty(deploymentAPIVersion)

// ============================================================================
// METADATA CONSTRUCTION
// ============================================================================

var baseMetadata = {
  deploymentInPath: deploymentInPath
}

var inferenceVersionMetadata = hasInferenceAPIVersion ? {
  inferenceAPIVersion: inferenceAPIVersion
} : {}

var deploymentVersionMetadata = hasDeploymentAPIVersion ? {
  deploymentAPIVersion: deploymentAPIVersion
} : {}

var modelDiscoveryMetadata = hasCustomDiscovery ? {
  modelDiscovery: string({
    listModelsEndpoint: listModelsEndpoint
    getModelEndpoint: getModelEndpoint
    deploymentProvider: deploymentProvider
  })
} : {}

var staticModelsMetadata = hasStaticModels && !hasCustomDiscovery ? {
  models: string(staticModels)
} : {}

// Always emit customHeaders (portal requires this field even if empty)
var customHeadersMetadata = {
  customHeaders: hasCustomHeaders ? string(effectiveCustomHeaders) : '{}'
}

var authConfigMetadata = hasAuthConfig ? {
  authConfig: string(authConfig)
} : {}

// Managed identity connections record the token audience so the project MI requests the right resource.
var audienceMetadata = isManagedIdentity ? {
  audience: managedIdentityAudience
} : {}

var metadata = union(
  baseMetadata,
  inferenceVersionMetadata,
  deploymentVersionMetadata,
  modelDiscoveryMetadata,
  staticModelsMetadata,
  customHeadersMetadata,
  authConfigMetadata,
  audienceMetadata
)

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2026-03-01' existing = {
  name: aiFoundryAccountName
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2026-03-01' existing = {
  name: aiFoundryProjectName
  parent: aiFoundry
}

// ============================================================================
// APIM CONNECTION RESOURCE
// ============================================================================

resource apimConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01' = {
  name: connectionName
  parent: aiProject
  properties: {
    category: connectionCategory
    target: targetUrl
    // 'ProjectManagedIdentity' is a valid runtime value for BYO AI gateway connections but is not yet
    // in the ARM type definition, so any() is used to bypass the stale type check.
    authType: any(authType)
    audience: isManagedIdentity ? managedIdentityAudience : ''
    isSharedToAll: isSharedToAll
    // ApiKey: subscription key stored as the credential. ProjectManagedIdentity: no stored key
    // (the project MI provides a Bearer token); the subscription key travels as the api-key header.
    credentials: isManagedIdentity ? {} : {
      key: apimSubscriptionKey
    }
    metadata: metadata
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Name of the created connection')
output connectionName string = apimConnection.name

@description('ID of the created connection')
output connectionId string = apimConnection.id

@description('Target URL for the APIM connection')
output targetUrl string = targetUrl

@description('Authentication type used for the connection')
output authType string = authType

@description('Managed identity token audience (empty when authType is ApiKey)')
output managedIdentityAudience string = isManagedIdentity ? managedIdentityAudience : ''
