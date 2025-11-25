using '../../main.bicep'

// ============================================================================
// Customer Support Agent Use Case - Onboarding Parameters
// ============================================================================
// This use case demonstrates onboarding a customer support agent that uses:
// - Azure OpenAI for conversational AI and sentiment analysis
// - Azure AI Search for knowledge base RAG (Retrieval Augmented Generation)
// - Multiple model support for different support tiers
// ============================================================================

// Target APIM instance where APIs are published
param apim = {
  subscriptionId: '00000000-0000-0000-0000-000000000000' // Replace with your subscription ID
  resourceGroupName: 'rg-apim-ai-gateway'                 // Replace with your APIM resource group
  name: 'apim-ai-gateway'                                 // Replace with your APIM name
}

// Target Key Vault for storing endpoint URLs and API keys
// Set useTargetAzureKeyVault to false if you don't want to use Key Vault
param keyVault = {
  subscriptionId: '00000000-0000-0000-0000-000000000000' // Replace with your subscription ID
  resourceGroupName: 'rg-customer-support'                // Replace with your Key Vault resource group
  name: 'kv-customer-support'                             // Replace with your Key Vault name
}

// Whether to store secrets in Key Vault (true) or output them directly (false)
param useTargetAzureKeyVault = true

// Use case identification for naming and organization
param useCase = {
  businessUnit: 'CustomerService' // Your business unit or department
  useCaseName: 'SupportAgent'     // Descriptive name for this use case
  environment: 'PROD'             // Environment (DEV, TEST, PROD, etc.)
}

// Mapping of service codes to their API names in APIM
// These API names must already exist in your APIM instance
param apiNameMapping = {
  OAI: [
    'azure-openai-service-api', 'universal-llm-api'
  ]
  SRCH: [
    'azure-ai-search-index-api'
  ]
}

// Services required for this use case
param services = [
  {
    code: 'OAI'
    endpointSecretName: 'SUPPORT-OPENAI-ENDPOINT'
    apiKeySecretName: 'SUPPORT-OPENAI-KEY'
    policyXml: loadTextContent('policy.xml')
  }
  {
    code: 'SRCH'
    endpointSecretName: 'SUPPORT-SEARCH-ENDPOINT'
    apiKeySecretName: 'SUPPORT-SEARCH-KEY'
    policyXml: '' // Uses default policy
  }
]

// Optional: Product terms of service
param productTerms = 'This service is for internal customer support operations only. Usage is monitored and must comply with company data privacy policies.'
