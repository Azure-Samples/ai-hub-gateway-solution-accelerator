# 🏗️ Full Deployment Guide - All Environments

This comprehensive guide covers deploying AI Citadel Governance Hub across **development, staging, and production** environments with enterprise-grade configuration, networking, and governance.

For quick non-production deployments, see the [Quick Deployment Guide](./quick-deployment-guide.md).

---

## 📋 Table of Contents

1. [Prerequisites](#-prerequisites)
2. [Deployment Preparation](#-deployment-preparation)
   - [Parameter Files Strategy](#1-parameter-files-strategy)
   - [Resource Naming & Tagging](#2-resource-naming--tagging)
   - [Network Architecture](#3-network-architecture)
   - [AI Model Deployment](#4-ai-model-deployment-optional)
   - [Log Analytics Strategy](#5-log-analytics-strategy)
   - [Security & Compliance](#6-security--compliance)
3. [Source Control Strategy](#-source-control-strategy)
4. [Deployment Execution](#-deployment-execution)
5. [Environment-Specific Configurations](#-environment-specific-configurations)
6. [Post-Deployment Validation](#-post-deployment-validation)
7. [Troubleshooting](#-troubleshooting)

---

## ✅ Prerequisites

### Azure Requirements

| Requirement | Details |
|-------------|---------|
| **Azure Subscription** | Active subscription with sufficient quota |
| **Permissions** | Owner or Contributor + User Access Administrator |
| **Resource Providers** | All required providers registered (see below) |
| **Service Quotas** | Verified for APIM, Cosmos DB, Event Hub |

### Required Resource Providers

```bash
# Register all required providers
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.EventHub
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Web

# Verify registration status
az provider list --query "[?registrationState=='Registered'].namespace" -o table
```

### Development Tools

**Option 1: Local Machine**
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.50.0+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (v0.20.0+)
- [Git](https://git-scm.com/downloads)
- [VS Code](https://code.visualstudio.com/) with extensions:
  - Bicep

**Option 2: Azure Cloud Shell**
- All tools pre-installed
- Storage account for persistence
- Built-in editor

**Option 3: Azure DevOps / GitHub Actions**
- Self-hosted or Microsoft-hosted agents
- Service Principal with appropriate permissions
- Secure variable groups for secrets

---

## 🎯 Deployment Preparation

First you need to get the deployment template files:

```bash

azd init --template Azure-Samples/ai-hub-gateway-solution-accelerator -e ai-hub-citadel-dev --branch citadel-v1

# or use git clone:
# git clone https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator.git
# git checkout citadel-v1

# Make the repository your current directory:
cd ai-hub-citadel-deployment # it may differ if you used git clone

```

### 1. Parameter Files Strategy

AI Citadel Governance Hub uses **Bicep parameter files (.bicepparam)** for environment-specific configurations.

#### Available Parameter Files

| File | Purpose | Use Case |
|------|---------|----------|
| [`main.bicepparam`](../bicep/infra/main.bicepparam) | Environment variables | Used in azd deployments, CI/CD |
| [`main.parameters.dev.bicepparam`](../bicep/infra/main.parameters.dev.bicepparam) | Development | Dev/test environments |
| [`main.parameters.prod.bicepparam`](../bicep/infra/main.parameters.prod.bicepparam) | Production | Production workloads |
| [`main.parameters.complete.bicepparam`](../bicep/infra/main.parameters.complete.bicepparam) | Reference | All parameters documented |

#### Parameter File Structure

```bicep
using './main.bicep'

// Basic Configuration
param environmentName = 'citadel-dev'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-dev'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Compute SKUs
param apimSku = 'Developer'
param apimSkuUnits = 1

// Networking
param useExistingVnet = false
param useExistingLogAnalytics = false

// Features
param enableAIFoundry = true
param enableAPICenter = true
```

#### Choosing the Right Parameter File

**For Development:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.dev.bicepparam
```

**For Production:**
```bash
az deployment sub create \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.prod.bicepparam
```

**For Custom Environments:**
1. Copy `main.parameters.complete.bicepparam`
2. Rename to `main.parameters.<env>.bicepparam`
3. Customize values
4. Version control the file

---

### 2. Resource Naming & Tagging

#### Naming Strategy

AI Citadel supports two naming approaches:

**Option A: Auto-Generated Names (for default non-production deployment)**
```bicep
param resourceGroupName = ''  // Auto-generated: rg-citadel-dev
param apimServiceName = ''    // Auto-generated: apim-abc123def
param logAnalyticsName = ''   // Auto-generated: log-abc123def
```

Benefits:
- ✅ Quick naming across environments
- ✅ Unique names prevent conflicts
- ✅ Includes environment hash for traceability

**Option B: Custom Names**
```bicep
param resourceGroupName = 'rg-ai-gov-citadel-prod-eastus'
param apimServiceName = 'apim-ai-gov-citadel-prod'
param logAnalyticsName = 'law-ai-gov-citadel-shared'
```

Benefits:
- ✅ Human-readable names
- ✅ Matches organizational naming standards
- ✅ Easier to locate in portal

#### Tagging Strategy

**Minimum Required Tags:**
```bicep
param tags = {
  'azd-env-name': 'ai-gov-citadel-prod'
  Environment: 'Production'
  CostCenter: 'Platform'
  Owner: 'platform-team@company.com'
  Criticality: 'High'
}
```

**Recommended Tags by Environment:**

| Tag | Dev | Staging | Production |
|-----|-----|---------|------------|
| Environment | Development | Staging | Production |
| Criticality | Low | Medium | High |
| CostCenter | Engineering | Engineering | Platform |

---

### 3. Network Architecture

#### Network Deployment Approaches

AI Citadel Governance Hub supports **two architectural patterns** for network integration:

##### **Approach 1: Hub-Based (Citadel as Part of Hub)**

Citadel Governance Hub deployed **within** your existing hub VNet.

```
┌─────────────────────────────────────┐
│         Hub Network (VNet)          │
│  ┌──────────────────────────────┐   │
│  │   Citadel Governance Hub     │   │
│  │   - APIM (External/Internal) │   │
│  │   - Private Endpoints        │   │
│  │   - Log Analytics            │   │
│  └──────────────────────────────┘   │
│  ┌──────────────────────────────┐   │
│  │   Shared Services            │   │
│  │   - Azure Firewall           │   │
│  │   - DNS                      │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
           │           │
           ▼           ▼
    ┌──────────┐  ┌──────────┐
    │ Spoke 1  │  │ Spoke 2  │
    │ Agents   │  │ Agents   │
    └──────────┘  └──────────┘
```

**Configuration:**
```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-eastus'
param existingVnetRG = 'rg-network-hub'
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-private-endpoints'
param dnsZoneRG = 'rg-network-hub'
param dnsSubscriptionId = '<hub-subscription-id>'
```

**When to Use:**
- ✅ Citadel manages all enterprise AI traffic
- ✅ Direct spoke-to-hub connectivity
- ✅ Simplified network topology

---

##### **Approach 2: Hub-Spoke-Hub (Citadel as Dedicated Spoke)**

Citadel deployed in a **dedicated spoke** with firewall in between.

```
                 ┌─────────────┐
                 │ Hub Network │
                 │  - Firewall │
                 │  - DNS      │
                 └──────┬──────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
  ┌────────────┐ ┌────────────┐ ┌────────────┐
  │  Spoke 1   │ │  Citadel   │ │  Spoke 2   │
  │  Agents    │ │  Governance│ │  Agents    │
  └────────────┘ │   Hub      │ └────────────┘
                 │  - APIM    │
                 │  - PE      │
                 └────────────┘
```

**Configuration:**
```bicep
param useExistingVnet = false  // Creates new spoke VNet
param vnetName = 'vnet-citadel-eastus'
param vnetAddressPrefix = '10.170.0.0/24'
param dnsZoneRG = 'rg-network-hub'
param dnsSubscriptionId = '<hub-subscription-id>'

// Post-deployment: Configure VNet peering to hub
```

**When to Use:**
- ✅ Defense-in-depth security (dual inspection)
- ✅ Isolated AI workloads from general traffic
- ✅ Separate cost centers/subscriptions
- ✅ Compliance requirements for network isolation

---

#### Network Setup Options

##### **Option 1: Create New Network (Greenfield)**

Citadel creates all networking components:

```bicep
param useExistingVnet = false
param vnetAddressPrefix = '10.170.0.0/24'
param apimSubnetPrefix = '10.170.0.0/26'
param privateEndpointSubnetPrefix = '10.170.0.64/26'
param functionAppSubnetPrefix = '10.170.0.128/26'

// Network access
param apimNetworkType = 'External'  // or 'Internal' for production
param apimV2UsePrivateEndpoint = true
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Enabled'  // Required during deployment of APIM v2 SKUs
```

**Includes:**
- ✅ Virtual Network with subnets
- ✅ Network Security Groups
- ✅ Private DNS Zones
- ✅ Private Endpoints for all services
- ✅ Route tables (needed for APIM Developer and Premium SKUs)

---

##### **Option 2: Bring Your Own Network (Brownfield)**

Integrate with existing enterprise network:

```bicep
param useExistingVnet = true
param vnetName = 'vnet-hub-prod-eastus'
param existingVnetRG = 'rg-network-prod'

// Subnet names (must exist)
param apimSubnetName = 'snet-citadel-apim'
param privateEndpointSubnetName = 'snet-citadel-pe'
param functionAppSubnetName = 'snet-citadel-functions'

// DNS configuration
param dnsZoneRG = 'rg-network-dns'
param dnsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

**Prerequisites:**
1. VNet with sufficient address space
2. Three subnets created:
   - APIM subnet: `/26` or larger (64 IPs)
   - Private endpoint subnet: `/26` or larger
   - Function App subnet: `/26` or larger
3. Private DNS zones created (or delegated)
4. NSG required rules configured for APIM subnet

**Required DNS Zones:**
- `privatelink.openai.azure.com`
- `privatelink.cognitiveservices.azure.com`
- `privatelink.vaultcore.azure.net`
- `privatelink.monitor.azure.com`
- `privatelink.servicebus.windows.net`
- `privatelink.documents.azure.com`
- `privatelink.blob.core.windows.net`
- `privatelink.file.core.windows.net`
- `privatelink.table.core.windows.net`
- `privatelink.queue.core.windows.net`
- `privatelink.azure-api.net` (for APIM v2 SKUs)
- `privatelink.services.ai.azure.com` (for AI Foundry)

**APIM Subnet Requirements:**

For **Developer/Premium SKU** (VNet injection):
```bash
# No special delegation required
# NSG must allow all required APIM management traffic
# must have required service endpoints enabled
# associated with APIM route table
```

For **StandardV2/PremiumV2 SKU** (Private Endpoint):
```bash
# Standard subnet configuration
# Private endpoint will be created
```

Detailed guide: [Bring Your Own Network](./bring-your-own-network.md)

---

### 4. AI Model Deployment (Optional)

#### AI Foundry Configuration

AI Citadel can deploy **AI Foundry instances** with model deployments automatically.

##### Single Instance Deployment

```bicep
param aiFoundryInstances = [
  {
    name: ''  // Auto-generated
    location: 'eastus'
    customSubDomainName: ''
    defaultProjectName: 'citadel-governance-project'
  }
]

param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0  // Deploy to first instance
  }
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
]
```

##### Multi-Instance Deployment (Geo-Redundancy)

```bicep
param aiFoundryInstances = [
  {
    name: 'aif-citadel-eastus'
    location: 'eastus'
    customSubDomainName: 'citadel-eastus'
    defaultProjectName: 'production-project'
  }
  {
    name: 'aif-citadel-westus'
    location: 'westus'
    customSubDomainName: 'citadel-westus'
    defaultProjectName: 'production-project'
  }
]

param aiFoundryModelsConfig = [
  // Deploy to BOTH instances (omit aiserviceIndex)
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 200
    // No aiserviceIndex = deployed to all instances
  }
  // Deploy to specific instance
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0  // Only eastus
  }
  {
    name: 'DeepSeek-R1'
    publisher: 'DeepSeek'
    version: '1'
    sku: 'GlobalStandard'
    capacity: 1
    aiserviceIndex: 1  // Only westus
  }
]
```

##### Available Model Types

**Foundry Models:**
Check Microsoft Foundry model catalog to understand the available models and versions.
- `gpt-4o` - Latest GPT-4 Omni (multimodal)
- `gpt-4o-mini` - Cost-optimized GPT-4 Omni
- `text-embedding-3-large` - Latest embeddings
- `gpt-image-1` - Image generation
- `DeepSeek-R1` - Document search and retrieval
- `gpt-realtime` - Real-time audio-in audio out model

**Deployment SKUs:**
- `GlobalStandard` - Global deployment (recommended)
- `Standard` - Regional deployment
- `ProvisionedManaged` - Reserved capacity

##### Disable Microsoft Foundry Model deployment

To skip Microsoft Foundry models deployment:

```bicep
param aiFoundryModelsConfig = []
```

You can add Microsoft Foundry models later or use existing deployment instances.

---

### 5. Log Analytics Strategy

#### Option 1: Create New Log Analytics Workspace

**Recommended for:** Isolated environments, proof-of-concept, dedicated subscriptions

```bicep
param useExistingLogAnalytics = false
param logAnalyticsName = ''  // Auto-generated: log-abc123def

// Private Link Scope (optional)
param useAzureMonitorPrivateLinkScope = false
```

**Benefits:**
- ✅ Isolated logs per environment
- ✅ Independent retention policies
- ✅ Simplified RBAC
- ✅ Environment-specific dashboards

**Typical Setup:**
```
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ LAW Dev        │  │ LAW Staging    │  │ LAW Prod       │
│ - 30d retention│  │ - 90d retention│  │ - 180d retention│
│ - Dev RBAC     │  │ - Ops RBAC     │  │ - Audit RBAC   │
└────────────────┘  └────────────────┘  └────────────────┘
```

---

#### Option 2: Bring Your Own Log Analytics (Recommended for Enterprise)

**Recommended for:** Enterprise, multi-environment, centralized monitoring

```bicep
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-centralized-prod'
param existingLogAnalyticsRG = 'rg-monitoring-prod'
param existingLogAnalyticsSubscriptionId = '00000000-0000-0000-0000-000000000000'
```

**Benefits:**
- ✅ Centralized logging across all environments
- ✅ Integration with central SIEM
- ✅ Cross-environment correlation
- ✅ Unified dashboards and alerting
- ✅ Cost optimization (single workspace)
- ✅ Compliance and audit requirements

**Typical Setup:**
```
                  ┌──────────────────────────┐
                  │ Centralized LAW (Prod)   │
                  │ - All environments       │
                  │ - 180d retention         │
                  │ - Advanced analytics     │
                  └──────────────────────────┘
                            ▲
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
    ┌────────┐         ┌────────┐        ┌────────┐
    │  Dev   │         │Staging │        │  Prod  │
    │ Citadel│         │Citadel │        │ Citadel│
    └────────┘         └────────┘        └────────┘
```

**Cross-Subscription Support:**

Citadel supports Log Analytics in a different subscription:

```bicep
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-platform-shared'
param existingLogAnalyticsRG = 'rg-platform-monitoring'
param existingLogAnalyticsSubscriptionId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
```

**Required Permissions:**
- Reader on Log Analytics workspace
- Contributor on Application Insights (created in target subscription)

---

### 6. Security & Compliance

#### Entra ID Authentication

**Production Requirement:** Enable JWT-based authentication

```bicep
param entraAuth = true
param entraTenantId = '00000000-0000-0000-0000-000000000000'
param entraClientId = '11111111-2222-3333-4444-555555555555'
param entraAudience = 'api://citadel-gateway'
```

**Setup Steps:**
1. Register App in Entra ID
2. Configure API permissions
3. Create client secret (store in Key Vault)
4. Update parameter file

Guide: [Entra ID Authentication](./entraid-auth-validation.md)

#### Network Security

**Production Configuration:**
```bicep
// APIM Security
param apimNetworkType = 'Internal'  // No public access
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = false

// Service Network Access
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Disabled'  // Enable during deployment, disable after
param languageServiceExternalNetworkAccess = 'Disabled'
param aiContentSafetyExternalNetworkAccess = 'Disabled'

// Private Link Scope
param useAzureMonitorPrivateLinkScope = true
```

#### Data Protection

**PII Detection & Masking:**
```bicep
param enableAIGatewayPiiRedaction = true
```

Automatically detects and redacts:
- Email addresses
- Phone numbers
- SSN/Tax IDs
- Credit card numbers
- Custom patterns

**Content Safety:**
```bicep
// Enabled by default
// Protects against:
// - Harmful content
// - Prompt injection attacks
// - Jailbreak attempts
```

---

## 🚀 Deployment Execution

### Method 1: Azure Cloud Shell

**Best for:** Quick deployments, testing, no local setup

```bash
# 1. Open Azure Cloud Shell
# https://shell.azure.com

# 2. Clone repository
git clone https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator.git
cd ai-hub-gateway-solution-accelerator

# 3. Authenticate
az login
az account set --subscription "<subscription-name>"

# 4. Deploy using parameter file
az deployment sub create \
  --name "citadel-$(date +%Y%m%d-%H%M%S)" \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.prod.bicepparam

# 5. Monitor deployment
az deployment sub show \
  --name citadel-<timestamp> \
  --query properties.provisioningState
```

---

### Method 2: Local Machine (azd)

**Best for:** Development, iteration, local testing

```bash
# 1. Install prerequisites
# - Azure Developer CLI
# - Azure CLI

# 2. Clone and navigate
git clone https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator.git
cd ai-hub-gateway-solution-accelerator

# 3. Create environment
azd env new citadel-prod

# 4. Set environment variables
azd env set AZURE_LOCATION eastus
azd env set APIM_SKU PremiumV2
azd env set ENABLE_AI_FOUNDRY true

# 5. Login and deploy
azd auth login
azd up

# 6. View outputs
azd env get-values
```

**Using Custom Parameter File:**

```bash
# Override with parameter file
az deployment sub create \
  --name citadel-prod \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.prod.bicepparam
```

---

## 🌍 Environment-Specific Configurations

### Development Environment

**File:** `main.parameters.dev.bicepparam`

```bicep
using './main.bicep'

param environmentName = 'citadel-dev'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-dev'
  Environment: 'Development'
  CostCenter: 'Engineering'
}

// Cost-optimized SKUs
param apimSku = 'Developer'
param apimSkuUnits = 1
param cosmosDbRUs = 400
param eventHubCapacityUnits = 1

// Simplified networking
param apimNetworkType = 'External'
param cosmosDbPublicAccess = 'Enabled'
param eventHubNetworkAccess = 'Enabled'

// Features
param enableAIFoundry = true
param enableAPICenter = false  // Save costs
param createAppInsightsDashboards = true
param entraAuth = false  // Simplify testing

// Models
param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o-mini'
    publisher: 'OpenAI'
    version: '2024-07-18'
    sku: 'GlobalStandard'
    capacity: 50
    aiserviceIndex: 0
  }
]
```

**Deployment:**
```bash
az deployment sub create \
  --name citadel-dev \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.dev.bicepparam
```

---

### Staging Environment

**File:** `main.parameters.staging.bicepparam`

```bicep
using './main.bicep'

param environmentName = 'citadel-staging'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-staging'
  Environment: 'Staging'
  CostCenter: 'Platform'
  Criticality: 'Medium'
}

// Production SKUs with reduced capacity
param apimSku = 'StandardV2'
param apimSkuUnits = 1
param cosmosDbRUs = 1000
param eventHubCapacityUnits = 2

// Secure networking (mirrors production)
param useExistingVnet = true
param vnetName = 'vnet-hub-staging-eastus'
param existingVnetRG = 'rg-network-staging'
param apimNetworkType = 'Internal'
param apimV2UsePrivateEndpoint = true
param cosmosDbPublicAccess = 'Disabled'

// Use shared Log Analytics
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-platform-shared'
param existingLogAnalyticsRG = 'rg-monitoring-prod'

// Enable all features
param enableAIFoundry = true
param enableAPICenter = true
param createAppInsightsDashboards = true
param entraAuth = true

// Staging models
param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 100
    aiserviceIndex: 0
  }
]
```

---

### Production Environment

**File:** `main.parameters.prod.bicepparam`

```bicep
using './main.bicep'

param environmentName = 'citadel-prod'
param location = 'eastus'
param tags = {
  'azd-env-name': 'citadel-prod'
  Environment: 'Production'
  CostCenter: 'Platform'
  Criticality: 'High'
  ComplianceFramework: 'SOC2'
}

// Production-grade SKUs
param apimSku = 'PremiumV2'
param apimSkuUnits = 2
param cosmosDbRUs = 3000
param eventHubCapacityUnits = 5

// Secure networking
param useExistingVnet = true
param vnetName = 'vnet-hub-prod-eastus'
param existingVnetRG = 'rg-network-prod'
param apimNetworkType = 'Internal'
param apimV2UsePrivateEndpoint = true
param apimV2PublicNetworkAccess = false
param cosmosDbPublicAccess = 'Disabled'
param eventHubNetworkAccess = 'Disabled'
param useAzureMonitorPrivateLinkScope = true

// Use shared Log Analytics
param useExistingLogAnalytics = true
param existingLogAnalyticsName = 'law-platform-prod'
param existingLogAnalyticsRG = 'rg-monitoring-prod'

// Enable all features
param enableAIFoundry = true
param enableAPICenter = true
param createAppInsightsDashboards = true
param entraAuth = true
param entraTenantId = '00000000-0000-0000-0000-000000000000'
param entraClientId = '11111111-2222-3333-4444-555555555555'

// Multi-region AI Foundry
param aiFoundryInstances = [
  {
    name: 'aif-citadel-prod-eastus'
    location: 'eastus'
    customSubDomainName: 'citadel-prod-eastus'
    defaultProjectName: 'production-project'
  }
  {
    name: 'aif-citadel-prod-westus'
    location: 'westus'
    customSubDomainName: 'citadel-prod-westus'
    defaultProjectName: 'production-project'
  }
]

param aiFoundryModelsConfig = [
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 200
    aiserviceIndex: 0
  }
  {
    name: 'gpt-4o'
    publisher: 'OpenAI'
    version: '2024-11-20'
    sku: 'GlobalStandard'
    capacity: 200
    aiserviceIndex: 1
  }
]
```

---

## ✅ Post-Deployment Validation

### 1. Verify Resource Deployment

```bash
# List all resources in resource group
RG_NAME=$(az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.resourceGroupName.value -o tsv)

az resource list \
  --resource-group $RG_NAME \
  --output table

```

### 2. Validate APIM Gateway

```bash
# Get APIM details
APIM_NAME=$(az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.APIM_NAME.value -o tsv)

APIM_URL=$(az deployment sub show \
  --name <deployment-name> \
  --query properties.outputs.APIM_GATEWAY_URL.value -o tsv)

# Test health endpoint
curl -I $APIM_URL/status-0123456789abcdef
```

### 3. Test End-to-End Flow

```bash
# Get subscription key
SUBSCRIPTION_KEY=$(az apim subscription show \
  --resource-group $RG_NAME \
  --service-name $APIM_NAME \
  --subscription-id master \
  --query primaryKey -o tsv)

# Test LLM endpoint
curl -X POST "$APIM_URL/llm/chat/completions" \
  -H "api-key: $SUBSCRIPTION_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }'
```

### 5. Verify Monitoring

```bash
# Check Application Insights
az monitor app-insights component show \
  --resource-group $RG_NAME \
  --app appi-apim-* \
  --query applicationId -o tsv

# Query recent telemetry
az monitor app-insights query \
  --app <app-id> \
  --analytics-query "requests | take 10" \
  --output table
```

---

## 🚨 Troubleshooting

Visit the [Deployment Troubleshooting Guide](./#) for common issues and resolutions.

---

### Getting Help

- **GitHub Issues:** [Report a bug](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/issues)
- **Discussions:** [Ask a question](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/discussions)

---

## 📚 Next Steps

**After Successful Deployment:**

1. **Configure AI Services**
   - [OpenAI Integration](./#)
   - [AI Search Setup](./#)
   - [Document Intelligence](./#)

2. **Enable Security**
   - [Entra ID Authentication](./entraid-auth-validation.md)
   - [PII Detection](./pii-masking-apim.md)

3. **Set Up Monitoring**
   - [Power BI Dashboard](./power-bi-dashboard.md)
   - [Alert Configuration](./throttling-events-handling.md)

4. **Onboard Teams**
   - [Citadel Access Contracts](./Citadel-Access-Contracts.md)

---

**Congratulations! Your AI Citadel Governance Hub is now deployed and ready for enterprise AI workloads.** 🎉
