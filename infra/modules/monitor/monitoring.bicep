param logAnalyticsName string
param apimApplicationInsightsName string
param apimApplicationInsightsDashboardName string
param functionApplicationInsightsName string
param functionApplicationInsightsDashboardName string
param location string = resourceGroup().location
param tags object = {}

// Networking
var privateLinkScopeName = 'ampls-monitoring'
param vNetName string
param privateEndpointSubnetName string
param applicationInsightsDnsZoneName string

resource privateLinkScope 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: privateLinkScopeName
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'Open'
      queryAccessMode: 'Open'
    }
  }
}

module logAnalytics 'loganalytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    privateLinkScopeName: privateLinkScopeName
  }
}

// APIM App Insights
module apimApplicationInsights 'applicationinsights.bicep' = {
  name: 'application-insights'
  params: {
    name: '${apimApplicationInsightsName}-apim'
    location: location
    tags: tags
    dashboardName: apimApplicationInsightsDashboardName
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    privateLinkScopeName: privateLinkScopeName
  }
}

// Function App Insights
module functionApplicationInsights 'applicationinsights.bicep' = {
  name: 'func-application-insights'
  params: {
    name: functionApplicationInsightsName
    location: location
    tags: tags
    dashboardName: functionApplicationInsightsDashboardName
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    privateLinkScopeName: privateLinkScopeName
  }
}

module privateEndpoint '../networking/private-endpoint.bicep' = {
  name: '${privateLinkScopeName}-privateEndpoint'
  params: {
    groupIds: [
      'azuremonitor'
    ]
    dnsZoneName: applicationInsightsDnsZoneName
    name: '${privateLinkScopeName}-pe'
    subnetName: privateEndpointSubnetName
    privateLinkServiceId: privateLinkScope.id
    vNetName: vNetName
    location: location
  }
}

output applicationInsightsName string = apimApplicationInsights.outputs.name
output applicationInsightsConnectionString string = apimApplicationInsights.outputs.connectionString
output applicationInsightsInstrumentationKey string = apimApplicationInsights.outputs.instrumentationKey
output funcApplicationInsightsName string = functionApplicationInsights.outputs.name
output funcApplicationInsightsConnectionString string = functionApplicationInsights.outputs.connectionString
output funcApplicationInsightsInstrumentationKey string = functionApplicationInsights.outputs.instrumentationKey
output logAnalyticsWorkspaceId string = logAnalytics.outputs.id
output logAnalyticsWorkspaceName string = logAnalytics.outputs.name
