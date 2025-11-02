/**
 * @module llm-backends
 * @description Creates APIM backends for LLM services (AI Foundry, Azure OpenAI, and other providers)
 * 
 * This module dynamically creates backend resources based on the provided configuration array.
 * Each backend represents an LLM endpoint that can serve one or more model deployments.
 * 
 * Supported backend types:
 * - ai-foundry: Azure AI Foundry projects with model deployments
 * - azure-openai: Azure OpenAI Service endpoints
 * - external: Other LLM providers (OpenAI, Anthropic, etc.)
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
      authScheme: 'managedIdentity'
      supportedModels: ['gpt-4', 'gpt-4-turbo']
      priority: 1
      weight: 100
    }
    {
      backendId: 'azure-openai-eastus'
      backendType: 'azure-openai'
      endpoint: 'https://my-openai-eastus.openai.azure.com'
      authScheme: 'managedIdentity'
      supportedModels: ['gpt-35-turbo', 'text-embedding-ada-002']
      priority: 1
      weight: 100
    }
  ]
})
param llmBackendConfig array

@description('Whether to configure circuit breaker for backends')
param configureCircuitBreaker bool = true

@description('Tags to apply to resources')
param tags object = {}

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

/**
 * Create individual backends for each LLM endpoint
 * Each backend represents a single LLM service endpoint with its configuration
 */
resource llmBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for (config, i) in llmBackendConfig: {
  name: config.backendId
  parent: apimService
  properties: {
    description: 'LLM Backend: ${config.backendType} - ${config.backendId} - Supports models: ${config.supportedModels}'
    url: config.endpoint
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
          name: '${config.backendId}-breaker-rule'
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    } : null
    
    // Authentication configuration based on auth scheme
    credentials: config.authScheme == 'managedIdentity' ? {
      header: {
        'x-ms-client-id': [
          managedIdentityClientId
        ]
      }
    } : {}
    
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
  resourceId: llmBackends[i].id
  supportedModels: config.supportedModels
  priority: config.?priority ?? 1
  weight: config.?weight ?? 100
}]
