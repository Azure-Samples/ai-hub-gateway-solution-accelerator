using '../../main.bicep'

// ============================================================================
// Healthcare Chatbot Use Case - Onboarding Parameters
// ============================================================================
// This use case demonstrates onboarding a healthcare chatbot that uses:
// - Azure OpenAI for conversational AI
// - Document Intelligence for medical document processing
// - Content Safety for ensuring safe and compliant responses
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
  resourceGroupName: 'rg-healthcare-chatbot'              // Replace with your Key Vault resource group
  name: 'kv-healthcare-chatbot'                           // Replace with your Key Vault name
}

// Whether to store secrets in Key Vault (true) or output them directly (false)
param useTargetAzureKeyVault = true

// Use case identification for naming and organization
param useCase = {
  businessUnit: 'Healthcare'      // Your business unit or department
  useCaseName: 'PatientAssistant' // Descriptive name for this use case
  environment: 'DEV'              // Environment (DEV, TEST, PROD, etc.)
}

// Mapping of service codes to their API names in APIM
// These API names must already exist in your APIM instance
param apiNameMapping = {
  OAI: [
    'azure-openai-api', 'universal-llm-api'
  ]
  DOC: [
    'document-intelligence-api'
  ]
}

// Services required for this use case
param services = [
  {
    code: 'OAI'
    endpointSecretName: 'OPENAI-ENDPOINT'
    apiKeySecretName: 'OPENAI-API-KEY'
    policyXml: loadTextContent('policy.xml')
  }
  {
    code: 'DOC'
    endpointSecretName: 'DOCINTELL-ENDPOINT'
    apiKeySecretName: 'DOCINTELL-API-KEY'
    policyXml: '' // Uses default policy
  }
]

// Optional: Product terms of service
param productTerms = 'This service is for healthcare professionals only. All usage must comply with HIPAA regulations and organizational policies.'
