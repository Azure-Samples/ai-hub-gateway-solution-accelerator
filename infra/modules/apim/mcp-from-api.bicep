param apimServiceName string

param appInsightsLoggerName string = 'appinsights-logger'

param apiName string = 'default-api'
param operationNames array

param mcpPath string = 'default-mcp'
param mcpName string = 'default-mcp'
param mcpDisplayName string = 'default MCP'
param mcpDescription string = 'MCP for default data'

param mcpPolicyXml string = ''

// ------------------
//    VARIABLES
// ------------------

var defaultPolicyXml = loadTextContent('policies/mcp-default-policy.xml')
var effectivePolicyXml = empty(mcpPolicyXml) ? defaultPolicyXml : mcpPolicyXml

var logSettings = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens' , 'x-ratelimit-remaining-requests' ]
  body: { bytes: 8192 }
}


resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' existing =  {
  parent: apim
  name: apiName
}

resource operations 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = [for operationName in operationNames: {
  parent: api
  name: operationName
}]


resource mcp 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: mcpName
  properties: {
    type: 'mcp'
    displayName: mcpDisplayName
    description: mcpDescription
    subscriptionRequired: false
    path: mcpPath
    protocols: [
      'https'
    ]
    mcpTools: [for (operationName, i) in operationNames: {
      name: operations[i].name
      operationId: operations[i].id
      description: operations[i].properties.description
    }]
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
    frontend: {
      // request: logSettings
      // response: logSettings // Do not access the response body using the context.Response.Body variable within MCP server policies. Doing so triggers response buffering, which interferes with the streaming behavior required by MCP servers and may cause them to malfunction.
    }
    backend: {
      // request: logSettings
      // response: logSettings
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
