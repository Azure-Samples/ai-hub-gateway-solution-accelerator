targetScope = 'resourceGroup'

@description('Existing VNet resource IDs to link to every zone. Leave empty to create zones before deploying the accelerator VNet, then redeploy with its ID.')
param virtualNetworkIds string[] = []

@description('Tags applied to private DNS zones and VNet links. Resource group tags are managed separately.')
param tags object = {}

// Match the accelerator's Azure public cloud zone names.
#disable-next-line no-hardcoded-env-urls
var storageDnsSuffix = 'core.windows.net'

var privateDnsZoneNames = {
  openai: 'privatelink.openai.azure.com'
  keyVault: 'privatelink.vaultcore.azure.net'
  monitor: 'privatelink.monitor.azure.com'
  eventHub: 'privatelink.servicebus.windows.net'
  cosmosDb: 'privatelink.documents.azure.com'
  storageBlob: 'privatelink.blob.${storageDnsSuffix}'
  storageFile: 'privatelink.file.${storageDnsSuffix}'
  storageTable: 'privatelink.table.${storageDnsSuffix}'
  storageQueue: 'privatelink.queue.${storageDnsSuffix}'
  cognitiveServices: 'privatelink.cognitiveservices.azure.com'
  apimGateway: 'privatelink.azure-api.net'
  aiServices: 'privatelink.services.ai.azure.com'
  redis: 'privatelink.redis.azure.net'
  logicApp: 'privatelink.azurewebsites.net'
  containerRegistry: 'privatelink.azurecr.io'
  aiSearch: 'privatelink.search.windows.net'
}

module privateDnsZones './private-dns-zone.bicep' = [for zone in items(privateDnsZoneNames): {
  name: 'central-dns-${zone.key}'
  params: {
    name: zone.value
    virtualNetworkIds: union(virtualNetworkIds, [])
    tags: tags
  }
}]

var zoneIds = [for zone in items(privateDnsZoneNames): {
  key: zone.key
  id: resourceId('Microsoft.Network/privateDnsZones', zone.value)
}]

@description('Resource ID of the independently managed DNS resource group.')
output resourceGroupId string = resourceGroup().id

@description('Pass this object directly to existingPrivateDnsZones in the accelerator main.bicepparam.')
output existingPrivateDnsZones object = toObject(zoneIds, zone => zone.key, zone => zone.id)

@description('Flat zone ID list, also usable by the optional developer-vpn deployment.')
output privateDnsZoneIds string[] = map(zoneIds, zone => zone.id)
