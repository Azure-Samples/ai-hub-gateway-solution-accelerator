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
param managedIdentityName string
param clientAppId string = ' '
param tenantId string = tenant().tenantId
param audience string = 'https://cognitiveservices.azure.com/.default'
param eventHubName string
param eventHubEndpoint string

// Networking
param apimNetworkType string = 'External'
param apimSubnetId string

var openAiApiBackendId = 'openai-backend'
var openAiApiUamiNamedValue = 'uami-client-id'
var openAiApiEntraNamedValue = 'entra-auth'
var openAiApiClientNamedValue = 'client-id'
var openAiApiTenantNamedValue = 'tenant-id'
var openAiApiAudienceNamedValue = 'audience'

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
    type: 'UserAssigned'
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
}

resource apimOpenaiApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: 'azure-openai-service-api'
  parent: apimService
  properties: {
    path: 'openai'
    apiRevision: '1'
    displayName: 'Azure OpenAI API'
    subscriptionRequired: entraAuth ? false:true 
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
    format: 'openapi'
    value: string(loadYamlContent('./openai-api/oai-api-spec-2024-05-01-preview.yaml'))
    protocols: [
      'https'
    ]
  }
}

resource apimAiSearchApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: 'azure-ai-search-api'
  parent: apimService
  properties: {
    path: 'search'
    apiRevision: '1'
    displayName: 'Azure AI Search API'
    subscriptionRequired: entraAuth ? false:true 
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
    format: 'openapi'
    value: loadTextContent('./ai-search-api/ai-search-api-spec.yaml')
    protocols: [
      'https'
    ]
  }
}

// Create retail product
resource retailProduct 'Microsoft.ApiManagement/service/products@2020-06-01-preview' = {
  name: 'ai-retail'
  parent: apimService
  properties: {
    displayName: 'AI-Retail'
    description: 'Offering AI services for the retail and e-commerce platforms.'
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
    apiId: apimOpenaiApi.id
  }
}

resource retailProductAISearchApi 'Microsoft.ApiManagement/service/products/apiLinks@2023-05-01-preview' = {
  name: 'retail-product-ai-search-api'
  parent: retailProduct
  properties: {
    apiId: apimAiSearchApi.id
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

resource retailSubscription 'Microsoft.ApiManagement/service/subscriptions@2020-06-01-preview' = {
  name: 'ai-retail-internal-sub'
  parent: apimService
  properties: {
    displayName: 'AI-Retail-Internal-Subscription'
    state: 'active'
    scope: retailProduct.id
  }
}

// Create HR product
resource hrProduct 'Microsoft.ApiManagement/service/products@2020-06-01-preview' = {
  name: 'ai-hr'
  parent: apimService
  properties: {
    displayName: 'AI-HR'
    description: 'Offering AI services for the internal HR platforms.'
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
    apiId: apimOpenaiApi.id
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

resource hrSubscription 'Microsoft.ApiManagement/service/subscriptions@2020-06-01-preview' = {
  name: 'hr-retail-internal-sub'
  parent: apimService
  properties: {
    displayName: 'AI-HR-Internal-Subscription'
    state: 'active'
    scope: hrProduct.id
  }
}

resource openAiBackends 'Microsoft.ApiManagement/service/backends@2021-08-01' = [for (openAiUri, i) in openAiUris: {
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
resource aadAuthPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
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

resource validateRoutesPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apimService
  name: 'validate-routes'
  properties: {
    value: loadTextContent('./policies/frag-validate-routes.xml')
    format: 'rawxml'
  }
  dependsOn: [
    openAiBackends
  ]
}

resource backendRoutingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
  parent: apimService
  name: 'backend-routing'
  properties: {
    value: loadTextContent('./policies/frag-backend-routing.xml')
    format: 'rawxml'
  }
  dependsOn: [
    openAiBackends
  ]
}

resource openAIUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2023-05-01-preview' = {
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

resource openaiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' =  {
  name: 'policy'
  parent: apimOpenaiApi
  properties: {
    value: loadTextContent('./policies/openai_api_policy.xml')
    format: 'rawxml'
  }
  dependsOn: [
    openAiBackends
    apiopenAiApiClientNamedValue
    apiopenAiApiEntraNamedValue
    apimOpenaiApiAudienceiNamedValue
    apiopenAiApiTenantNamedValue
    aadAuthPolicyFragment
    validateRoutesPolicyFragment
    backendRoutingPolicyFragment
    openAIUsagePolicyFragment
  ]
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2021-12-01-preview' = {
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
  dependsOn: [
    eventHub
  ]
}

resource apimRetailDevUser 'Microsoft.ApiManagement/service/users@2020-06-01-preview' = {
  parent: apimService
  name: 'ai-retail-dev-user'
  properties: {
    firstName: 'Retail AI'
    lastName: 'Developer'
    email: 'myuser@example.com'
    state: 'active'
  }
}

resource apimRetailDevUserSubscription 'Microsoft.ApiManagement/service/subscriptions@2020-06-01-preview' = {
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
output apimOpenaiApiPath string = apimOpenaiApi.properties.path

@description('Gateway URL for the deployed API Management resource.')
output apimGatewayUrl string = apimService.properties.gatewayUrl
