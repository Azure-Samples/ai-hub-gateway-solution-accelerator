/**
 * @module 
 * @description This module defines the API resources using Bicep.
 * It includes configurations for creating and managing APIs, products, and policies.
 * This is version 2 (v2) of the APIM Bicep module.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('The suffix to append to the API Management instance name. Defaults to a unique string based on subscription and resource group IDs.')
param resourceSuffix string = uniqueString(subscription().id, resourceGroup().id)

@description('The name of the API Management instance. Defaults to "apim-<resourceSuffix>".')
param apiManagementName string = 'apim-${resourceSuffix}'

@description('Id of the APIM Logger')
param apimLoggerId string = ''

@description('The instrumentation key for Application Insights')
@secure()
param appInsightsInstrumentationKey string = ''

@description('The resource ID for Application Insights')
param appInsightsId string = ''

@description('The XML content for the API policy')
param policyXml string

@description('Configuration array for AI Services')
param aiServicesConfig array = []

@description('The name of the Inference API in API Management.')
param inferenceAPIName string = 'inference-api'

@description('The description of the Inference API in API Management.')
param inferenceAPIDescription string = 'Inferencing API for language models'

@description('The display name of the Inference API in API Management. .')
param inferenceAPIDisplayName string = 'Inference API'

@description('The name of the Inference backend pool.')
param inferenceBackendPoolName string = 'inference-backend-pool'

@description('Allow the use subscription key for the inference API (in case of using JWT auth only this can be set to false)')
param allowSubscriptionKey bool = true

@description('The inference API type')
@allowed([
  'AzureOpenAI'
  'AzureAI'
  'OpenAI'
])
param inferenceAPIType string = 'AzureOpenAI'

@description('The path to the inference API in the APIM service')
param inferenceAPIPath string = 'inference' // Path to the inference API in the APIM service

@description('Whether to configure the circuit breaker for the inference backend')
param configureCircuitBreaker bool = false

// ------------------
//    VARIABLES
// ------------------

var logSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens' , 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

// to allow future modifications to the policy XML if needed
var updatedPolicyXml = policyXml

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apiManagementName
}

var endpointPath = (inferenceAPIType == 'AzureOpenAI') ? 'openai' : (inferenceAPIType == 'AzureAI') ? 'models' : ''

// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  name: inferenceAPIName
  parent: apimService
  properties: {
    apiType: 'http'
    description: inferenceAPIDescription
    displayName: inferenceAPIDisplayName
    format: 'openapi+json'
    path: '${inferenceAPIPath}/${endpointPath}'
    protocols: [
      'https'
    ]
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    subscriptionRequired: allowSubscriptionKey
    type: 'http'
    value: string((inferenceAPIType == 'AzureOpenAI') ? loadJsonContent('./universal-llm-api/AIFoundryOpenAI.json') : (inferenceAPIType == 'AzureAI') ? loadJsonContent('./universal-llm-api/AIFoundryAzureAI.json') : (inferenceAPIType == 'OpenAI') ? loadJsonContent('./universal-llm-api/AIFoundryAzureAI.json') : loadJsonContent('./universal-llm-api/PassThrough.json'))
  }
}
// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis/policies
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  name: 'policy'
  parent: api
  properties: {
    format: 'rawxml'
    value: updatedPolicyXml
  }
}


// Reference the backend module
module inferenceBackends './inference-backend.bicep' = {
  name: 'inferenceBackends-${inferenceAPIName}'
  params: {
    resourceSuffix: resourceSuffix
    apiManagementName: apiManagementName
    aiServicesConfig: aiServicesConfig
    inferenceBackendPoolName: inferenceBackendPoolName
    configureCircuitBreaker: configureCircuitBreaker
    inferenceAPIType: inferenceAPIType
  }
}

resource apiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = if(length(apimLoggerId) > 0) {
  parent: api
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
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    largeLanguageModel: {
      logs: 'enabled'
      requests: {
        messages: 'all'
        maxSizeInBytes: 262144
      }
      responses: {
        messages: 'all'
        maxSizeInBytes: 262144
      }
    }
  }
}

resource apiDiagnosticsAppInsights 'Microsoft.ApiManagement/service/apis/diagnostics@2022-08-01' = if (!empty(appInsightsId) && !empty(appInsightsInstrumentationKey)) {
  name: 'applicationinsights'
  parent: api
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    loggerId: resourceId(resourceGroup().name, 'Microsoft.ApiManagement/service/loggers', apiManagementName, 'appinsights-logger')
    metrics: true
    verbosity: 'verbose'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: logSettings
      response: logSettings
    }
    backend: {
      request: logSettings
      response: logSettings
    }
  }
}

// ------------------
//    OUTPUTS
// ------------------

output apiId string = api.id
output path string = api.properties.path
output backendNames array = inferenceBackends.outputs.backendNames
output backendPoolName string = inferenceBackends.outputs.backendPoolName
output backendPoolId string = inferenceBackends.outputs.backendPoolId
