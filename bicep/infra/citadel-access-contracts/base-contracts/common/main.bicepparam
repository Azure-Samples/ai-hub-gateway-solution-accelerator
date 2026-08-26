using '../../main.bicep'

// ============================================================================
// Base Access Contract
// Dynamic policy attributes:
//   allowedModels       : gpt-5.4 (replace)
//   tokens-per-minute   : 5000 (replace)
//   token-quota         : 500000 / Monthly (replace)
// ============================================================================

// Deployment Command
// az deployment sub create --name <ACCESS-CONTRACT-NAME> --location <location> --template-file main.bicep --parameters <./contracts/business-unit-1/use-case-1/DEV/main.bicepparam>

param apim = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'REPLACE-WITH-APIM-RG-NAME'
  name: 'REPLACE-WITH-APIM-NAME'
}

param useCase = {
  businessUnit: 'REPLACE'
  useCaseName: 'REPLACE'
  environment: 'REPLACE'
}

param services = [
  {
    code: 'LLM'
    endpointSecretName: 'HR-LLM-ENDPOINT'
    apiKeySecretName: 'HR-LLM-KEY'
    policyXml: loadTextContent('ai-product-policy.xml')
  }
]

// MULTI-ASSET ALTERNATIVE (one product granting LLM + Tool/MCP + Agent/A2A):
// The contract shares ONE api-key (apiKeySecretName) and publishes an endpoint
// secret PER asset. foundryApiName selects the LLM endpoint for the Foundry
// connection. Set apiNameMapping.MULTI to the union of granted APIs.
// param apiNameMapping = { MULTI: ['universal-llm-api', 'weather-tool', 'hr-chat-agent'] }
// param services = [
//   {
//     code: 'MULTI'
//     apiKeySecretName: 'HR-CHATAGENT-KEY'
//     foundryApiName: 'universal-llm-api'
//     assetEndpoints: [
//       { apiName: 'universal-llm-api', endpointSecretName: 'HR-CHATAGENT-LLM-ENDPOINT' }
//       { apiName: 'weather-tool' }        // auto-named endpoint secret
//       { apiName: 'hr-chat-agent' }       // auto-named endpoint secret
//     ]
//     policyXml: loadTextContent('ai-product-policy.xml')
//   }
// ]

param useTargetAzureKeyVault = false
param keyVault = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'REPLACE-WITH-KV-RG-NAME'
  name: 'REPLACE-WITH-KV-NAME'
}

param productTerms = 'Citadel Governance Hub Access Contract Terms and Conditions'

// Azure AI Foundry Integration
param useTargetFoundry = false

param foundry = {
  subscriptionId: '00000000-0000-0000-0000-000000000000'
  resourceGroupName: 'REPLACE-WITH-FOUNDRY-RG-NAME'
  accountName: 'REPLACE-WITH-FOUNDRY-ACCOUNT-NAME'
  projectName: 'REPLACE-WITH-FOUNDRY-PROJECT-NAME'
}

param foundryConfig = {
  connectionNamePrefix: ''
  authType: 'ProjectManagedIdentity'
  managedIdentityAudience: 'https://cognitiveservices.azure.com'
  deploymentInPath: 'false'
  isSharedToAll: false
  inferenceAPIVersion: '2024-05-01-preview'
  deploymentAPIVersion: ''
  staticModels: []
  listModelsEndpoint: ''
  getModelEndpoint: ''
  deploymentProvider: ''
  customHeaders: {}
  authConfig: {}
}

//INTERNAL MECHANICS: DO NOT NEED TO BE EDITED UNLESS BELOW IS CHANGED
param apiNameMapping = {
  LLM: ['universal-llm-api', 'azure-openai-api', 'unified-ai-api']
}
