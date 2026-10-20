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
param apimPrincipalId string

@description('AI Foundry project name')
param foundryProjectName string = 'citadel-governance-project'

@description('The full connection string for Application Insights')
@secure()
param appInsightsConnectionString string = ''

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
//    NETWORKING PARAMETERS
// ------------------

@description('Name of the Virtual Network')
param vNetName string

@description('Location of the Virtual Network')
param vNetLocation string

@description('Name of the private endpoint subnet')
param privateEndpointSubnetName string

@description('Resource group containing the Virtual Network')
param vNetRG string

@description('Base name for AI Foundry private endpoints. Leave blank to use default naming.')
param aiFoundryPrivateEndpointBaseName string = ''

@description('DNS zone names for AI Foundry private endpoints (supports all required zones)')
param aiServicesDnsZoneNames array = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

@description('Resource group containing the DNS zones (legacy - used when dnsZoneResourceId is not provided)')
param dnsZoneRG string = ''

@description('Subscription ID containing the DNS zones (legacy - used when dnsZoneResourceIds is not provided)')
param dnsSubscriptionId string = ''

@description('Array of direct DNS zone resource IDs (preferred over dnsZoneRG/dnsSubscriptionId). Order should match aiServicesDnsZoneNames.')
param dnsZoneResourceIds array = []

@description('Enable network injection for AI Foundry resources (requires additional configuration)')
param networkInjectionEnabled bool = false

@description('Name of the subnet to use for AI Foundry network injection (required if network injection is enabled)')
param agentSubnetName string = ''
// ------------------
//    KEY VAULT PARAMETERS
// ------------------

@description('Key Vault resource ID for connection')
param keyVaultId string = ''

@description('Key Vault URI for connection')
param keyVaultUri string = ''

// ------------------
//    VARIABLES
// ------------------

var azureRoles = loadJsonContent('../azure-roles.json')
var cognitiveServicesUserRoleDefinitionID = resourceId('Microsoft.Authorization/roleDefinitions', azureRoles.CognitiveServicesUser)

// Get existing VNet and subnet for private endpoint
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: vNetName
  scope: resourceGroup(vNetRG)
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: privateEndpointSubnetName
  parent: vnet
}

resource agentSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = if (networkInjectionEnabled) {
  name: agentSubnetName
  parent: vnet
}


// ------------------
//    RESOURCES
// ------------------
resource foundryResources 'Microsoft.CognitiveServices/accounts@2026-01-15-preview' = [for (config, i) in aiServicesConfig: {
  name: !empty(config.name) ? config.name : 'aif-${resourceToken}-${i}'
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
    customSubDomainName: toLower(!empty(config.customSubDomainName) ? config.customSubDomainName : (!empty(config.name) ? config.name : 'aif-${resourceToken}-${i}'))

    disableLocalAuth: disableKeyAuth

    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    // Per-instance network injection: each entry in aiServicesConfig may set
    // `networkInjectionEnabled: true|false`. When the property is omitted, the
    // module-level `networkInjectionEnabled` flag (default) applies. Injection is
    // only attempted when the agent subnet is available.
    networkInjections: ((networkInjectionEnabled && (config.?networkInjectionEnabled ?? true)) ? [
      {
        scenario: 'agent'
        subnetArmId: agentSubnet.id
        useMicrosoftManagedNetwork: false
      }
    ] : null)
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
    description: 'Citadel Governance Hub default project for AI Evaluation default LLMs'
  }
  dependsOn: [
    privateEndpoints
  ]
}]


var aiProjectManagerRoleDefinitionID = 'eadc314b-1a2d-4efa-be10-5d325db5065e' 
resource aiProjectManagerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (config, i) in aiServicesConfig: {
    scope: foundryResources[i]
    name: guid(subscription().id, resourceGroup().id, foundryResources[i].name, aiProjectManagerRoleDefinitionID)
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

resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/connections@2025-06-01' = [for (config, i) in aiServicesConfig: if (length(appInsightsId) > 0 && length(appInsightsConnectionString) > 0) {
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
      key: appInsightsConnectionString
    }    
  }
}]

// Key Vault connection for AI Foundry resources
// resource keyVaultConnection 'Microsoft.CognitiveServices/accounts/connections@2025-06-01' = [for (config, i) in aiServicesConfig: if (!empty(keyVaultId) && !empty(keyVaultUri)) {
//   parent: foundryResources[i]
//   name: 'keyvault-connection'
//   properties: {
//     authType: 'AccountManagedIdentity'
//     category: 'AzureKeyVault'
//     target: keyVaultUri
//     useWorkspaceManagedIdentity: true
//     isSharedToAll: true
//     sharedUserList: []
//     peRequirement: 'NotRequired'
//     peStatus: 'NotApplicable'
//     metadata: {
//       ApiType: 'Azure'
//       ResourceId: keyVaultId
//     }
//   }
// }]

resource roleAssignmentCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (config, i) in aiServicesConfig: {
  scope: foundryResources[i]
  name: guid(subscription().id, resourceGroup().id, foundryResources[i].name, cognitiveServicesUserRoleDefinitionID, apimPrincipalId)
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
    modelsConfig: filter(modelsConfig, model => !contains(model, 'aiservice') || model.aiservice == foundryResources[i].name )
  }
  dependsOn: [
    privateEndpoints
    aiProject
    aiProjectManagerRoleAssignment
    roleAssignmentCognitiveServicesUser
    appInsightsConnection
    diagnosticSettings
  ]
}]

// Private endpoints for AI Foundry instances (with all 3 required DNS zones)
module privateEndpoints '../networking/private-endpoint-multi-dns.bicep' = [for (config, i) in aiServicesConfig: {
  name: 'pe-${foundryResources[i].name}'
  params: {
    name: !empty(aiFoundryPrivateEndpointBaseName) ? '${aiFoundryPrivateEndpointBaseName}-${i}' : '${foundryResources[i].name}-pe'
    privateLinkServiceId: foundryResources[i].id
    groupIds: [
      'account'
    ]
    dnsZoneNames: aiServicesDnsZoneNames
    location: vNetLocation
    privateEndpointSubnetId: subnet.id
    dnsZoneRG: dnsZoneRG
    dnsSubId: dnsSubscriptionId
    dnsZoneResourceIds: dnsZoneResourceIds
    tags: tags
  }
  dependsOn: []
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

output aiFoundryPrincipalIds array = [for (config, i) in aiServicesConfig: foundryResources[i].identity.principalId]
