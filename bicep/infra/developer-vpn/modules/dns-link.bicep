param zoneName string
param linkName string
param hubVnetId string
param tags object

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: zoneName
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: linkName
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnetId
    }
  }
}
