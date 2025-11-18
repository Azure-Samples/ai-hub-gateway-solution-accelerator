# Quick Start: Bicep Deployment with Parameters

This guide provides quick commands for deploying the AI Hub Gateway Solution Accelerator using Bicep parameter files (.bicepparam).

## Prerequisites

- Azure CLI installed and logged in: `az login`
- Azure Developer CLI (azd) installed (for Method 1)
- Appropriate Azure subscription permissions
- Bicep CLI (included with Azure CLI 2.20.0+)

## Method 1: Azure Developer CLI (Recommended for Quick Start)

### Step 1: Initialize Environment
```powershell
azd init
```

### Step 2: Configure Environment Variables
Copy the template and configure:
```powershell
Copy-Item .env.template .azure/citadel-dev/.env
```

Edit `.azure/citadel-dev/.env` with your values:
```bash
AZURE_ENV_NAME="citadel-dev"
AZURE_LOCATION="eastus"
AZURE_SUBSCRIPTION_ID="your-subscription-id"
```

### Step 3: Deploy
```powershell
azd up
```

**Parameters File Used:** `bicep/infra/main.bicepparam` (automatic)

---

## Method 2: Azure CLI with Bicep Parameters

### Step 1: Choose or Create Your Parameters File
```powershell
# Option A: Use pre-configured development environment
$paramsFile = "bicep/infra/main.parameters.dev.bicepparam"

# Option B: Use pre-configured production environment  
$paramsFile = "bicep/infra/main.parameters.prod.bicepparam"

# Option C: Create custom from template
Copy-Item bicep/infra/main.parameters.complete.bicepparam bicep/infra/main.parameters.custom.bicepparam
$paramsFile = "bicep/infra/main.parameters.custom.bicepparam"
# Edit the file with your custom values
```

### Step 2: Customize Parameters (if needed)
Edit your `.bicepparam` file:
```bicep
param environmentName = 'my-environment'
param location = 'eastus'
param apimSku = 'StandardV2'
param enableAIFoundry = true
```

### Step 3: Preview Deployment (Optional but Recommended)
```powershell
az deployment sub what-if `
  --name "citadel-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters $paramsFile
```

### Step 4: Deploy
```powershell
az deployment sub create `
  --name "citadel-$(Get-Date -Format 'yyyyMMddHHmmss')" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters $paramsFile
```

Note: No @ prefix needed for .bicepparam files

---

## Common Deployment Scenarios

### Scenario 1: Development Environment (Minimal Cost)
**Parameters:**
```json
{
  "environmentName": { "value": "citadel-dev" },
  "location": { "value": "eastus" },
  "apimSku": { "value": "Developer" },
  "cosmosDbRUs": { "value": 400 },
  "eventHubCapacityUnits": { "value": 1 },
  "createAppInsightsDashboards": { "value": false }
}
```

**Deploy:**
```powershell
azd up
# or
az deployment sub create --parameters "@bicep/infra/main.parameters.dev.json" ...
```

### Scenario 2: Production Environment (High Availability)
**Parameters:**
```json
{
  "environmentName": { "value": "citadel-prod" },
  "location": { "value": "eastus" },
  "apimSku": { "value": "PremiumV2" },
  "apimSkuUnits": { "value": 2 },
  "cosmosDbRUs": { "value": 1000 },
  "eventHubCapacityUnits": { "value": 2 },
  "createAppInsightsDashboards": { "value": true },
  "entraAuth": { "value": true }
}
```

### Scenario 3: Bring Your Own Network (BYON)
**Parameters:**
```json
{
  "environmentName": { "value": "citadel-byon" },
  "location": { "value": "eastus" },
  "useExistingVnet": { "value": true },
  "existingVnetRG": { "value": "network-rg" },
  "vnetName": { "value": "my-vnet" },
  "apimSubnetName": { "value": "snet-apim" },
  "privateEndpointSubnetName": { "value": "snet-pe" },
  "functionAppSubnetName": { "value": "snet-func" },
  "dnsZoneRG": { "value": "dns-rg" }
}
```

### Scenario 4: Enable Entra ID Authentication
**Environment Variables (.env):**
```bash
AZURE_ENTRA_AUTH="true"
AZURE_TENANT_ID="your-tenant-id"
AZURE_CLIENT_ID="your-app-client-id"
AZURE_AUDIENCE="api://your-api-id"
```

