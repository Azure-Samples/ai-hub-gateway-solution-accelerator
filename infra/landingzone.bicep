param location string
param tags object

param vnetName string = 'landingzone-vnet'
param addressPrefix string = '192.168.10.0/24'
param subnetName string = 'default'
param subnetPrefix string = '192.168.10.0/24'
param nsgName string = '${subnetName}-nsg'
param logAnalyticsName string = 'lz-loganalytics'
param keyVaultName string = 'lz-keyvault${uniqueString(resourceGroup().id)}'
param storageAccountName string = toLower('lzstorage${uniqueString(resourceGroup().id)}')

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {}
}

// Virtual Network with Subnet and NSG association
resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableSoftDelete: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Storage Account
resource storage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

output vnetId string = vnet.id
output nsgId string = nsg.id
output logAnalyticsId string = logAnalytics.id
output keyVaultId string = keyVault.id
output storageAccountId string = storage.id
