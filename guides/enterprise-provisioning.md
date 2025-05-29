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

## ⚙️ Basic Configuration

### Core Parameters

| Parameter | Description | Default | Enterprise Considerations |
|-----------|-------------|---------|--------------------------|
| `environmentName` | Environment identifier (1-64 chars) | Required | Use naming convention: `{org}-{env}-{region}` |
| `location` | Primary Azure region | Required | Choose region with OpenAI availability |
| `tags` | Resource tags | `{'azd-env-name': environmentName}` | Add compliance, cost center, owner tags |

### Example Configuration
```json
{
  "environmentName": {"value": "contoso-prod-eastus"},
  "location": {"value": "eastus"},
  "tags": {
    "value": {
      "azd-env-name": "contoso-prod-eastus",
      "Environment": "Production",
      "CostCenter": "IT-AI-Services",
      "Owner": "ai-team@contoso.com",
      "Compliance": "SOC2"
    }
  }
}
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
```json
{
  "useExistingVnet": {"value": false},
  "vnetName": {"value": "vnet-contoso-ai-hub"},
  "vnetAddressPrefix": {"value": "10.170.0.0/24"},
  "apimSubnetPrefix": {"value": "10.170.0.0/26"},
  "privateEndpointSubnetPrefix": {"value": "10.170.0.64/26"},
  "functionAppSubnetPrefix": {"value": "10.170.0.128/26"}
}
```

#### Existing VNet Integration (BYOVNET)
```json
{
  "useExistingVnet": {"value": true},
  "vnetName": {"value": "vnet-contoso-hub"},
  "existingVnetRG": {"value": "rg-contoso-networking"},
  "apimSubnetName": {"value": "snet-apim"},
  "privateEndpointSubnetName": {"value": "snet-private-endpoints"},
  "functionAppSubnetName": {"value": "snet-functions"}
}
```

### Network Security Groups

| Parameter | Purpose | Enterprise Considerations |
|-----------|---------|--------------------------|
| `apimNsgName` | API Management subnet NSG | Allow HTTPS (443), Management (3443) |
| `privateEndpointNsgName` | Private endpoints NSG | Restrict to required traffic only |
| `functionAppNsgName` | Function app subnet NSG | Allow outbound to dependencies |

### DNS Configuration

For existing VNet scenarios, specify DNS zone details:

```json
{
  "dnsZoneRG": {"value": "rg-contoso-dns"},
  "dnsSubscriptionId": {"value": "subscription-id-with-dns"}
}
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
| Function App Processing | `provisionFunctionApp` | `false` | Deploys .NET-based usage processor |
| Stream Analytics | `provisionStreamAnalytics` | `false` | Real-time stream processing |

### AI Capabilities

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
| `apimSkuUnits` | 1-n | Start with 2+ units for HA |

**Developer SKU Limitations:**
- Single unit only
- No SLA guarantee
- No VNet integration in some regions
- 1 million calls/month limit

**Premium SKU Benefits:**
- Multi-region deployment
- VNet integration
- Unlimited API calls
- 99.95% SLA

### Azure OpenAI

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
| `eventHubCapacityUnits` | 1-20 | Start with 2 for production |

### Cosmos DB

| Parameter | Values | Recommendations |
|-----------|--------|-----------------|
| `cosmosDbRUs` | 400-n | Use autoscale for production |

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

# Set minimal required variables (parameters are in main.bicep)
azd env set AZURE_LOCATION eastus
azd env set AZURE_SUBSCRIPTION_ID "your-subscription-id"

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
azd env set AZURE_LOCATION eastus
azd up
```

### 2. Automated Deployment (CI/CD Pipelines)

CI/CD pipelines automatically deploy from environment branches when changes are merged.

## 🔄 CI/CD Pipeline Implementation

### GitHub Actions Workflow

#### Development Environment Pipeline
Create `.github/workflows/deploy-dev.yml`:

```yaml
name: Deploy to Development

on:
  push:
    branches: [ environments/dev ]
  pull_request:
    branches: [ environments/dev ]

