param name string
param location string = resourceGroup().location
param tags object = {}
param entraAuth bool = false

@minLength(1)
param publisherEmail string = 'noreply@microsoft.com'

@minLength(1)
param publisherName string = 'n/a'
param sku string = 'Developer'
param skuCount int = 1
param applicationInsightsName string
param openAiInstances array
param openAiUris array
param managedIdentityName string
param clientAppId string = ' '
param tenantId string = tenant().tenantId
param audience string = 'https://cognitiveservices.azure.com/.default'
param eventHubName string
param eventHubEndpoint string

param enableAzureAISearch bool = false
param aiSearchInstances array

param enableAIModelInference bool = false
param enableOpenAIRealtime bool = false

// Networking
param apimNetworkType string = 'External'
param apimSubnetId string

param productEnvironments string[] = [
  'development'
  'staging'
  'production'
]

var openAiApiBackendId = 'openai-backend'
var openAiApiUamiNamedValue = 'uami-client-id'
var openAiApiEntraNamedValue = 'entra-auth'
var openAiApiClientNamedValue = 'client-id'
var openAiApiTenantNamedValue = 'tenant-id'
var openAiApiAudienceNamedValue = 'audience'

var apiManagementMinApiVersion = '2021-08-01'

// Add this variable near the top with other variables
// var apimZones = sku == 'Premium' && skuCount > 1 ? ['1','2','3'] : []
// Replace the existing apimZones variable
var apimZones = (sku == 'Premium' && skuCount > 1) ? (skuCount == 2 ? ['1','2'] : ['1','2','3']) : []

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: managedIdentityName
}
/*
resource eventHub 'Microsoft.EventHub/namespaces/@2024-01-01' existing = {
  name: eventHubName
}
*/
resource apimService 'Microsoft.ApiManagement/service@2021-08-01' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  sku: {
    name: sku
    capacity: (sku == 'Consumption') ? 0 : ((sku == 'Developer') ? 1 : skuCount)
  }
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: apimNetworkType
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    apiVersionConstraint: {
      minApiVersion: apiManagementMinApiVersion
    }
    // Custom properties are not supported for Consumption SKU
    customProperties: sku == 'Consumption' ? {} : {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
  zones: apimZones
}

