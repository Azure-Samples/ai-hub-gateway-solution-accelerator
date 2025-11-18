/**
 * @module 
 * @description This module defines the backend resources for the Inference API.
 * It includes configurations for creating and managing individual backends and backend pools.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('The suffix to append to the API Management instance name. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('The name of the API Management instance. Defaults to "apim-<resourceSuffix>".')
param apiManagementName string = 'apim-${resourceSuffix}'

@description('Configuration array for AI Services')
param aiServicesConfig array = []

@description('The name of the Inference backend pool.')
param inferenceBackendPoolName string = 'inference-backend-pool'

@description('Whether to configure the circuit breaker for the inference backend')
param configureCircuitBreaker bool = false

@description('The inference API type')
@allowed([
  'AzureOpenAI'
  'AzureAI'
  'OpenAI'
])
param inferenceAPIType string = 'AzureOpenAI'

// ------------------
//    VARIABLES
// ------------------

var endpointPath = (inferenceAPIType == 'AzureOpenAI') ? 'openai' : (inferenceAPIType == 'AzureAI') ? 'models' : ''

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apiManagementName
}

// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/backends
resource inferenceBackend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' =  [for (config, i) in aiServicesConfig: if(length(aiServicesConfig) > 0) {
  name: config.name
  parent: apimService
  properties: {
    description: 'Inference backend'
    url: '${config.endpoint}${endpointPath}'
    protocol: 'http'
    circuitBreaker: (configureCircuitBreaker) ? {
      rules: [
      {
        failureCondition: {
        count: 1
        errorReasons: [
          'Server errors'
        ]
        interval: 'PT5M'
        statusCodeRanges: [
          {
          min: 429
          max: 429
          }
        ]
        }
        name: 'InferenceBreakerRule'
        tripDuration: 'PT1M'
        acceptRetryAfter: true
      }
      ]
    }: null
    credentials: {
      #disable-next-line BCP037
      managedIdentity: {
          resource: 'https://cognitiveservices.azure.com'
      }
    }
  }
}]

// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/backends
resource backendPoolOpenAI 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if(length(aiServicesConfig) > 1) {
  name: inferenceBackendPoolName
  parent: apimService
  // BCP035: protocol and url are not needed in the Pool type. This is an incorrect error.
  #disable-next-line BCP035
  properties: {
    description: 'Load balancer for multiple inference endpoints'
    type: 'Pool'
    pool: {
      services: [for (config, i) in aiServicesConfig: {
        id: '/backends/${inferenceBackend[i].name}'
        priority: config.?priority
        weight: config.?weight
      }]
    }
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Array of backend names created')
output backendNames array = [for (config, i) in aiServicesConfig: inferenceBackend[i].name]

@description('The name of the backend pool (if created)')
output backendPoolName string = length(aiServicesConfig) > 1 ? backendPoolOpenAI.name : ''

@description('The ID of the backend pool (if created)')
output backendPoolId string = length(aiServicesConfig) > 1 ? backendPoolOpenAI.id : ''