**Or in Parameters File:**
```json
{
  "entraAuth": { "value": true },
  "entraTenantId": { "value": "your-tenant-id" },
  "entraClientId": { "value": "your-app-client-id" },
  "entraAudience": { "value": "api://your-api-id" }
}
```

---

## Override Parameters on Command Line

You can override specific parameters without modifying the file:

```powershell
az deployment sub create `
  --name "citadel-deployment" `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json" `
  --parameters environmentName="citadel-test" apimSku="StandardV2"
```

---

## Validation Commands

### 1. Validate Template Syntax
```powershell
az deployment sub validate `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json"
```

### 2. Preview Changes (What-If)
```powershell
az deployment sub what-if `
  --location "eastus" `
  --template-file "bicep/infra/main.bicep" `
  --parameters "@bicep/infra/main.parameters.dev.json"
```

### 3. Build Bicep to ARM
```powershell
az bicep build --file bicep/infra/main.bicep
```

---

## Monitoring Deployment

### Azure Developer CLI
```powershell
# View deployment logs
azd monitor --overview

# View specific resource logs
azd monitor --logs
```

### Azure CLI
```powershell
# List deployments
az deployment sub list --query "[?name=='citadel-deployment']"

# Show deployment details
az deployment sub show --name "citadel-deployment"

# Monitor deployment operations
az deployment operation sub list --name "citadel-deployment"
```

### Azure Portal
1. Navigate to: **Subscriptions** → **Your Subscription** → **Deployments**
2. Find your deployment by name
3. Review deployment details and outputs

---

## Post-Deployment

### Get Deployment Outputs
```powershell
# Using azd
azd env get-values

# Using Azure CLI
az deployment sub show --name "citadel-deployment" --query properties.outputs
```

### Important Outputs
- `APIM_GATEWAY_URL` - API Management gateway URL
- `APIM_NAME` - API Management service name
- `AI_FOUNDRY_SERVICES` - AI Foundry service details
- `LLM_BACKEND_CONFIG` - LLM backend configuration

---

## Cleanup

### Azure Developer CLI
```powershell
azd down
```

### Azure CLI
```powershell
# Delete resource group
az group delete --name "rg-citadel-dev" --yes
```

---

## Troubleshooting

### Issue: Deployment fails with parameter validation error
**Solution:** Verify parameter types and values match the Bicep template requirements.

### Issue: Cannot find parameters file
**Solution:** Use absolute or relative path with @ prefix:
```powershell
--parameters "@C:/full/path/to/main.parameters.dev.json"
# or
--parameters "@./bicep/infra/main.parameters.dev.json"
```

### Issue: azd not substituting environment variables
**Solution:** 
1. Verify `.azure/<env>/.env` file exists
2. Run `azd env refresh`
3. Use `azd env get-values` to check current values

---

## Complete Example Workflow

```powershell
# 1. Clone repository
git clone https://github.com/your-org/ai-hub-gateway-solution-accelerator
cd ai-hub-gateway-solution-accelerator

# 2. Initialize Azure Developer CLI
azd init

# 3. Configure environment
Copy-Item .env.template .azure/citadel-dev/.env
# Edit .azure/citadel-dev/.env with your values

# 4. Preview deployment
azd provision --preview

# 5. Deploy
azd up

# 6. Get outputs
azd env get-values

# 7. Test APIM endpoint
$apimUrl = azd env get-values | Select-String "APIM_GATEWAY_URL" | ForEach-Object { $_.Line.Split('=')[1] }
curl "$apimUrl/health"

# 8. When done, cleanup
azd down
```

---

## Next Steps

- Review [Complete Parameters Deployment Guide](./parameters-deployment-guide.md)
- Configure [Use Case Onboarding](./use-case-onboarding-decision-guide.md)
- Set up [Enterprise Provisioning](./enterprise-provisioning.md)
- Enable [Entra ID Authentication](./entraid-auth-validation.md)

---

## Resources

| Resource | Location |
|----------|----------|
| Complete Parameters File | `bicep/infra/main.parameters.complete.json` |
| AZD Parameters File | `bicep/infra/main.parameters.json` |
| Environment Template | `.env.template` |
| Main Bicep Template | `bicep/infra/main.bicep` |
| Detailed Guide | `guides/parameters-deployment-guide.md` |
