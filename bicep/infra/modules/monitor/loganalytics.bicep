param name string
param location string = resourceGroup().location
param tags object = {}

// Networking
param privateLinkScopeName string

// Existing Log Analytics workspace parameters
param useExistingLogAnalytics bool = false
param existingLogAnalyticsName string = ''
param existingLogAnalyticsRG string = ''
param existingLogAnalyticsSubscriptionId string = ''

resource privateLinkScope 'microsoft.insights/privateLinkScopes@2021-07-01-preview' existing = if (privateLinkScopeName != '') {
  name: privateLinkScopeName
}

// Reference existing Log Analytics workspace (potentially cross-subscription)
resource existingLogAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = if (useExistingLogAnalytics) {
  name: existingLogAnalyticsName
  scope: resourceGroup(existingLogAnalyticsSubscriptionId, existingLogAnalyticsRG)
}

// Create new Log Analytics workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = if (!useExistingLogAnalytics) {
  name: name
  location: location
  tags: union(tags, { 'azd-service-name': name })
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
    publicNetworkAccessForIngestion: privateLinkScopeName != '' ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: privateLinkScopeName != '' ? 'Enabled' : 'Enabled'
  })
}

resource logAnalyticsScopedResource 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = if (privateLinkScopeName != '' && !useExistingLogAnalytics) {
  parent: privateLinkScope
  name: '${logAnalytics.name}-connection'
  properties: {
    linkedResourceId: logAnalytics.id
  }
}

output id string = useExistingLogAnalytics ? existingLogAnalytics.id : logAnalytics.id
output name string = useExistingLogAnalytics ? existingLogAnalytics.name : logAnalytics.name
