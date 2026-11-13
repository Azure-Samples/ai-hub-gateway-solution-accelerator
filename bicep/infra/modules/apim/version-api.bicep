/**
 * @module version-api
 * @description Creates a lightweight "Release Version" API in API Management that exposes
 * a single GET operation returning the accelerator release version manifest (release.json)
 * as static JSON content. The content is embedded into an operation-level policy at deploy
 * time via a mock (return-response) response, so no backend is required.
 *
 * This module is shared by both the primary accelerator deployment (apim.bicep) and the
 * APIM Gateway Upgrade (apim-gateway-upgrade/main.bicep) so the version endpoint is always
 * created/updated to reflect the currently deployed release manifest.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('The name of the API Management instance to deploy the version API to.')
@minLength(1)
param apiManagementName string

@description('The name (resource id segment) of the version API.')
param versionApiName string = 'release-version-api'

@description('The display name of the version API.')
param versionApiDisplayName string = 'Release Version API'

@description('The description of the version API.')
param versionApiDescription string = 'Returns the AI Hub Gateway accelerator release version manifest (release.json) as static JSON content.'

@description('The relative path (URL suffix) for the version API in the APIM gateway.')
param versionApiPath string = 'version'

@description('Set to true if a subscription key is required to call the version API. Defaults to false so the endpoint can be queried anonymously (health/version style).')
param subscriptionRequired bool = false

@description('The name of the subscription key header (only relevant when subscriptionRequired is true). Accepts the LLM-style "api-key" (default) or the APIM-native "Ocp-Apim-Subscription-Key".')
@allowed([
  'api-key'
  'Ocp-Apim-Subscription-Key'
])
param subscriptionKeyName string = 'api-key'

@description('The raw JSON content of the release manifest to serve. Defaults to the repository release.json.')
param releaseContent string = loadTextContent('../../../../release.json')

@description('Whether to add the GET backend-contract operation that returns the active LLM backend routing contract via the backend-contract policy fragment.')
param includeBackendContractOperation bool = true

@description('The id of the policy fragment that returns the active backend contract. Created/updated by the primary deployment and the LLM onboarding submodule.')
param backendContractFragmentId string = 'backend-contract'

// ------------------
//    VARIABLES
// ------------------

// The release manifest is embedded verbatim into a return-response policy as a literal body.
// release.json contains only JSON-safe characters ({ } " : , and version strings) so it does
// not need XML escaping. If this ever changes, escape < > & before embedding.
// NOTE: Bicep multi-line strings ('''...''') do NOT support interpolation, so the policy is
// composed from a prefix and suffix with the release content concatenated in between.
var versionApiPolicyPrefix = '''
<policies>
    <inbound>
        <base />
        <return-response>
            <set-status code="200" reason="OK" />
            <set-header name="Content-Type" exists-action="override">
                <value>application/json</value>
            </set-header>
            <set-body>'''

var versionApiPolicySuffix = '''</set-body>
        </return-response>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>'''

var versionApiPolicyXml = '${versionApiPolicyPrefix}${releaseContent}${versionApiPolicySuffix}'

// Operation policy for the backend-contract operation. It simply includes the dynamically
// generated `backend-contract` fragment, which emits the active routing contract as JSON.
var backendContractOperationPolicyXml = replace('''
<policies>
    <inbound>
        <base />
        <include-fragment fragment-id="FRAGMENTID" />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>''', 'FRAGMENTID', backendContractFragmentId)

// Query-string key name mirrors the header: APIM-native header uses the 'subscription-key' query param,
// the LLM-style 'api-key' header uses an 'api-key' query param.
var subscriptionKeyQueryName = subscriptionKeyName == 'Ocp-Apim-Subscription-Key' ? 'subscription-key' : 'api-key'

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apiManagementName
}

resource versionApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  name: versionApiName
  parent: apimService
  properties: {
    apiType: 'http'
    description: versionApiDescription
    displayName: versionApiDisplayName
    path: versionApiPath
    protocols: [
      'https'
    ]
    subscriptionRequired: subscriptionRequired
    subscriptionKeyParameterNames: {
      header: subscriptionKeyName
      query: subscriptionKeyQueryName
    }
    serviceUrl: 'https://to-be-replaced-by-policy'
  }
}

resource versionApiGetOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  name: 'get-version'
  parent: versionApi
  properties: {
    displayName: 'Get Release Version'
    method: 'GET'
    urlTemplate: '/'
    description: 'Returns the accelerator release version manifest as static JSON content.'
    responses: [
      {
        statusCode: 200
        description: 'The release version manifest.'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource versionApiGetOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  name: 'policy'
  parent: versionApiGetOperation
  properties: {
    format: 'rawxml'
    value: versionApiPolicyXml
  }
}

resource versionApiBackendContractOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = if (includeBackendContractOperation) {
  name: 'get-backend-contract'
  parent: versionApi
  properties: {
    displayName: 'Get Backend Contract'
    method: 'GET'
    urlTemplate: '/backend-contract'
    description: 'Returns the active LLM backend routing contract (version, pools, backends) deployed on this gateway. The response is produced by the dynamically generated backend-contract policy fragment.'
    responses: [
      {
        statusCode: 200
        description: 'The active backend routing contract.'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource versionApiBackendContractOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = if (includeBackendContractOperation) {
  name: 'policy'
  parent: versionApiBackendContractOperation
  properties: {
    format: 'rawxml'
    value: backendContractOperationPolicyXml
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('The resource id of the version API.')
output versionApiId string = versionApi.id

@description('The name (resource id segment) of the version API.')
output versionApiResourceName string = versionApi.name

@description('The gateway path of the version API.')
output versionApiPathOut string = versionApiPath
