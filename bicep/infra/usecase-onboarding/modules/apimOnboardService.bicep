@description('Existing APIM service name')
param apimName string

@description('APIM product identifier (resource name). e.g., OAI-HR-InternalAssistant-DEV')
param productId string
@description('APIM product display name')
param productDisplayName string
@description('APIM product description')
param productDescription string = 'AI Gateway product for use case'
@description('APIM product terms')
param productTerms string = ''

@description('List of API names to include in product')
param apiNames array

@description('Optional product policy XML; if empty, a default minimal policy is applied')
param productPolicyXml string = ''

@description('Subscription name (resource name) e.g., <productId>-SUB-01')
param subscriptionName string
@description('Subscription display name')
param subscriptionDisplayName string

var defaultPolicy = '<policies>\n  <inbound>\n    <base />\n    <rate-limit calls="60" renewal-period="60" />\n    <check-header name="Ocp-Apim-Subscription-Key" failed-check-httpcode="401" failed-check-error-message="Subscription key required" />\n  </inbound>\n  <backend>\n    <base />\n  </backend>\n  <outbound>\n    <base />\n  </outbound>\n  <on-error>\n    <base />\n  </on-error>\n</policies>'

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
    subscriptionRequired: true
    approvalRequired: false
    subscriptionsLimit: 10
    state: 'published'
  }
}

resource productApis 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = [for (apiName, i) in apiNames: {
  name: apiName
  parent: product
}]

resource policy 'Microsoft.ApiManagement/service/products/policies@2024-05-01' = {
  name: 'policy'
  parent: product
  properties: {
    format: 'rawxml'
    value: empty(productPolicyXml) ? defaultPolicy : productPolicyXml
  }
}

resource sub 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  name: subscriptionName
  parent: apim
  properties: {
    displayName: subscriptionDisplayName
    scope: product.id
    state: 'active'
  }
}

// first API path for endpoint URL construction
var firstApiName = apiNames[0]
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = {
  name: firstApiName
  parent: apim
}

output productName string = product.name
output subscriptionNameOut string = sub.name
@secure()
output subscriptionPrimaryKey string = sub.listSecrets().primaryKey
output apiPath string = api.properties.path
