param name string
param vnetRG string
param apimSubnetName string
param privateEndpointSubnetName string
param functionAppSubnetName string
param appGatewaySubnetName string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: name
  scope: resourceGroup(vnetRG)
}

resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: apimSubnetName
  parent: virtualNetwork
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: privateEndpointSubnetName
  parent: virtualNetwork
}

resource functionAppSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: functionAppSubnetName
  parent: virtualNetwork
}

resource appGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: appGatewaySubnetName
  parent: virtualNetwork
}

output virtualNetworkId string = virtualNetwork.id
output vnetName string = virtualNetwork.name
output apimSubnetName string = apimSubnet.name
output apimSubnetId string = '${virtualNetwork.id}/subnets/${apimSubnetName}'
output privateEndpointSubnetName string = privateEndpointSubnet.name
output privateEndpointSubnetId string = '${virtualNetwork.id}/subnets/${privateEndpointSubnetName}'
output functionAppSubnetName string = functionAppSubnet.name
output functionAppSubnetId string = '${virtualNetwork.id}/subnets/${functionAppSubnetName}'
output appGatewaySubnetName string = appGatewaySubnet.name
output appGatewaySubnetId string = '${virtualNetwork.id}/subnets/${appGatewaySubnetName}'
output location string = virtualNetwork.location
output vnetRG string = vnetRG
