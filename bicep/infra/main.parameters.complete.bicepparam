using './main.bicep'

/* 
 * AI Hub Gateway Solution Accelerator - Complete Parameters File
 * This file contains ALL available parameters with default values
 * Customize values as needed for your deployment
 */

// =============================================================================
// BASIC PARAMETERS
// =============================================================================

// Name of the environment (generates unique hash for resources)
param environmentName = 'citadel-dev'

// Primary Azure region for deployment
// Allowed: uaenorth, southafricanorth, westeurope, southcentralus, australiaeast, 
//          canadaeast, eastus, eastus2, francecentral, japaneast, northcentralus, 
//          swedencentral, switzerlandnorth, uksouth
param location = 'eastus'

// Tags applied to all resources
param tags = {
  'azd-env-name': 'citadel-dev'
  SecurityControl: 'Ignore'
  Environment: 'Development'
  Project: 'AI-Citadel-Gateway'
}

// =============================================================================
// RESOURCE NAMES (leave empty for auto-generated names)
// =============================================================================

param resourceGroupName = ''
param apimIdentityName = ''
param usageLogicAppIdentityName = ''
param apimServiceName = ''
param logAnalyticsName = ''
param apimApplicationInsightsDashboardName = ''
param funcAplicationInsightsDashboardName = ''
param foundryApplicationInsightsDashboardName = ''
param apimApplicationInsightsName = ''
param funcApplicationInsightsName = ''
param foundryApplicationInsightsName = ''
param eventHubNamespaceName = ''
param cosmosDbAccountName = ''
param usageProcessingLogicAppName = ''
param storageAccountName = ''
param languageServiceName = ''
param aiContentSafetyName = ''
param apicServiceName = ''
param aiFoundryResourceName = ''

// =============================================================================
// MONITORING PARAMETERS
// =============================================================================

// Log Analytics Workspace Configuration
param useExistingLogAnalytics = false
param existingLogAnalyticsName = ''  // Name of existing Log Analytics workspace
param existingLogAnalyticsRG = ''  // Resource group of existing workspace
param existingLogAnalyticsSubscriptionId = ''  // Subscription ID (leave empty for current subscription)

// =============================================================================
// NETWORKING PARAMETERS
// =============================================================================

// Virtual Network Configuration
param vnetName = ''
param useExistingVnet = false
param existingVnetRG = ''

// Subnet Names
param apimSubnetName = ''
param privateEndpointSubnetName = ''
param functionAppSubnetName = ''

// Network Security Groups and Route Tables
param apimNsgName = ''
param privateEndpointNsgName = ''
param functionAppNsgName = ''
param apimRouteTableName = ''

// VNet Address Spaces and Subnet Prefixes
param vnetAddressPrefix = '10.170.0.0/24'
param apimSubnetPrefix = '10.170.0.0/26'
param privateEndpointSubnetPrefix = '10.170.0.64/26'
param functionAppSubnetPrefix = '10.170.0.128/26'

// DNS Zone Configuration (for existing VNet scenarios)
param dnsZoneRG = ''
param dnsSubscriptionId = ''

// =============================================================================
// PRIVATE ENDPOINTS
// =============================================================================

param storageBlobPrivateEndpointName = ''
param storageFilePrivateEndpointName = ''
param storageTablePrivateEndpointName = ''
param storageQueuePrivateEndpointName = ''
param cosmosDbPrivateEndpointName = ''
param eventHubPrivateEndpointName = ''
param openAiPrivateEndpointName = ''
param languageServicePrivateEndpointName = ''
param aiContentSafetyPrivateEndpointName = ''
param apimV2PrivateEndpointName = ''

// =============================================================================
// SERVICES NETWORK ACCESS CONFIGURATION
// =============================================================================

// API Management Network Configuration
// apimNetworkType: External (public) or Internal (private)
param apimNetworkType = 'External'
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = true

// Azure Services Public Network Access
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Enabled'
param languageServiceExternalNetworkAccess = 'Disabled'
param aiContentSafetyExternalNetworkAccess = 'Disabled'

// Azure Monitor Private Link Scope
param useAzureMonitorPrivateLinkScope = false

// =============================================================================
// FEATURE FLAGS
// =============================================================================

param createAppInsightsDashboards = false
param enableAIModelInference = true
param enableDocumentIntelligence = true
param enableAzureAISearch = true
param enableAIGatewayPiiRedaction = true
param enableOpenAIRealtime = true
param enableAIFoundry = true
param entraAuth = false
param enableAPICenter = true
param apicLocation = '' // blank to use param location

// =============================================================================
// COMPUTE SKU & SIZE
// =============================================================================

// API Management SKU
// Allowed: Developer, Premium, StandardV2, PremiumV2
param apimSku = 'StandardV2'
param apimSkuUnits = 1

// Event Hub & Cosmos DB Capacity
param eventHubCapacityUnits = 1
param cosmosDbRUs = 400

// Logic Apps & Language Services
param logicAppsSkuCapacityUnits = 1
param languageServiceSkuName = 'S'
param aiContentSafetySkuName = 'S0'

// API Center SKU
param apicSku = 'Free'

// =============================================================================
// ACCELERATOR SPECIFIC PARAMETERS
// =============================================================================

param logicContentShareName = 'usage-logic-content'

// AI Search Instances Configuration
// Add your AI Search instances here
param aiSearchInstances = [
  // Example:
  // {
  //   name: 'ai-search-01'
  //   url: 'https://mysearch01.search.windows.net/'
  //   description: 'AI Search Instance 1'
  // }
]

// AI Foundry Instances Configuration
// Configure AI Foundry instances and their locations
param aiFoundryInstances = [
  {
    name: ''  // Leave empty for auto-generated name
    location: location
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
  {
    name: ''  // Leave empty for auto-generated name
    location: 'eastus2'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]

// AI Foundry Model Deployments Configuration
// aiserviceIndex: Index of the AI Foundry instance in aiFoundryInstances array
// Leave aiserviceIndex empty to deploy to all instances
param aiFoundryModelsConfig = [
  // Models for all AI Foundry instances
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
  }
  // Models specific to AI Foundry Instance 0
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
  {
    name: 'Phi-4'
    publisher: 'Microsoft'
    version: '3'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 0
  }
  // Models specific to AI Foundry Instance 1
  {
    name: 'gpt-5'
    publisher: 'OpenAI'
    version: '2025-08-07'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 1
  }
]

// =============================================================================
// MICROSOFT ENTRA ID AUTHENTICATION
// =============================================================================

param entraTenantId = ''
param entraClientId = ''
param entraAudience = ''
