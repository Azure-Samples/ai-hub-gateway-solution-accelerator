using './main.bicep'

/*
 * Production Environment Configuration
 * Optimized for high availability and performance
 */

// Basic Configuration
param environmentName = 'citadel-prod'
param location = 'eastus'
param resourceGroupName = ''  // Auto-generated based on environmentName
param tags = {
  'azd-env-name': 'citadel-prod'
  SecurityControl: 'Required'
  Environment: 'Production'
  CostCenter: 'Platform'
  Criticality: 'High'
}

// Production-grade SKUs
param apimSku = 'PremiumV2'
param apimSkuUnits = 2

// Higher capacity for production workloads
param cosmosDbRUs = 3000
param eventHubCapacityUnits = 5

// Enable monitoring dashboards
param createAppInsightsDashboards = true

// Enable all production features
param enableAPICenter = true
param enableAIFoundry = true
param enableAIGatewayPiiRedaction = true
param enableAIModelInference = true
param enableDocumentIntelligence = true
param enableAzureAISearch = true
param enableOpenAIRealtime = true

// Enable Entra ID authentication for production
param entraAuth = true
param entraTenantId = ''  // Set via environment variable or override
param entraClientId = ''  // Set via environment variable or override
param entraAudience = ''  // Set via environment variable or override

// Secure network configuration
param apimNetworkType = 'Internal'
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = false
param openAIExternalNetworkAccess = 'Disabled'
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Disabled'
param languageServiceExternalNetworkAccess = 'Disabled'
param aiContentSafetyExternalNetworkAccess = 'Disabled'

// Enable Azure Monitor Private Link Scope
param useAzureMonitorPrivateLinkScope = true

// Production AI Foundry configuration
param aiFoundryInstances = [
  {
    name: ''
    location: 'eastus'
    customSubDomainName: ''
    defaultProjectName: 'production-project'
  }
  {
    name: ''
    location: 'westus'
    customSubDomainName: ''
    defaultProjectName: 'production-project'
  }
]

param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 200
    aiserviceIndex: 0
  }
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 200
    aiserviceIndex: 0
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 200
    aiserviceIndex: 1
  }
]
