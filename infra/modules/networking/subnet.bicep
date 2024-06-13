param name string
param properties object
param vnetName string
param vnetRG string

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetRG)
}


resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' = {
  name: '${vnet.name}/${name}'
  properties: properties
}
