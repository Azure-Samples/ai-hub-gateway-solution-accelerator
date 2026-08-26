using 'main.bicep'

// ============================================================================
// Citadel Access Contracts - Use Case Onboarding Parameters
// ============================================================================
// This parameter file is used to onboard a new use case to the AI Governance Hub.
// It creates APIM products, subscriptions, and optionally stores credentials
// in Azure Key Vault and/or creates Azure AI Foundry connections.
//
// REQUIRED PARAMETERS: apim, keyVault, useCase, apiNameMapping, services
// OPTIONAL PARAMETERS: useTargetAzureKeyVault, productTerms, useTargetFoundry, foundry, foundryConfig
// ============================================================================

// ============================================================================
// REQUIRED: API Management (APIM) Configuration
// ============================================================================
// Specifies the target APIM instance where the use case APIs will be published.
// This APIM instance should already exist and have the necessary APIs configured.
//
// Properties:
// - subscriptionId: Azure subscription ID where APIM is deployed
// - resourceGroupName: Resource group containing the APIM instance
// - name: Name of the APIM service instance
//
// Example:
// param apim = {
//   subscriptionId: 'd287984f-2790-4baa-9520-59ae8169ed0d'
//   resourceGroupName: 'rg-ai-hub-gateway-prod'
//   name: 'apim-aihub-prod-001'
// }
// ============================================================================
param apim = {
  subscriptionId: '00000000-0000-0000-0000-000000000000' // Replace with your subscription ID
  resourceGroupName: 'rg-apim-resource-group'             // Replace with your APIM resource group
  name: 'apim-instance-name'                              // Replace with your APIM name
}

// ============================================================================
// OPTIONAL: Use Azure Key Vault for Secret Storage
// ============================================================================
// Determines whether to store endpoint URLs and API keys in Azure Key Vault.
//
// - true (default): Secrets are stored in the specified Key Vault
//   - More secure, recommended for production
//   - Applications retrieve secrets from Key Vault at runtime
//   - Secret names are normalized (underscores replaced with hyphens)
//
// - false: Secrets are output directly from the deployment
//   - Useful for testing or CI/CD scenarios
//   - Secrets appear in deployment outputs (handle with care!)
//   - Consumer is responsible for securing the output values
//
// Default: true
// ============================================================================
param useTargetAzureKeyVault = false

// ============================================================================
// OPTIONAL: Azure Key Vault Configuration (required if useTargetAzureKeyVault=true)
// ============================================================================
// Specifies the target Key Vault for storing endpoint URLs and API keys.
// This Key Vault will store the generated APIM gateway endpoints and 
// subscription keys for secure access by applications.
//
// Properties:
// - subscriptionId: Azure subscription ID where Key Vault is deployed
// - resourceGroupName: Resource group containing the Key Vault
// - name: Name of the Key Vault instance
//
// Note: This parameter is required even if useTargetAzureKeyVault is set to false.
// When useTargetAzureKeyVault=false, secrets will be output directly instead
// of being stored in Key Vault.
//
// Example:
// param keyVault = {
//   subscriptionId: 'd287984f-2790-4baa-9520-59ae8169ed0d'
//   resourceGroupName: 'rg-ai-hub-gateway-prod'
//   name: 'kv-aihub-prod-001'
// }
// ============================================================================
param keyVault = {
  subscriptionId: '00000000-0000-0000-0000-000000000000' // Replace with your subscription ID
  resourceGroupName: 'rg-keyvault-resource-group'         // Replace with your Key Vault resource group
  name: 'kv-instance-name'                                // Replace with your Key Vault name
}

// ============================================================================
// REQUIRED: Use Case Identification
// ============================================================================
// Defines the use case context used in naming conventions and organization.
// The naming pattern follows: <code>-<businessUnit>-<useCaseName>-<environment>
//
// Properties:
// - businessUnit: Your business unit, department, or team name
//   Examples: 'Finance', 'Healthcare', 'Sales', 'Engineering'
//
// - useCaseName: Descriptive name for this specific use case
//   Examples: 'CustomerSupport', 'DocumentProcessing', 'PatientAssistant'
//   Keep it concise and avoid spaces (use PascalCase or kebab-case)
//
// - environment: Deployment environment identifier
//   Examples: 'DEV', 'TEST', 'UAT', 'STAGING', 'PROD'
//
// These values are used to construct:
// - Product IDs: OAI-Finance-CustomerSupport-PROD
// - Subscription names: OAI-Finance-CustomerSupport-PROD-SUB-01
// - Display names and descriptions
//
// Example:
// param useCase = {
//   businessUnit: 'Finance'
//   useCaseName: 'CustomerSupport'
//   environment: 'PROD'
// }
// ============================================================================
param useCase = {
  businessUnit: 'YourBusinessUnit'   // Replace with your business unit
  useCaseName: 'YourUseCaseName'     // Replace with your use case name
  environment: 'DEV'                 // Replace with your environment (DEV, TEST, PROD, etc.)
}

