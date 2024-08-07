param logicAppName string

param tags object = {}
param azdserviceName string

param storageAccountName string
param fileShareName string

param applicationInsightsName string

param location string = resourceGroup().location

param skuName string
param skuFamily string
param skuSize string
param skuCapaicty int
param skuTier string
param isReserved bool

param cosmosDbAccountName string

param functionAppSubnetId string

param dotnetFrameworkVersion string = 'v6.0'

var docDbAccNativeContributorRoleDefinitionId = '00000000-0000-0000-0000-000000000002'
var eventHubsDataOwnerRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec')

param eventHubNamespaceName string
param eventHubName string

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: cosmosDbAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var storageAccountConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'hosting-plan-${logicAppName}'
  tags: union(tags, { 'azd-service-name': 'hosting-plan-${logicAppName}' })
  location: location
  sku: {
    name: skuName //'WS1'
    tier: skuTier //'WorkflowStandard'
    family: skuFamily //'WS'
    size: skuSize //'WS1'
    capacity: skuCapaicty //1
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    reserved: isReserved
  }
}

resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  location: location
  kind: 'functionapp,workflowapp'
  tags: union(tags, { 'azd-service-name': azdserviceName })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlan.id
    reserved: isReserved       
    virtualNetworkSubnetId: functionAppSubnetId
  }
}

resource networkConfig 'Microsoft.Web/sites/networkConfig@2023-12-01' = {
  parent: logicApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: functionAppSubnetId
    swiftSupported: true
  }
}

resource functionAppSiteConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: logicApp
  name: 'web'
  properties: {
    detailedErrorLoggingEnabled: true
    vnetRouteAllEnabled: true
    ftpsState: 'FtpsOnly'
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    minimumElasticInstanceCount: 1
    publicNetworkAccess: 'Enabled'  
    functionsRuntimeScaleMonitoringEnabled: true
    netFrameworkVersion: dotnetFrameworkVersion
    preWarmedInstanceCount: 1
    cors: {
      allowedOrigins: ['https://portal.azure.com', 'https://ms.portal.azure.com']
      supportCredentials: false
    }
  }
  dependsOn: [
    applicationInsights
  ]
}

resource functionAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: logicApp
  name: 'appsettings'
  properties: {
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      AzureWebJobsStorage: storageAccountConnectionString
      //AzureWebJobsStorage__accountname: storageAccountName      
      FUNCTIONS_EXTENSION_VERSION:  '~4'
      FUNCTIONS_WORKER_RUNTIME: 'node'
      WEBSITE_NODE_DEFAULT_VERSION: '~18'
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: storageAccountConnectionString
      WEBSITE_CONTENTSHARE: fileShareName
      WEBSITE_VNET_ROUTE_ALL: '1'
      WEBSITE_CONTENTOVERVNET: '1'
  }
  dependsOn: [
    storageAccount
  ]
}

resource sqlRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: guid(docDbAccNativeContributorRoleDefinitionId, logicAppName, cosmosDbAccount.id)
  parent: cosmosDbAccount
  properties:{
    principalId: logicApp.identity.principalId
    roleDefinitionId: '/${cosmosDbAccount.id}/sqlRoleDefinitions/${docDbAccNativeContributorRoleDefinitionId}'
    scope: cosmosDbAccount.id
  }
}

// Assign to Azure Event Hubs Data Owner role to the user-defined managed identity used by workloads
resource eventHubsDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicAppName, eventHubsDataOwnerRoleDefinitionId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: eventHubsDataOwnerRoleDefinitionId
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventhubs 'Microsoft.Web/connections@2016-06-01' = {
  name: 'eventhubs'
  location: location
  properties: {
    displayName: 'eh-ai-gateway'
    api: {
      name: 'eventhubs'
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'eventhubs')
      type: 'Microsoft.Web/locations/managedApis'
      
    }
    parameterValues:{
    }
  }
}


// resource vnet 'Microsoft.Network/virtualNetworks@2020-07-01' = {
//   name: vnetName
//   location: location
//   properties: {
//     addressSpace: {
//       addressPrefixes: [
//         virtualNetworkAddressPrefix
//       ]
//     }
//     subnets: [
//       {
//         name: subnetName
//         properties: {
//           addressPrefix: functionSubnetAddressPrefix
//           privateEndpointNetworkPolicies: 'Enabled'
//           privateLinkServiceNetworkPolicies: 'Enabled'
//           delegations: [
//             {
//               name: 'webapp'
//               properties: {
//                 serviceName: 'Microsoft.Web/serverFarms'
//                 actions: [
//                   'Microsoft.Network/virtualNetworks/subnets/action'
//                 ]
//               }
//             }
//           ]
//         }
//       }
//       {
//         name: contentStorageAccountName
//         properties: {
//           addressPrefix: privateEndpointSubnetAddressPrefix
//           privateLinkServiceNetworkPolicies: 'Enabled'
//           privateEndpointNetworkPolicies: 'Disabled'
//         }
//       }
//     ]
//     enableDdosProtection: false
//     enableVmProtection: false
//   }
// }

// resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
//   name: contentStorageAccountName
//   location: location
//   sku: {
//     name: 'Standard_LRS'
//     tier: 'Standard'
//   }
//   kind: 'StorageV2'
//   properties: {
//     networkAcls: {
//       bypass: 'AzureServices'
//       defaultAction: 'Deny'
//     }
//     supportsHttpsTrafficOnly: true
//     encryption: {
//       services: {
//         file: {
//           keyType: 'Account'
//           enabled: true
//         }
//         blob: {
//           keyType: 'Account'
//           enabled: true
//         }
//       }
//       keySource: 'Microsoft.Storage'
//     }
//   }
// }

// resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2021-04-01' = {
//   name: '${contentStorageAccountName}/default/${toLower(fileShareName)}'
//   dependsOn: [
//     storageAccount
//   ]
// }

// resource privateDnsZoneFile 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: privateStorageFileDnsZoneName
//   location: 'global'
//   dependsOn: [
//     vnet
//   ]
// }

// resource privateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: privateStorageBlobDnsZoneName
//   location: 'global'
//   dependsOn: [
//     vnet
//   ]
// }

// resource privateDnsZoneQueue 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: privateStorageQueueDnsZoneName
//   location: 'global'
//   dependsOn: [
//     vnet
//   ]
// }

// resource privateDnsZoneTable 'Microsoft.Network/privateDnsZones@2020-06-01' = {
//   name: privateStorageTableDnsZoneName
//   location: 'global'
//   dependsOn: [
//     vnet
//   ]
// }

// resource vnetLinkFile 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   name: '${privateStorageFileDnsZoneName}/${virtualNetworkLinksSuffixFileStorageName}'
//   location: 'global'
//   dependsOn: [
//     privateDnsZoneFile
//     vnet
//   ]
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: vnet.id
//     }
//   }
// }

// resource vnetLinkBlob 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   name: '${privateStorageBlobDnsZoneName}/${virtualNetworkLinksSuffixBlobStorageName}'
//   location: 'global'
//   dependsOn: [
//     privateDnsZoneBlob
//     vnet
//   ]
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: vnet.id
//     }
//   }
// }

// resource vnetLinkQueue 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   name: '${privateStorageQueueDnsZoneName}/${virtualNetworkLinksSuffixQueueStorageName}'
//   location: 'global'
//   dependsOn: [
//     privateDnsZoneQueue
//     vnet
//   ]
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: vnet.id
//     }
//   }
// }

// resource vnetLinkTable 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
//   name: '${privateStorageTableDnsZoneName}/${virtualNetworkLinksSuffixTableStorageName}'
//   location: 'global'
//   dependsOn: [
//     privateDnsZoneTable
//     vnet
//   ]
//   properties: {
//     registrationEnabled: false
//     virtualNetwork: {
//       id: vnet.id
//     }
//   }
// }

// resource privateEndpointFile 'Microsoft.Network/privateEndpoints@2020-06-01' = {
//   name: privateEndpointFileStorageName
//   location: location
//   dependsOn: [
//     fileShare
//     vnet
//   ]
//   properties: {
//     subnet: {
//       id: '${vnet.id}/subnets/${contentStorageAccountName}'
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'MyStorageQueuePrivateLinkConnection'
//         properties: {
//           privateLinkServiceId: storageAccount.id
//           groupIds: [
//             'file'
//           ]
//         }
//       }
//     ]
//   }
// }

// resource privateEndpointBlob 'Microsoft.Network/privateEndpoints@2020-06-01' = {
//   name: privateEndpointBlobStorageName
//   location: location
//   dependsOn: [
//     fileShare
//     vnet
//   ]
//   properties: {
//     subnet: {
//       id: '${vnet.id}/subnets/${contentStorageAccountName}'
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'MyStorageQueuePrivateLinkConnection'
//         properties: {
//           privateLinkServiceId: storageAccount.id
//           groupIds: [
//             'blob'
//           ]
//         }
//       }
//     ]
//   }
// }

// resource privateEndpointQueue 'Microsoft.Network/privateEndpoints@2020-06-01' = {
//   name: privateEndpointQueueStorageName
//   location: location
//   dependsOn: [
//     fileShare
//     vnet
//   ]
//   properties: {
//     subnet: {
//       id: '${vnet.id}/subnets/${contentStorageAccountName}'
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'MyStorageQueuePrivateLinkConnection'
//         properties: {
//           privateLinkServiceId: storageAccount.id
//           groupIds: [
//             'queue'
//           ]
//         }
//       }
//     ]
//   }
// }

// resource privateEndpointTable 'Microsoft.Network/privateEndpoints@2020-06-01' = {
//   name: privateEndpointTableStorageName
//   location: location
//   dependsOn: [
//     fileShare
//     vnet
//   ]
//   properties: {
//     subnet: {
//       id: '${vnet.id}/subnets/${contentStorageAccountName}'
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'MyStorageQueuePrivateLinkConnection'
//         properties: {
//           privateLinkServiceId: storageAccount.id
//           groupIds: [
//             'table'
//           ]
//         }
//       }
//     ]
//   }
// }

// resource dnsZoneGroupFile 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-06-01' = {
//   name: '${privateEndpointFileStorageName}/default'
//   location: location
//   dependsOn: [
//     privateDnsZoneFile
//     privateEndpointFile
//   ]
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: 'config1'
//         properties: {
//           privateDnsZoneId: privateDnsZoneFile.id
//         }
//       }
//     ]
//   }
// }

// resource dnsZoneGroupBlob 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-06-01' = {
//   name: '${privateEndpointBlobStorageName}/default'
//   location: location
//   dependsOn: [
//     privateDnsZoneBlob
//     privateEndpointBlob
//   ]
//   properties: {
//     privateDnsZoneConfigs: [
//       {
//         name: 'config1'
//         properties: {
//           privateDnsZoneId: privateDnsZoneBlob.id
//         }
//       }
//     ]
//   }
// }
