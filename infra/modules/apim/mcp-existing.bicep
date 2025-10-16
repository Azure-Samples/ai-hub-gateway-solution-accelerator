param apimServiceName string
param backendName string
param backendDescription string
param backendURL string
param mcpPolicyXml string = ''
param mcpApiName string = 'ms-learn-mcp'
param mcpDisplayName string = 'Microsoft Learn MCP'
param mcpDescription string = 'Microsoft Learn MCP Server'
param mcpPath string = 'ms-learn-mcp'
param mcpProtocols array = [
  'https'
]
param mcpSubscriptionRequired bool = false
param mcpTransportType string = 'streamable'

param appInsightsLoggerName string = 'appinsights-logger'

var defaultPolicyXml = loadTextContent('policies/mcp-default-policy.xml')
var effectivePolicyXml = empty(mcpPolicyXml) ? defaultPolicyXml : mcpPolicyXml

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

resource backend 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = {
  parent: apim
  name: backendName
  properties: {
    description: backendDescription
    url: backendURL
    protocol: 'http'
  }
}

resource mcp 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: mcpApiName
  properties: {
    type: 'mcp'
    displayName: mcpDisplayName
    description: mcpDescription
    subscriptionRequired: mcpSubscriptionRequired
    path: mcpPath
    protocols: mcpProtocols
    backendId: backend.name
    mcpPropperties: {
      transportType: mcpTransportType
    }
  }
}

resource mcpInsights 'Microsoft.ApiManagement/service/apis/diagnostics@2022-08-01' = {
  name: 'applicationinsights'
  parent: mcp
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    loggerId: resourceId(resourceGroup().name, 'Microsoft.ApiManagement/service/loggers', apimServiceName, appInsightsLoggerName)
    metrics: true
    verbosity: 'information'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
  }
}

resource policy 'Microsoft.ApiManagement/service/apis/policies@2021-12-01-preview' = {
  parent: mcp
  name: 'policy'
  properties: {
    value: effectivePolicyXml
    format: 'rawxml'
  }
}

// ------------------
//    OUTPUTS
// ------------------

output name string = mcp.name
output path string = mcpPath
output endpoint string = '${apim.properties.gatewayUrl}/${mcpPath}/mcp'
