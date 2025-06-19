# 🏢 Enterprise Provisioning Guide

This comprehensive guide provides detailed guidance on customizing the AI Hub Gateway deployment for enterprise environments. The solution includes numerous configuration parameters that allow fine-tuning for specific organizational requirements, security policies, and operational needs.

## 📋 Table of Contents

- [Overview](#overview)
- [Enterprise Repository Strategy](#enterprise-repository-strategy)
- [Branch-Based Environment Management](#branch-based-environment-management)
- [Parameter Management](#parameter-management)
- [Basic Configuration](#basic-configuration)
- [Resource Naming Standards](#resource-naming-standards)
- [Network Configuration](#network-configuration)
- [Feature Toggles](#feature-toggles)
- [Compute SKUs & Capacity](#compute-skus--capacity)
- [AI Service Configuration](#ai-service-configuration)
- [Security & Authentication](#security--authentication)
- [Deployment Approaches](#deployment-approaches)
- [CI/CD Pipeline Implementation](#cicd-pipeline-implementation)
- [Environment Variables](#environment-variables)
- [Deployment Scenarios](#deployment-scenarios)
- [Best Practices](#best-practices)
- [Quick Reference](#quick-reference)

## 🔍 Overview

The AI Hub Gateway solution uses Azure Bicep templates with extensive parameterization to support various enterprise deployment scenarios. All parameters are defined in `infra/main.bicep` and can be customized through:

1. **Azure Developer CLI (azd)** - Environment variables and direct parameter modification
2. **Direct Bicep deployment** - Modified Bicep files per environment
3. **CI/CD pipelines** - Automated deployment with branch-based configuration

This guide recommends an **enterprise repository strategy** using branch-based environment management where each environment (dev, test, prod) has its own branch with customized `main.bicep` parameters, enabling both manual deployments and automated CI/CD pipelines.

## 🏛️ Enterprise Repository Strategy

### Repository Structure

Establish a dedicated enterprise repository for the AI Hub Gateway accelerator with the following structure:

```
ai-hub-gateway-enterprise/
├── .github/
│   └── workflows/
│       ├── deploy-dev.yml
│       ├── deploy-test.yml
│       └── deploy-prod.yml
├── docs/
│   ├── deployment-guide.md
│   ├── runbooks/
│   └── architecture/
├── environments/
│   ├── dev/
│   │   ├── main.bicep
│   │   └── azure.yaml
│   ├── test/
│   │   ├── main.bicep
│   │   └── azure.yaml
│   └── prod/
│       ├── main.bicep
│       └── azure.yaml
├── infra/
│   ├── modules/
│   └── shared/
├── scripts/
├── src/
├── azure.yaml
├── main.bicep (base template)
└── README.md
```

### Initial Setup Process

1. **Fork/Clone the Accelerator**
   ```bash
   # Clone the original accelerator
   git clone https://github.com/Azure/ai-hub-gateway-solution-accelerator.git
   cd ai-hub-gateway-solution-accelerator
   
   # Add your enterprise remote
   git remote add enterprise https://github.com/contoso/ai-hub-gateway-enterprise.git
   git push enterprise main
   ```

2. **Create Environment Branches**
   ```bash
   # Create development branch
   git checkout -b environments/dev
   git push enterprise environments/dev
   
   # Create test branch
   git checkout -b environments/test
   git push enterprise environments/test
   
   # Create production branch
   git checkout -b environments/prod
   git push enterprise environments/prod
   ```

### Branch Protection Rules

Configure branch protection for production environments:

```yaml
# GitHub branch protection example
protection_rules:
  environments/prod:
    required_status_checks: true
    enforce_admins: true
    required_pull_request_reviews:
      required_approving_review_count: 2
      dismiss_stale_reviews: true
      require_code_owner_reviews: true
    restrictions:
      users: ["prod-deployment-team"]
      teams: ["cloud-architects", "security-team"]
```

## 🌿 Branch-Based Environment Management

### Environment Branch Strategy

Each environment branch contains customized parameters directly in `main.bicep`:

#### Development Branch (`environments/dev`)
```bicep
// Environment-specific parameters in main.bicep
@description('Environment name')
param environmentName string = 'contoso-ai-hub-dev'

@description('Primary location')
param location string = 'eastus'

@description('API Management SKU')
@allowed([ 'Developer', 'Premium' ])
param apimSku string = 'Developer'

@description('OpenAI deployment capacity')
param deploymentCapacity int = 10

@description('Enable Entra ID authentication')
param entraAuth bool = false

@description('Use existing VNet')
param useExistingVnet bool = false
```

#### Test Branch (`environments/test`)
```bicep
// Environment-specific parameters in main.bicep
@description('Environment name')
param environmentName string = 'contoso-ai-hub-test'

@description('Primary location')
param location string = 'eastus'

@description('API Management SKU')
@allowed([ 'Developer', 'Premium' ])
param apimSku string = 'Premium'

@description('OpenAI deployment capacity')
param deploymentCapacity int = 50

@description('Enable Entra ID authentication')
param entraAuth bool = true

@description('Use existing VNet')
param useExistingVnet bool = true

@description('Existing VNet resource group')
param existingVnetRG string = 'rg-contoso-networking-test'
```

#### Production Branch (`environments/prod`)
```bicep
// Environment-specific parameters in main.bicep
@description('Environment name')
param environmentName string = 'contoso-ai-hub-prod'

@description('Primary location')
param location string = 'eastus'

@description('API Management SKU')
@allowed([ 'Developer', 'Premium' ])
param apimSku string = 'Premium'

@description('API Management SKU units')
param apimSkuUnits int = 3

@description('OpenAI deployment capacity')
param deploymentCapacity int = 200

@description('Enable Entra ID authentication')
param entraAuth bool = true

@description('Use existing VNet')
param useExistingVnet bool = true

@description('Existing VNet resource group')
param existingVnetRG string = 'rg-contoso-networking-prod'

@description('Network access controls')
param openAIExternalNetworkAccess string = 'Disabled'
param cosmosDbPublicAccess string = 'Disabled'
param eventHubNetworkAccess string = 'Disabled'
```

### Environment Synchronization

Keep environments synchronized with upstream changes:

```bash
# Update from upstream accelerator
git checkout main
git pull origin main
git push enterprise main

# Merge updates into environment branches
git checkout environments/dev
git merge main
# Resolve conflicts, maintain environment-specific parameters
git push enterprise environments/dev

# Repeat for test and prod branches
```

## ⚙️ Parameter Management

### Direct Parameter Modification Approach

Instead of using JSON parameter files, modify parameters directly in each environment's `main.bicep` file. This approach provides:

- **Version Control**: All changes are tracked in git
- **Environment Isolation**: Each branch has its own parameter values
- **Simplified Deployment**: No need to manage separate parameter files
- **Clear Auditing**: Parameter changes are visible in commit history

### Parameter Customization Examples

#### Resource Naming Parameters
```bicep
// Production naming standards
param resourceGroupName string = 'rg-contoso-ai-hub-prod'
param apimServiceName string = 'apim-contoso-ai-hub-prod'
param identityName string = 'id-contoso-ai-hub-prod'
param logAnalyticsName string = 'log-contoso-ai-hub-prod'
param eventHubNamespaceName string = 'evhns-contoso-ai-hub-prod'
param cosmosDbAccountName string = 'cosmos-contoso-ai-hub-prod'
```

#### Network Configuration Parameters
```bicep
// Enterprise network settings
param useExistingVnet bool = true
param vnetName string = 'vnet-contoso-hub-prod'
param existingVnetRG string = 'rg-contoso-networking-prod'
param apimSubnetName string = 'snet-contoso-apim-prod'
param privateEndpointSubnetName string = 'snet-contoso-pe-prod'
param apimNetworkType string = 'Internal'
```

#### Security Parameters
```bicep
// Security and compliance settings
param entraAuth bool = true
param entraTenantId string = '12345678-1234-1234-1234-123456789abc'
param entraClientId string = 'abcdef12-3456-7890-abcd-ef1234567890'
param entraAudience string = 'api://contoso-ai-hub'
param openAIExternalNetworkAccess string = 'Disabled'
param cosmosDbPublicAccess string = 'Disabled'
```

#### Feature Toggle Parameters
```bicep
// Production feature configuration
param createAppInsightsDashboard bool = true
param provisionFunctionApp bool = false
param provisionStreamAnalytics bool = true
param enableAIGatewayPiiRedaction bool = true
param enableOpenAIRealtime bool = true
```

## 🏷️ Resource Naming Standards

The solution supports custom naming for all resources. Enterprise organizations should establish consistent naming conventions.

### API Management & Core Services

| Parameter | Default Pattern | Enterprise Example |
|-----------|----------------|-------------------|
| `resourceGroupName` | `rg-{environmentName}` | `rg-contoso-ai-hub-prod` |
| `apimServiceName` | `apim-{resourceToken}` | `apim-contoso-ai-hub-prod` |
| `identityName` | `id-apim-{resourceToken}` | `id-contoso-ai-hub-apim` |

### Monitoring & Analytics

| Parameter | Default Pattern | Enterprise Example |
|-----------|----------------|-------------------|
| `logAnalyticsName` | `log-{resourceToken}` | `log-contoso-ai-hub-prod` |
| `applicationInsightsName` | `appi-apim-{resourceToken}` | `appi-contoso-ai-hub-apim` |
| `applicationInsightsDashboardName` | `dash-apim-{resourceToken}` | `dash-contoso-ai-hub-apim` |

### Data & Events

| Parameter | Default Pattern | Enterprise Example |
|-----------|----------------|-------------------|
| `eventHubNamespaceName` | `evhns-{resourceToken}` | `evhns-contoso-ai-hub-prod` |
| `cosmosDbAccountName` | `cosmos-{resourceToken}` | `cosmos-contoso-ai-hub-prod` |
| `storageAccountName` | `funcusage{resourceToken}` | `stcontosohubprod` |

### AI Services

| Parameter | Default Pattern | Enterprise Example |
|-----------|----------------|-------------------|
| `languageServiceName` | `cog-language-{resourceToken}` | `cog-contoso-language-prod` |
| `aiContentSafetyName` | `cog-consafety-{resourceToken}` | `cog-contoso-safety-prod` |

## 🌐 Network Configuration

### Virtual Network Settings

The solution supports both new VNet creation and integration with existing enterprise networks.

#### New VNet Deployment
```bicep

// New VNet creation parameters
param useExistingVnet bool = false
param vnetName string = 'vnet-contoso-ai-hub'
param vnetAddressPrefix string = '10.170.0.0/24'
param apimSubnetPrefix string = '10.170.0.0/26'
param privateEndpointSubnetPrefix string = '10.170.0.64/26'
param functionAppSubnetPrefix string = '10.170.0.128/26'

```

#### Existing VNet Integration (Bring Your Own VNet - BYOVNET)

>NOTE: virtual network subnets must comply with mentioned requirements in the [bring you own network guide](./bring-your-own-network.md)

```bicep
// Existing VNet integration parameters
param useExistingVnet bool = true
param vnetName string = 'vnet-contoso-hub'
param existingVnetRG string = 'rg-contoso-networking'
param apimSubnetName string = 'snet-apim'
param privateEndpointSubnetName string = 'snet-private-endpoints'
param functionAppSubnetName string = 'snet-functions'
```

### Network Security Groups

>NOTE: Applies only to new VNet deployments. For existing VNet, ensure NSGs are configured according to your security policies.

| Parameter | Purpose | Enterprise Considerations |
|-----------|---------|--------------------------|
| `apimNsgName` | API Management subnet NSG | Allow HTTPS (443), Management (3443) |
| `privateEndpointNsgName` | Private endpoints NSG | Restrict to required traffic only |
| `functionAppNsgName` | Function app subnet NSG | Allow outbound to dependencies |

### DNS Configuration

For existing VNet scenarios, specify DNS zone details (all target private zones must belong to a single resource group but it can be in a different subscription):

```bicep
// DNS Zone configuration for private endpoints
param dnsZoneRG string = 'rg-contoso-dns'
param dnsSubscriptionId string = 'subscription-id-with-dns'
```

### Network Access Controls

| Parameter | Options | Production Recommendation |
|-----------|---------|--------------------------|
| `apimNetworkType` | `External`, `Internal` | `Internal` for enterprise |
| `openAIExternalNetworkAccess` | `Enabled`, `Disabled` | `Disabled` |
| `cosmosDbPublicAccess` | `Enabled`, `Disabled` | `Disabled` |
| `eventHubNetworkAccess` | `Enabled`, `Disabled` | `Disabled` |

## 🔧 Feature Toggles

Control which capabilities are deployed based on organizational needs.

### Core Features

| Feature | Parameter | Default | Description |
|---------|-----------|---------|-------------|
| Application Insights Dashboard | `createAppInsightsDashboard` | `false` | Creates monitoring dashboards |
| Function App Processing | `provisionFunctionApp` | `false` | Deploys .NET-based usage processor (usage ingestion is replaced with logic apps) |

### AI Capabilities in the AI Gateway

| Feature | Parameter | Default | Description |
|---------|-----------|---------|-------------|
| AI Model Inference | `enableAIModelInference` | `true` | Azure AI Studio model support |
| Document Intelligence | `enableDocumentIntelligence` | `true` | Document processing APIs |
| Azure AI Search | `enableAzureAISearch` | `true` | Vector and semantic search |
| PII Redaction | `enableAIGatewayPiiRedaction` | `true` | Automatic PII detection/masking |
| OpenAI Realtime API | `enableOpenAIRealtime` | `true` | WebSocket-based real-time APIs |

### Security Features

| Feature | Parameter | Default | Description |
|---------|-----------|---------|-------------|
| Entra ID Authentication | `entraAuth` | `false` | JWT token validation |
| Azure Monitor Private Link | `useAzureMonitorPrivateLinkScope` | `!useExistingVnet` | Private monitoring connectivity |

## 💻 Compute SKUs & Capacity

### API Management

| Parameter | Options | Production Guidelines |
|-----------|---------|----------------------|
| `apimSku` | `Developer`, `Premium` | Use `Premium` for production |
| `apimSkuUnits` | 1-n | Start with 2+ units for HA (not applicable for Developer SKU) |

**Developer SKU Limitations:**
- Single unit only
- No SLA guarantee

**Premium SKU Benefits:**
- Multi-region deployment
- VNet integration
- Unlimited API calls
- 99.95% SLA

### Azure OpenAI

>NOTE: provisioning OpenAI as part of the accelerator is for demonstration purposes. In production, it is recommended to on-board existing OpenAI service directly.

| Parameter | Description | Enterprise Considerations |
|-----------|-------------|--------------------------|
| `openAiSkuName` | OpenAI service SKU | `S0` for production workloads |
| `deploymentCapacity` | Tokens per minute (thousands) | Plan based on expected load |

**Capacity Planning:**
```json
{
  "deploymentCapacity": {"value": 100},
  "openAiInstances": {
    "value": {
      "openAi1": {
        "name": "openai-east",
        "location": "eastus",
        "deployments": [
          {
            "name": "gpt-4o",
            "model": {"name": "gpt-4o", "version": "2024-05-13"},
            "sku": {"name": "GlobalStandard", "capacity": 100}
          }
        ]
      }
    }
  }
}
```

### Event Hub

| Parameter | Values | Recommendations |
|-----------|--------|-----------------|
| `eventHubCapacityUnits` | 1-20 | Start with 10 for production |

### Cosmos DB

| Parameter | Values | Recommendations |
|-----------|--------|-----------------|
| `cosmosDbRUs` | 400-n | Use autoscale for production (3000 RUs is recommended for production) |

### Logic Apps

| Parameter | Values | Recommendations |
|-----------|--------|-----------------|
| `logicAppsSkuCapacityUnits` | 1-n | Scale based on processing needs |

## 🤖 AI Service Configuration

### OpenAI Instances

The solution supports multiple OpenAI instances across regions for load balancing and redundancy:

```json
{
  "openAiInstances": {
    "value": {
      "primary": {
        "name": "openai-primary",
        "location": "eastus",
        "deployments": [
          {
            "name": "chat",
            "model": {"name": "gpt-4o", "version": "2024-05-13"},
            "sku": {"name": "GlobalStandard", "capacity": 50}
          },
          {
            "name": "embedding",
            "model": {"name": "text-embedding-3-large", "version": "1"},
            "sku": {"name": "Standard", "capacity": 20}
          }
        ]
      },
      "secondary": {
        "name": "openai-secondary",
        "location": "westus",
        "deployments": [
          {
            "name": "chat",
            "model": {"name": "gpt-4o-mini", "version": "2024-07-18"},
            "sku": {"name": "Standard", "capacity": 30}
          }
        ]
      }
    }
  }
}
```

### Azure AI Search Integration

Configure multiple AI Search instances for load balancing:

```json
{
  "aiSearchInstances": {
    "value": [
      {
        "name": "search-primary",
        "url": "https://contoso-search-prod.search.windows.net/",
        "description": "Primary search instance"
      },
      {
        "name": "search-secondary", 
        "url": "https://contoso-search-dr.search.windows.net/",
        "description": "Disaster recovery search instance"
      }
    ]
  }
}
```

### Cognitive Services SKUs

| Service | Parameter | SKU Options | Production Recommendation |
|---------|-----------|-------------|-------------------------|
| Language Service | `languageServiceSkuName` | `F0`, `S` | `S` for production |
| Content Safety | `aiContentSafetySkuName` | `F0`, `S0` | `S0` for production |

## 🔐 Security & Authentication

### Entra ID Integration

For enterprise authentication, configure Entra ID parameters:

```json
{
  "entraAuth": {"value": true},
  "entraTenantId": {"value": "your-tenant-id"},
  "entraClientId": {"value": "your-app-registration-id"},
  "entraAudience": {"value": "api://your-api-audience"}
}
```

### Private Endpoint Configuration

All services support private endpoints. Configure names for consistency:

```json
{
  "storageBlobPrivateEndpointName": {"value": "pe-contoso-storage-blob"},
  "cosmosDbPrivateEndpointName": {"value": "pe-contoso-cosmos"},
  "eventHubPrivateEndpointName": {"value": "pe-contoso-eventhub"},
  "openAiPrivateEndpointName": {"value": "pe-contoso-openai"}
}
```

## 🚀 Deployment Approaches

The enterprise setup supports two primary deployment approaches:

### 1. Manual Deployment (Azure Developer CLI)

#### Local Machine Deployment
```bash
# Switch to target environment branch
git checkout environments/prod

# Authenticate with Azure
azd auth login

# Create new environment
azd env new contoso-ai-hub-prod

# Deploy infrastructure
azd up
```

#### Azure Cloud Shell Deployment
```bash
# Open Azure Cloud Shell (bash)
git clone https://github.com/contoso/ai-hub-gateway-enterprise.git
cd ai-hub-gateway-enterprise

# Switch to environment branch
git checkout environments/prod

# Azure Cloud Shell is already authenticated
azd env new contoso-ai-hub-prod
azd up
```

### 2. Automated Deployment (CI/CD Pipelines)

For additional context on CI/CD pipeline implementation, refer to the [CI/CD Pipeline Implementation Guide](./enterprise-provisioning-devops.md).

## 🚀 Getting Started

1. **Review Requirements**: Ensure you have the necessary permissions and quotas
2. **Plan Your Configuration**: Decide on naming conventions, network architecture, and feature requirements
3. **Customize Parameters**: Modify `main.bicep` directly or set environment variables
4. **Deploy**: Use `azd up` or direct Bicep deployment
5. **Validate**: Test functionality and monitor deployment
6. **Document**: Record any customizations and operational procedures

For additional guidance on specific scenarios, refer to the other guides in this repository:
- [Architecture Overview](./architecture.md)
- [Deployment Guide](./deployment.md)
- [Bring Your Own Network](./bring-your-own-network.md)
- [Entra ID Authentication](./entraid-auth-validation.md)

## 📚 Quick Reference

### Common AZD Commands
```bash
# Environment management
azd env list                          # List all environments
azd env new <env-name>               # Create new environment
azd env select <env-name>            # Switch environment
azd env set <key> <value>            # Set environment variable
azd env get-values                   # Show all environment variables

# Deployment commands
azd up                               # Deploy infrastructure and application
azd provision                       # Deploy infrastructure only
azd deploy                          # Deploy application only
azd down                            # Delete all resources

# Monitoring and troubleshooting
azd monitor                         # Open monitoring dashboard
azd show                           # Show deployment status
azd logs                           # View application logs
```

### Branch Management Commands
```bash
# Switch between environment branches
git checkout environments/dev
git checkout environments/test  
git checkout environments/prod

# Sync with upstream accelerator
git remote add upstream https://github.com/Azure/ai-hub-gateway-solution-accelerator.git
git fetch upstream
git merge upstream/main

# Push environment changes
git add infra/main.bicep
git commit -m "Update production parameters"
git push origin environments/prod
```

## 🎯 Summary

This enterprise provisioning guide provides a comprehensive framework for deploying and managing the AI Hub Gateway solution at scale. The key advantages of this approach include:

**🏛️ Enterprise Repository Strategy**
- Branch-based environment management with clear separation of concerns
- Version-controlled parameter management with audit trails
- Streamlined updates from upstream accelerator repository

**⚙️ Flexible Parameter Management**
- Direct modification of `main.bicep` for environment-specific configurations
- Support for both manual deployments and automated CI/CD pipelines
- Comprehensive parameter documentation for all 90+ configuration options

**🚀 Multiple Deployment Approaches**
- Manual deployment via Azure Developer CLI for development and testing
- Automated CI/CD pipelines with GitHub Actions and Azure DevOps support
- Support for both new infrastructure and existing enterprise networking

**🔒 Enterprise-Grade Security**
- Private endpoint connectivity for all services
- Federated credential authentication for CI/CD pipelines
- Comprehensive RBAC and network security configurations
