@description('Name of the Application Gateway')
param appGatewayName string

@description('Azure location where the Application Gateway will be deployed')
param location string = resourceGroup().location

@description('Resource ID of the subnet where Application Gateway will be deployed')
@minLength(1)
param subnetId string

@description('Resource ID of the public IP for the Application Gateway frontend')
@minLength(1)
param publicIpId string

@description('Resource ID of the WAF policy to associate with the Application Gateway')
@minLength(1)
param wafPolicyId string

@description('APIM internal gateway hostname for health probes and backend HTTP settings')
@minLength(1)
param apimGatewayHostname string

@description('Backend address type for APIM')
@allowed([
  'ip'
  'fqdn'
])
param backendType string = 'ip'

@description('APIM private IP address (required when backendType is ip)')
param apimPrivateIp string = ''

@description('APIM backend FQDN (required when backendType is fqdn)')
@minLength(1)
param apimBackendFqdn string

// Note: Identity, certificates, and custom domains removed for Azure-generated DNS simplicity

@description('Application Gateway capacity (number of instances)')
@minValue(1)
@maxValue(32)
param capacity int = 2

@description('Enable autoscaling for the Application Gateway')
param enableAutoscaling bool = false

@description('Minimum capacity when autoscaling is enabled')
@minValue(0)
@maxValue(100)
param minCapacity int = 1

@description('Maximum capacity when autoscaling is enabled')
@minValue(2)
@maxValue(125)
param maxCapacity int = 10

@description('Request timeout in seconds for backend HTTP settings')
@minValue(1)
@maxValue(86400)
param requestTimeout int = 60

@description('Health probe interval in seconds')
@minValue(1)
@maxValue(86400)
param probeInterval int = 30

@description('Health probe timeout in seconds')
@minValue(1)
@maxValue(86400)
param probeTimeout int = 30

@description('Health probe unhealthy threshold')
@minValue(1)
@maxValue(20)
param probeUnhealthyThreshold int = 3

@description('Tags to apply to the Application Gateway')
param tags object = {}

// Validation
var validBackendConfig = (backendType == 'ip' && !empty(apimPrivateIp)) || (backendType == 'fqdn' && !empty(apimBackendFqdn))

// Resource naming
var gatewayIpConfigName = 'appGatewayIpConfig'
var publicFrontendName = 'publicFrontend'
var httpPortName = 'httpPort'
var apimPoolName = 'apimPool'
var apimProbeName = 'apimProbe'
var httpsSettingsName = 'httpsSettings'

// Metadata
metadata name = 'Application Gateway Module'
metadata description = 'Deploys Azure Application Gateway WAF_v2 with HTTP listener (Azure-generated DNS), WAF policy, and APIM backend integration'
metadata version = '1.0.0'

// Core Application Gateway resource
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: appGatewayName
  location: location
  tags: union(tags, {
    'azd-service-name': appGatewayName
    'Component': 'ApplicationGateway'
  })
  // Note: No identity needed for Azure-generated DNS
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: enableAutoscaling ? null : capacity
    }
    autoscaleConfiguration: enableAutoscaling ? {
      minCapacity: minCapacity
      maxCapacity: maxCapacity
    } : null
    firewallPolicy: {
      id: wafPolicyId
    }
    gatewayIPConfigurations: [
      {
        name: gatewayIpConfigName
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    // Frontend IP Configuration - Associates Public IP with Application Gateway
    frontendIPConfigurations: [
      {
        name: publicFrontendName
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
    // Frontend Ports - HTTP 80 for Azure-generated DNS
    frontendPorts: [
      {
        name: httpPortName
        properties: {
          port: 80
        }
      }
    ]
    // SSL Certificates - none needed for Azure-generated DNS
    sslCertificates: []
    // HTTP Listeners - single HTTP listener for Azure-generated DNS
    httpListeners: [
      {
        name: 'listener0'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, publicFrontendName)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, httpPortName)
          }
          protocol: 'Http'
        }
      }
    ]
    // Backend address pool - points to APIM (IP or FQDN)
    backendAddressPools: [
      {
        name: apimPoolName
        properties: {
          backendAddresses: backendType == 'ip' ? [
            {
              ipAddress: apimPrivateIp
            }
          ] : [
            {
              fqdn: apimBackendFqdn
            }
          ]
        }
      }
    ]
    // Health probe - APIM status endpoint with required Host header
    probes: [
      {
        name: apimProbeName
        properties: {
          protocol: 'Https'
          path: '/status-0123456789abcdef'
          host: apimGatewayHostname
          interval: probeInterval
          timeout: probeTimeout
          unhealthyThreshold: probeUnhealthyThreshold
          port: 443
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    // Backend HTTP settings - HTTPS 443 with Host header override and probe
    backendHttpSettingsCollection: [
      {
        name: httpsSettingsName
        properties: {
          port: 443
          protocol: 'Https'
          pickHostNameFromBackendAddress: false
          hostName: apimGatewayHostname
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, apimProbeName)
          }
          cookieBasedAffinity: 'Disabled'
          requestTimeout: requestTimeout
        }
      }
    ]
    // Routing rules - single rule for HTTP listener to APIM backend
    requestRoutingRules: [
      {
        name: 'rule0'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'listener0')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, apimPoolName)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, httpsSettingsName)
          }
        }
      }
    ]
  }
}

// Outputs (minimal approach following accelerator pattern)
output appGatewayName string = applicationGateway.name
output appGatewayFqdn string = '' // Not used for Azure-generated DNS - use Public IP FQDN instead
