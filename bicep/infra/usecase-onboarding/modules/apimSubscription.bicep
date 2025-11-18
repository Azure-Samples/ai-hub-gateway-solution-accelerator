@description('Existing APIM service name')
param apimName string
@description('Subscription display name')
param subscriptionDisplayName string
@description('Subscription name (resource name). e.g., OAI-HR-InternalAssistant-DEV-SUB-01')
param subscriptionName string
@description('Scope like /products/{productId}')
param scope string
@description('Optional owner userId path in APIM like /users/1')
param ownerId string = ''
@description('Initial subscription state')
@allowed([ 'active', 'submitted', 'rejected', 'cancelled', 'suspended', 'expired' ])
param state string = 'active'

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource sub 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  name: subscriptionName
  parent: apim
  properties: {
    displayName: subscriptionDisplayName
    scope: scope
    ownerId: empty(ownerId) ? null : ownerId
    state: state
  }
}

output subscriptionId string = sub.name
output subscriptionResourceId string = sub.id
@secure()
output primaryKey string = sub.listSecrets().primaryKey
@secure()
output secondaryKey string = sub.listSecrets().secondaryKey
