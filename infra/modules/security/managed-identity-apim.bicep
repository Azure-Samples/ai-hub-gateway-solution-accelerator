param name string
param location string = resourceGroup().location
param tags object = {}

var cognitiveServicesUserRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
var eventHubsDataSenderRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '2b629674-e913-4c01-ae53-ef4638d8f975')

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
}

// Assign the Cognitive Services User role to the user-defined managed identity used by workloads
resource cognitiveServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, cognitiveServicesUserRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinitionId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign to Azure Event Hubs Data Sender role to the user-defined managed identity used by workloads
resource eventHubsDataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, eventHubsDataSenderRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataSenderRoleDefinitionId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


output managedIdentityName string = managedIdentity.name