// ============================================================================
// REQUIRED: API Name Mapping (bundled APIs)
// ============================================================================
// Maps service codes to their corresponding API names in APIM.
// These APIs must already exist in your APIM instance before deployment.
//
// Structure: { <ServiceCode>: [<API-Name-1>, <API-Name-2>, ...] }
//
// Common service codes:
// - OAI: Azure OpenAI Service APIs
// - DOC: Document Intelligence APIs
// - CS: Content Safety APIs
// - CV: Computer Vision APIs
// - SEARCH: Azure AI Search APIs
//
// Each service code can map to one or more APIM API names. This allows:
// 1. Multiple APIs per service (e.g., different OpenAI deployments)
// 2. Grouping related APIs under a single product
// 3. Version management (e.g., 'api-v1', 'api-v2')
//
// Example:
// param apiNameMapping = {
//   LLM: [
//     'azure-openai-api',
//     'universal-llm-api'
//   ]
//   DOC: [
//     'document-intelligence-api'
//   ]
//   SRCH: [
//     'azure-ai-search-index-api'
//   ]
// }
//
// Note: API names are case-sensitive and must match exactly with APIM.
// ============================================================================
param apiNameMapping = {
  LLM: ['universal-llm-api', 'azure-openai-api']
  DOC: ['document-intelligence-api', 'document-intelligence-api-legacy']
  SRCH: ['azure-ai-search-index-api']
  OAIRT: ['openai-realtime-ws-api']
  // Add more service codes and API mappings as needed
}

// ============================================================================
// REQUIRED: Services Configuration
// ============================================================================
// Defines the AI services required for this use case. Each service creates:
// - An APIM product
// - A subscription with primary and secondary keys
// - Key Vault secrets (if useTargetAzureKeyVault=true)
//
// Each service object requires:
// - code: Service identifier (must match a key in apiNameMapping)
//   Examples: 'LLM', 'DOC', 'SRCH', 'CV'
//
// - endpointSecretName: Name for the endpoint URL secret in Key Vault
//   Convention: <SERVICE>_ENDPOINT or <SERVICE>-ENDPOINT
//   Examples: 'OPENAI_ENDPOINT', 'DOCINTELL_ENDPOINT'
//   Note: Underscores will be replaced with hyphens in Key Vault
//
// - apiKeySecretName: Name for the API key secret in Key Vault
//   Convention: <SERVICE>_API_KEY or <SERVICE>-API-KEY
//   Examples: 'LLM_API_KEY', 'DOCINTELL_API_KEY'
//   Note: Underscores will be replaced with hyphens in Key Vault
//
// Optional properties:
// - policyXml: Custom APIM policy XML for this product
//   - Can be inline XML string or loaded via loadTextContent()
//   - If not provided or empty, default product policy is used
//   - Use for service-specific rate limiting, transformation, etc.
//
// Example with inline policy:
// {
//   code: 'LLM'
//   endpointSecretName: 'OPENAI_ENDPOINT'
//   apiKeySecretName: 'OPENAI_API_KEY'
//   policyXml: '<policies>...</policies>'
// }
//
// Example loading policy from file:
// {
//   code: 'LLM'
//   endpointSecretName: 'OPENAI_ENDPOINT'
//   apiKeySecretName: 'OPENAI_API_KEY'
//   policyXml: loadTextContent('policies/openai-custom-policy.xml')
// }
//
// Example using default policy (empty or omitted policyXml):
// {
//   code: 'DOC'
//   endpointSecretName: 'DOCINTELL_ENDPOINT'
//   apiKeySecretName: 'DOCINTELL_API_KEY'
//   policyXml: '' // Uses default policy from ./policies/default-ai-product-policy.xml
// }
//
// ----------------------------------------------------------------------------
// MULTI-ASSET CONTRACTS (LLM + Tools/MCP + Agents/A2A in ONE product)
// ----------------------------------------------------------------------------
// A single product shares ONE api-key (apiKeySecretName) across every granted
// asset. Because each asset (LLM inference API, published Tool, published Agent)
// has its own gateway path, publish an endpoint secret PER asset with either:
//
//   * assetEndpoints — explicit list; empty endpointSecretName auto-generates
//     <code>-<businessUnit>-<useCase>-<env>-<apiName>-endpoint
//   * publishAllAssetEndpoints: true — auto-publish an endpoint secret for EVERY
//     API in apiNameMapping[code] (names overridable via assetEndpoints)
//
// foundryApiName selects which granted API is the LLM endpoint wired to the
// Foundry connection (Foundry supports the LLM endpoint only). It defaults to the
// first known LLM API, else the first API.
//
// Example (MULTI product granting LLM + a Tool + an Agent, KV endpoint per asset):
// param apiNameMapping = { MULTI: ['universal-llm-api', 'weather-tool', 'hr-chat-agent'] }
// param services = [
//   {
//     code: 'MULTI'
//     apiKeySecretName: 'HR_CHATAGENT_KEY'          // one shared key for the contract
//     foundryApiName: 'universal-llm-api'           // Foundry connects to the LLM endpoint
//     assetEndpoints: [
//       { apiName: 'universal-llm-api', endpointSecretName: 'HR_CHATAGENT_LLM_ENDPOINT' }
//       { apiName: 'weather-tool' }                 // auto-named endpoint secret
//       { apiName: 'hr-chat-agent' }                // auto-named endpoint secret
//     ]
//     policyXml: loadTextContent('ai-product-policy.xml')
//   }
// ]
//
// ============================================================================
param services = [
  {
    code: 'LLM'                              // Service code (must exist in apiNameMapping)
    endpointSecretName: 'OPENAI_ENDPOINT'    // Key Vault secret name for endpoint URL
    apiKeySecretName: 'OPENAI_API_KEY'       // Key Vault secret name for API key
    policyXml: ''                            // Optional: Custom policy XML (empty = use default)
  }
  // Add more services as needed
  // {
  //   code: 'DOC'
  //   endpointSecretName: 'DOCINTELL_ENDPOINT'
  //   apiKeySecretName: 'DOCINTELL_API_KEY'
  //   policyXml: loadTextContent('policies/doc-intel-policy.xml')
  // }
]

