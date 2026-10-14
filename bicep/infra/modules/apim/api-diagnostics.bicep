@description('The name of the API Management service.')
param serviceName string

@description('The name of the API to configure diagnostics for.')
param apiName string

@description('The resource ID of the Azure Monitor logger.')
param apimLoggerId string

@description('Azure Monitor request, response, and large language model log settings.')
param azureMonitorLogSettings object = {
  frontend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  backend: {
    request: { headers: [], body: { bytes: 0 } }
    response: { headers: [], body: { bytes: 0 } }
  }
  largeLanguageModel: {
    logs: 'enabled'
    requests: { messages: 'all', maxSizeInBytes: 262144 }
    responses: { messages: 'all', maxSizeInBytes: 262144 }
  }
}

@description('Application Insights headers to capture and body bytes.')
param appInsightsLogSettings object = {
  headers: [ 'Content-type', 'User-agent', 'x-ms-region', 'x-ratelimit-remaining-tokens', 'x-ratelimit-remaining-requests' ]
  body: { bytes: 0 }
}

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: serviceName
}

resource apiDefinition 'Microsoft.ApiManagement/service/apis@2022-08-01' existing = {
  name: apiName
  parent: apimService
}

resource apiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  parent: apiDefinition
  name: 'azuremonitor'
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'Information'
    logClientIp: true
    loggerId: apimLoggerId
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: azureMonitorLogSettings.frontend
    backend: azureMonitorLogSettings.backend
    largeLanguageModel: azureMonitorLogSettings.largeLanguageModel
  }
}

resource apiDiagnosticsAppInsights 'Microsoft.ApiManagement/service/apis/diagnostics@2022-08-01' = {
  name: 'applicationinsights'
  parent: apiDefinition
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    logClientIp: true
    loggerId: resourceId(resourceGroup().name, 'Microsoft.ApiManagement/service/loggers', apimService.name, 'appinsights-logger')
    metrics: true
    verbosity: 'Information'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: appInsightsLogSettings
      response: appInsightsLogSettings
    }
    backend: {
      request: appInsightsLogSettings
      response: appInsightsLogSettings
    }
  }
}
