targetScope = 'subscription'

@description('APIM resource coordinates')
param apim object

@description('Target Key Vault for storing endpoint and API key secrets')
param keyVault object

@description('Whether to use Azure Key Vault for storing secrets. If false, secrets will be output instead.')
param useTargetAzureKeyVault bool = true

@description('Use case descriptor used in naming: <code>-<businessUnit>-<useCaseName>-<environment>')
param useCase object

@description('Catalog of existing AI services in APIM as an object map by code. Example: { OAI: { apiResourceIds: ["/subscriptions/.../resourceGroups/.../providers/Microsoft.ApiManagement/service/<apimName>/apis/<apiName>"] } }')
param existingServices object

@description('Required AI services for this use case. Each item: { code: "OAI", endpointSecretName: "OAI_ENDPOINT", apiKeySecretName: "OAI_KEY", policyXml?: "<policies>...</policies>" }. If omitted or empty, the default policy at policies/default-ai-product-policy.xml is used.')
param services array

@description('Optional product terms shown to subscribers')
param productTerms string = ''

var productPostfix = '${useCase.businessUnit}-${useCase.useCaseName}-${useCase.environment}'

// // Normalize services by merging a default policyXml property
// var normalizedServices = [for s in services: union({ policyXml: '' }, s)]

// Default APIM product policy (applied when a service item does not provide policyXml)
var defaultProductPolicyXml = loadTextContent('./policies/default-ai-product-policy.xml')

resource apimRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription(apim.subscriptionId)
  name: apim.resourceGroupName
}

resource apimSvc 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  scope: apimRg
  name: apim.name
}

resource kvRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = if (useTargetAzureKeyVault) {
  scope: subscription(keyVault.subscriptionId)
  name: keyVault.resourceGroupName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (useTargetAzureKeyVault) {
  scope: kvRg
  name: keyVault.name
}

// Onboard each requested service into APIM
module onboard 'modules/apimOnboardService.bicep' = [for s in services: {
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
  productPolicyXml: s.policyXml == '' ? defaultProductPolicyXml : s.policyXml
    subscriptionName: '${s.code}-${productPostfix}-SUB-01'
    subscriptionDisplayName: '${s.code}-${productPostfix}-SUB-01'
  }
}]

// Write Key Vault secrets per service (only if useTargetAzureKeyVault is true)
// Create/update KV secrets; normalize names (Key Vault does not allow underscores)
module kvWrites 'modules/kvSecrets.bicep' = [for (s, i) in services: if (useTargetAzureKeyVault) {
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
output useKeyVault bool = useTargetAzureKeyVault

output products array = [for s in services: {
  productId: '${s.code}-${productPostfix}'
  displayName: '${s.code} ${useCase.businessUnit} ${useCase.useCaseName} ${useCase.environment}'
}]

// When using Key Vault, output references to the secret names in Key Vault
output subscriptions array = [for s in services: {
  name: '${s.code}-${productPostfix}-SUB-01'
  productId: '${s.code}-${productPostfix}'
  keyVaultApiKeySecretName: useTargetAzureKeyVault ? toLower(replace(s.apiKeySecretName, '_', '-')) : ''
  keyVaultEndpointSecretName: useTargetAzureKeyVault ? toLower(replace(s.endpointSecretName, '_', '-')) : ''
}]

// When NOT using Key Vault, output the actual endpoints and keys
// These outputs contain runtime values from the onboarding modules
// Note: When useTargetAzureKeyVault=false, the 'endpoints' output will contain sensitive API keys.
// Consumers should handle these values securely (e.g., store in environment variables, CI/CD secrets, etc.)
// The linter warning about secrets in outputs is intentional when Key Vault is disabled
#disable-next-line outputs-should-not-contain-secrets
output endpoints array = [for (s, i) in services: {
  code: s.code
  productId: '${s.code}-${productPostfix}'
  subscriptionName: '${s.code}-${productPostfix}-SUB-01'
  endpoint: useTargetAzureKeyVault ? '' : '${apimSvc.properties.gatewayUrl}/${onboard[i].outputs.apiPath}'
  // API key is marked secure in the module output, consumers should treat this as sensitive when not using Key Vault
  #disable-next-line outputs-should-not-contain-secrets
  apiKey: useTargetAzureKeyVault ? '' : string(onboard[i].outputs.subscriptionPrimaryKey)
}]