// ============================================================================
// OPTIONAL: Product Terms of Service
// ============================================================================
// Defines the terms and conditions shown to API subscribers.
// This text is displayed when users subscribe to the APIM product.
//
// Use this to:
// - Define acceptable use policies
// - Specify compliance requirements (HIPAA, GDPR, etc.)
// - Set usage limitations or expectations
// - Include legal disclaimers
// - Reference organizational policies
//
// Examples:
// - 'This API is for internal use only. All usage is subject to company IT policies.'
// - 'By using this service, you agree to handle all data in compliance with GDPR regulations.'
// - 'This service is for healthcare professionals only. All usage must comply with HIPAA regulations.'
//
// Default: '' (empty string - no terms displayed)
// ============================================================================
param productTerms = ''

// ============================================================================
// OPTIONAL: Azure AI Foundry Integration
// ============================================================================
// Enable this section to automatically create Azure AI Foundry connections
// for each service being onboarded. This allows Foundry agents to access
// AI models through the APIM gateway using the created subscription keys.
//
// When to use:
// - Building AI agents in Azure AI Foundry that need APIM gateway access
// - Implementing the "Bring Your Own AI Gateway" pattern
// - Centralizing AI model access through governance policies
//
// Requirements:
// - Azure AI Foundry account and project must already exist
// - Deploying identity must have Contributor role on the Foundry resource group
// ============================================================================

// Set to true to create Foundry APIM connections for each service
param useTargetFoundry = false

// Azure AI Foundry resource coordinates (required if useTargetFoundry=true)
// Example:
// param foundry = {
//   subscriptionId: 'd287984f-2790-4baa-9520-59ae8169ed0d'
//   resourceGroupName: 'rg-ai-foundry-prod'
//   accountName: 'my-foundry-account'
//   projectName: 'my-ai-project'
// }
param foundry = {
  subscriptionId: '00000000-0000-0000-0000-000000000000' // Replace with Foundry subscription ID
  resourceGroupName: 'rg-foundry-resource-group'         // Replace with Foundry resource group
  accountName: 'foundry-account-name'                    // Replace with AI Foundry account name
  projectName: 'foundry-project-name'                    // Replace with AI Foundry project name
}

