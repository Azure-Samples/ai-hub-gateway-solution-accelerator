@description('Existing APIM service name')
param apimName string

@description('Product display name')
param productDisplayName string
@description('Product description')
param productDescription string = 'AI Gateway product for a specific use case'
@description('Product identifier (resource name). No spaces. e.g., OAI-HR-InternalAssistant-DEV')
param productId string
@description('Product terms for subscription signup')
param productTerms string = ''
@description('Whether product requires subscription')
param subscriptionRequired bool = true
@description('Whether subscriptions are approval required')
param approvalRequired bool = false
@description('Number of subscriptions a user can have. -1 for unlimited')
param subscriptionsLimit int = 10
@description('Array of API resourceIds to include in the product')
param apiResourceIds array

@description('Optional policy XML content to attach to product. If empty, no policy will be set.')
@secure()
param productPolicyXml string = ''

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  name: productId
  parent: apim
  properties: {
    displayName: productDisplayName
    description: productDescription
    terms: productTerms
    subscriptionRequired: subscriptionRequired
    approvalRequired: approvalRequired
    subscriptionsLimit: subscriptionsLimit
    state: 'published'
  }
}

@batchSize(1)
resource productApis 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for apiId in apiResourceIds: {
  name: last(split(apiId, '/'))
  parent: product
}]

resource setPolicy 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = if (!empty(productPolicyXml)) {
  name: 'policy'
  parent: product
  properties: {
    format: 'xml'
    value: productPolicyXml
  }
}

output productName string = product.name
output productResourceId string = product.id
output productDisplay string = product.properties.displayName
