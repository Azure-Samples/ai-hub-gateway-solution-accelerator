param location string
param tags object
param vnetId string
param logAnalyticsId string

// Get existing VNet reference
resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: split(vnetId, '/')[8]
}

// AKS Subnet
resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' = {
  parent: vnet
  name: 'aks-subnet'
  properties: {
    addressPrefix: '10.0.1.0/24'
    serviceEndpoints: [
      {
        service: 'Microsoft.ContainerRegistry'
      }
    ]
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'aihubreg${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-07-02-preview' = {
  name: 'aihub-aks'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: 'aihub-aks-dns'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 2
        vmSize: 'Standard_D2s_v3'
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: aksSubnet.id
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsId
        }
      }
    }
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'aihub-asp'
  location: location
  tags: tags
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

// App Service for Customer Care Chat
resource customerCareApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'aihub-customer-care-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      appSettings: [
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '18-lts'
        }
      ]
    }
    httpsOnly: true
  }
}

// App Service for Retail Shopping App
resource retailShoppingApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'aihub-retail-shopping-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      appSettings: [
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '18-lts'
        }
      ]
    }
    httpsOnly: true
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'aihub-cae'
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {
      internal: false
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsId, '2023-09-01').customerId
        sharedKey: listKeys(logAnalyticsId, '2023-09-01').primarySharedKey
      }
    }
  }
}

// Container App for Finance Smart Analysis
resource financeAnalysisApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'aihub-finance-analysis'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
      }
    }
    template: {
      containers: [
        {
          name: 'finance-analysis'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

// Outputs
output aksClusterId string = aksCluster.id
output containerRegistryId string = containerRegistry.id
output appServicePlanId string = appServicePlan.id
output customerCareAppUrl string = customerCareApp.properties.defaultHostName
output retailShoppingAppUrl string = retailShoppingApp.properties.defaultHostName
output containerAppsEnvironmentId string = containerAppsEnvironment.id
output financeAnalysisAppUrl string = financeAnalysisApp.properties.configuration.ingress.fqdn
