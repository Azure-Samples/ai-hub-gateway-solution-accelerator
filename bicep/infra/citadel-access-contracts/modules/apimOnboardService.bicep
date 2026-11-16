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

@description('Entra tenantId/objectId pairs explicitly authorized to use THIS subscription. Entries automatically require JWT for this Product. Existing JWT-required Products without bindings fail closed.')
param jwtAuthorizedCallers array = []

@description('Additional existing Product-scoped APIM subscriptions and their approved callers: [{ subscriptionId, callers: [{ tenantId, objectId }] }]. Allows independent subscribers to the same Product without sharing quota ownership.')
param jwtAdditionalSubscriptionBindings array = []

@description('Subscription name (resource name) e.g., <productId>-SUB-01')
param subscriptionName string
@description('Subscription display name')
param subscriptionDisplayName string

@description('Optional explicit subscription primary key. When set (e.g., mirroring a contract onto an additional APIM gateway), the subscription is created with this exact primary key so keys stay consistent across gateways. When empty (default), APIM auto-generates the key (existing behavior).')
@secure()
param explicitPrimaryKey string = ''

@description('Optional explicit subscription secondary key. When set (e.g., mirroring a contract onto an additional APIM gateway), the subscription is created with this exact secondary key so BOTH keys stay consistent across gateways (required for zero-downtime rotation). When empty (default), APIM auto-generates the key (existing behavior).')
@secure()
param explicitSecondaryKey string = ''

@description('Which subscription key is the ACTIVE key handed to consumers (Key Vault / Foundry). true = primary (default), false = secondary. Used to select the active key output and to determine which key is the NON-active key eligible for rotation.')
param usePrimaryKey bool = true

@description('When true, the NON-active key slot is overwritten with rotationKey, invalidating the old value (declarative key regeneration). Only applied on the primary gateway subscription (when no explicit keys are supplied). Default false = keys are preserved.')
param keyRotationEnabled bool = false

@description('Fresh key value used to overwrite the NON-active key slot when keyRotationEnabled is true. Supplied by the caller (typically derived from newGuid()).')
@secure()
param rotationKey string = ''

var defaultPolicy = '<policies>\n  <inbound>\n    <base />\n    <rate-limit calls="60" renewal-period="60" />\n    <check-header name="Ocp-Apim-Subscription-Key" failed-check-httpcode="401" failed-check-error-message="Subscription key required" />\n  </inbound>\n  <backend>\n    <base />\n  </backend>\n  <outbound>\n    <base />\n  </outbound>\n  <on-error>\n    <base />\n  </on-error>\n</policies>'

// Every subscriber to this Product must be bound to the exact subscription ID
// resolved by APIM. This includes optional existing Product-scoped subscriptions.
// Reject ambiguous duplicate IDs, rather than selecting the first matching grant.
var ownJwtSubscriptionBinding = empty(jwtAuthorizedCallers) ? [] : [
  {
    subscriptionId: subscriptionName
    callers: jwtAuthorizedCallers
  }
]
var allJwtSubscriptionBindings = concat(ownJwtSubscriptionBinding, jwtAdditionalSubscriptionBindings)
var jwtBindingIds = map(allJwtSubscriptionBindings, binding => toLower(binding.subscriptionId))
var validatedJwtSubscriptionBindings = length(union(jwtBindingIds, [])) == length(jwtBindingIds)
  ? allJwtSubscriptionBindings
  : fail('Duplicate subscription ID in JWT caller bindings')

// The Product policy runs before the API-level security-handler. Append bindings
// and mandatory JWT flag after custom policy statements to prevent override.
// Base64 embeds JSON safely in the APIM XML expression (no caller-supplied XML).
var bindingVariablesXml = '<set-variable name="jwtSubscriptionBindingsJson" value="@(Encoding.UTF8.GetString(Convert.FromBase64String(&quot;${base64(string(validatedJwtSubscriptionBindings))}&quot;)))" /><set-variable name="jwtRequired" value="true" />'
var sourcePolicyXml = empty(productPolicyXml) ? defaultPolicy : productPolicyXml
var securedProductPolicyXml = empty(validatedJwtSubscriptionBindings)
  ? sourcePolicyXml
  : (contains(sourcePolicyXml, '</inbound>')
      ? replace(sourcePolicyXml, '</inbound>', '${bindingVariablesXml}</inbound>')
      : fail('Subscription-bound JWT Product policies require a standard </inbound> element'))

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
    value: securedProductPolicyXml
  }
}

resource sub 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  name: subscriptionName
  parent: apim
  properties: union(
    {
      displayName: subscriptionDisplayName
      scope: product.id
      state: 'active'
    },
    // Explicit keys keep additional gateways in sync with the primary gateway (both keys mirrored).
    empty(explicitPrimaryKey) ? {} : { primaryKey: explicitPrimaryKey },
    empty(explicitSecondaryKey) ? {} : { secondaryKey: explicitSecondaryKey },
    // Declarative rotation: overwrite the NON-active key with a fresh value on the primary gateway
    // (skipped when explicit keys are supplied, i.e. additional gateways receive already-rotated values).
    (keyRotationEnabled && empty(explicitPrimaryKey) && empty(explicitSecondaryKey) && !empty(rotationKey))
      ? (usePrimaryKey ? { secondaryKey: rotationKey } : { primaryKey: rotationKey })
      : {}
  )
}

// Resolve every granted API's path (ordered same as apiNames) for per-asset endpoint construction
resource apis 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' existing = [for apiName in apiNames: {
  name: apiName
  parent: apim
}]

output productName string = product.name
output subscriptionNameOut string = sub.name
@secure()
output subscriptionPrimaryKey string = sub.listSecrets().primaryKey
@secure()
output subscriptionSecondaryKey string = sub.listSecrets().secondaryKey
@secure()
output subscriptionActiveKey string = usePrimaryKey ? sub.listSecrets().primaryKey : sub.listSecrets().secondaryKey
// First API path (backward compatible single-endpoint consumers)
output apiPath string = apis[0].properties.path
// All granted API paths, aligned to apiNames order (per-asset endpoint publishing)
output apiPaths array = [for (apiName, i) in apiNames: apis[i].properties.path]
