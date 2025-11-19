# API Center Onboarding - All APIs

## Overview
Extended the API Center onboarding implementation to register all APIM APIs in Azure API Center, providing a centralized catalog of all available APIs with rich metadata.

## APIs Registered in API Center

### 1. **Azure OpenAI API**
- **Path**: `/openai`
- **Type**: REST API
- **Lifecycle**: Production
- **Description**: Azure OpenAI API for accessing GPT models and other AI capabilities
- **Categories**: AI/ML, OpenAI
- **Documentation**: https://learn.microsoft.com/azure/ai-services/openai/

### 2. **Azure AI Search Index API** (Conditional: `enableAzureAISearch`)
- **Path**: `/search`
- **Type**: REST API
- **Lifecycle**: Production
- **Description**: Azure AI Search Index Client APIs for search operations
- **Categories**: AI/ML, Search
- **Documentation**: https://learn.microsoft.com/azure/search/

### 3. **AI Model Inference API** (Conditional: `enableAIModelInference`)
- **Path**: `/models`
- **Type**: REST API
- **Lifecycle**: Production
- **Description**: Access to AI inference models published through Azure AI Foundry
- **Categories**: AI/ML, Model Inference
- **Documentation**: https://learn.microsoft.com/azure/ai-studio/

### 4. **Azure OpenAI Realtime API** (Conditional: `enableOpenAIRealtime`)
- **Path**: `/openai/realtime`
- **Type**: WebSocket API
- **Lifecycle**: Production
- **Description**: Real-time voice and text conversion using Azure OpenAI
- **Categories**: AI/ML, OpenAI, Real-time
- **Documentation**: https://learn.microsoft.com/azure/ai-services/openai/realtime-audio

### 5. **Document Intelligence API (Legacy)** (Conditional: `enableDocumentIntelligence`)
- **Path**: `/formrecognizer`
- **Type**: REST API
- **Lifecycle**: Deprecated
- **Description**: Legacy path for document intelligence services
- **Categories**: AI/ML, Document Processing
- **Documentation**: https://learn.microsoft.com/azure/ai-services/document-intelligence/

### 6. **Document Intelligence API** (Conditional: `enableDocumentIntelligence`)
- **Path**: `/documentintelligence`
- **Type**: REST API
- **Lifecycle**: Production
- **Description**: Extract content, layout, and structured data from documents
- **Categories**: AI/ML, Document Processing
- **Documentation**: https://learn.microsoft.com/azure/ai-services/document-intelligence/

### 7. **Universal LLM API**
- **Path**: `/llm`
- **Type**: REST API
- **Lifecycle**: Production
- **Description**: Universal LLM API to route requests to different LLM providers
- **Categories**: AI/ML, LLM, Multi-Provider
- **Documentation**: GitHub repository

### 8. **Weather API** (Conditional: `isMCPSampleDeployed`)
- **Path**: `/weather`
- **Type**: REST API
- **Lifecycle**: Development
- **Description**: Sample weather API for MCP demonstration
- **Categories**: Sample, Weather

### 9. **Weather MCP** (Conditional: `isMCPSampleDeployed`)
- **Path**: `/weather-mcp`
- **Type**: MCP
- **Lifecycle**: Development
- **Description**: MCP server for weather data operations
- **Categories**: AI/ML, Developer Tools

### 10. **Microsoft Learn MCP** (Conditional: `isMCPSampleDeployed`)
- **Path**: `/ms-learn-mcp`
- **Type**: MCP
- **Lifecycle**: Development
- **Description**: Microsoft Learn MCP Server
- **Categories**: Developer Tools, Productivity

## Custom Properties Applied

Each API is registered with custom properties that provide rich metadata:

```bicep
{
  Visibility: true/false          // Whether the API is publicly visible
  Categories: ['Cat1', 'Cat2']    // Categorization for filtering
  Vendor: 'Microsoft' | 'Internal' // Provider information
  Type: 'AI Service' | 'AI Gateway' | 'Sample API' // API type
  Icon: 'https://...'             // Icon URL for UI display
}
```

## Environment Configuration

APIs are registered in different environments based on their purpose:

- **Production APIs**: Registered in `apiCenterAPIEnvironment` (default: 'api-dev')
- **MCP Servers**: Registered in `apiCenterMCPEnvironment` (default: 'mcp-dev')

## Lifecycle Stages

APIs are assigned lifecycle stages based on their maturity:

- **Production**: Stable, production-ready APIs
- **Development**: Under active development (samples, experimental)
- **Deprecated**: Legacy APIs maintained for backward compatibility

## Benefits

1. **Centralized API Catalog**: All APIs are discoverable in one place
2. **Rich Metadata**: Categories, vendors, icons, and documentation links
3. **Lifecycle Management**: Track API maturity and deprecation
4. **Environment Tracking**: Know which APIs are deployed where
5. **Version Management**: Track API versions over time
6. **Governance**: Enable API governance and compliance policies
7. **Discovery**: Developers can easily find and understand available APIs
8. **Integration**: API Center can integrate with developer portals and catalogs

## Deployment

All API Center onboarding modules are deployed conditionally based on:
- Whether the API feature is enabled (`enableAzureAISearch`, `enableAIModelInference`, etc.)
- Whether sample MCPs are deployed (`isMCPSampleDeployed`)

This ensures only active APIs are registered in API Center.

## Next Steps

To extend this pattern for new APIs:

1. Create the API in APIM using `./api.bicep` module
2. Define custom properties for the API
3. Add an API Center onboarding module call with appropriate parameters
4. Set the correct lifecycle stage and environment
5. Provide documentation URL and metadata

Example:
```bicep
var myApiCustomProperties = {
  Visibility: true
  Categories: ['Category1', 'Category2']
  Vendor: 'Vendor Name'
  Type: 'API Type'
  Icon: 'https://icon-url.com/icon.png'
}

module myApiCenter './api-center-onboarding.bicep' = {
  name: 'my-api-center'
  params: {
    apicServiceName: apiCenterServiceName
    apicWorkspaceName: apiCenterWorkspaceName
    environmentName: apiCenterAPIEnvironment
    apiName: 'my-api'
    apiDisplayName: 'My API'
    apiDescription: 'Description of my API'
    apiKind: 'rest'
    lifecycleStage: 'production'
    versionName: '1-0-0'
    versionDisplayName: '1.0.0'
    gatewayUrl: apimService.properties.gatewayUrl
    apiPath: 'my-api'
    customProperties: myApiCustomProperties
    documentationUrl: 'https://docs.example.com/my-api'
  }
}
```
