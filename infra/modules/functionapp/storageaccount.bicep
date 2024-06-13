param storageAccountName string
param location string = resourceGroup().location
param tags object = {}

param functionAppManagedIdentityName string

//Networking
param vNetName string
param privateEndpointSubnetName string
param storageBlobDnsZoneName string
param storageBlobPrivateEndpointName string
param storageFileDnsZoneName string
param storageFilePrivateEndpointName string
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage-blob-data-owner
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')

// Use existing network/dns zone
param dnsZoneRG string
param dnsSubscriptionId string
param vNetRG string
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

// Get existing subnet
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

param functionContentShareName string

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
  properties: {
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-05-01' = {
  name: '${storageAccountName}/default/${functionContentShareName}'
  dependsOn: [
    storageAccount
  ]
}

resource storageAccountFunctionAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionAppmanagedIdentity.name, storageBlobDataOwnerRoleId)
  properties: {
    principalId: functionAppmanagedIdentity.properties.principalId
    roleDefinitionId: storageBlobDataOwnerRoleId
  }
  scope: storageAccount
}

module privateEndpointBlob '../networking/private-endpoint.bicep' = {
  name: '${storageAccountName}-blob-privateEndpoint'
  params: {
    groupIds: [
      'blob'
    ]
    dnsZoneName: storageBlobDnsZoneName
    name: storageBlobPrivateEndpointName
    privateLinkServiceId: storageAccount.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: subnet.id
    dnsSubId: dnsSubscriptionId
  }
}

module privateEndpointFile '../networking/private-endpoint.bicep' = {
  name: '${storageAccountName}-file-privateEndpoint'
  params: {
    groupIds: [
      'file'
    ]
    dnsZoneName: storageFileDnsZoneName
    name: storageFilePrivateEndpointName
    privateLinkServiceId: storageAccount.id
    location: location
    dnsZoneRG: dnsZoneRG
    privateEndpointSubnetId: subnet.id
    dnsSubId: dnsSubscriptionId
  }
}


output storageAccountName string = storageAccount.name