// ============================================================================
// OPTIONAL: Foundry Connection Configuration
// ============================================================================
// Advanced configuration for Foundry APIM connections. These settings control
// how Foundry agents interact with the APIM gateway.
//
// Configuration Options:
// - connectionNamePrefix: Custom prefix for connection names
//   Default: Uses '<businessUnit>-<useCaseName>-<environment>' from useCase
//   Final name: '<prefix>-<serviceCode>' (e.g., 'HR-ChatBot-DEV-LLM')
//
// - authType: Connection authentication mode
//   'ProjectManagedIdentity' (default): Foundry project managed identity presents an Entra ID Bearer
//     token (audience = managedIdentityAudience) AND the subscription key is sent as the 'api-key'
//     custom header. The product policy MUST validate the JWT for that audience (see the policy guide).
//   'ApiKey': subscription key only, stored in credentials.key (original behavior, fully backward compatible)
//
// - managedIdentityAudience: Audience the project MI requests a token for (only for ProjectManagedIdentity)
//   Default: 'https://cognitiveservices.azure.com' — must match the JWT audience validated by the policy
//
// - deploymentInPath: Controls how model names are passed in requests
//   'true': Model name in URL path (/deployments/{model}/chat/completions)
//   'false': Model name in request body ({"model": "{model}"})
//
// - isSharedToAll: Share connection with all project users
//   true: All users in the Foundry project can use this connection
//   false: Only the connection creator can use it initially
//
// - inferenceAPIVersion: API version for chat/embeddings calls
//   Leave empty to use APIM defaults (recommended)
//
// - deploymentAPIVersion: API version for model discovery calls
//   Leave empty to use APIM defaults (recommended)
//
// - staticModels: Define a fixed list of models (skips dynamic discovery)
//   Format: [{ name: 'gpt-4o', properties: { model: { name: 'gpt-4o', version: '2024-11-20', format: 'OpenAI' } } }]
//
// - listModelsEndpoint: Custom endpoint for listing available models
//   Default (empty): Uses APIM's /deployments endpoint
//
// - getModelEndpoint: Custom endpoint for getting model details
//   Default (empty): Uses APIM's /deployments/{deployment-id} endpoint
//
// - deploymentProvider: Format for model discovery responses ('AzureOpenAI' or 'OpenAI')
//   Default (empty): Uses AzureOpenAI format
//
// - customHeaders: Additional headers to include in all requests
//   Useful for routing policies or custom metadata
//   Example: { 'X-Environment': 'production', 'X-Route-Policy': 'premium' }
//
// - authConfig: Custom authentication header configuration
//   Default: Uses 'api-key' header with the subscription key
//   Example for Bearer: { type: 'api_key', name: 'Authorization', format: 'Bearer {api_key}' }
// ============================================================================
param foundryConfig = {
  connectionNamePrefix: ''           // Empty = use useCase naming convention
  authType: 'ProjectManagedIdentity' // Default: MI Bearer token (JWT) + api-key custom header. 'ApiKey' = subscription key only
  managedIdentityAudience: 'https://cognitiveservices.azure.com' // MI token audience; product policy must validate this JWT
  deploymentInPath: 'false'          // Model name in request body (false for Azure OpenAI /deployments/[deployment-id])
  isSharedToAll: false               // Share with all project users
  inferenceAPIVersion: ''            // Empty = APIM defaults
  deploymentAPIVersion: ''           // Empty = APIM defaults
  staticModels: []                   // Empty = use dynamic discovery
  listModelsEndpoint: ''             // Empty = APIM defaults (/deployments)
  getModelEndpoint: ''               // Empty = APIM defaults (/deployments/{deployment-id})
  deploymentProvider: ''             // Empty = AzureOpenAI format
  customHeaders: {}                  // No custom headers (api-key added automatically for ProjectManagedIdentity)
  authConfig: {}                     // Default api-key header is used
}

// ============================================================================
// OPTIONAL: Business Continuity & Resiliency (multi-instance)
// ============================================================================
// All parameters below are OPTIONAL and default to empty. Leaving them unset
// keeps the exact existing behavior (single primary APIM gateway + primary
// Key Vault + primary Foundry). Populate them to mirror THIS single contract
// across additional APIM gateways / Key Vaults / Foundry instances so the
// contract keeps working if the primary instance/region becomes unavailable.
//
// Key guarantee: the subscription key generated by the PRIMARY gateway is
// reused (as an explicit key) on every additional gateway, so clients use the
// SAME api-key regardless of which gateway serves the request.
//
// For full guidance see: ./access-contract-resiliency-guide.md
// ----------------------------------------------------------------------------