env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  AZURE_ENV_NAME: contoso-ai-hub-dev
  AZURE_LOCATION: eastus

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: development
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Log in with Azure (Federated Credentials)
      run: |
        azd auth login \
          --client-id "${{ env.AZURE_CLIENT_ID }}" \
          --federated-credential-provider "github" \
          --tenant-id "${{ env.AZURE_TENANT_ID }}"
          
    - name: Provision Infrastructure
      run: |
        azd env new ${{ env.AZURE_ENV_NAME }} --location ${{ env.AZURE_LOCATION }}
        azd provision --no-prompt
        
    - name: Deploy Application
      run: azd deploy --no-prompt
```

#### Production Environment Pipeline
Create `.github/workflows/deploy-prod.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [ environments/prod ]
  workflow_dispatch:
    inputs:
      confirm_deployment:
        description: 'Type "deploy" to confirm production deployment'
        required: true
        default: ''

env:
  AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID_PROD }}
  AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID_PROD }}
  AZURE_ENV_NAME: contoso-ai-hub-prod
  AZURE_LOCATION: eastus

jobs:
  validate:
    runs-on: ubuntu-latest
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.confirm_deployment == 'deploy'
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Validate Bicep Templates
      run: |
        az bicep build --file infra/main.bicep
        
  deploy:
    runs-on: ubuntu-latest
    needs: validate
    environment: 
      name: production
      url: ${{ steps.deploy.outputs.gateway_url }}
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Install azd
      uses: Azure/setup-azd@v1.0.0
      
    - name: Log in with Azure (Federated Credentials)
      run: |
        azd auth login \
          --client-id "${{ env.AZURE_CLIENT_ID }}" \
          --federated-credential-provider "github" \
          --tenant-id "${{ env.AZURE_TENANT_ID }}"
          
    - name: Provision Infrastructure
      run: |
        azd env new ${{ env.AZURE_ENV_NAME }} --location ${{ env.AZURE_LOCATION }}
        azd provision --no-prompt
        
    - name: Deploy Application
      id: deploy
      run: |
        azd deploy --no-prompt
        echo "gateway_url=$(azd env get-values | grep APIM_GATEWAY_URL | cut -d'=' -f2)" >> $GITHUB_OUTPUT
        
    - name: Run Smoke Tests
      run: |
        # Add smoke test scripts here
        echo "Running smoke tests..."
```

### Azure DevOps Pipeline

Create `azure-pipelines-prod.yml`:

```yaml
trigger:
  branches:
    include:
    - environments/prod

pool:
  vmImage: 'ubuntu-latest'

variables:
  azureServiceConnection: 'contoso-prod-service-connection'
  environmentName: 'contoso-ai-hub-prod'
  azureLocation: 'eastus'

stages:
- stage: Validate
  displayName: 'Validate Infrastructure'
  jobs:
  - job: ValidateBicep
    displayName: 'Validate Bicep Templates'
    steps:
    - task: AzureCLI@2
      displayName: 'Validate Bicep'
      inputs:
        azureSubscription: $(azureServiceConnection)
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          az bicep build --file infra/main.bicep
          
