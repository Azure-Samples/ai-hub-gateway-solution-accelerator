# Dynamic LLM Backend Configuration Guide

## Overview

This solution enables **dynamic LLM backend routing** in Azure API Management (APIM), allowing you to:

- **Route requests to multiple LLM providers** (Azure OpenAI, AI Foundry, external providers)
- **Load balance across multiple backends** for the same model
- **Automatically failover** when backends are unavailable
- **Easily add new models and backends** without modifying policy XML
- **Support flexible authentication** schemes per backend

## Architecture

### Components

1. **LLM Backend Configuration** (`llmBackendConfig` parameter)
   - Defines all available LLM backends and their supported models
   - Passed to deployment via parameter file

2. **Backend Module** (`llm-backends.bicep`)
   - Creates individual APIM backend resources for each LLM endpoint
   - Configures authentication, circuit breakers, and TLS settings

3. **Backend Pool Module** (`llm-backend-pools.bicep`)
   - Analyzes backend configuration to identify models supported by multiple backends
   - Creates backend pools for load balancing and failover
   - Generates routing maps for policy fragments

4. **Policy Fragment Module** (`llm-policy-fragments.bicep`)
   - Dynamically generates policy fragments with backend pool configurations
   - Injects C# code into `set-backend-pools` fragment
   - Configures authentication for different backend types in `set-backend-authorization`

5. **Universal LLM API** (`inference-api.bicep`)
   - Exposes unified endpoint for all LLM requests
   - Uses policy fragments for intelligent routing

### Flow Diagram

```
Request → APIM → Policy Validation → Model Extraction → Backend Pool Selection → Authentication → Backend → Response
```

## Configuration

### Backend Configuration Structure

Each backend in the `llmBackendConfig` array has the following properties:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `backendId` | string | Yes | Unique identifier for the backend (used in APIM resource name) |
| `backendType` | string | Yes | Type of backend: `ai-foundry`, `azure-openai`, or `external` |
| `endpoint` | string | Yes | Base URL of the LLM service endpoint |
| `authScheme` | string | Yes | Authentication method: `managedIdentity`, `apiKey`, or `token` |
| `supportedModels` | array | Yes | Array of model names this backend can serve |
| `priority` | number | No | Priority for routing (1-5, lower = higher priority). Default: 1 |
| `weight` | number | No | Weight for load balancing (1-1000, higher = more traffic). Default: 100 |

### Example Configuration

#### Single AI Foundry Backend

```json
{
  "llmBackendConfig": [
    {
      "backendId": "ai-foundry-eastus-gpt4",
      "backendType": "ai-foundry",
      "endpoint": "https://my-project-eastus.eastus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4", "gpt-4-turbo", "gpt-4o"]
    }
  ]
}
```

#### Multiple Backends with Load Balancing

```json
{
  "llmBackendConfig": [
    {
      "backendId": "ai-foundry-eastus-gpt4",
      "backendType": "ai-foundry",
      "endpoint": "https://my-project-eastus.eastus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4", "gpt-4-turbo"],
      "priority": 1,
      "weight": 100
    },
    {
      "backendId": "azure-openai-westus-gpt4",
      "backendType": "azure-openai",
      "endpoint": "https://my-openai-westus.openai.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4", "gpt-4-turbo"],
      "priority": 2,
      "weight": 50
    },
    {
      "backendId": "azure-openai-eastus-embeddings",
      "backendType": "azure-openai",
      "endpoint": "https://my-openai-eastus.openai.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["text-embedding-ada-002", "text-embedding-3-large"]
    }
  ]
}
```

#### Mixed Providers (AI Foundry + Azure OpenAI + External)

```json
{
  "llmBackendConfig": [
    {
      "backendId": "ai-foundry-llama",
      "backendType": "ai-foundry",
      "endpoint": "https://llama-project.eastus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["Llama-3.3-70B-Instruct", "Llama-3.2-11B-Vision-Instruct"]
    },
    {
      "backendId": "ai-foundry-phi",
      "backendType": "ai-foundry",
      "endpoint": "https://phi-project.westus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["phi-4", "Phi-4-multimodal-instruct"]
    },
    {
      "backendId": "azure-openai-primary",
      "backendType": "azure-openai",
      "endpoint": "https://primary-openai.openai.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4o", "gpt-35-turbo", "text-embedding-ada-002"]
    }
  ]
}
```

