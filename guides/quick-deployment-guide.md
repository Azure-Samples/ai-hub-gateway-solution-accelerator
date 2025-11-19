# 🚀 Quick Deployment Guide - Non-Production

This guide provides the fastest path to deploying AI Citadel Governance Hub for **development and testing environments**. For production deployments, see the [Full Deployment Guide](./full-deployment-guide.md).

---

## ⚡ Prerequisites

**Required:**
- Azure subscription with **Contributor** or **Owner** permissions
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed

**Optional:**
- [VS Code](https://code.visualstudio.com/) with Bicep extension
- Git for version control

> 💡 **Tip:** You can use [Azure Cloud Shell](https://shell.azure.com) which has all tools pre-installed.

---

## 🎯 Deployment Options

Choose your deployment method:

### Option 1: Default Quick Deploy (Recommended)

Deploy with minimal configuration using intelligent defaults:

```bash
# Authenticate to Azure
azd auth login

# Initialize environment
azd env new ai-hub-citadel-dev

# Deploy everything
azd up
```

This will:
- ✅ Create a new resource group
- ✅ Deploy all infrastructure with default settings
- ✅ Use StandardV2 SKU for API Management (production-capable)
- ✅ Create new Virtual Network with private endpoints
- ✅ Create new Log Analytics workspace
- ✅ Deploy 2 AI Foundry instances with sample models
- ✅ Enable all core features (PII detection, content safety, API Center)

**Expected deployment time:** 30-45 minutes

---

### Option 2: Customized Quick Deploy

Customize key settings using environment variables:

```bash
# Authenticate and initialize
azd auth login
azd env new citadel-dev

# Set custom environment variables
azd env set AZURE_LOCATION eastus2
azd env set APIM_SKU Developer
azd env set ENABLE_AI_FOUNDRY true
azd env set CREATE_DASHBOARDS true

# Deploy
azd up
```

#### Common Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AZURE_LOCATION` | `eastus` | Primary Azure region |
| `APIM_SKU` | `StandardV2` | API Management SKU (use `Developer` for dev) |
| `COSMOS_DB_RUS` | `400` | Cosmos DB throughput |
| `EVENTHUB_CAPACITY` | `1` | Event Hub capacity units |
| `ENABLE_AI_FOUNDRY` | `true` | Deploy AI Foundry instances |
| `ENABLE_API_CENTER` | `true` | Enable API Center registry |
| `ENABLE_PII_REDACTION` | `true` | Enable PII detection/masking |
| `CREATE_DASHBOARDS` | `false` | Create Application Insights dashboards |

---

### Option 3: Parameter File Deploy

Use the pre-configured dev parameter file:

```bash
# Authenticate
azd auth login

# Deploy using parameter file
az deployment sub create \
  --name citadel-dev-deployment \
  --location eastus \
  --template-file ./bicep/infra/main.bicep \
  --parameters ./bicep/infra/main.parameters.dev.bicepparam
```

The `main.parameters.dev.bicepparam` file includes:
- Developer SKU for cost savings
- Minimal capacity settings
- Public network access enabled (easier development)
- Application Insights dashboards enabled
- API Center disabled (reduce costs)

---

## 🔧 Post-Deployment Configuration

### 1. Verify Deployment

```bash
# Get deployment outputs
azd env get-values

# Key outputs:
# - APIM_GATEWAY_URL: Your AI Gateway endpoint
# - APIM_NAME: API Management service name
```

### 2. Access API Management

```bash
# Get APIM Gateway URL
APIM_URL=$(azd env get-values | grep APIM_GATEWAY_URL | cut -d'=' -f2)
echo "AI Gateway: $APIM_URL"

# Navigate to Azure Portal
az apim show --name <APIM_NAME> --resource-group <RG_NAME> --query id -o tsv
```

### 3. Get API Subscription Key

```bash
# List subscriptions
az apim subscription list \
  --resource-group <RG_NAME> \
  --service-name <APIM_NAME> \
  --output table

# Get primary key for a subscription
az apim subscription show \
  --resource-group <RG_NAME> \
  --service-name <APIM_NAME> \
  --subscription-id <SUBSCRIPTION_ID> \
  --query primaryKey -o tsv
```

---

## 🧪 Test Your Deployment

### Test AI Foundry Model Access

```bash
curl -X POST "${APIM_URL}/llm/chat/completions" \
  -H "api-key: YOUR_SUBSCRIPTION_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "Hello from Citadel!"}
    ]
  }'
```

### Verify Content Safety

Test that harmful content is blocked:

```bash
curl -X POST "${APIM_URL}/llm/chat/completions" \
  -H "api-key: YOUR_SUBSCRIPTION_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "user", "content": "How to make a dangerous weapon"}
    ]
  }'
```

Expected: Request blocked with appropriate error message.

---

## 📊 Monitor Your Deployment

### Application Insights

1. Navigate to Azure Portal
2. Find Application Insights resource (name: `appi-apim-*`)
3. View:
   - Live Metrics
   - Transaction Search
   - Failures and Performance

### Usage Analytics

1. Navigate to Cosmos DB resource
2. Open Data Explorer
3. Query `usage-db` database, `usage` container

```sql
SELECT * FROM c 
WHERE c._ts > (GetCurrentTimestamp()/1000 - 3600) 
ORDER BY c._ts DESC
```

---

## 🔄 Update Deployment

### Update Infrastructure

```bash
# Pull latest changes
git pull

# Redeploy
azd up
```

### Update Configuration Only

```bash
# Update environment variables
azd env set COSMOS_DB_RUS 800

# Redeploy affected resources
azd deploy
```

---

## 🧹 Clean Up

### Remove All Resources

```bash
# Delete all deployed resources
azd down --purge
```

### Keep Data, Remove Compute

```bash
# Manual cleanup via Azure Portal
# Delete: APIM, Function App, Logic App
# Keep: Cosmos DB, Storage Account, Log Analytics
```

---

## 🚨 Troubleshooting

### Deployment Fails

**Check provider registration:**
```bash
az provider register --namespace Microsoft.ApiManagement
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.EventHub
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Logic
```

**Check quota limits:**
```bash
# Verify APIM quota
az apim check-name-availability \
  --name <your-apim-name> \
  --output table
```

### APIM Takes Too Long

API Management deployment can take 30-45 minutes. This is normal.

```bash
# Check deployment status
az deployment sub show \
  --name <deployment-name> \
  --query properties.provisioningState
```

### Can't Access AI Models

**Verify AI Foundry deployment:**
```bash
# List AI services
az cognitiveservices account list \
  --resource-group <RG_NAME> \
  --output table

# Check model deployments
az cognitiveservices account deployment list \
  --resource-group <RG_NAME> \
  --name <AI_SERVICE_NAME> \
  --output table
```

---

## ⚙️ Default Configuration

The quick deployment uses these defaults (from `main.bicepparam`):

| Component | Setting | Value |
|-----------|---------|-------|
| **APIM SKU** | `apimSku` | `StandardV2` |
| **APIM Units** | `apimSkuUnits` | `1` |
| **Cosmos DB** | `cosmosDbRUs` | `400 RU/s` |
| **Event Hub** | `eventHubCapacityUnits` | `1` |
| **Network** | `useExistingVnet` | `false` (creates new) |
| **Log Analytics** | `useExistingLogAnalytics` | `false` (creates new) |
| **AI Foundry** | `enableAIFoundry` | `true` |
| **API Center** | `enableAPICenter` | `true` |
| **PII Detection** | `enableAIGatewayPiiRedaction` | `true` |
| **Dashboards** | `createAppInsightsDashboards` | `false` |

---

## 📚 Next Steps

**For Development:**
- ✅ [Test OpenAI Integration](./openai-onboarding.md)
- ✅ [Configure PII Masking](./pii-masking-apim.md)
- ✅ [Set Up Usage Analytics](./power-bi-dashboard.md)

**For Production:**
- 📘 [Full Deployment Guide](./full-deployment-guide.md)
- 🔒 [Enable Entra ID Auth](./entraid-auth-validation.md)
- 🌐 [Bring Your Own Network](./bring-your-own-network.md)
- 🏗️ [Enterprise Provisioning](./enterprise-provisioning.md)

---

## 💡 Pro Tips

1. **Use Azure Cloud Shell** - No local setup required
2. **Start Small** - Use Developer SKU and minimal capacity
3. **Enable Dashboards** - Set `CREATE_DASHBOARDS=true` for visibility
4. **Monitor Costs** - Check Azure Cost Management daily
5. **Version Control** - Commit your `.env` file structure (not values!)
6. **Tag Resources** - Use meaningful tags for cost allocation

---

**Need Help?** 
- [Deployment Troubleshooting Guide](./deployment-troubleshooting.md)
- [GitHub Issues](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/issues)
- [GitHub Discussions](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator/discussions)
