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
param openAiUris array
param aiFoundryUris array
param managedIdentityName string
param clientAppId string = ' '
param tenantId string = tenant().tenantId
param audience string = 'https://cognitiveservices.azure.com/.default'
param eventHubName string
param eventHubEndpoint string

param enableAzureAISearch bool = false
param aiSearchInstances array

param enableAIModelInference bool = true

param enableOpenAIRealtime bool = true

// Networking
param apimNetworkType string = 'External'
param apimSubnetId string

var openAiApiBackendId = 'openai-backend'
var openAiApiUamiNamedValue = 'uami-client-id'
var openAiApiEntraNamedValue = 'entra-auth'
var openAiApiClientNamedValue = 'client-id'
var openAiApiTenantNamedValue = 'tenant-id'
var openAiApiAudienceNamedValue = 'audience'

var aiFoundryApiBackendId = 'ai-foundry-backend'

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

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' existing = {
  name: eventHubName
}

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
    openApiSpecification: string(loadYamlContent('./openai-api/oai-api-spec-2024-10-21.yaml'))
    apiDescription: 'Azure OpenAI API'
    policyDocument: loadTextContent('./policies/openai_api_policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    openAIUsagePolicyFragment
    openAIUsageStreamingPolicyFragment
    openAiBackends
    throttlingEventsPolicyFragment
    dynamicThrottlingAssignmentFragment
  ]
}

module apimAiFoundryApi './api.bicep' = if (length(aiFoundryUris) > 0) {
  name: 'azure-ai-foundry-service-api'
  params: {
    serviceName: apimService.name
    apiName: 'azure-ai-foundry-service-api'
    path: 'ai-foundry'
    apiRevision: '1'
    apiDispalyName: 'Azure AI Foundry API'
    subscriptionRequired: entraAuth ? false:true
    subscriptionKeyName: 'api-key'
    openApiSpecification: string(loadYamlContent('./ai-foundry-api/ai-foundry-api-spec.yaml'))
    apiDescription: 'Azure AI Foundry API'
    policyDocument: loadTextContent('./policies/ai-foundry-api-policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    openAIUsagePolicyFragment
    openAIUsageStreamingPolicyFragment
    aiFoundryBackends
    throttlingEventsPolicyFragment
    dynamicThrottlingAssignmentFragment
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
    openApiSpecification: loadTextContent('./ai-search-api/ai-search-api-spec.yaml')
    apiDescription: 'Azure AI Search APIs'
    policyDocument: loadTextContent('./policies/ai-search-api-policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    aiUsagePolicyFragment
    throttlingEventsPolicyFragment
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
    openApiSpecification: loadTextContent('./ai-model-inference/ai-model-inference-api-spec.yaml')
    apiDescription: 'Access to AI inference models published through Azure AI Foundry'
    policyDocument: loadTextContent('./policies/ai-model-inference-api-policy.xml')
    enableAPIDeployment: true
  }
  dependsOn: [
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    aiUsagePolicyFragment
    throttlingEventsPolicyFragment
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
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    throttlingEventsPolicyFragment
  ]
}

// Create AI-Retail product
resource retailProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = {
  name: 'oai-retail-assistant'
  parent: apimService
  properties: {
    displayName: 'OAI-Retail-Assistant'
    description: 'Offering OpenAI services for the retail and e-commerce platforms assistant.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 200
    state: 'published'
    terms: 'By subscribing to this product, you agree to the terms and conditions.'
  }
}

resource retailProductOpenAIApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-05-01-preview' = {
  name: 'retail-product-openai-api'
  parent: retailProduct
  properties: {
    apiId: apimOpenaiApi.outputs.id
  }
}

resource retailProductPolicy 'Microsoft.ApiManagement/service/products/policies@2022-08-01' =  {
  name: 'policy'
  parent: retailProduct
  properties: {
    value: loadTextContent('./policies/retail_product_policy.xml')
    format: 'rawxml'
  }
  dependsOn: [
    apimOpenaiApi
  ]
}

resource retailSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  name: 'oai-retail-assistant-sub-01'
  parent: apimService
  properties: {
    displayName: 'AI-Retail-Internal-Subscription'
    state: 'active'
    scope: retailProduct.id
  }
}

