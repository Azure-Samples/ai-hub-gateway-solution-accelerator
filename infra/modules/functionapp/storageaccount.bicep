param storageAccountName string
param location string = resourceGroup().location
param tags object = {}
param functionAppManagedIdentityName string

// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-owner
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

resource functionAppmanagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  name: functionAppManagedIdentityName
}

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'


resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  tags: union(tags, { 'azd-service-name': storageAccountName })
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
}

resource storageAccountFunctionAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppmanagedIdentity.name, storageBlobDataOwnerRoleId)
  properties: {
    principalId: functionAppmanagedIdentity.properties.principalId
    roleDefinitionId: storageBlobDataOwnerRoleId
  }
  scope: storageAccount
}

output storageAccountName string = storageAccount.name
