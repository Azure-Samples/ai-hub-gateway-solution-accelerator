param vnetId string
param apimName string
param apimResourceGroup string
param tags object = {}

// Existing APIM resource to read private IP
resource apim 'Microsoft.ApiManagement/service@2021-08-01' existing = {
  name: apimName
  scope: resourceGroup(apimResourceGroup)
}

// Private DNS zone for internal APIM resolution
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'azure-api.net'
  location: 'global'
  tags: union(tags, { 'azd-service-name': 'azure-api.net' })
}

// Link VNet to the APIM DNS zone
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'link-${uniqueString(vnetId)}'
  parent: dnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// A record for the APIM gateway hostname: <apimName>.azure-api.net -> private IP
resource apimGatewayRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: apimName
  parent: dnsZone
  dependsOn: [ vnetLink ]
  properties: {
    aRecords: [
      {
        ipv4Address: apim.properties.privateIPAddresses[0]
      }
    ]
    ttl: 3600
  }
}

output dnsZoneName string = dnsZone.name