## Deployment

### 1. Update Parameter File

Add the `llmBackendConfig` parameter to your `main.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": {
      "value": "my-environment"
    },
    "location": {
      "value": "eastus"
    },
    "llmBackendConfig": {
      "value": [
        {
          "backendId": "ai-foundry-gpt4",
          "backendType": "ai-foundry",
          "endpoint": "https://my-project.eastus.inference.ml.azure.com",
          "authScheme": "managedIdentity",
          "supportedModels": ["gpt-4", "gpt-4-turbo"]
        }
      ]
    }
  }
}
```

### 2. Deploy Infrastructure

```bash
# Using Azure CLI
az deployment sub create \
  --name main-deployment \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json

# Using Azure Developer CLI (azd)
azd up
```

### 3. Verify Deployment

After deployment, verify the resources:

```bash
# List backends
az apim backend list \
  --resource-group <resource-group> \
  --service-name <apim-service-name>

# Check policy fragments
az apim policy-fragment list \
  --resource-group <resource-group> \
  --service-name <apim-service-name>
```

## How It Works

### 1. Backend Pool Generation

The `llm-backend-pools.bicep` module analyzes the backend configuration:

- **Single-backend models**: Requests route directly to the backend
- **Multi-backend models**: A backend pool is created for load balancing

Example:
- If backends A and B both support "gpt-4", a "gpt-4-backend-pool" is created
- If only backend C supports "phi-4", requests go directly to backend C

### 2. Policy Fragment Generation

The `llm-policy-fragments.bicep` module generates C# code for the policy fragment:

```csharp
// Auto-generated pool configuration
var gpt4Pool = new JObject()
{
    { "poolName", "gpt-4-backend-pool" },
    { "poolType", "ai-foundry" },
    { "supportedModels", new JArray("gpt-4", "gpt-4-turbo") }
};
backendPools.Add(gpt4Pool);
```

This code is injected into the `set-backend-pools` policy fragment.

### 3. Request Routing

When a request arrives:

1. **Model Extraction**: Policy extracts the `model` parameter from the request body
2. **Pool Selection**: `set-target-backend-pool` fragment matches the model to a backend pool
3. **RBAC Check**: Validates if the request has permission to use the selected pool
4. **Authentication**: `set-backend-authorization` fragment sets up auth based on backend type
5. **Routing**: Request is forwarded to the selected backend

### 4. Authentication by Backend Type

| Backend Type | Authentication Method | URL Rewriting |
|--------------|----------------------|---------------|
| `azure-openai` | Managed Identity (Cognitive Services) | Yes - adds `/deployments/{model}/` path |
| `ai-foundry` | Managed Identity (Cognitive Services) | No - uses standard OpenAI paths |
| `external` | Backend credentials configuration | No |

## Advanced Scenarios

### Load Balancing Configuration

Control traffic distribution using `priority` and `weight`:

```json
{
  "backendId": "primary-backend",
  "backendType": "ai-foundry",
  "endpoint": "https://primary.inference.ml.azure.com",
  "authScheme": "managedIdentity",
  "supportedModels": ["gpt-4"],
  "priority": 1,
  "weight": 80
},
{
  "backendId": "secondary-backend",
  "backendType": "azure-openai",
  "endpoint": "https://secondary.openai.azure.com",
  "authScheme": "managedIdentity",
  "supportedModels": ["gpt-4"],
  "priority": 2,
  "weight": 20
}
```

This routes 80% of traffic to the primary backend and 20% to secondary.

### Regional Deployments

Support different backends per APIM region:

```json
{
  "llmBackendConfig": [
    {
      "backendId": "eastus-gpt4",
      "backendType": "ai-foundry",
      "endpoint": "https://eastus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4"]
    },
    {
      "backendId": "westus-gpt4",
      "backendType": "ai-foundry",
      "endpoint": "https://westus.inference.ml.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4"]
    }
  ]
}
```

Modify the policy fragment to use `context.Deployment.Region` for region-specific routing.

### RBAC-Based Routing

Control which clients can access which backend pools:

In the Universal LLM API policy (`universal-llm-api-policy-v2.xml`):

```xml
<!-- Allow only specific backend pools -->
<set-variable name="allowedBackendPools" value="ai-foundry-gpt4,azure-openai-primary" />
```

