@description('Name of the Public IP resource')
param name string

@description('Location for the Public IP resource')
param location string = resourceGroup().location

@description('Optional DNS label for the Public IP (creates FQDN)')
param dnsLabel string = ''

@description('IP version for the Public IP')
@allowed([
  'IPv4'
  'IPv6'
])
param ipVersion string = 'IPv4'

@description('Zone configuration mode for the Public IP')
@allowed([
  'auto'           // zone-redundant if supported; else non-zonal (dynamic detection)
  'zoneRedundant'  // force zone-redundant (fail if region lacks zones)
  'accelerator'    // force zones ['1','2'] - high availability with broad regional support
  'nonZonal'       // force omit zones
  'zonal'          // force single zone (see selectedZone)
])
param zoneMode string = 'accelerator'

@description('Specific zone to use when zoneMode is zonal')
@allowed([
  '1'
  '2'
  '3'
])
param selectedZone string = '1'

@description('Idle timeout in minutes for the Public IP')
@minValue(4)
@maxValue(30)
param idleTimeoutInMinutes int = 4

@description('Tags to apply to the Public IP resource')
param tags object = {}

// Static zones logic without provider-based discovery (for compatibility)
var supportedZones = [ '1', '2', '3' ]

// Create the Public IP resource
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: name
  location: location
  tags: union(tags, {
    'azd-service-name': name
    'zone-mode': zoneMode
    'zone-redundant': length(supportedZones) > 0 ? 'true' : 'false'
  })
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  // Force two zones for high availability
  zones: ['1', '2']
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: ipVersion
    idleTimeoutInMinutes: idleTimeoutInMinutes
    dnsSettings: empty(dnsLabel) ? null : {
      domainNameLabel: dnsLabel
    }
  }
}

// Outputs
@description('Resource ID of the Public IP')
output publicIpId string = publicIp.id

@description('IP address of the Public IP')
output publicIpAddress string = publicIp.properties.ipAddress

@description('FQDN of the Public IP (if dnsLabel provided)')
output publicIpFqdn string = empty(dnsLabel) ? '' : publicIp.properties.dnsSettings.fqdn

