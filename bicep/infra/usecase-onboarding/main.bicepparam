using 'main.bicep'

// ============================================================================
// AI Hub Gateway - Use Case Onboarding Parameters
// ============================================================================
// This parameter file is used to onboard a new use case to the AI Hub Gateway.
// It creates APIM products, subscriptions, and optionally stores credentials
// in Azure Key Vault.
//
// REQUIRED PARAMETERS: apim, keyVault, useCase, apiNameMapping, services
// OPTIONAL PARAMETERS: useTargetAzureKeyVault, productTerms
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
//   subscriptionId: 'd2e7f84f-2790-4baa-9520-59ae8169ed0d'
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
// REQUIRED: Azure Key Vault Configuration
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
//   subscriptionId: 'd2e7f84f-2790-4baa-9520-59ae8169ed0d'
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
param useTargetAzureKeyVault = true

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
// REQUIRED: API Name Mapping
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
//   OAI: [
//     'azure-openai-service-api',
//     'universal-llm-api'
//   ]
//   DOC: [
//     'document-intelligence-api'
//   ]
//   CS: [
//     'content-safety-api'
//   ]
// }
//
// Note: API names are case-sensitive and must match exactly with APIM.
// ============================================================================
param apiNameMapping = {
  OAI: [
    'azure-openai-service-api' // Replace with your actual API ID(s) on APIM
  ]
  // Add more service codes and API mappings as needed
  // DOC: ['document-intelligence-api']
  // CS: ['content-safety-api']
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
//   Examples: 'OAI', 'DOC', 'CS', 'CV'
//
// - endpointSecretName: Name for the endpoint URL secret in Key Vault
//   Convention: <SERVICE>_ENDPOINT or <SERVICE>-ENDPOINT
//   Examples: 'OPENAI_ENDPOINT', 'DOCINTELL_ENDPOINT'
//   Note: Underscores will be replaced with hyphens in Key Vault
//
// - apiKeySecretName: Name for the API key secret in Key Vault
//   Convention: <SERVICE>_API_KEY or <SERVICE>-API-KEY
//   Examples: 'OPENAI_API_KEY', 'DOCINTELL_API_KEY'
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
//   code: 'OAI'
//   endpointSecretName: 'OPENAI_ENDPOINT'
//   apiKeySecretName: 'OPENAI_API_KEY'
//   policyXml: '<policies>...</policies>'
// }
//
// Example loading policy from file:
// {
//   code: 'OAI'
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
// Full example:
// param services = [
//   {
//     code: 'OAI'
//     endpointSecretName: 'OPENAI_ENDPOINT'
//     apiKeySecretName: 'OPENAI_API_KEY'
//     policyXml: loadTextContent('policies/openai-throttling.xml')
//   }
//   {
//     code: 'DOC'
//     endpointSecretName: 'DOCINTELL_ENDPOINT'
//     apiKeySecretName: 'DOCINTELL_API_KEY'
//     policyXml: '' // Uses default policy
//   }
//   {
//     code: 'CS'
//     endpointSecretName: 'CONTENTSAFETY_ENDPOINT'
//     apiKeySecretName: 'CONTENTSAFETY_API_KEY'
//   }
// ]
// ============================================================================
param services = [
  {
    code: 'OAI'                              // Service code (must exist in apiNameMapping)
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
// DEPLOYMENT NOTES
// ============================================================================
// Prerequisites:
// 1. APIM instance must exist with APIs already configured
// 2. Key Vault must exist (if useTargetAzureKeyVault=true)
// 3. Deploying identity must have permissions:
//    - APIM: Contributor or API Management Service Contributor
//    - Key Vault: Key Vault Secrets Officer (if using Key Vault)
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
//
// Security considerations:
// - When useTargetAzureKeyVault=false, API keys appear in deployment outputs
// - Always secure deployment outputs in CI/CD pipelines
// - Rotate subscription keys periodically
// - Use managed identities when possible for Key Vault access
// ============================================================================