Or use JWT claims:

```xml
<set-variable name="allowedBackendPools" value="@{
    var jwt = context.Request.Headers.GetValueOrDefault("Authorization");
    // Extract allowed pools from JWT claims
    return jwt.Contains("premium") ? "all" : "azure-openai-basic";
}" />
```

## Adding New Backends

To add a new backend:

1. **Update parameter file** with new backend configuration
2. **Redeploy** infrastructure
3. **No policy changes needed** - routing is automatic

Example - Adding Claude via AI Foundry:

```json
{
  "backendId": "ai-foundry-claude",
  "backendType": "ai-foundry",
  "endpoint": "https://claude-project.eastus.inference.ml.azure.com",
  "authScheme": "managedIdentity",
  "supportedModels": ["claude-3-5-sonnet-20241022"]
}
```

Clients can immediately start using `"model": "claude-3-5-sonnet-20241022"` in requests.

## Troubleshooting

### Backend Not Found Error

**Symptom**: `400 Bad Request - Model could not be mapped to a backend`

**Solutions**:
1. Verify model name matches `supportedModels` array (case-insensitive)
2. Check backend pool deployment status in APIM
3. Ensure policy fragments are deployed correctly

### Authentication Failures

**Symptom**: `401 Unauthorized` from backend

**Solutions**:
1. Verify managed identity has required roles:
   - `Cognitive Services OpenAI User` for Azure OpenAI
   - `Cognitive Services User` for AI Foundry
2. Check named value `uami-client-id` is set correctly
3. Ensure backend endpoint URLs are correct

### Circuit Breaker Tripping

**Symptom**: `503 Service Unavailable - Backend pool is temporarily unavailable`

**Solutions**:
1. Check backend health in APIM → Backends
2. Review circuit breaker rules in `llm-backends.bicep`
3. Adjust `failureCondition` thresholds if needed

## Best Practices

1. **Use descriptive backend IDs**: Include provider and region (e.g., `ai-foundry-eastus-gpt4`)
2. **Group related models**: Deploy related models on the same backend for better cache utilization
3. **Set appropriate priorities**: Lower priority = higher preference in routing
4. **Configure circuit breakers**: Protect backends from cascading failures
5. **Monitor backend health**: Use APIM analytics and Application Insights
6. **Test failover scenarios**: Verify load balancing works as expected
7. **Document model mappings**: Keep track of which backends serve which models
8. **Use managed identities**: Avoid API keys in configuration

## Security Considerations

- **Managed Identity**: Always use managed identity for Azure resources
- **Private Endpoints**: Deploy backends with private endpoints when possible
- **Network Isolation**: Use VNet integration for APIM to secure traffic
- **RBAC**: Implement fine-grained access control using `allowedBackendPools`
- **Secrets**: Never store API keys in parameter files - use Key Vault references

## Monitoring

Key metrics to monitor:

1. **Backend Health**: Check APIM backend status
2. **Response Times**: Monitor latency per backend
3. **Error Rates**: Track 4xx and 5xx responses
4. **Token Usage**: Monitor consumption per backend
5. **Load Distribution**: Verify traffic is balanced correctly

Use Application Insights queries:

```kusto
requests
| where name contains "universal-llm-api"
| extend model = tostring(customDimensions.model)
| extend backend = tostring(customDimensions.backend)
| summarize count(), avg(duration) by model, backend, bin(timestamp, 5m)
```

## Migration Guide

### From Static OpenAI Backend

**Before** (static configuration):
- Single backend configured in `apim.bicep`
- Model routing hardcoded in policy XML

**After** (dynamic configuration):
```json
{
  "llmBackendConfig": [
    {
      "backendId": "openai-existing",
      "backendType": "azure-openai",
      "endpoint": "https://existing-openai.openai.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4", "gpt-35-turbo"]
    }
  ]
}
```

Benefits:
- Easier to add new backends
- Automatic load balancing
- Built-in failover support

## Support

For issues or questions:
1. Check the [deployment troubleshooting guide](./deployment-troubleshooting.md)
2. Review Application Insights logs
3. Open an issue in the repository

## References

- [APIM Backend Pools Documentation](https://learn.microsoft.com/azure/api-management/backends)
- [AI Foundry Documentation](https://learn.microsoft.com/azure/ai-foundry/)
- [Azure OpenAI Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
