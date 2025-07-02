param location string
param tags object
param vnetId string
param keyVaultId string

// Use a more unique naming pattern
var uniqueSuffix = substring(uniqueString(resourceGroup().id, subscription().subscriptionId), 0, 10)

// OpenAI Service with unique name
resource openAIService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'oai-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'oai-${uniqueSuffix}'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// GPT-4o-mini Model Deployment with reduced capacity
resource gpt4oMiniDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAIService
  name: 'gpt-4o-mini'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: 1  // Reduced from 10 to 1 to fit quota
  }
}

// Store OpenAI key in Key Vault
resource keyVaultReference 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: split(keyVaultId, '/')[8]
}

resource openAIKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVaultReference
  name: 'openai-key'
  properties: {
    value: openAIService.listKeys().key1
  }
}

// Outputs
output openAIServiceId string = openAIService.id
output openAIEndpoint string = openAIService.properties.endpoint
output openAIServiceName string = openAIService.name
