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

param apicServiceName string
param apicWorkspaceName string = 'default'
param environmentName string
param mcpLifecycleStage string = 'development'

param mcpVersionName string = '1-0-0'
param mcpVersionDisplayName string = '1.0.0'
param mcpDefinitionName string = '${mcpApiName}-definition'
param mcpDefinitionDisplayName string = '${mcpDisplayName} Definition'
param mcpDefinitionDescription string = '${mcpDisplayName} Definition for version ${mcpVersionName}'

param mcpDeploymentName string = '${mcpApiName}-deployment'
param mcpDeploymentDisplayName string = '${mcpDisplayName} Deployment'
param mcpDeploymentDescription string = '${mcpDisplayName} Deployment for version ${mcpVersionName} and environment ${environmentName}'

param customProperties object = {}

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
//    API Center Onboarding
// ------------------

resource apiCenterService 'Microsoft.ApiCenter/services@2024-06-01-preview' existing = {
  name: apicServiceName
}

resource apiCenterWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-06-01-preview' existing = {
  parent: apiCenterService
  name: apicWorkspaceName
}

// Add MCP to API Center
resource apiCenterMCP 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = {
  parent: apiCenterWorkspace
  name: mcpApiName
  properties: {
    title: mcpDisplayName
    kind: 'mcp'
    lifecycleState: mcpLifecycleStage
    externalDocumentation: [
      {
        description: mcpDescription
        title: mcpDisplayName
        url: 'https://example.com/mcp-docs'
      }
    ]
    contacts: []
    customProperties: customProperties
    summary: mcpDescription
    description: mcpDescription
  }
}

// Add API Version resources
resource mcpVersion 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview' = {
  parent: apiCenterMCP
  name: mcpVersionName
  properties: {
    title: mcpVersionDisplayName
    lifecycleStage: mcpLifecycleStage
  }
}

// Add API Definition resource
resource mcpDefinition 'Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview' = {
  parent: mcpVersion
  name: mcpDefinitionName
  properties: {
    description: mcpDefinitionDescription
    title: mcpDefinitionDisplayName
  }
}

// Add API Deployment resource
resource mcpDeployment 'Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview' = {
  parent: apiCenterMCP
  name: mcpDeploymentName
  properties: {
    description: mcpDeploymentDescription
    title: mcpDeploymentDisplayName
    environmentId: '/workspaces/default/environments/${environmentName}'
    definitionId: '/workspaces/${apiCenterWorkspace.name}/apis/${apiCenterMCP.name}/versions/${mcpVersion.name}/definitions/${mcpDefinition.name}'
    state: 'active'
    server: {
      runtimeUri: [
        '${apim.properties.gatewayUrl}/${mcpPath}'
      ]
    }
  }
}

// ------------------
//    OUTPUTS
// ------------------

output name string = mcp.name
output endpoint string = '${apim.properties.gatewayUrl}/${mcpPath}/mcp'
