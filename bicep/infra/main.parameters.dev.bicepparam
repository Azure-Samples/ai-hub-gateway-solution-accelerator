using './main.bicep'

/*
 * Development Environment Configuration
 * Optimized for cost and quick deployments
 */

// Basic Configuration
param environmentName = 'ai-hub-citadel-dev'
param location = 'eastus'
param resourceGroupName = ''  // Auto-generated based on environmentName
param tags = {
  'azd-env-name': 'ai-hub-citadel-dev'
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

// Enable dashboards for monitoring during development
param createAppInsightsDashboards = false

// Disable API Center in dev to save costs
param enableAPICenter = true

// Enable features for testing
param enableAIFoundry = true
param enableAIGatewayPiiRedaction = true
param enableAIModelInference = true

// No Entra ID auth in dev (simplifies testing)
param entraAuth = false

// Use new Log Analytics workspace (don't use existing)
param useExistingLogAnalytics = false

// Public network access for easier development
param cosmosDbPublicAccess = 'Enabled'
param eventHubNetworkAccess = 'Enabled'
