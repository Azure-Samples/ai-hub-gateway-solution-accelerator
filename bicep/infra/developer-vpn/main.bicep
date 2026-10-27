targetScope = 'subscription'

@description('Dedicated, new resource group for developer VPN resources. Must not be the primary deployment resource group.')
param vpnResourceGroupName string

@description('Azure region supporting VPN Gateway and DNS Private Resolver.')
param location string

@description('Full resource ID of the existing governance hub VNet, including BYO VNets in another resource group or subscription.')
param primaryVnetId string

@description('Prefix for resources inside the dedicated VPN resource group.')
@minLength(1)
@maxLength(40)
param resourcePrefix string = 'citadel-vpn'

@description('Non-overlapping private IPv4 CIDR, /26 or larger. Validate against primary, peered, client pool and developer LAN/corporate networks.')
param hubAddressPrefix string = '10.171.0.0/24'

@description('Non-overlapping IPv4 pool assigned to P2S clients.')
param clientAddressPrefix string = '172.30.240.0/24'

@description('Microsoft Entra tenant used to authenticate VPN clients.')
param tenantId string = tenant().tenantId

@description('Microsoft-registered Azure VPN Client audience or an explicitly configured custom audience. Azure Public cloud only.')
param audience string = 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'

@allowed(['VpnGw1AZ', 'VpnGw2AZ', 'VpnGw3AZ'])
param gatewaySku string = 'VpnGw1AZ'

@description('Public IP availability zones. Use [] for a regional IP; use supported zone numbers for a zone-redundant deployment.')
param publicIpZones string[] = []

@description('Deploy DNS Private Resolver with a static inbound endpoint. No outbound endpoint or forwarding ruleset is needed for this scenario.')
param deployDnsResolver bool = true

@description('Add resolution-only links from existing primary private DNS zones to the VPN hub.')
param linkPrivateDnsZones bool = true

@description('Full IDs of existing private DNS zones. The notebook discovers primary-owned, primary-linked and private-endpoint zone-group zones.')
param privateDnsZoneIds string[] = []

param tags object = {}

var ownershipTags = union(tags, {
  'managed-by': 'citadel-developer-vpn'
  'primary-vnet-id': primaryVnetId
})
var primaryParts = split(primaryVnetId, '/')

resource vpnGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: vpnResourceGroupName
  location: location
  tags: ownershipTags
}

module hub './modules/hub.bicep' = {
  scope: vpnGroup
  params: {
    location: location
    resourcePrefix: resourcePrefix
    hubAddressPrefix: hubAddressPrefix
    clientAddressPrefix: clientAddressPrefix
    tenantId: tenantId
    audience: audience
    gatewaySku: gatewaySku
    publicIpZones: publicIpZones
    deployDnsResolver: deployDnsResolver
    tags: ownershipTags
  }
}

module hubPeering './modules/peering.bicep' = {
  scope: vpnGroup
  params: {
    vnetName: hub.outputs.vnetName
    remoteVnetId: primaryVnetId
    peeringName: '${resourcePrefix}-to-primary'
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

// The reverse peering must wait until the hub gateway and its transit peering exist.
module primaryPeering './modules/peering.bicep' = {
  scope: resourceGroup(primaryParts[2], primaryParts[4])
  params: {
    vnetName: primaryParts[8]
    remoteVnetId: hub.outputs.vnetId
    peeringName: '${resourcePrefix}-to-vpn'
    allowGatewayTransit: false
    useRemoteGateways: true
  }
  dependsOn: [hubPeering]
}

@batchSize(1)
module dnsLinks './modules/dns-link.bicep' = [for zoneId in privateDnsZoneIds: if (linkPrivateDnsZones) {
  scope: resourceGroup(split(zoneId, '/')[2], split(zoneId, '/')[4])
  params: {
    zoneName: split(zoneId, '/')[8]
    linkName: '${resourcePrefix}-${uniqueString(hub.outputs.vnetId)}'
    hubVnetId: hub.outputs.vnetId
    tags: ownershipTags
  }
}]

output vpnResourceGroupId string = vpnGroup.id
output hubVnetId string = hub.outputs.vnetId
output gatewayId string = hub.outputs.gatewayId
output gatewayName string = hub.outputs.gatewayName
output dnsResolverInboundIp string = hub.outputs.dnsResolverInboundIp
output primaryPeeringName string = '${resourcePrefix}-to-vpn'
output hubPeeringName string = '${resourcePrefix}-to-primary'
output dnsLinkName string = '${resourcePrefix}-${uniqueString(hub.outputs.vnetId)}'
output linkedPrivateDnsZoneIds string[] = linkPrivateDnsZones ? privateDnsZoneIds : []
