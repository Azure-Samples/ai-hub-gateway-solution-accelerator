// ------------------
//    PARAMETERS
// ------------------

@description('API Center Service Name')
param apicServiceName string

@description('API Center Workspace Name')
param apicWorkspaceName string = 'default'

@description('API Center Environment Name (e.g., dev, staging, production)')
param environmentName string

@description('API/MCP Name (used as resource identifier)')
param apiName string

@description('API/MCP Display Name')
param apiDisplayName string

@description('API/MCP Description')
param apiDescription string

@description('API Type: api, graphql, grpc, soap, websocket, webhook, mcp')
param apiKind string = 'rest'

@description('Lifecycle Stage: design, development, testing, preview, production, deprecated, retired')
param lifecycleStage string = 'development'

@description('API Version Name (e.g., 1-0-0, v1, v2)')
param versionName string = '1-0-0'

@description('API Version Display Name (e.g., 1.0.0, v1, v2)')
param versionDisplayName string = '1.0.0'

@description('API Definition Name')
param definitionName string = '${apiName}-definition'

@description('API Definition Display Name')
param definitionDisplayName string = '${apiDisplayName} Definition'

@description('API Definition Description')
param definitionDescription string = '${apiDisplayName} Definition for version ${versionName}'

@description('API Deployment Name')
param deploymentName string = '${apiName}-deployment'

@description('API Deployment Display Name')
param deploymentDisplayName string = '${apiDisplayName} Deployment'

@description('API Deployment Description')
param deploymentDescription string = '${apiDisplayName} Deployment for version ${versionName} and environment ${environmentName}'

@description('API Gateway URL (e.g., https://apim-gateway.azure-api.net)')
param gatewayUrl string

@description('API Path (e.g., openai, weather-mcp, ms-learn-mcp)')
param apiPath string

@description('Custom Properties for API Center metadata')
param customProperties object = {}

@description('External Documentation URL')
param documentationUrl string = ''

@description('API Contacts')
param contacts array = []

@description('Deployment State: active, inactive')
param deploymentState string = 'active'

// ------------------
//    RESOURCES
// ------------------

resource apiCenterService 'Microsoft.ApiCenter/services@2024-06-01-preview' existing = {
  name: apicServiceName
}

resource apiCenterWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-06-01-preview' existing = {
  parent: apiCenterService
  name: apicWorkspaceName
}

// Register API in API Center
resource apiCenterAPI 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = {
  parent: apiCenterWorkspace
  name: apiName
  properties: {
    title: apiDisplayName
    kind: apiKind
    externalDocumentation: empty(documentationUrl) ? [] : [
      {
        description: apiDescription
        title: apiDisplayName
        url: documentationUrl
      }
    ]
    contacts: contacts
    customProperties: customProperties
    summary: apiDescription
    description: apiDescription
  }
}

// Register API Version
resource apiVersion 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview' = {
  parent: apiCenterAPI
  name: versionName
  properties: {
    title: versionDisplayName
    lifecycleStage: lifecycleStage
  }
}

// Register API Definition
resource apiDefinition 'Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-06-01-preview' = {
  parent: apiVersion
  name: definitionName
  properties: {
    description: definitionDescription
    title: definitionDisplayName
  }
}

// Register API Deployment
resource apiDeployment 'Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-06-01-preview' = {
  parent: apiCenterAPI
  name: deploymentName
  properties: {
    description: deploymentDescription
    title: deploymentDisplayName
    environmentId: '/workspaces/default/environments/${environmentName}'
    definitionId: '/workspaces/${apicWorkspaceName}/apis/${apiName}/versions/${versionName}/definitions/${definitionName}'
    state: deploymentState
    server: {
      runtimeUri: [
        '${gatewayUrl}/${apiPath}'
      ]
    }
  }
  dependsOn: [
    apiDefinition
  ]
}

// ------------------
//    OUTPUTS
// ------------------

@description('API Center API Name')
output apiCenterApiName string = apiCenterAPI.name

@description('API Center API Resource ID')
output apiCenterApiId string = apiCenterAPI.id

@description('API Center API Version Name')
output apiCenterApiVersionName string = apiVersion.name

@description('API Center API Definition Name')
output apiCenterApiDefinitionName string = apiDefinition.name

@description('API Center API Deployment Name')
output apiCenterApiDeploymentName string = apiDeployment.name
