// ------------------
//    PARAMETERS
// ------------------

@description('API Center Service Name')
param apiCenterServiceName string

@description('API Center Workspace Name')
param apiCenterWorkspaceName string = 'default'

@description('API Center MCP Environment Name')
param apiCenterMCPEnvironment string = 'mcp-dev'

@description('API Center API Environment Name')
param apiCenterAPIEnvironment string = 'api-dev'

@description('Whether MCP sample APIs are deployed')
param isMCPSampleDeployed bool = false

@description('APIM Gateway URL')
param apimGatewayUrl string

@description('Enable Azure AI Search API Center registration')
param enableAzureAISearch bool = false

@description('Enable AI Model Inference API Center registration')
param enableAIModelInference bool = true

@description('Enable OpenAI Realtime API Center registration')
param enableOpenAIRealtime bool = true

@description('Enable Document Intelligence API Center registration')
param enableDocumentIntelligence bool = true

@description('Register the Orders and Products demo APIs in API Center')
param enableOrderApiDemo bool = false

// ------------------
//    MCP API Center Onboarding
// ------------------

var weatherMCPCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Developer Tools']
  Vendor: 'Internal'
  Type: 'AI Gateway'
  Icon: 'https://cdn-icons-png.flaticon.com/512/1163/1163661.png'
}
module weatherMCPApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-mcp-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterMCPEnvironment
    apiName: 'weather-mcp'
    apiDisplayName: 'Weather MCP Development'
    apiDescription: 'MCP server for weather data operations for given location (Development)'
    apiKind: 'mcp'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'weather-mcp-definition'
    definitionDisplayName: 'Weather MCP Definition'
    definitionDescription: 'Weather MCP Definition for version 1.0.0'
    deploymentName: 'weather-mcp-deployment'
    deploymentDisplayName: 'Weather MCP Deployment'
    deploymentDescription: 'Weather MCP Deployment for version 1.0.0 and environment Development'
    gatewayUrl: apimGatewayUrl
    apiPath: 'weather-mcp'
    customProperties: weatherMCPCustomProperties
    documentationUrl: 'https://example.com/weather-mcp-docs'
  }
}

var microsoftLearnMCPProperties = {
  Visibility: true
  Categories: ['Developer Tools', 'Productivity']
  Vendor: 'Microsoft'
  Type: 'Remote'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module microsoftLearnMCPApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed) {
  name: 'ms-learn-mcp-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterMCPEnvironment
    apiName: 'ms-learn-mcp'
    apiDisplayName: 'Microsoft Learn MCP'
    apiDescription: 'Microsoft Learn MCP Server'
    apiKind: 'mcp'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'ms-learn-mcp-definition'
    definitionDisplayName: 'Microsoft Learn MCP Definition'
    definitionDescription: 'Microsoft Learn MCP Definition for version 1.0.0'
    deploymentName: 'ms-learn-mcp-deployment'
    deploymentDisplayName: 'Microsoft Learn MCP Deployment'
    deploymentDescription: 'Microsoft Learn MCP Deployment for version 1.0.0 and environment development'
    gatewayUrl: apimGatewayUrl
    apiPath: 'ms-learn-mcp'
    customProperties: microsoftLearnMCPProperties
    documentationUrl: 'https://learn.microsoft.com/mcp'
  }
}

// ------------------
//    API Center Onboarding - Regular APIs
// ------------------

var openAIApiCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'OpenAI']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://cdn.openai.com/API/logo-assets/openai-logo.svg'
}
module openAIApiCenter './api-center-onboarding.bicep' = {
  name: 'openai-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'azure-openai-service-api'
    apiDisplayName: 'Azure OpenAI API'
    apiDescription: 'Azure OpenAI API for accessing GPT models and other AI capabilities'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'azure-openai-service-api-definition'
    definitionDisplayName: 'Azure OpenAI API Definition'
    definitionDescription: 'Azure OpenAI API Definition for version 1.0.0'
    deploymentName: 'azure-openai-service-api-deployment'
    deploymentDisplayName: 'Azure OpenAI API Deployment'
    deploymentDescription: 'Azure OpenAI API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'openai'
    customProperties: openAIApiCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/openai/'
  }
}

var aiSearchCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Search']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module aiSearchApiCenter './api-center-onboarding.bicep' = if (enableAzureAISearch) {
  name: 'ai-search-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'azure-ai-search-index-api'
    apiDisplayName: 'Azure AI Search Index API'
    apiDescription: 'Azure AI Search Index Client APIs for search operations'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'azure-ai-search-index-api-definition'
    definitionDisplayName: 'Azure AI Search Index API Definition'
    definitionDescription: 'Azure AI Search Index API Definition for version 1.0.0'
    deploymentName: 'azure-ai-search-index-api-deployment'
    deploymentDisplayName: 'Azure AI Search Index API Deployment'
    deploymentDescription: 'Azure AI Search Index API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'search'
    customProperties: aiSearchCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/search/'
  }
}

var aiModelInferenceCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Model Inference']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module aiModelInferenceApiCenter './api-center-onboarding.bicep' = if (enableAIModelInference) {
  name: 'ai-model-inference-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'ai-model-inference-api'
    apiDisplayName: 'AI Model Inference API'
    apiDescription: 'Access to AI inference models published through Azure AI Foundry'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'ai-model-inference-api-definition'
    definitionDisplayName: 'AI Model Inference API Definition'
    definitionDescription: 'AI Model Inference API Definition for version 1.0.0'
    deploymentName: 'ai-model-inference-api-deployment'
    deploymentDisplayName: 'AI Model Inference API Deployment'
    deploymentDescription: 'AI Model Inference API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'models'
    customProperties: aiModelInferenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/en-us/rest/api/aifoundry/modelinference/'
  }
}

var openAIRealtimeCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'OpenAI', 'Real-time']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://cdn.openai.com/API/logo-assets/openai-logo.svg'
}
module openAIRealtimeApiCenter './api-center-onboarding.bicep' = if (enableOpenAIRealtime) {
  name: 'openai-realtime-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'openai-realtime-ws-api'
    apiDisplayName: 'Azure OpenAI Realtime API'
    apiDescription: 'Access Azure OpenAI Realtime API for real-time voice and text conversion'
    apiKind: 'websocket'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'openai-realtime-ws-api-definition'
    definitionDisplayName: 'Azure OpenAI Realtime API Definition'
    definitionDescription: 'Azure OpenAI Realtime API Definition for version 1.0.0'
    deploymentName: 'openai-realtime-ws-api-deployment'
    deploymentDisplayName: 'Azure OpenAI Realtime API Deployment'
    deploymentDescription: 'Azure OpenAI Realtime API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'openai/realtime'
    customProperties: openAIRealtimeCustomProperties
    documentationUrl: 'https://learn.microsoft.com/en-us/azure/ai-foundry/openai/realtime-audio-quickstart?tabs=keyless%2Cwindows'
  }
}

var documentIntelligenceCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'Document Processing']
  Vendor: 'Microsoft'
  Type: 'AI Service'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module documentIntelligenceLegacyApiCenter './api-center-onboarding.bicep' = if (enableDocumentIntelligence) {
  name: 'doc-intel-legacy-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'document-intelligence-api-legacy'
    apiDisplayName: 'Document Intelligence API (Legacy)'
    apiDescription: 'Uses /formrecognizer path. Extracts content, layout, and structured data from documents'
    apiKind: 'REST'
    lifecycleStage: 'deprecated'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'document-intelligence-api-legacy-definition'
    definitionDisplayName: 'Document Intelligence API (Legacy) Definition'
    definitionDescription: 'Document Intelligence API (Legacy) Definition for version 1.0.0'
    deploymentName: 'document-intelligence-api-legacy-deployment'
    deploymentDisplayName: 'Document Intelligence API (Legacy) Deployment'
    deploymentDescription: 'Document Intelligence API (Legacy) Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'formrecognizer'
    customProperties: documentIntelligenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/document-intelligence/'
  }
}

module documentIntelligenceApiCenter './api-center-onboarding.bicep' = if (enableDocumentIntelligence) {
  name: 'doc-intel-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'document-intelligence-api'
    apiDisplayName: 'Document Intelligence API'
    apiDescription: 'Uses /documentintelligence path. Extracts content, layout, and structured data from documents'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'document-intelligence-api-definition'
    definitionDisplayName: 'Document Intelligence API Definition'
    definitionDescription: 'Document Intelligence API Definition for version 1.0.0'
    deploymentName: 'document-intelligence-api-deployment'
    deploymentDisplayName: 'Document Intelligence API Deployment'
    deploymentDescription: 'Document Intelligence API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'documentintelligence'
    customProperties: documentIntelligenceCustomProperties
    documentationUrl: 'https://learn.microsoft.com/azure/ai-services/document-intelligence/'
  }
}

