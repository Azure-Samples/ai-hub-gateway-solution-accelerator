@description('Target Key Vault name where app secrets will be created/updated')
param keyVaultName string

@description('Secret names to create/update')
param secretNames array

@description('Secret values in same order as secretNames')
@secure()
param secretValues object

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for name in secretNames: {
  name: name
  parent: kv
  properties: {
    value: secretValues[name]
    contentType: 'string'
  }
}]

output createdSecretNames array = secretNames
