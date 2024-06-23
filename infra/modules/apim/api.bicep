@description('The name of the API')
@minLength(1)
@maxLength(63)
param apiName string

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


// Assume the content format is JSON format if the ending is .json - otherwise, it's YAML
var contentFormat = startsWith(openApiSpecification, '{') ? 'openapi+json' : 'openapi'

resource apimService 'Microsoft.ApiManagement/service@2022-04-01-preview' existing = {
  name: serviceName
}

resource apiDefinition 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: apiName
  parent: apimService
  properties: {
    path: (path == '') ? apiName : path
    apiRevision: apiRevision
    description: (apiDescription == '') ? apiName : apiDescription
    displayName: apiName
    format: contentFormat
    value: openApiSpecification
    subscriptionRequired: subscriptionRequired
    subscriptionKeyParameterNames: {
      header: empty(subscriptionKeyName) ? 'Ocp-Apim-Subscription-Key' : subscriptionKeyName
    }
    type: 'http'
    protocols: [ 'https' ]
    serviceUrl: (serviceUrl == '') ? null : serviceUrl
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  name: 'policy'
  parent: apiDefinition
  properties: {
    format: 'rawxml'
    value: policyDocument
  }
}
