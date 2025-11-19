param logicAppName string

param tags object = {}
param azdserviceName string

param storageAccountName string
param fileShareName string

param applicationInsightsName string

param location string = resourceGroup().location

param skuName string
param skuFamily string
param skuSize string
param skuCapaicty int
param skuTier string
param isReserved bool

param cosmosDbAccountName string

param functionAppSubnetId string

param dotnetFrameworkVersion string = 'v6.0'

var docDbAccNativeContributorRoleDefinitionId = '00000000-0000-0000-0000-000000000002'
var eventHubsDataOwnerRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec')
var azureMonitorLogsRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

param eventHubNamespaceName string
param eventHubName string
param eventHubPIIName string

param cosmosDBDatabaseName string
param cosmosDBContainerConfigName string
param cosmosDBContainerUsageName string
param cosmosDBContainerPIIName string
param cosmosDBContainerLLMUsageName string

param apimAppInsightsName string

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: cosmosDbAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'hosting-plan-${logicAppName}'
  tags: union(tags, { 'azd-service-name': 'hosting-plan-${logicAppName}' })
  location: location
  sku: {
    name: skuName //'WS1'
    tier: skuTier //'WorkflowStandard'
    family: skuFamily //'WS'
    size: skuSize //'WS1'
    capacity: skuCapaicty //1
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    reserved: isReserved
  }
}

resource logicApp 'Microsoft.Web/sites@2024-04-01' = {
  name: logicAppName
  location: location
  kind: 'functionapp,workflowapp'
  tags: union(tags, { 'azd-service-name': azdserviceName })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlan.id
    reserved: isReserved       
    virtualNetworkSubnetId: functionAppSubnetId
  }
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2024-04-01' = {
  parent: logicApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: functionAppSubnetId
    swiftSupported: true
  }
}

resource functionAppSiteConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: logicApp
  name: 'web'
  properties: {
    detailedErrorLoggingEnabled: true
    vnetRouteAllEnabled: true
    ftpsState: 'FtpsOnly'
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    minimumElasticInstanceCount: 1
    publicNetworkAccess: 'Enabled'  
    functionsRuntimeScaleMonitoringEnabled: true
    netFrameworkVersion: dotnetFrameworkVersion
    preWarmedInstanceCount: 1
    cors: {
      allowedOrigins: ['https://portal.azure.com', 'https://ms.portal.azure.com']
      supportCredentials: false
    }
  }
  dependsOn: [
    applicationInsights
  ]
}

resource functionAppSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: logicApp
  name: 'appsettings'
  properties: {
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      AzureWebJobsStorage: storageAccountConnectionString
      //AzureWebJobsStorage__accountname: storageAccountName      
      FUNCTIONS_EXTENSION_VERSION:  '~4'
      FUNCTIONS_WORKER_RUNTIME: 'node'
      WEBSITE_NODE_DEFAULT_VERSION: '~20'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageAccountConnectionString
      WEBSITE_CONTENTSHARE: fileShareName
      WEBSITE_VNET_ROUTE_ALL: '0'
      WEBSITE_CONTENTOVERVNET: '1'
      eventHub_fullyQualifiedNamespace: '${eventHubNamespaceName}.servicebus.windows.net'
      eventHub_name: eventHubName
      eventHub_pii_name: eventHubPIIName
      APP_KIND: 'workflowapp'
      AzureFunctionsJobHost_extensionBundle: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
      CosmosDBAccount: cosmosDbAccount.name
      CosmosDBDatabase: cosmosDBDatabaseName
      CosmosDBContainerConfig: cosmosDBContainerConfigName
      CosmosDBContainerUsage: cosmosDBContainerUsageName
      CosmosDBContainerPII: cosmosDBContainerPIIName
      CosmosDBContainerLLMUsage: cosmosDBContainerLLMUsageName
      AzureCosmosDB_connectionString: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
      AppInsights_SubscriptionId: subscription().subscriptionId
      AppInsights_ResourceGroup: resourceGroup().name
      AppInsights_Name: apimAppInsightsName
      AzureMonitor_Resource_Id: azureMonitorConnection.outputs.resourceId
      AzureMonitor_Api_Id: azureMonitorConnection.outputs.apiId
      AzureMonitor_ConnectRuntime_Url: azureMonitorConnection.outputs.connectRuntimeUrl
  }
  dependsOn: [
    storageAccount
    azureMonitorConnection
  ]
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: guid(docDbAccNativeContributorRoleDefinitionId, logicAppName, cosmosDbAccount.id)
  parent: cosmosDbAccount
  properties:{
    principalId: logicApp.identity.principalId
    roleDefinitionId: '/${cosmosDbAccount.id}/sqlRoleDefinitions/${docDbAccNativeContributorRoleDefinitionId}'
    scope: cosmosDbAccount.id
  }
}

// Assign to Azure Event Hubs Data Owner role to the user-defined managed identity used by workloads
resource eventHubsDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicAppName, eventHubsDataOwnerRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataOwnerRoleDefinitionId
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource azureMonitorReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicAppName, azureMonitorLogsRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: azureMonitorLogsRoleDefinitionId
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

module azureMonitorConnection 'api-connection.json' = {
  name: 'azuremonitorlogs-conn'
  params: {
    connection_name: 'azuremonitorlogs'
    display_name: 'conn-azure-monitor'
    location: location
    tags: tags
  }
}

module azureMonitorConnectionAccess 'api-connection-access.bicep' = {
  name: 'azuremonitorlogs-access'
  params: {
    connectionName: 'azuremonitorlogs'
    accessPolicyName: 'azuremonitorlogs-access'
    identityPrincipalId: logicApp.identity.principalId
    location: location
    tags: tags
  }
}
