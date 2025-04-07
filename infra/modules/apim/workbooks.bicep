param location string = resourceGroup().location
param applicationInsightsName string

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}



resource azureOpenAIInsightsWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'azureOpenAIInsights')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Azure OpenAI Insights'
    serializedData: string(loadJsonContent('../monitor/workbooks/azure-openai-insights.json'))
    sourceId: applicationInsights.id
    category: 'workbook'
  }
}
/*

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' =  {
  name: guid(resourceGroup().id, 'OpenAIUsageAnalysis')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'OpenAI Usage Analysis'
    serializedData:  loadTextContent('../monitor/workbooks/openai-usage-analysis-workbook.json')
    sourceId: applicationInsights.id
    category: 'OpenAI'
  }
}



resource alertsWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'alertsWorkbook')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Alerts Workbook'
    serializedData: loadTextContent('../monitor/workbooks/alerts.json')
    sourceId: applicationInsights.id
    category: 'workbook'
  }
}

resource openAIUsageWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'costAnalysis')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Cost Analysis'
    serializedData: replace(replace(loadTextContent('../monitor/workbooks/cost-analysis.json'), '{workspace-id}', applicationInsights.id), '{app-id}', applicationInsights.properties.AppId)
    sourceId: applicationInsights.id
    category: 'workbook'
  }
}

resource openAIUsageWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'costAnalysis')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Cost Analysis'
    serializedData: replace(replace(loadTextContent('../monitor/workbooks/cost-analysis.json'), '{workspace-id}', applicationInsights.id), '{app-id}', applicationInsights.properties.AppId)
    sourceId: applicationInsights.id
    category: 'workbook'
  }
}
*/
