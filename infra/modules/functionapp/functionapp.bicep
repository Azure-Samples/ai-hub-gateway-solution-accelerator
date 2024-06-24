
param functionAppName string 
param tags object = {}
param azdserviceName string
param storageAccountName string
param functionContentShareName string

param functionAppIdentityName string

param applicationInsightsName string
param eventHubNamespaceName string
param eventHubName string
//param vnetName string
param functionAppSubnetId string

param cosmosDBEndpoint string
param cosmosDatabaseName string
param cosmosContainerName string

param location string = resourceGroup().location

var functionPlanOS = 'Linux'
var functionRuntime  = 'dotnet-isolated'
var dotnetFrameworkVersion  = '8.0'
var linuxFxVersion  = 'DOTNET-ISOLATED|8.0'
var isReserved = functionPlanOS == 'Linux'

resource functionAppmanagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: functionAppIdentityName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}


var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'hosting-plan-${functionAppName}'
  tags: union(tags, { 'azd-service-name': 'hosting-plan-${functionAppName}' })
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 10
    reserved: isReserved
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  tags: union(tags, { 'azd-service-name': azdserviceName })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${functionAppmanagedIdentity.id}': {}
    }
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlan.id
    reserved: isReserved       
    virtualNetworkSubnetId: functionAppSubnetId
  }
}


// Add the function to the subnet
resource networkConfig 'Microsoft.Web/sites/networkConfig@2023-12-01' = {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: functionAppSubnetId
    swiftSupported: true
  }
}

//create functionapp siteconfig
resource functionAppSiteConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    linuxFxVersion: linuxFxVersion
    detailedErrorLoggingEnabled: true
    vnetRouteAllEnabled: true
    ftpsState: 'FtpsOnly'
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    minimumElasticInstanceCount: 1
    //vnetName: vnetName
    publicNetworkAccess: 'Enabled'  
    functionsRuntimeScaleMonitoringEnabled: true
    netFrameworkVersion: dotnetFrameworkVersion
  }
  dependsOn: [
    applicationInsights
  ]
}

//Create functionapp appsettings

resource functionAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      AzureWebJobsStorage: storageAccountConnectionString
      //AzureWebJobsStorage__accountname: storageAccountName      
      FUNCTIONS_EXTENSION_VERSION:  '~4'
      FUNCTIONS_WORKER_RUNTIME: functionRuntime
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageAccountConnectionString
      WEBSITE_CONTENTSHARE: functionContentShareName
      WEBSITE_VNET_ROUTE_ALL: '1'
      WEBSITE_CONTENTOVERVNET: '1'
      //EventHub Input Trigger Settings With Managed Identity
      //https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference?tabs=eventhubs&pivots=programming-language-csharp#common-properties-for-identity-based-connections
      EventHubConnection__clientId: functionAppmanagedIdentity.properties.clientId
      EventHubConnection__credential: 'managedidentity'
      EventHubConnection__fullyQualifiedNamespace: '${eventHubNamespaceName}.servicebus.windows.net'
      EventHubName: eventHubName

      //CosmosDB
      CosmosAccountEndpoint: cosmosDBEndpoint
      CosmosDatabaseName: cosmosDatabaseName
      CosmosContainerName: cosmosContainerName
      CosmosManagedIdentityId: functionAppmanagedIdentity.properties.clientId
  }
  dependsOn: [
    storageAccount
  ]
}
