targetScope = 'subscription'

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Use case descriptor used in naming: <code>-<businessUnit>-<useCaseName>-<environment>')
param useCase object

@description('Catalog of existing AI services in APIM as an object map by code. Example: { OAI: { apiResourceIds: ["/subscriptions/.../resourceGroups/.../providers/Microsoft.ApiManagement/service/<apimName>/apis/<apiName>"] } }')
param existingServices object

@description('Required AI services for this use case. Each item: { code: "OAI", endpointSecretName: "OAI_ENDPOINT", apiKeySecretName: "OAI_KEY", policyXml: "<policies>...</policies>" }')
param services array

@description('Optional product terms shown to subscribers')
param productTerms string = ''

var productPostfix = '${useCase.businessUnit}-${useCase.useCaseName}-${useCase.environment}'

// Normalize services by merging a default policyXml property
var normalizedServices = [for s in services: union({ policyXml: '' }, s)]

resource apimRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription(apim.subscriptionId)
  name: apim.resourceGroupName
}

resource apimSvc 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  scope: apimRg
  name: apim.name
}

resource kvRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription(keyVault.subscriptionId)
  name: keyVault.resourceGroupName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: kvRg
  name: keyVault.name
}

// Onboard each requested service into APIM
module onboard 'modules/apimOnboardService.bicep' = [for s in normalizedServices: {
  name: 'onboard-${s.code}-${productPostfix}'
  scope: apimRg
  params: {
    apimName: apim.name
    productId: '${s.code}-${productPostfix}'
    productDisplayName: '${s.code} ${useCase.businessUnit} ${useCase.useCaseName} ${useCase.environment}'
    productDescription: 'AI Gateway product for ${s.code} - ${useCase.useCaseName}'
    productTerms: productTerms
    apiResourceIds: existingServices[s.code].apiResourceIds
  // policyXml is optional per service; pass normalized value
  productPolicyXml: s.policyXml
    subscriptionName: '${s.code}-${productPostfix}-SUB-01'
    subscriptionDisplayName: '${s.code}-${productPostfix}-SUB-01'
  }
}]

// Write Key Vault secrets per service
// Create/update KV secrets; normalize names (Key Vault does not allow underscores)
module kvWrites 'modules/kvSecrets.bicep' = [for (s, i) in normalizedServices: {
  name: 'kv-${s.code}-${productPostfix}'
  scope: kvRg
  params: {
    keyVaultName: kv.name
    secretNames: [ toLower(replace(s.endpointSecretName, '_', '-')), toLower(replace(s.apiKeySecretName, '_', '-')) ]
    secretValues: {
      '${toLower(replace(s.endpointSecretName, '_', '-'))}': '${apimSvc.properties.gatewayUrl}/${onboard[i].outputs.apiPath}'
      '${toLower(replace(s.apiKeySecretName, '_', '-'))}': onboard[i].outputs.subscriptionPrimaryKey
    }
  }
}]

output apimGatewayUrl string = apimSvc.properties.gatewayUrl
output products array = [for s in services: {
  productId: '${s.code}-${productPostfix}'
  displayName: '${s.code} ${useCase.businessUnit} ${useCase.useCaseName} ${useCase.environment}'
}]
output subscriptions array = [for s in normalizedServices: {
  name: '${s.code}-${productPostfix}-SUB-01'
  productId: '${s.code}-${productPostfix}'
  keyVaultApiKeySecretName: toLower(replace(s.apiKeySecretName, '_', '-'))
  keyVaultEndpointSecretName: toLower(replace(s.endpointSecretName, '_', '-'))
}]

// Intentionally omit emitting keys at runtime to keep template start-time evaluable. Keys are stored in Key Vault.