// Create AI-HR product
resource hrProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = {
  name: 'oai-hr-assistant'
  parent: apimService
  properties: {
    displayName: 'OAI-HR-Assistant'
    description: 'Offering OpenAI services for the internal HR platforms.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 200
    state: 'published'
    terms: 'By subscribing to this product, you agree to the terms and conditions.'
  }
}

resource hrProductOpenAIApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-05-01-preview' = {
  name: 'hr-product-openai-api'
  parent: hrProduct
  properties: {
    apiId: apimOpenaiApi.outputs.id
  }
}

resource hrProductPolicy 'Microsoft.ApiManagement/service/products/policies@2022-08-01' =  {
  name: 'policy'
  parent: hrProduct
  properties: {
    value: loadTextContent('./policies/hr_product_policy.xml')
    format: 'rawxml'
  }
  dependsOn: [
    apimOpenaiApi
  ]
}

resource hrSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  name: 'oai-hr-assistant-sub-01'
  parent: apimService
  properties: {
    displayName: 'OAI-HR-Assistant-Sub-01'
    state: 'active'
    scope: hrProduct.id
  }
}

// Create Search-HR product
resource searchHRProduct 'Microsoft.ApiManagement/service/products@2022-08-01' = if(enableAzureAISearch) {
  name: 'src-hr-assistant'
  parent: apimService
  properties: {
    displayName: 'SRC-HR-Assistant'
    description: 'Offering AI Search services for the HR systems.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 200
    state: 'published'
    terms: 'By subscribing to this product, you agree to the terms and conditions.'
  }
}

resource searchHRProductAISearchApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-05-01-preview' = if (enableAzureAISearch) {
  name: 'src-hr-product-ai-search-api'
  parent: searchHRProduct
  properties: {
    apiId: apimAiSearchApi.outputs.id
  }
}

resource searchHRProductProductPolicy 'Microsoft.ApiManagement/service/products/policies@2022-08-01' =  if (enableAzureAISearch) {
  name: 'policy'
  parent: searchHRProduct
  properties: {
    value: loadTextContent('./policies/search_hr_product_policy.xml')
    format: 'rawxml'
  }
}

resource searchHRSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = if (enableAzureAISearch) {
  name: 'src-hr-assistant-sub-01'
  parent: apimService
  properties: {
    displayName: 'SRC-HR-Assistant-Sub-01'
    state: 'active'
    scope: searchHRProduct.id
  }
}

resource openAiBackends 'Microsoft.ApiManagement/service/backends@2022-08-01' = [for (openAiUri, i) in openAiUris: {
  name: '${openAiApiBackendId}-${i}'
  parent: apimService
  properties: {
    description: openAiApiBackendId
    url: openAiUri
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource aiFoundryBackends 'Microsoft.ApiManagement/service/backends@2022-08-01' = [for (aiFoundryUri, i) in aiFoundryUris: if(length(aiFoundryUris) > 0) {
  name: '${aiFoundryApiBackendId}-${i}'
  parent: apimService
  properties: {
    description: aiFoundryApiBackendId
    url: aiFoundryUri
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

resource aiSearchBackends 'Microsoft.ApiManagement/service/backends@2022-08-01' = [for (aiSearchInstance, i) in aiSearchInstances: if(enableAzureAISearch) {
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

resource apimOpenaiApiUamiNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiUamiNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiUamiNamedValue
    secret: true
    value: managedIdentity.properties.clientId
  }
}

resource apiopenAiApiEntraNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiEntraNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiEntraNamedValue
    secret: false
    value: entraAuth
  }
}
resource apiopenAiApiClientNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiClientNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiClientNamedValue
    secret: true
    value: clientAppId
  }
}
resource apiopenAiApiTenantNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' = {
  name: openAiApiTenantNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiTenantNamedValue
    secret: true
    value: tenantId
  }
}
resource apimOpenaiApiAudienceiNamedValue 'Microsoft.ApiManagement/service/namedValues@2022-08-01' =  {
  name: openAiApiAudienceNamedValue
  parent: apimService
  properties: {
    displayName: openAiApiAudienceNamedValue
    secret: true
    value: audience
  }
}