- stage: Deploy
  displayName: 'Deploy to Production'
  dependsOn: Validate
  condition: succeeded()
  jobs:
  - deployment: DeployInfrastructure
    displayName: 'Deploy Infrastructure'
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - checkout: self
          
          - task: AzureCLI@2
            displayName: 'Install Azure Developer CLI'
            inputs:
              azureSubscription: $(azureServiceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                curl -fsSL https://aka.ms/install-azd.sh | bash
                
          - task: AzureCLI@2
            displayName: 'Deploy with AZD'
            inputs:
              azureSubscription: $(azureServiceConnection)
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                azd env new $(environmentName) --location $(azureLocation)
                azd provision --no-prompt
                azd deploy --no-prompt
```

### Secret Management

#### GitHub Secrets Configuration
```bash
# Required secrets for GitHub Actions
AZURE_CLIENT_ID          # Service Principal Client ID
AZURE_TENANT_ID           # Azure AD Tenant ID
AZURE_SUBSCRIPTION_ID     # Target Subscription ID

# Production-specific secrets
AZURE_CLIENT_ID_PROD      # Production Service Principal
AZURE_SUBSCRIPTION_ID_PROD # Production Subscription
```

#### Azure Service Principal Setup
```bash
# Create service principal for CI/CD
az ad sp create-for-rbac \
  --name "contoso-ai-hub-cicd" \
  --role "Contributor" \
  --scopes "/subscriptions/{subscription-id}" \
  --sdk-auth

# Configure federated credentials for GitHub
az ad app federated-credential create \
  --id {app-id} \
  --parameters '{
    "name": "contoso-ai-hub-github",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:contoso/ai-hub-gateway-enterprise:environment:production",
    "description": "GitHub Actions deployment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### Pipeline Triggers and Approvals

#### Environment-based Deployment Flow
1. **Development**: Auto-deploy on push to `environments/dev`
2. **Test**: Auto-deploy on push to `environments/test`
3. **Production**: Manual approval required, deploy on push to `environments/prod`

#### Approval Gates Configuration
```yaml
# GitHub Environment Protection Rules
environments:
  production:
    protection_rules:
      - type: required_reviewers
        required_reviewers:
          - users: ["cloud-architect", "security-lead"]
          - teams: ["platform-team"]
      - type: wait_timer
        wait_timer: 5 # minutes
      - type: branch_policy
        branch_policy:
          protected_branches: true
```

## 🏗️ Deployment Scenarios

## 🏗️ Deployment Scenarios

The enterprise repository strategy supports multiple deployment scenarios using branch-based environment management.

### Scenario 1: Development Environment
```bash
# Clone enterprise repository and switch to dev branch
git clone https://github.com/contoso/ai-hub-gateway-enterprise.git
cd ai-hub-gateway-enterprise
git checkout environments/dev

# Deploy using customized dev parameters
azd env new contoso-ai-hub-dev
azd env set AZURE_LOCATION eastus
azd up
```

### Scenario 2: Production Deployment via CI/CD
```bash
# Push changes to production branch triggers automated deployment
git checkout environments/prod
git pull origin main  # Merge latest changes
# Edit main.bicep with production-specific parameters
git add infra/main.bicep
git commit -m "Update production capacity to 200 TPM"
git push origin environments/prod  # Triggers GitHub Actions workflow
```

### Scenario 3: Manual Production Deployment
```bash
# Deploy production manually with branch-specific parameters
git checkout environments/prod
azd auth login
azd env new contoso-ai-hub-prod
azd env set AZURE_LOCATION eastus
azd env set AZURE_SUBSCRIPTION_ID "prod-subscription-id"
azd up
```

### Scenario 4: BYOVNET Enterprise Deployment
```bash
# Use existing networking infrastructure
git checkout environments/prod

# Parameters already configured in main.bicep:
# - useExistingVnet: true
# - existingVnetRG: "rg-contoso-networking" 
# - vnetName: "vnet-contoso-hub"

azd env new contoso-enterprise-prod
azd env set AZURE_LOCATION eastus
azd up
```

### Scenario 5: Multi-Region Disaster Recovery
```bash
# Deploy to secondary region for DR
git checkout environments/dr
# main.bicep configured with:
# - location: "westus2" 
# - deploymentCapacity: 50 (reduced capacity for DR)

azd env new contoso-ai-hub-dr
azd env set AZURE_LOCATION westus2
azd up
```

## 📋 Best Practices

## 📋 Best Practices

### Repository Management
- Use environment branches for different deployment targets
- Implement branch protection rules for production environments
- Keep main branch synchronized with upstream accelerator updates
- Tag releases for environment deployments

### Parameter Management
- Embed environment-specific parameters directly in `main.bicep` per branch
- Use environment variables only for sensitive values (subscription IDs, tenant IDs)
- Document parameter customizations in branch-specific README files
- Version control all parameter changes with descriptive commit messages

### Naming Conventions
- Use consistent naming patterns across environments: `{org}-{solution}-{env}`
- Include organization, environment, and region identifiers
- Avoid special characters that may cause deployment issues
- Maintain naming consistency across all Azure resources

### Security
- Always use private endpoints in production environments
- Enable Entra ID authentication for API access in production
- Implement proper RBAC on resource groups and subscriptions
- Use Azure Key Vault for sensitive configuration values
- Configure service principal with minimal required permissions

### Capacity Planning
- Start with conservative capacity and scale up based on usage patterns
- Monitor usage patterns and adjust TPM/RPM limits accordingly
- Consider regional distribution for high availability and performance
- Plan for disaster recovery scenarios with secondary regions
- Implement proper throttling policies for different user tiers

### Cost Optimization
- Use appropriate SKUs for each environment (Developer for dev, Premium for prod)
- Monitor usage through Power BI dashboards and set up cost alerts
- Consider reserved instances for predictable workloads
- Implement proper tagging for cost allocation and chargeback

### CI/CD Best Practices
- Use federated credentials instead of client secrets for GitHub Actions
- Implement approval gates for production deployments
- Run validation and smoke tests after deployment
- Store environment-specific secrets in GitHub environments or Azure Key Vault
- Implement proper rollback procedures for failed deployments
- Implement resource tagging for cost allocation
- Monitor usage through the Power BI dashboard
- Consider reserved instances for predictable workloads

### Monitoring
- Enable Application Insights dashboards
- Set up alerts for throttling events
- Monitor API Management metrics
- Track cost and usage trends

### Network Security
- Use NSGs to restrict traffic flow
- Implement Azure Firewall for egress control
- Consider ExpressRoute for hybrid connectivity
- Plan DNS resolution for private endpoints

### Change Management
- Version control all parameter files
- Use separate environments for dev/test/prod
- Implement proper CI/CD pipelines
- Document customizations and deviations

## 🔧 Environment Variables

When using Azure Developer CLI (azd), you can override Bicep parameters using environment variables. This approach is useful for CI/CD pipelines and when you want to keep sensitive values separate from code.

### Core Environment Variables

```bash
# Required for azd deployment
azd env set AZURE_LOCATION "eastus"
azd env set AZURE_SUBSCRIPTION_ID "your-subscription-id"

# Optional: Override default environment name
azd env set AZURE_ENV_NAME "contoso-ai-hub-prod"

# Optional: Custom resource group name
azd env set AZURE_RESOURCE_GROUP "rg-contoso-ai-hub-prod"
```

### Parameter Override Examples

You can override any Bicep parameter by prefixing it with the parameter name:

```bash
# Networking configuration
azd env set useExistingVnet "true"
azd env set existingVnetRG "rg-networking-prod"
azd env set vnetName "vnet-contoso-prod"

# API Management configuration
azd env set apimSku "Premium"
azd env set apimSkuUnits "2"
azd env set apimNetworkType "Internal"

# OpenAI configuration
azd env set deploymentCapacity "100"
azd env set openAiSkuName "Standard"

# Feature toggles
azd env set provisionFunctionApp "true"
azd env set enableAzureAISearch "true"
azd env set entraAuth "true"
```

### Environment Variable Naming Convention

- Use exact parameter names from `main.bicep`
- Boolean values: `"true"` or `"false"` (strings)
- Numeric values: `"100"` (strings)
- Arrays and objects: Use JSON string format

### CI/CD Environment Variables

For automated deployments, set these in your CI/CD system:

```bash
# Authentication (GitHub Actions / Azure DevOps)
AZURE_CLIENT_ID="your-service-principal-client-id"
AZURE_TENANT_ID="your-tenant-id"  
AZURE_SUBSCRIPTION_ID="your-subscription-id"

# Environment-specific overrides
ENVIRONMENT_NAME="contoso-ai-hub-prod"
LOCATION="eastus"
APIM_SKU="Premium"
DEPLOYMENT_CAPACITY="100"
```

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

Ready to get started? Begin with the [Quick Deploy](#🚀-quick-deploy) section and customize the parameters in your environment branch to match your organization's requirements.
