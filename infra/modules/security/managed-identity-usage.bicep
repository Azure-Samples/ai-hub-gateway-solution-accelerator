param name string
param location string = resourceGroup().location
param tags object = {}
param cosmosDbAccountName string

var docDbAccNativeContributorRoleDefinitionId = '00000000-0000-0000-0000-000000000002'
var eventHubsDataOwnerRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec')

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: cosmosDbAccountName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: guid(docDbAccNativeContributorRoleDefinitionId, managedIdentity.id, cosmosDbAccount.id)
  parent: cosmosDbAccount
  properties:{
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: '/${cosmosDbAccount.id}/sqlRoleDefinitions/${docDbAccNativeContributorRoleDefinitionId}'
    scope: cosmosDbAccount.id
  }
}

// Assign to Azure Event Hubs Data Owner role to the user-defined managed identity used by workloads
resource eventHubsDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, eventHubsDataOwnerRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataOwnerRoleDefinitionId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


output managedIdentityName string = managedIdentity.name
