# Using Parameters Files for Bicep Deployment

This guide explains how to use native Bicep parameter files (.bicepparam) for deploying the AI Hub Gateway Solution Accelerator.

## Overview

Bicep parameter files (.bicepparam) provide a strongly-typed, native way to define deployment configurations separately from your Bicep templates, offering:
- Type safety and IntelliSense support in VS Code
- Better validation and error checking at design time
- Cleaner syntax with support for expressions and functions
- Environment variable support with `readEnvironmentVariable()`
- Manage different environment configurations (dev, test, prod)
- Version control your deployment settings

## Available Parameter Files

The solution provides native Bicep parameter files:

### 1. `main.bicepparam` (Minimal - for Azure Developer CLI)
This file contains only essential parameters and reads values from environment variables for Azure Developer CLI (`azd`):

```bicep
using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'citadel-dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus')
param entraAuth = bool(readEnvironmentVariable('AZURE_ENTRA_AUTH', 'false'))
...
```

**Use this file when:**
- Deploying with `azd up` or `azd provision`
- Using Azure Developer CLI workflow
- Following the quick-start deployment path
- Want environment variable substitution

### 2. `main.parameters.complete.bicepparam` (Comprehensive Template)
This file contains **all** available parameters with default values and detailed comments:

**Use this file as a template when:**
- Creating custom environment configurations
- Deploying directly with Azure CLI or Bicep
- Customizing resource names, SKUs, or network configurations
- Need full control over all deployment settings

### 3. Environment-Specific Files
- `main.parameters.dev.bicepparam` - Development environment optimized for cost
- `main.parameters.prod.bicepparam` - Production environment with HA configuration

## Deployment Methods

### Method 1: Using Azure Developer CLI (azd) - Recommended for Quick Start

The Azure Developer CLI uses `main.parameters.json` automatically and reads values from your `.azure/<env-name>/.env` file.

**Steps:**

1. **Initialize your environment:**
   ```powershell
   azd init
   ```

2. **Configure environment variables:**
   Edit `.azure/<your-env-name>/.env` to set your values:
   ```bash
   AZURE_ENV_NAME="citadel-dev"
   AZURE_LOCATION="eastus"
   AZURE_SUBSCRIPTION_ID="your-subscription-id"
   AZURE_ENTRA_AUTH="false"
   OPENAI_CAPACITY="20"
   ```

3. **Deploy:**
   ```powershell
   azd up
   ```
   or
   ```powershell
   azd provision
   ```

### Method 2: Using Azure CLI with Bicep Parameters File

For more control, use Bicep parameter files (.bicepparam) directly with Azure CLI.

**Steps:**

1. **Use an existing environment file or copy the complete template:**
   ```powershell
   # Use existing dev or prod configuration
   # OR copy the complete template
   Copy-Item bicep/infra/main.parameters.complete.bicepparam bicep/infra/main.parameters.myenv.bicepparam
   ```

2. **Edit your .bicepparam file** to match your requirements:
   - Set `environmentName` parameter (e.g., 'citadel-dev')
   - Set `location` parameter (e.g., 'eastus')
   - Customize resource names, SKUs, networking, etc.
   - Bicep parameters use native syntax, no JSON quotes needed

3. **Deploy using Azure CLI:**
   ```powershell
   # Create the deployment
   az deployment sub create `
     --name "citadel-deployment" `
     --location "eastus" `
     --template-file "bicep/infra/main.bicep" `
     --parameters "bicep/infra/main.parameters.dev.bicepparam"
   ```
   
   Note: Use the file path directly (no @ prefix needed for .bicepparam files)

### Method 3: Using Bicep CLI

**Steps:**

1. **Prepare your parameters file** (as shown in Method 2)

2. **Build and deploy using Bicep CLI:**
   ```powershell
   az deployment sub create `
     --name "citadel-deployment" `
     --location "eastus" `
     --template-file "bicep/infra/main.bicep" `
     --parameters "@bicep/infra/main.parameters.dev.json"
   ```

## Parameter File Structure

### Understanding the Complete Parameters File

The `main.parameters.complete.json` file is organized into sections:

#### 1. **Basic Parameters**
```json
"environmentName": { "value": "citadel-dev" },
"location": { "value": "eastus" },
"tags": { "value": { ... } }
```