// Adding Policy Fragments
resource aadAuthPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'aad-auth'
  properties: {
    value: loadTextContent('./policies/frag-aad-auth.xml')
    format: 'rawxml'
  }
  dependsOn: [
    apiopenAiApiClientNamedValue
    apiopenAiApiEntraNamedValue
    apimOpenaiApiAudienceiNamedValue
    apiopenAiApiTenantNamedValue
  ]
}

resource validateRoutesPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'validate-routes'
  properties: {
    value: loadTextContent('./policies/frag-validate-routes.xml')
    format: 'rawxml'
  }
}

resource backendRoutingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'backend-routing'
  properties: {
    value: loadTextContent('./policies/frag-backend-routing.xml')
    format: 'rawxml'
  }
}

resource openAIUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'openai-usage'
  properties: {
    value: loadTextContent('./policies/frag-openai-usage.xml')
    format: 'rawxml'
  }
  dependsOn: [
    ehUsageLogger
  ]
}

resource openAIUsageStreamingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'openai-usage-streaming'
  properties: {
    value: loadTextContent('./policies/frag-openai-usage-streaming.xml')
    format: 'rawxml'
  }
  dependsOn: [
  ]
}

resource aiUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'ai-usage'
  properties: {
    value: loadTextContent('./policies/frag-ai-usage.xml')
    format: 'rawxml'
  }
  dependsOn: [
    ehUsageLogger
  ]
}

resource throttlingEventsPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'throttling-events'
  properties: {
    value: loadTextContent('./policies/frag-throttling-events.xml')
    format: 'rawxml'
  }
}

resource dynamicThrottlingAssignmentFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'dynamic-throttling-assignment'
  properties: {
    value: loadTextContent('./policies/frag-dynamic-throttling-assignment.xml')
    format: 'rawxml'
  }
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
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

resource apimAppInsights 'Microsoft.ApiManagement/service/diagnostics@2022-08-01' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'Legacy'
    verbosity: 'information'
    logClientIp: true
    loggerId: apimLogger.id
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        body: {
          bytes: 0
        }
      }
      response: {
        body: {
          bytes: 0
        }
      }
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
      name: eventHub.name
      endpointAddress: replace(eventHubEndpoint, 'https://', '')
      identityClientId: managedIdentity.properties.clientId
    }
  }
}

resource apimRetailDevUser 'Microsoft.ApiManagement/service/users@2022-08-01' = {
  parent: apimService
  name: 'ai-retail-dev-user'
  properties: {
    firstName: 'Retail AI'
    lastName: 'Developer'
    email: 'myuser@example.com'
    state: 'active'
  }
}

resource apimRetailDevUserSubscription 'Microsoft.ApiManagement/service/subscriptions@2022-08-01' = {
  parent: apimService
  name: 'retail-ai-dev-user-subscription'
  properties: {
    displayName: 'Retail AI Dev User Subscription'
    ownerId: '/users/${apimRetailDevUser.id}'
    state: 'active'
    allowTracing: true
    scope: '/products/${retailProduct.id}'
  }
}

@description('The name of the deployed API Management service.')
output apimName string = apimService.name

@description('The path for the OpenAI API in the deployed API Management service.')
output apimOpenaiApiPath string = apimOpenaiApi.outputs.path

@description('The path for the AI Foundry API in the deployed API Management service.')
output apimAiFoundryApiPath string = length(aiFoundryUris) > 0 ? apimAiFoundryApi.outputs.path : ''

@description('Gateway URL for the deployed API Management resource.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('Primary private IP address of the API Management service (for Internal network type).')
output apimPrivateIp string = apimService.properties.privateIPAddresses != null && length(apimService.properties.privateIPAddresses) > 0 ? apimService.properties.privateIPAddresses[0] : ''
