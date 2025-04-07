@description('The name of the API Management service to deploy the API to.')
@minLength(1)
param serviceName string
param productDisplayName string = 'OpenAI Product'
param productDescription string = 'Offering OpenAI services.'

param subscriptionRequired bool = true
param approvalRequired bool = true
param subscriptionsLimit int = 200
param state string = 'published'

param apiList array

param xmlPolicy string

param productSubscriptions array = [
  {
    name: 'Test'
    description: 'Test subscription'
    state: 'active'
  }
  {
    name: 'App 1'
    description: 'App 1 subscription'
    state: 'active'
  }
]

var productName = toLower(replace(productDisplayName, ' ', '-')) 
var productTerms = 'By subscribing to this product, you agree to the terms and conditions.'

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: serviceName
}

resource product 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = {
  name: productName
  parent: apimService
  properties: {
    displayName: productDisplayName
    description: productDescription
    subscriptionRequired: subscriptionRequired
    approvalRequired: approvalRequired
    subscriptionsLimit: subscriptionsLimit
    state: state
    terms: productTerms
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apiLinks@2024-06-01-preview' = [for (api, i) in apiList: {
  name: '${productName}-api-${api.name}'
  parent: product
  properties: {
    apiId: api.id
  }
}]

resource openAIProductPolicy 'Microsoft.ApiManagement/service/products/policies@2024-06-01-preview' = if (!empty(xmlPolicy)) {
  name: 'policy'
  parent: product
  properties: {
    value: xmlPolicy
    format: 'rawxml'
  }
}

resource openAIProductSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = [for (subscription, i) in productSubscriptions: {
  name: '${productName}-${toLower(replace(subscription.name, ' ', '-'))}'
  parent: apimService
  properties: {
    displayName: '${productDisplayName} ${subscription.name}'
    state: subscription.state
    scope: product.id
  }
}]