#### 2. **Resource Names**
Leave empty ("") for auto-generated names or specify custom names:
```json
"apimServiceName": { "value": "" },  // Auto-generated
"apimServiceName": { "value": "my-apim-service" }  // Custom
```

#### 3. **Networking Parameters**
Configure VNet, subnets, and network security:
```json
"vnetAddressPrefix": { "value": "10.170.0.0/24" },
"useExistingVnet": { "value": false },
"apimNetworkType": { "value": "External" }
```

#### 4. **Feature Flags**
Enable or disable specific capabilities:
```json
"enableAIFoundry": { "value": true },
"enableAPICenter": { "value": true },
"enableAIGatewayPiiRedaction": { "value": true }
```

#### 5. **Compute SKU & Size**
Define service tiers and capacity:
```json
"apimSku": { "value": "StandardV2" },
"apimSkuUnits": { "value": 1 },
"cosmosDbRUs": { "value": 400 }
```

#### 6. **AI Foundry Configuration**
Configure AI Foundry instances and model deployments:
```json
"aiFoundryInstances": { "value": [...] },
"aiFoundryModelsConfig": { "value": [...] }
```

## Creating Environment-Specific Parameters

### Development Environment

**File:** `main.parameters.dev.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "citadel-dev" },
    "location": { "value": "eastus" },
    "apimSku": { "value": "Developer" },
    "apimSkuUnits": { "value": 1 },
    "cosmosDbRUs": { "value": 400 },
    "createAppInsightsDashboards": { "value": true },
    "enableAPICenter": { "value": false }
  }
}
```

### Production Environment

**File:** `main.parameters.prod.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "citadel-prod" },
    "location": { "value": "eastus" },
    "apimSku": { "value": "PremiumV2" },
    "apimSkuUnits": { "value": 2 },
    "cosmosDbRUs": { "value": 1000 },
    "eventHubCapacityUnits": { "value": 2 },
    "createAppInsightsDashboards": { "value": true },
    "enableAPICenter": { "value": true },
    "entraAuth": { "value": true },
    "entraTenantId": { "value": "your-tenant-id" },
    "entraClientId": { "value": "your-client-id" },
    "entraAudience": { "value": "your-audience" }
  }
}
```

## Common Customization Scenarios

### Scenario 1: Bring Your Own Network

```json
{
  "parameters": {
    "useExistingVnet": { "value": true },
    "existingVnetRG": { "value": "network-rg" },
    "vnetName": { "value": "my-existing-vnet" },
    "apimSubnetName": { "value": "snet-apim" },
    "privateEndpointSubnetName": { "value": "snet-pe" },
    "functionAppSubnetName": { "value": "snet-func" },
    "dnsZoneRG": { "value": "dns-rg" },
    "dnsSubscriptionId": { "value": "your-subscription-id" }
  }
}
```

### Scenario 2: Custom Resource Names

```json
{
  "parameters": {
    "apimServiceName": { "value": "mycompany-apim-prod" },
    "cosmosDbAccountName": { "value": "mycompany-cosmos-prod" },
    "eventHubNamespaceName": { "value": "mycompany-evhns-prod" },
    "logAnalyticsName": { "value": "mycompany-law-prod" }
  }
}
```

### Scenario 3: AI Foundry with Custom Models

```json
{
  "parameters": {
    "enableAIFoundry": { "value": true },
    "aiFoundryInstances": {
      "value": [
        {
          "name": "my-foundry-eastus",
          "location": "eastus",
          "customSubDomainName": "",
          "defaultProjectName": "production-project"
        }
      ]
    },
    "aiFoundryModelsConfig": {
      "value": [
        {
          "name": "gpt-4o",
          "publisher": "OpenAI",
          "version": "2024-11-20",
          "sku": "GlobalStandard",
          "capacity": 100,
          "aiserviceIndex": 0
        }
      ]
    }
  }
}
```

### Scenario 4: Enable Microsoft Entra ID Authentication

```json
{
  "parameters": {
    "entraAuth": { "value": true },
    "entraTenantId": { "value": "your-tenant-id" },
    "entraClientId": { "value": "your-client-id" },
    "entraAudience": { "value": "api://your-api-id" }
  }
}
```

### Scenario 5: Configure AI Search Integration