module apimOpenaiApi './api.bicep' = {
  name: 'azure-openai-service-api'
  params: {
    serviceName: apimService.name
    apiName: 'azure-openai-service-api'
    path: 'openai'
    apiRevision: '1'
    apiDispalyName: 'Azure OpenAI API'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'api-key'
    openApiSpecification: string(loadYamlContent('./api-specs/openai-api/oai-api-spec-2024-10-21.yaml'))
    apiDescription: 'Azure OpenAI API'
    policyDocument: loadTextContent('./policies/api/openai_api_policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    policyFragments
    openAiBackends
  ]
}

module apimAiSearchApi './api.bicep' = if (enableAzureAISearch) {
  name: 'azure-ai-search-api'
  params: {
    serviceName: apimService.name
    apiName: 'azure-ai-search-api'
    path: 'search'
    apiRevision: '1'
    apiDispalyName: 'Azure AI Search API'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./api-specs/ai-search-api/ai-search-api-spec.yaml')
    apiDescription: 'Azure AI Search APIs'
    policyDocument: loadTextContent('./policies/api/ai-search-api-policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    policyFragments
  ]
}

module apimAiModelInferenceApi './api.bicep' = if (enableAIModelInference) {
  name: 'ai-model-inference-api'
  params: {
    serviceName: apimService.name
    apiName: 'ai-model-inference-api'
    path: 'models'
    apiRevision: '1'
    apiDispalyName: 'AI Model Inference API'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'api-key'
    openApiSpecification: loadTextContent('./api-specs/ai-model-inference/ai-model-inference-api-spec.yaml')
    apiDescription: 'Access to AI inference models published through Azure AI Foundry'
    policyDocument: loadTextContent('./policies/api/ai-model-inference-api-policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    policyFragments
  ]
}

module apimOpenAIRealTimetApi './api.bicep' = if (enableOpenAIRealtime) {
  name: 'openai-realtime-ws-api'
  params: {
    serviceName: apimService.name
    apiName: 'openai-realtime-ws-api'
    path: 'openai/realtime'
    apiRevision: '1'
    apiDispalyName: 'Azure OpenAI Realtime API'
    subscriptionRequired: entraAuth ? false : true
    subscriptionKeyName: 'api-key'
    openApiSpecification: 'NA'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion.'
    policyDocument: 'NA'
    enableAPIDeployment: true
    serviceUrl: 'wss://to-be-replaced-by-policy'
    apiType: 'websocket'
    apiProtocols: ['wss']
  }
  dependsOn: [
    policyFragments
  ]
}

var apimOpenAIProductPolicies = {
  development: loadTextContent('./policies/products/openai_product_policy_development.xml')
  staging: loadTextContent('./policies/products/openai_product_policy_staging.xml')
  production: loadTextContent('./policies/products/openai_product_policy_production.xml')
}

module apimOpenAIProduct './product.bicep' = [for (environment, i) in productEnvironments: {
  name: 'product-openai-${environment}'
  params: {
    serviceName: apimService.name
    productDisplayName: 'OpenAI Product ${environment}'
    productDescription: 'Product for OpenAI services in the ${environment} environment.'
    apiList: [
      {
        name: 'openai-api'
        id: apimOpenaiApi.outputs.id
      }
    ]
    xmlPolicy: apimOpenAIProductPolicies[environment]
  }
}]

var apimAIInferenceProductPolicies = {
  development: loadTextContent('./policies/products/ai_inference_product_policy_development.xml')
  staging: loadTextContent('./policies/products/ai_inference_product_policy_staging.xml')
  production: loadTextContent('./policies/products/ai_inference_product_policy_production.xml')
}

module aiInferenceProduct './product.bicep' = [for (environment, i) in productEnvironments: if(enableAIModelInference) {
  name: 'product-ai-inference-${environment}'
  params: {
    serviceName: apimService.name
    productDisplayName: 'AI Inference Product ${environment}'
    productDescription: 'Product for AI inference services in the ${environment} environment.'
    apiList: [
      {
        name: 'ai-model-inference-api'  
        id: apimAiModelInferenceApi.outputs.id
      }
    ]
    xmlPolicy: apimAIInferenceProductPolicies[environment]
    }
}]



module openAIRealtimeProduct './product.bicep' = [for (environment, i) in productEnvironments: if(enableOpenAIRealtime){
  name: 'product-openai-realtime-${environment}'
  params: {
    serviceName: apimService.name
    productDisplayName: 'OpenAI Realtime Product ${environment}'
    productDescription: 'Product for OpenAI realtime services in the ${environment} environment.'
    apiList: [
      {
        name: 'openai-realtime-ws-api'  
        id: apimOpenAIRealTimetApi.outputs.id
      }
    ]
    xmlPolicy: ''
  }
}]


var apimSearchProductPolicies = {
  development: loadTextContent('./policies/products/search_product_policy_development.xml')
  staging: loadTextContent('./policies/products/search_product_policy_staging.xml')
  production: loadTextContent('./policies/products/search_product_policy_production.xml')
}
module apimSearchProduct './product.bicep' = [for (environment, i) in productEnvironments: if (enableAzureAISearch) {
  name: 'product-search-${environment}'
  params: {
    serviceName: apimService.name
    productDisplayName: 'Search Product ${environment}'
    productDescription: 'Product for Search services in the ${environment} environment.'
    apiList: [
      {
        name: 'search-api'  
        id: apimAiSearchApi.outputs.id
      }
    ]
    xmlPolicy: apimSearchProductPolicies[environment]
  }
}]


resource openAiBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for (openAiUri, i) in openAiUris: {
  name: '${openAiInstances[i].name}-backend'
  parent: apimService
  properties: {
    description: openAiApiBackendId
    url: openAiUri
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 1
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT3M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
          }
          name: 'openAIBreakerRule'
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}]

// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/backends
resource backendPoolOpenAI 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = if(length(openAiInstances) > 1) {
  name: 'openai-backend-pool'
  parent: apimService
  // BCP035: protocol and url are not needed in the Pool type. This is an incorrect error.
  #disable-next-line BCP035
  properties: {
    description: 'OpenAI Backend Pool'
    type: 'Pool'
    pool: {
      services: [for (config, i) in openAiInstances: {
        id: '/backends/${config.name}-backend'
        priority: config.?priority
        weight: config.?weight
      }]
    }
  }
  dependsOn: [
    openAiBackends
  ]
}


resource aiSearchBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [for (aiSearchInstance, i) in aiSearchInstances: if(enableAzureAISearch) {
  name: aiSearchInstance.name
  parent: apimService
  properties: {
    description: aiSearchInstance.description
    url: aiSearchInstance.url
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource apimOpenaiApiUamiNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: openAiApiUamiNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiUamiNamedValue
    secret: true
    value: managedIdentity.properties.clientId
  }
}

resource apiopenAiApiEntraNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: openAiApiEntraNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiEntraNamedValue
    secret: false
    value: entraAuth
  }
}
resource apiopenAiApiClientNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: openAiApiClientNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiClientNamedValue
    secret: true
    value: clientAppId
  }
}
resource apiopenAiApiTenantNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  name: openAiApiTenantNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiTenantNamedValue
    secret: true
    value: tenantId
  }
}
resource apimOpenaiApiAudienceiNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' =  {
  name: openAiApiAudienceNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiAudienceNamedValue
    secret: true
    value: audience
  }
}

// Adding Policy Fragments
module policyFragments './policy-fragments.bicep' = {
  name: 'policy-fragments'
  params: {
    serviceName: apimService.name
  }
  dependsOn: [
    //ehUsageLogger
  ]
}


resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  name: 'appinsights-logger'
  parent: apimService
  properties: {
    credentials: {
      instrumentationKey: applicationInsights.properties.InstrumentationKey
    }
    description: 'Application Insights logger for API observability'
    isBuffered: false
    loggerType: 'applicationInsights'
    resourceId: applicationInsights.id
  }
}

var logSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens' , 'x-ratelimit-remaining-requests' ]
  body: { bytes: 8192 }
}

resource apimAppInsights 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: apimLogger.id
    metrics: true
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


resource ehUsageLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  name: 'usage-eventhub-logger'
  parent: apimService
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for OpenAI usage metrics'
    credentials: {
      name: eventHubName
      endpointAddress: replace(eventHubEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
  
}

module workbooks 'workbooks.bicep' = {
  name : 'workbooks'
  params: {
    applicationInsightsName: applicationInsights.name
  }
}

@description('The name of the deployed API Management service.')
output apimName string = apimService.name

@description('The path for the OpenAI API in the deployed API Management service.')
output apimOpenaiApiPath string = apimOpenaiApi.outputs.path

@description('Gateway URL for the deployed API Management resource.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('List of OpenAI instances deployed.')
output extendedOpenAiInstances array = [for (config, i) in openAiInstances: {
  // Original openAIConfig properties
  name: config.name
  location: config.location
  priority: config.?priority
  weight: config.?weight

}]
