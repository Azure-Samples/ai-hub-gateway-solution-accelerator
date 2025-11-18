using './main.bicep'

/*
 * Development Environment Configuration
 * Optimized for cost and quick deployments
 */

// Basic Configuration
param environmentName = 'citadel-dev'
param location = 'eastus'
param resourceGroupName = ''  // Auto-generated based on environmentName
param tags = {
  'azd-env-name': 'citadel-dev'
  SecurityControl: 'Ignore'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Use Developer SKU for lower cost
param apimSku = 'Developer'
param apimSkuUnits = 1

// Minimal capacity for dev
param cosmosDbRUs = 400
param eventHubCapacityUnits = 1
param deploymentCapacity = 20

// Enable dashboards for monitoring during development
param createAppInsightsDashboards = true

// Disable API Center in dev to save costs
param enableAPICenter = false

// Enable features for testing
param enableAIFoundry = true
param enableAIGatewayPiiRedaction = true
param enableAIModelInference = true

// No Entra ID auth in dev (simplifies testing)
param entraAuth = false

// Public network access for easier development
param openAIExternalNetworkAccess = 'Enabled'
param cosmosDbPublicAccess = 'Enabled'
param eventHubNetworkAccess = 'Enabled'