```json
{
  "parameters": {
    "enableAzureAISearch": { "value": true },
    "aiSearchInstances": {
      "value": [
        {
          "name": "ai-search-prod-01",
          "url": "https://mysearch01.search.windows.net/",
          "description": "Production AI Search Instance 1"
        },
        {
          "name": "ai-search-prod-02",
          "url": "https://mysearch02.search.windows.net/",
          "description": "Production AI Search Instance 2"
        }
      ]
    }
  }
}
```

## Parameter Override Precedence

When using parameters, values are resolved in this order (highest to lowest priority):

1. **Command-line parameters** (e.g., `--parameters key=value`)
2. **Parameters file** (e.g., `@main.parameters.json`)
3. **Default values** in the Bicep template

### Example with Mixed Approach:

```powershell
az deployment sub create `
  --name "citadel-deployment" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json" `
  --parameters environmentName="citadel-test" apimSku="StandardV2"
```

In this example:
- Most values come from `main.parameters.dev.json`
- `environmentName` and `apimSku` are overridden via command line

## Validation and Best Practices

### 1. Validate Before Deployment

Use What-If to preview changes:

```powershell
az deployment sub what-if `
  --name "citadel-deployment" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json"
```

### 2. Keep Secrets Secure

**Never** store sensitive values in parameter files. Use one of these approaches:

#### Option A: Azure Key Vault Reference
```json
{
  "entraTenantId": {
    "reference": {
      "keyVault": {
        "id": "/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/Microsoft.KeyVault/vaults/{vault-name}"
      },
      "secretName": "entraTenantId"
    }
  }
}
```

#### Option B: Command-line Override
```powershell
az deployment sub create `
  --parameters "@bicep/infra/main.parameters.prod.json" `
  --parameters entraTenantId="$env:ENTRA_TENANT_ID"
```

#### Option C: Azure Developer CLI Environment Variables
Use `.azure/<env>/.env` file (git-ignored):
```bash
AZURE_TENANT_ID="your-secret-value"
```

### 3. Version Control

- **DO** commit: `main.parameters.dev.json`, `main.parameters.prod.json` (with placeholders)
- **DON'T** commit: Files with actual secrets or sensitive values
- Use `.gitignore` to exclude files with real values:
  ```
  # .gitignore
  *.local.json
  *.secrets.json
  .azure/*/. env
  ```

### 4. Documentation

Document your parameter choices:
```json
{
  "parameters": {
    "apimSku": { 
      "value": "PremiumV2",
      "metadata": {
        "description": "Using PremiumV2 for production workload with multi-region support"
      }
    }
  }
}
```

## Troubleshooting

### Issue: Parameter validation errors

**Error:** `The parameter 'environmentName' expects a value of type 'String'`

**Solution:** Ensure your parameter file uses correct JSON syntax and types:
```json
"environmentName": { "value": "citadel-dev" }  // Correct
"environmentName": "citadel-dev"  // Wrong - missing value wrapper
```

### Issue: Template and parameter file mismatch

**Error:** `The parameter 'someParameter' is not defined in the template`

**Solution:** Ensure you're using the correct template and parameter file versions. Remove any parameters not defined in `main.bicep`.

### Issue: Azure Developer CLI not substituting variables

**Error:** Variables like `${AZURE_ENV_NAME}` appear as literal values

**Solution:** 
1. Ensure you're using `azd` commands (not direct `az` commands)
2. Verify your `.azure/<env>/.env` file has the required variables
3. Run `azd env refresh` to reload environment variables

## Additional Resources

- [Bicep Parameter Files Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Solution Architecture Guide](./architecture.md)
- [Deployment Guide](./deployment.md)
- [Troubleshooting Guide](./deployment-troubleshooting.md)

## Quick Reference

| Deployment Scenario | Command | Parameters File |
|-------------------|---------|-----------------|
| Quick start with azd | `azd up` | `main.parameters.json` (auto) |
| Development deployment | `az deployment sub create --parameters @main.parameters.dev.json` | `main.parameters.dev.json` |
| Production deployment | `az deployment sub create --parameters @main.parameters.prod.json` | `main.parameters.prod.json` |
| Full customization | `az deployment sub create --parameters @main.parameters.complete.json` | `main.parameters.complete.json` |
| Preview changes | `az deployment sub what-if --parameters @<file>` | Any parameters file |

## Next Steps

1. Review the [Deployment Guide](./deployment.md) for detailed deployment instructions
2. Customize your parameters file based on your requirements
3. Validate your configuration with `az deployment sub what-if`
4. Deploy using your preferred method
5. Monitor the deployment in Azure Portal
