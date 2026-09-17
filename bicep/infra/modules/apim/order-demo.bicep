@description('Name of the API Management service')
param apiManagementName string

@description('Name of the Key Vault used for the demo backend credential')
param keyVaultName string

@secure()
@description('Synthetic backend credential stored in Key Vault and exposed to APIM only through a named value')
param orderBackendApiKey string = newGuid()

@description('Unique developer portal revision identifier used when publishing the demo content')
param portalRevisionId string = utcNow('yyyyMMddHHmmss')

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apiManagementName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource orderBackendSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'order-backend-api-key'
  parent: keyVault
  properties: {
    value: orderBackendApiKey
    contentType: 'APIM Order API demo credential'
  }
}

resource orderBackendNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'order-backend-api-key'
  parent: apimService
  properties: {
    displayName: 'order-backend-api-key'
    secret: true
    tags: [
      'demo'
      'key-vault'
    ]
    keyVault: {
      secretIdentifier: orderBackendSecret.properties.secretUri
    }
  }
}

resource ordersApiV1 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'orders-api;rev=1'
  parent: apimService
  properties: {
    apiRevision: '1'
    apiRevisionDescription: 'Original Order API contract'
    apiType: 'http'
    displayName: 'Orders API'
    description: 'Self-contained Order Management API used by the APIM lifecycle demo.'
    format: 'openapi'
    isCurrent: true
    path: 'orders-demo'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://example.invalid'
    subscriptionRequired: true
    value: loadTextContent('./order-demo/orders-api-v1.openapi.yaml')
  }
}

resource ordersApiV1Policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: ordersApiV1
  properties: {
    format: 'rawxml'
    value: loadTextContent('./order-demo/orders-v1-policy.xml')
  }
  dependsOn: [
    orderBackendNamedValue
  ]
}

resource ordersApiV2 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'orders-api;rev=2'
  parent: apimService
  properties: {
    apiRevision: '2'
    apiRevisionDescription: 'Adds estimatedDelivery as a non-breaking response field'
    apiType: 'http'
    displayName: 'Orders API'
    description: 'Order lifecycle demo API. Revision 1 is the current public revision.'
    format: 'openapi'
    path: 'orders-demo'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://example.invalid'
    sourceApiId: ordersApiV1.id
    subscriptionRequired: true
    value: loadTextContent('./order-demo/orders-api-v2.openapi.yaml')
  }
}

resource ordersApiV2Policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: ordersApiV2
  properties: {
    format: 'rawxml'
    value: loadTextContent('./order-demo/orders-v2-policy.xml')
  }
  dependsOn: [
    orderBackendNamedValue
  ]
}

resource productsApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: 'products-api;rev=1'
  parent: apimService
  properties: {
    apiRevision: '1'
    apiRevisionDescription: 'Product catalogue cache demo'
    apiType: 'http'
    displayName: 'Products API'
    description: 'Product catalogue API with a 60-second APIM response cache.'
    format: 'openapi'
    isCurrent: true
    path: 'products-demo'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://example.invalid'
    subscriptionRequired: true
    value: loadTextContent('./order-demo/products-api.openapi.yaml')
  }
}

resource productsApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  name: 'policy'
  parent: productsApi
  properties: {
    format: 'rawxml'
    value: loadTextContent('./order-demo/products-policy.xml')
  }
}

resource orderManagementProduct 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  name: 'order-management-apis'
  parent: apimService
  properties: {
    displayName: 'Order Management APIs'
    description: 'Orders and product catalogue APIs for the Order-to-Cash demo.'
    approvalRequired: false
    state: 'published'
    subscriptionRequired: true
    subscriptionsLimit: 10
  }
}

resource ordersProductAssociation 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  name: 'orders-api'
  parent: orderManagementProduct
  dependsOn: [
    ordersApiV1
  ]
}

resource productsProductAssociation 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  name: 'products-api'
  parent: orderManagementProduct
  dependsOn: [
    productsApi
  ]
}

resource ordersAzureMonitorDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  name: 'azuremonitor'
  parent: ordersApiV1
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apiManagementName, 'azuremonitor')
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

resource ordersAppInsightsDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  name: 'applicationinsights'
  parent: ordersApiV1
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'Information'
    logClientIp: true
    metrics: true
    httpCorrelationProtocol: 'W3C'
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apiManagementName, 'appinsights-logger')
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

resource productsAzureMonitorDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  name: 'azuremonitor'
  parent: productsApi
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apiManagementName, 'azuremonitor')
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

resource productsAppInsightsDiagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  name: 'applicationinsights'
  parent: productsApi
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'Information'
    logClientIp: true
    metrics: true
    httpCorrelationProtocol: 'W3C'
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', apiManagementName, 'appinsights-logger')
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

// Publishing is a snapshot operation, so every deployment needs a new portal revision identifier.
#disable-next-line use-stable-resource-identifiers
resource developerPortalRevision 'Microsoft.ApiManagement/service/portalRevisions@2024-05-01' = {
  name: portalRevisionId
  parent: apimService
  properties: {
    description: 'Published for the Order Management API demo'
    isCurrent: true
  }
  dependsOn: [
    ordersProductAssociation
    productsProductAssociation
  ]
}

output ordersApiName string = 'orders-api'
output productsApiName string = 'products-api'
output productName string = orderManagementProduct.name
