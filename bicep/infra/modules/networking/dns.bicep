param name string
param tags object = {}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: name
  location: 'global'
  tags: union(tags, { 'azd-service-name': name })
}

output privateDnsZoneName string = privateDnsZone.name
