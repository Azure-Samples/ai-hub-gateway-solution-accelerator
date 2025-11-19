using './main.bicep'

// BASIC PARAMETERS
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param tags = {
  'azd-env-name': readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
  SecurityControl: 'Ignore'
}

// RESOURCE NAMES
param resourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', '')

// API MANAGEMENT
param apimSku = readEnvironmentVariable('APIM_SKU', 'StandardV2')
param apimSkuUnits = int(readEnvironmentVariable('APIM_SKU_UNITS', '1'))

// FEATURE FLAGS
param enableAIFoundry = bool(readEnvironmentVariable('ENABLE_AI_FOUNDRY', 'true'))
param enableAPICenter = bool(readEnvironmentVariable('ENABLE_API_CENTER', 'true'))
param enableAIGatewayPiiRedaction = bool(readEnvironmentVariable('ENABLE_PII_REDACTION', 'true'))
param createAppInsightsDashboards = bool(readEnvironmentVariable('CREATE_DASHBOARDS', 'false'))

// CAPACITY SETTINGS
param cosmosDbRUs = int(readEnvironmentVariable('COSMOS_DB_RUS', '400'))
param eventHubCapacityUnits = int(readEnvironmentVariable('EVENTHUB_CAPACITY', '1'))

// ENTRA ID AUTHENTICATION
param entraAuth = bool(readEnvironmentVariable('AZURE_ENTRA_AUTH', 'false'))
param entraTenantId = readEnvironmentVariable('AZURE_TENANT_ID', '')
param entraClientId = readEnvironmentVariable('AZURE_CLIENT_ID', '')
param entraAudience = readEnvironmentVariable('AZURE_AUDIENCE', '')

// NETWORKING
param useExistingVnet = bool(readEnvironmentVariable('USE_EXISTING_VNET', 'false'))
param existingVnetRG = readEnvironmentVariable('EXISTING_VNET_RG', '')
param vnetName = readEnvironmentVariable('VNET_NAME', '')
param dnsZoneRG = readEnvironmentVariable('DNS_ZONE_RG', '')
param dnsSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID', '')