// Global endpoint fronting all gateways (e.g. Azure Front Door / Traffic Manager).
// When set, this URL is used as the endpoint base stored in ALL Key Vault secrets
// and Foundry connections (primary + additional). Empty = use primary APIM gateway.
param globalGatewayUrl = ''

// Additional APIM gateways to mirror this contract into (deployed AFTER primary,
// reusing the primary subscription key). Each item: { subscriptionId, resourceGroupName, name }.
// Example:
// param additionalApimGateways = [
//   {
//     subscriptionId: '00000000-0000-0000-0000-000000000000'
//     resourceGroupName: 'rg-apim-secondary'
//     name: 'apim-instance-secondary'
//   }
// ]
param additionalApimGateways = []

// Additional Key Vaults to also store the endpoint + shared key.
// endpointSource selects which endpoint URL is stored:
//   'global'        -> globalGatewayUrl
//   'primary'       -> primary APIM gateway URL
//   'secondary:<n>' -> additionalApimGateways[n] gateway URL (0-based index)
//   ''  (default)   -> globalGatewayUrl if set, else primary gateway URL
// Example:
// param additionalKeyVaults = [
//   {
//     subscriptionId: '00000000-0000-0000-0000-000000000000'
//     resourceGroupName: 'rg-keyvault-secondary'
//     name: 'kv-secondary'
//     endpointSource: 'secondary:0'
//   }
// ]
param additionalKeyVaults = []

// Additional Foundry instances to also create APIM connections in.
// endpointSource behaves the same as additionalKeyVaults above.
// Example:
// param additionalFoundries = [
//   {
//     subscriptionId: '00000000-0000-0000-0000-000000000000'
//     resourceGroupName: 'rg-foundry-secondary'
//     accountName: 'foundry-account-secondary'
//     projectName: 'foundry-project-secondary'
//     endpointSource: ''
//   }
// ]
param additionalFoundries = []

// ============================================================================
// OPTIONAL: Zero-downtime Key Rotation
// ============================================================================
// All parameters below are OPTIONAL. Defaults (usePrimaryKey=true,
// keyRotationEnabled=false) reproduce the existing behavior exactly (primary
// key active, nothing regenerated). Use the 3-step flow to rotate a key with
// no downtime: (1) switch consumers to the standby key, (2) confirm they are
// healthy, (3) regenerate the now non-active key.
//
// For full guidance see: ./access-contract-key-rotation-guide.md
// ----------------------------------------------------------------------------

// Which subscription key is ACTIVE (handed to consumers via Key Vault / Foundry
// / additional gateways). true = primary (default), false = secondary.
// Set to false as step 1 of rotation to move all services onto the secondary
// key while the primary remains valid (no downtime).
param usePrimaryKey = true

// When true, the NON-active key is regenerated (its old value is invalidated).
// Enable this ONLY as the final rotation step, after consumers are confirmed
// healthy on the active key.
param keyRotationEnabled = false

// Optional explicit rotation key for deterministic re-runs. Empty (default) =
// a fresh 64-char key is auto-generated on each rotation deployment.
param rotationKeyOverride = ''

// ============================================================================
// DEPLOYMENT NOTES
// ============================================================================
// Prerequisites:
// 1. APIM instance must exist with APIs already configured
// 2. Key Vault must exist (if useTargetAzureKeyVault=true)
// 3. AI Foundry account and project must exist (if useTargetFoundry=true)
// 4. Deploying identity must have permissions:
//    - APIM: Contributor or API Management Service Contributor
//    - Key Vault: Key Vault Secrets Officer (if using Key Vault)
//    - Foundry Resource Group: Contributor (if using Foundry)
//
// Deployment command:
// az deployment sub create \
//   --name <deployment-name> \
//   --location <region> \
//   --template-file main.bicep \
//   --parameters main.bicepparam
//
// Outputs:
// - apimGatewayUrl: Base URL of the APIM gateway
// - products: Array of created products with IDs and display names
// - subscriptions: Array of subscriptions with Key Vault secret references
// - endpoints: Array of endpoint URLs and API keys (only if useTargetAzureKeyVault=false)
// - useFoundry: Whether Foundry connections were created
// - foundryConnections: Array of Foundry connection details (if useTargetFoundry=true)
//
// Security considerations:
// - When useTargetAzureKeyVault=false, API keys appear in deployment outputs
// - Always secure deployment outputs in CI/CD pipelines
// - Rotate subscription keys periodically
// - Use managed identities when possible for Key Vault access
// - Foundry connections store API keys securely in the connection config
// ============================================================================