var universalLLMCustomProperties = {
  Visibility: true
  Categories: ['AI/ML', 'LLM', 'Multi-Provider']
  Vendor: 'Internal'
  Type: 'AI Gateway'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}
module universalLLMApiCenter './api-center-onboarding.bicep' = {
  name: 'universal-llm-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'universal-llm-api'
    apiDisplayName: 'Universal LLM API'
    apiDescription: 'Universal LLM API to route requests to different LLM providers including Azure OpenAI and AI Foundry'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'universal-llm-api-definition'
    definitionDisplayName: 'Universal LLM API Definition'
    definitionDescription: 'Universal LLM API Definition for version 1.0.0'
    deploymentName: 'universal-llm-api-deployment'
    deploymentDisplayName: 'Universal LLM API Deployment'
    deploymentDescription: 'Universal LLM API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'llm'
    customProperties: universalLLMCustomProperties
    documentationUrl: 'https://github.com/mohamedsaif/ai-hub-gateway-solution-accelerator'
  }
}

var weatherAPICustomProperties = {
  Visibility: true
  Categories: ['Sample', 'Weather']
  Vendor: 'Internal'
  Type: 'Sample API'
  Icon: 'https://cdn-icons-png.flaticon.com/512/1163/1163661.png'
}
module weatherAPIApiCenter './api-center-onboarding.bicep' = if (isMCPSampleDeployed) {
  name: 'weather-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'weather-api'
    apiDisplayName: 'Weather API'
    apiDescription: 'Weather API for getting dynamic weather information for a given location'
    apiKind: 'REST'
    lifecycleStage: 'development'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'weather-api-definition'
    definitionDisplayName: 'Weather API Definition'
    definitionDescription: 'Weather API Definition for version 1.0.0'
    deploymentName: 'weather-api-deployment'
    deploymentDisplayName: 'Weather API Deployment'
    deploymentDescription: 'Weather API Deployment for version 1.0.0'
    gatewayUrl: apimGatewayUrl
    apiPath: 'weather'
    customProperties: weatherAPICustomProperties
    documentationUrl: 'https://example.com/weather-api-docs'
  }
}

var orderDemoCustomProperties = {
  Visibility: true
  Categories: ['Commerce', 'Demo']
  Vendor: 'Internal'
  Type: 'Business API'
  Icon: 'https://learn.microsoft.com/media/logos/logo-ms-social.png'
}

module ordersApiCenter './api-center-onboarding.bicep' = if (enableOrderApiDemo) {
  name: 'orders-demo-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'orders-api'
    apiDisplayName: 'Orders API'
    apiDescription: 'Order Management API governed by Azure API Management'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'orders-api-definition'
    definitionDisplayName: 'Orders API Definition'
    definitionDescription: 'Orders API OpenAPI definition for version 1.0.0'
    deploymentName: 'orders-api-apim'
    deploymentDisplayName: 'Orders API - APIM'
    deploymentDescription: 'Orders API deployment in Azure API Management'
    gatewayUrl: apimGatewayUrl
    apiPath: 'orders-demo'
    customProperties: orderDemoCustomProperties
  }
}

module productsApiCenter './api-center-onboarding.bicep' = if (enableOrderApiDemo) {
  name: 'products-demo-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'products-api'
    apiDisplayName: 'Products API'
    apiDescription: 'Product catalogue API governed and cached by Azure API Management'
    apiKind: 'REST'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    definitionName: 'products-api-definition'
    definitionDisplayName: 'Products API Definition'
    definitionDescription: 'Products API OpenAPI definition for version 1.0.0'
    deploymentName: 'products-api-apim'
    deploymentDisplayName: 'Products API - APIM'
    deploymentDescription: 'Products API deployment in Azure API Management'
    gatewayUrl: apimGatewayUrl
    apiPath: 'products-demo'
    customProperties: orderDemoCustomProperties
  }
}
