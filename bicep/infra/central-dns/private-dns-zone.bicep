@description('Private DNS zone name.')
param name string

@description('Existing VNet resource IDs to link for resolution only.')
param virtualNetworkIds string[] = []

param tags object = {}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: name
  location: 'global'
  tags: tags
}

resource virtualNetworkLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for virtualNetworkId in virtualNetworkIds: {
  parent: privateDnsZone
  name: 'vnet-${uniqueString(virtualNetworkId)}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}]

output privateDnsZoneId string = privateDnsZone.id
