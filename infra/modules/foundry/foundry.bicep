/**
 * @module openai-v2
 * @description This module defines the Azure Cognitive Services OpenAI resources using Bicep.
 * This is version 2 (v2) of the OpenAI Bicep module.
 */

// ------------------
//    PARAMETERS
// ------------------

// ------------------

// aiservices_config = [{"name": "foundry1", "location": "swedencentral"},
//                      {"name": "foundry2", "location": "eastus2"}]

// models_config = [{"name": "gpt-4o-mini", "publisher": "OpenAI", "version": "2024-07-18", "sku": "GlobalStandard", "capacity": 100},
//                  {"name": "DeepSeek-R1", "publisher": "DeepSeek", "version": "1", "sku": "GlobalStandard", "capacity": 1},
//                  {"name": "Phi-4", "publisher": "Microsoft", "version": "3", "sku": "GlobalStandard", "capacity": 1}]

// aiservices_config = [{"name": "foundry1", "location": "eastus"},
//                     {"name": "foundry2", "location": "swedencentral"},
//                     {"name": "foundry3", "location": "eastus2"}]

// models_config = [{"name": "gpt-4.1", "publisher": "OpenAI", "version": "2025-04-14", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry1"},
//                  {"name": "gpt-4.1-mini", "publisher": "OpenAI", "version": "2025-04-14", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry2"},
//                  {"name": "gpt-4.1-nano", "publisher": "OpenAI", "version": "2025-04-14", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry2"},
//                  {"name": "model-router", "publisher": "OpenAI", "version": "2025-05-19", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry3"},
//                  {"name": "gpt-5", "publisher": "OpenAI", "version": "2025-08-07", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry3"},
//                  {"name": "DeepSeek-R1", "publisher": "DeepSeek", "version": "1", "sku": "GlobalStandard", "capacity": 20, "aiservice": "foundry3"}]

@description('Configuration array for AI Foundry resources')
param aiServicesConfig array = []

@description('Configuration array for the model deployments')
param modelsConfig array = []

@description('Log Analytics Workspace Id')
param lawId string = ''

@description('APIM Pricipal Id')
param  apimPrincipalId string

@description('AI Foundry project name')
param  foundryProjectName string = 'citadel-governance-project'

@description('The instrumentation key for Application Insights')
@secure()
param appInsightsInstrumentationKey string = ''

@description('The resource ID for Application Insights')
param appInsightsId string = ''

@description('Controls public network access for the Cognitive Services account')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Disable key based authentication, enabling only Azure AD authentication')
param disableKeyAuth bool = false

@description('Main deployment resource token')
param resourceToken string = uniqueString(subscription().id, resourceGroup().id)

@description('Tags to be applied to all resources')
param tags object = {}

// ------------------
//    VARIABLES
// ------------------

var azureRoles = loadJsonContent('../azure-roles.json')
var cognitiveServicesUserRoleDefinitionID = resourceId('Microsoft.Authorization/roleDefinitions', azureRoles.CognitiveServicesUser)


// ------------------
//    RESOURCES
// ------------------
resource foundryResources 'Microsoft.CognitiveServices/accounts@2025-06-01' = [for config in aiServicesConfig: {
  name: !empty(config.name) ? config.name : 'aif-${resourceToken}'
  location: config.location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  properties: {
    // required to work in AI Foundry
    allowProjectManagement: true 
//!empty(languageServiceName) ? languageServiceName : '${abbrs.cognitiveServicesAccounts}language-${resourceToken}'
    customSubDomainName: toLower(!empty(config.customSubDomainName) ? config.customSubDomainName : (!empty(config.name) ? config.name : 'aif-${resourceToken}'))

    disableLocalAuth: disableKeyAuth

    publicNetworkAccess: publicNetworkAccess
  }  
}]

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = [for (config, i) in aiServicesConfig: {  
  #disable-next-line BCP334
  name: config.defaultProjectName != null ? config.defaultProjectName : foundryProjectName
  parent: foundryResources[i]
  location: config.location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Citadel Governance Hub central for AI Evaluation default LLMs project'
  }
}]


var aiProjectManagerRoleDefinitionID = 'eadc314b-1a2d-4efa-be10-5d325db5065e' 
resource aiProjectManagerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (config, i) in aiServicesConfig: {
    scope: foundryResources[i]
    name: guid(subscription().id, resourceGroup().id, config.name, aiProjectManagerRoleDefinitionID)
    properties: {
      roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', aiProjectManagerRoleDefinitionID)
      principalId: deployer().objectId
    }
}]


// https://learn.microsoft.com/azure/templates/microsoft.insights/diagnosticsettings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [for (config, i) in aiServicesConfig: if (lawId != '') {
  name: '${foundryResources[i].name}-diagnostics'
  scope: foundryResources[i]
  properties: {
    workspaceId: lawId != '' ? lawId : null
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}]

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-06-01' = [for (config, i) in aiServicesConfig: if (length(appInsightsId) > 0 && length(appInsightsInstrumentationKey) > 0) {
  parent: foundryResources[i]
  name: '${foundryResources[i].name}-appInsights-connection'
  properties: {
    authType: 'ApiKey'
    category: 'AppInsights'
    target: appInsightsId
    useWorkspaceManagedIdentity: false
    isSharedToAll: false
    sharedUserList: []
    peRequirement: 'NotRequired'
    peStatus: 'NotApplicable'
    metadata: {
      ApiType: 'Azure'
      ResourceId: appInsightsId
    }
    credentials: {
      key: appInsightsInstrumentationKey
    }    
  }
}]

resource roleAssignmentCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (config, i) in aiServicesConfig: {
  scope: foundryResources[i]
  name: guid(subscription().id, resourceGroup().id, config.name, cognitiveServicesUserRoleDefinitionID)
    properties: {
        roleDefinitionId: cognitiveServicesUserRoleDefinitionID
        principalId: apimPrincipalId
        principalType: 'ServicePrincipal'
    }
}]

module modelDeployments 'deployments.bicep' = [for (config, i) in aiServicesConfig: {
  name: take('models-${foundryResources[i].name}', 64)
  params: {
    cognitiveServiceName: foundryResources[i].name
    modelsConfig: modelsConfig
  }
}]


// ------------------
//    OUTPUTS
// ------------------

output extendedAIServicesConfig array = [for (config, i) in aiServicesConfig: {
  // Original openAIConfig properties
  name: config.name
  location: config.location
  priority: config.?priority
  weight: config.?weight
  // Additional properties
  cognitiveService: foundryResources[i]
  cognitiveServiceName: foundryResources[i].name
  endpoint: foundryResources[i].properties.endpoint
  foundryProjectEndpoint: 'https://${foundryResources[i].name}.services.ai.azure.com/api/projects/${aiProject[i].name}'
}]
