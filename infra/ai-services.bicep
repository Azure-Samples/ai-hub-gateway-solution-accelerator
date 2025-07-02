param location string
param tags object
param vnetId string
param keyVaultId string

// Get existing VNet reference
resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: split(vnetId, '/')[8]
}

// AI Services Subnet
resource aiServicesSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' = {
  parent: vnet
  name: 'ai-services-subnet'
  properties: {
    addressPrefix: '192.168.10.128/26'
    serviceEndpoints: [
      {
        service: 'Microsoft.CognitiveServices'
      }
      {
        service: 'Microsoft.KeyVault'
      }
    ]
  }
}

// Azure OpenAI Service
resource openAI 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'aihub-openai-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'aihub-openai-${uniqueString(resourceGroup().id)}'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: aiServicesSubnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

// GPT-4 Deployment
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-4'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4'
      version: '1106-Preview'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.Default'
  }
}

// GPT-35-Turbo Deployment
resource gpt35Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-35-turbo'
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '1106'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.Default'
  }
  dependsOn: [
    gpt4Deployment
  ]
}

// Azure AI Search
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: 'aihub-search-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'basic'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'enabled'
  }
}

// Cognitive Services Multi-Service Account
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'aihub-cognitive-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  kind: 'CognitiveServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'aihub-cognitive-${uniqueString(resourceGroup().id)}'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: aiServicesSubnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

// Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: 'aihub-ml-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Hub Machine Learning Workspace'
    keyVault: keyVaultId
    storageAccount: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Storage/storageAccounts/lzstorage${uniqueString(resourceGroup().id)}'
    applicationInsights: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Insights/components/aihub-appinsights'
    publicNetworkAccess: 'Enabled'
  }
}

// Outputs
output openAIId string = openAI.id
output openAIEndpoint string = openAI.properties.endpoint
output searchServiceId string = searchService.id
output searchServiceUrl string = 'https://${searchService.name}.search.windows.net'
output cognitiveServicesId string = cognitiveServices.id
output mlWorkspaceId string = mlWorkspace.id
