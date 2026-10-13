/**
 * @module unified-ai-api
 * @description Creates the Unified AI Wildcard API in APIM with deployment listing operations.
 *
 * This module registers a wildcard API (/*) that routes all AI requests through
 * dynamic path-based routing using policy fragments. It includes:
 * - Wildcard catch-all operations for all HTTP methods
 * - /deployments and /deployments/{deployment-id} GET operations for model discovery
 * - Operation-level policies for deployment listing
 * - API-level policy for request routing orchestration
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apiManagementName string

@description('Id of the APIM Logger for Azure Monitor diagnostics')
param apimLoggerId string = ''

@description('Whether to enable the Unified AI API (feature flag)')
param enabled bool = true

@description('Azure Monitor diagnostic log settings')
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

@description('Header name callers use to present the subscription (API) key. Accepts the LLM-style "api-key" (default) or the APIM-native "Ocp-Apim-Subscription-Key".')
@allowed([
  'api-key'
  'Ocp-Apim-Subscription-Key'
])
param subscriptionKeyName string = 'api-key'

// Query-string key name mirrors the header: APIM-native header uses the 'subscription-key' query param,
// the LLM-style 'api-key' header uses an 'api-key' query param.
var subscriptionKeyQueryName = subscriptionKeyName == 'Ocp-Apim-Subscription-Key' ? 'subscription-key' : 'api-key'

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apiManagementName
}

// Unified AI Wildcard API
resource unifiedAiApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = if (enabled) {
  name: 'unified-ai-api'
  parent: apimService
  properties: {
    apiType: 'http'
    description: 'Unified AI Gateway API - Routes requests to multiple AI model providers (Azure OpenAI, AI Foundry, Gemini) using dynamic path-based routing with support for multiple API types.'
    displayName: 'Unified AI API'
    format: 'openapi+json'
    path: 'unified-ai'
    protocols: [
      'https'
    ]
    subscriptionKeyParameterNames: {
      header: subscriptionKeyName
      query: subscriptionKeyQueryName
    }
    subscriptionRequired: true
    type: 'http'
    value: string(loadJsonContent('./unified-ai-api/UnifiedAIWildcard.json'))
  }
}

// API-level policy (orchestration policy with all fragments)
resource unifiedAiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = if (enabled) {
  name: 'policy'
  parent: unifiedAiApi
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/unified-ai-api-policy.xml')
  }
}

// APIM Product for Unified AI API (subscription-based, API Key auth)
resource unifiedAiProduct 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = if (enabled) {
  name: 'unified-ai-product'
  parent: apimService
  properties: {
    displayName: 'Unified AI Gateway'
    description: 'Unified AI Gateway product - provides access to all AI model providers through a single wildcard endpoint.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 10
    state: 'published'
  }
}

// Associate API with product
// NOTE: The name is a string literal that matches the API name, so Bicep cannot infer a
// dependency on the API resource. Without an explicit dependsOn, ARM may attempt to create
// this product/API association before the 'unified-ai-api' API exists (since the product can
// be created independently), causing intermittent deployment failures. The explicit dependsOn
// guarantees the API is provisioned first.
resource unifiedAiProductApi 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = if (enabled) {
  name: 'unified-ai-api'
  parent: unifiedAiProduct
  dependsOn: [
    unifiedAiApi
  ]
}

// Product policy
resource unifiedAiProductPolicy 'Microsoft.ApiManagement/service/products/policies@2024-06-01-preview' = if (enabled) {
  name: 'policy'
  parent: unifiedAiProduct
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/unified-ai-product-subscription.xml')
  }
}

////// Deployment Listing Operations //////

// Reference the deployment operations from the OpenAPI spec
resource deploymentsOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = if (enabled) {
  name: 'deployments'
  parent: unifiedAiApi
}

resource deploymentByNameOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = if (enabled) {
  name: 'deployment-by-name'
  parent: unifiedAiApi
}

// Operation-level policy for listing all deployments
resource deploymentsOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (enabled) {
  name: 'policy'
  parent: deploymentsOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/unified-ai-api-deployments-policy.xml')
  }
}

// Operation-level policy for getting a specific deployment by name
resource deploymentByNameOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (enabled) {
  name: 'policy'
  parent: deploymentByNameOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('./policies/unified-ai-api-deployment-by-name-policy.xml')
  }
}

////// Diagnostics //////

resource apiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if (enabled && length(apimLoggerId) > 0) {
  parent: unifiedAiApi
  name: 'azuremonitor'
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: apimLoggerId
    sampling: {
      samplingType: 'fixed'
      percentage: json('100')
    }
    frontend: {
      request: {
        headers: azureMonitorLogSettings.frontend.request.headers
        body: {
          bytes: azureMonitorLogSettings.frontend.request.body.bytes
        }
      }
      response: {
        headers: azureMonitorLogSettings.frontend.response.headers
        body: {
          bytes: azureMonitorLogSettings.frontend.response.body.bytes
        }
      }
    }
    backend: {
      request: {
        headers: azureMonitorLogSettings.backend.request.headers
        body: {
          bytes: azureMonitorLogSettings.backend.request.body.bytes
        }
      }
      response: {
        headers: azureMonitorLogSettings.backend.response.headers
        body: {
          bytes: azureMonitorLogSettings.backend.response.body.bytes
        }
      }
    }
    largeLanguageModel: {
      logs: azureMonitorLogSettings.largeLanguageModel.logs
      requests: {
        messages: azureMonitorLogSettings.largeLanguageModel.requests.messages
        maxSizeInBytes: azureMonitorLogSettings.largeLanguageModel.requests.maxSizeInBytes
      }
      responses: {
        messages: azureMonitorLogSettings.largeLanguageModel.responses.messages
        maxSizeInBytes: azureMonitorLogSettings.largeLanguageModel.responses.maxSizeInBytes
      }
    }
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Name of the Unified AI API')
output apiName string = enabled ? unifiedAiApi.name : ''

@description('Path of the Unified AI API')
output apiPath string = enabled ? 'unified-ai' : ''

@description('Name of the Unified AI product')
output productName string = enabled ? unifiedAiProduct.name : ''
