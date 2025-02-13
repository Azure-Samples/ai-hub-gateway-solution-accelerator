@description('The name of the API')
@minLength(1)
@maxLength(63)
param apiName string

@description('The display name of the API')
@minLength(1)
@maxLength(63)
param apiDispalyName string

@description('The contents of the OpenAPI definition')
@minLength(1)
param openApiSpecification string

@description('The XML Policy document for the API')
@minLength(1)
param policyDocument string

@description('The name of the API Management service to deploy the API to.')
@minLength(1)
param serviceName string

@description('The API description (if blank, use the name of the API)')
param apiDescription string = ''

@description('The relative path for the API (if different to the API name)')
param path string = ''

@description('The (optional) service URL')
param serviceUrl string = ''

@description('Set to true if a subscription is required')
param subscriptionRequired bool = true

@description('API Revision number. Default is 1')
param apiRevision string = '1'

@description('Ability to override the subscription key name. Default is Ocp-Apim-Subscription-Key')
param subscriptionKeyName string = ''

param enableAPIDeployment bool = true

// Assume the content format is JSON format if the ending is .json - otherwise, it's YAML
var contentFormat = startsWith(openApiSpecification, '{') ? 'openapi+json' : 'openapi'

@description('The type of the API')
@allowed([
  'http'
  'soap'
  'graphql'
  'websocket'
])
param apiType string = 'http'

@description('The protocols supported by the API')
@allowed([
  'http'
  'https'
  'ws'
  'wss'
])
param apiProtocols array = [
  'https'
]

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: serviceName
}

resource apiDefinition 'Microsoft.ApiManagement/service/apis@2022-08-01' = if(enableAPIDeployment) {
  name: apiName
  parent: apimService
  properties: {
    path: (path == '') ? apiName : path
    apiRevision: apiRevision
    description: (apiDescription == '') ? apiName : apiDescription
    displayName: apiDispalyName
    format: contentFormat
    value: (openApiSpecification != 'NA') ? openApiSpecification : null
    subscriptionRequired: subscriptionRequired
    subscriptionKeyParameterNames: {
      header: empty(subscriptionKeyName) ? 'Ocp-Apim-Subscription-Key' : subscriptionKeyName
    }
    type: apiType
    protocols: apiProtocols
    serviceUrl: (serviceUrl == '') ? 'https://to-be-replaced-by-policy' : serviceUrl
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = if(enableAPIDeployment && policyDocument != 'NA') {
  name: 'policy'
  parent: apiDefinition
  properties: {
    format: 'rawxml'
    value: policyDocument
  }
}

output id string = (enableAPIDeployment) ? apiDefinition.id : ''
output path string = (enableAPIDeployment) ? apiDefinition.properties.path : ''
