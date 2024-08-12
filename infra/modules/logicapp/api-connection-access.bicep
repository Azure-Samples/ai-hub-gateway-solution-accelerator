param connectionName string
param accessPolicyName string
param identityPrincipalId string
param location string = resourceGroup().location

resource logicAppConnectionExisting 'Microsoft.Web/connections@2016-06-01' existing = {
  name: connectionName
  resource accessPolicy 'accessPolicies@2016-06-01' = {
    name: accessPolicyName
    location: location
    properties: {
      principal: {
        type: 'ActiveDirectory'
        identity: {
          tenantId: subscription().tenantId
          objectId: identityPrincipalId
        }
      }
    }
  }
}
