param location string
param resourcePrefix string
param hubAddressPrefix string
param clientAddressPrefix string
param tenantId string
param audience string
param gatewaySku string
param publicIpZones string[]
param deployDnsResolver bool
param tags object

var gatewaySubnetPrefix = cidrSubnet(hubAddressPrefix, 27, 0)
var resolverSubnetPrefix = cidrSubnet(hubAddressPrefix, 28, 2)
var resolverIp = cidrHost(resolverSubnetPrefix, 4)

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${resourcePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [hubAddressPrefix]
    }
    // Keep Azure-provided DNS on this VNet to avoid a resolver forwarding loop.
    subnets: concat([
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
    ], deployDnsResolver ? [
      {
        name: 'snet-dns-inbound'
        properties: {
          addressPrefix: resolverSubnetPrefix
          delegations: [
            {
              name: 'dns-resolver'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ] : [])
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${resourcePrefix}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: publicIpZones
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource gateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: '${resourcePrefix}-gateway'
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    activeActive: false
    enableBgp: false
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
    ipConfigurations: [
      {
        name: 'gateway-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/GatewaySubnet'
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [clientAddressPrefix]
      }
      vpnClientProtocols: ['OpenVPN']
      vpnAuthenticationTypes: ['AAD']
      aadTenant: uri(environment().authentication.loginEndpoint, tenantId)
      aadAudience: audience
      aadIssuer: 'https://sts.windows.net/${tenantId}/'
    }
  }
}

resource resolver 'Microsoft.Network/dnsResolvers@2022-07-01' = if (deployDnsResolver) {
  name: '${resourcePrefix}-dns'
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource inbound 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = if (deployDnsResolver) {
  parent: resolver
  name: 'inbound'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Static'
        privateIpAddress: resolverIp
        subnet: {
          id: '${vnet.id}/subnets/snet-dns-inbound'
        }
      }
    ]
  }
}

output vnetName string = vnet.name
output vnetId string = vnet.id
output gatewayId string = gateway.id
output gatewayName string = gateway.name
output dnsResolverInboundIp string = deployDnsResolver ? resolverIp : ''
