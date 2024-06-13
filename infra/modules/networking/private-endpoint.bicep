param name string
param privateLinkServiceId string
param groupIds array
param dnsZoneName string
param location string

param privateEndpointSubnetId string
param dnsZoneRG string
param dnsSubId string


resource privateEndpointDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: dnsZoneName
  scope: resourceGroup(dnsSubId ,dnsZoneRG)
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-09-01' = {
  name: name
  location: location
  dependsOn: [
    privateEndpointDnsZone
  ]
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-09-01' = {
  parent: privateEndpoint
  name: 'privateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'default'
        properties: {
          privateDnsZoneId: privateEndpointDnsZone.id
        }
      }
    ]
  }
}

output privateEndpointName string = privateEndpoint.name
