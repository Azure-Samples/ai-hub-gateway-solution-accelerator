param location string
param tags object

// Shortened naming convention
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Use existing Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: 'aihub-cae'
}

// Customer Service Container App
resource customerServiceApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'customer-svc-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
      }
    }
    template: {
      containers: [
        {
          name: 'customer-service'
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
  identity: {
    type: 'SystemAssigned'
  }
}

// Finance Analysis Container App
resource financeAnalysisApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'finance-svc-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
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
  identity: {
    type: 'SystemAssigned'
  }
}

// Outputs
output customerServiceAppId string = customerServiceApp.id
output financeAnalysisAppId string = financeAnalysisApp.id
output containerAppEnvironmentId string = containerAppEnvironment.id
