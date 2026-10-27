using './main.bicep'

param vpnResourceGroupName = 'REPLACE'
param location = 'REPLACE'
param primaryVnetId = 'REPLACE'
param tenantId = 'REPLACE'

param resourcePrefix = 'citadel-vpn'
param hubAddressPrefix = '10.171.0.0/24'
param clientAddressPrefix = '172.30.240.0/24'
param gatewaySku = 'VpnGw1AZ'
param publicIpZones = []
param audience = 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'

param deployDnsResolver = true
param linkPrivateDnsZones = true
// Populate with full resource IDs discovered by the notebook, not copied zone names.
param privateDnsZoneIds = []
