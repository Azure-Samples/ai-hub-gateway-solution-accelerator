# Implementation Summary: Dynamic LLM Backend Configuration

## Overview

This implementation enables **flexible, scalable LLM backend management** in Azure API Management (APIM) through a parameter-driven approach. The solution supports multiple LLM providers (Azure OpenAI, AI Foundry, external providers) with automatic load balancing, failover, and policy fragment generation.

## Key Features

✅ **Multi-Provider Support**: Azure OpenAI, AI Foundry, and external LLM services
✅ **Dynamic Backend Creation**: Backends created from parameter array
✅ **Automatic Load Balancing**: Requests distributed across multiple backends for the same model
✅ **Intelligent Failover**: Circuit breakers and health checks for resilience
✅ **Zero Policy Changes**: Add new models/backends without modifying XML policies
✅ **Flexible Authentication**: Managed identity, API key, or token-based auth
✅ **Priority & Weight Routing**: Control traffic distribution with granular settings

## Architecture Changes

### New Modules Created

1. **`llm-backends.bicep`**
   - Creates individual APIM backend resources
   - Configures circuit breakers, TLS, and authentication
   - Location: `infra/modules/apim/llm-backends.bicep`

2. **`llm-backend-pools.bicep`**
   - Analyzes backend configuration
   - Creates pools for multi-backend models
   - Generates policy fragment configuration
   - Location: `infra/modules/apim/llm-backend-pools.bicep`

3. **`llm-policy-fragments.bicep`**
   - Dynamically generates policy fragments
   - Injects backend pool C# code
   - Configures authentication per backend type
   - Location: `infra/modules/apim/llm-policy-fragments.bicep`

### Modified Files

1. **`infra/main.bicep`**
   - Added `llmBackendConfig` parameter
   - Passes configuration to APIM module

2. **`infra/modules/apim/apim.bicep`**
   - Added `llmBackendConfig` parameter
   - Integrated new backend modules
   - Updated dependencies

### New Documentation

1. **`guides/dynamic-llm-backend-configuration.md`**
   - Comprehensive user guide
   - Configuration examples
   - Troubleshooting tips
   - Best practices

2. **`infra/modules/apim/README-llm-backends.md`**
   - Technical module documentation
   - API reference
   - Integration examples

3. **`infra/main.parameters.llm-example.json`**
   - Example parameter file
   - Multiple backend configurations
   - Load balancing examples

## How It Works

### 1. Configuration Input

User provides backend configuration in parameter file:

```json
{
  "llmBackendConfig": {
    "value": [
      {
        "backendId": "ai-foundry-gpt4",
        "backendType": "ai-foundry",
        "endpoint": "https://project.eastus.inference.ml.azure.com",
        "authScheme": "managedIdentity",
        "supportedModels": ["gpt-4", "gpt-4-turbo"]
      }
    ]
  }
}
```

### 2. Backend Creation

`llm-backends.bicep` creates APIM backend resources:
- One backend per configuration entry
- Circuit breaker for resilience
- Managed identity authentication
- TLS validation

### 3. Pool Generation

`llm-backend-pools.bicep` analyzes backends:
- Groups backends by supported models
- Creates pools for models with multiple backends
- Direct routing for single-backend models

**Example**:
- Backend A: supports `gpt-4`, `gpt-4-turbo`
- Backend B: supports `gpt-4`, `phi-4`
- Backend C: supports `phi-4`

**Result**:
- Pool created: `gpt-4-backend-pool` (backends A, B)
- Pool created: `phi-4-backend-pool` (backends B, C)
- `gpt-4-turbo` routes directly to backend A

### 4. Policy Fragment Generation

`llm-policy-fragments.bicep` creates fragments:

**Fragment: set-backend-pools**
```csharp
var gpt4Pool = new JObject() {
    { "poolName", "gpt-4-backend-pool" },
    { "poolType", "ai-foundry" },
    { "supportedModels", new JArray("gpt-4", "gpt-4-turbo") }
};
backendPools.Add(gpt4Pool);
```

**Fragment: set-backend-authorization**
- Azure OpenAI: Adds managed identity token + URL rewrite
- AI Foundry: Adds managed identity token
- External: Uses backend credentials

### 5. Request Routing

Universal LLM API uses fragments:

```
Request → Extract Model → Match to Pool → Authenticate → Route → Response
```

## Benefits

### For Developers

- **Simple Configuration**: JSON-based backend definition
- **No XML Editing**: Policy fragments auto-generated
- **Quick Iteration**: Add backends without redeploying policies
- **Type Safety**: Bicep provides compile-time validation

### For Operations

- **Load Balancing**: Traffic distributed automatically
- **High Availability**: Automatic failover to healthy backends
- **Circuit Breakers**: Prevents cascading failures
- **Observability**: Built-in monitoring via APIM analytics

### For Business

- **Multi-Cloud Ready**: Support any OpenAI-compatible provider
- **Cost Optimization**: Route to most cost-effective backend
- **Regional Redundancy**: Deploy across multiple regions
- **Scalability**: Add capacity by adding backends

## Usage Example

### 1. Configure Backends

Create `main.parameters.json`:

```json
{
  "parameters": {
    "llmBackendConfig": {
      "value": [
        {
          "backendId": "ai-foundry-eastus",
          "backendType": "ai-foundry",
          "endpoint": "https://my-project.eastus.inference.ml.azure.com",
          "authScheme": "managedIdentity",
          "supportedModels": ["gpt-4", "gpt-4-turbo"],
          "priority": 1,
          "weight": 100
        },
        {
          "backendId": "ai-foundry-westus",
          "backendType": "ai-foundry",
          "endpoint": "https://my-project.westus.inference.ml.azure.com",
          "authScheme": "managedIdentity",
          "supportedModels": ["gpt-4"],
          "priority": 2,
          "weight": 50
        }
      ]
    }
  }
}
```

### 2. Deploy

```bash
az deployment sub create \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json
```

### 3. Use API

```bash
curl -X POST "https://apim.azure-api.net/llm/openai/chat/completions" \
  -H "Content-Type: application/json" \
  -H "api-key: <subscription-key>" \
  -d '{
    "model": "gpt-4",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

**Result**: 
- Request routed to `gpt-4-backend-pool`
- 67% traffic → eastus backend (priority 1, weight 100)
- 33% traffic → westus backend (priority 1, weight 50)
- Automatic failover if one backend is down

## Migration Path

### Existing Deployments

If you have an existing deployment with static backends:

1. **Identify Current Backends**
   - List Azure OpenAI instances
   - Note their endpoints and models

2. **Create Configuration**
   - Convert to `llmBackendConfig` format
   - Add any new AI Foundry backends

3. **Deploy Update**
   - Existing APIs continue to work
   - New Universal LLM API uses dynamic routing

4. **Gradual Migration**
   - Test new API endpoint
   - Migrate clients gradually
   - Deprecate old endpoints when ready

### Example Migration

**Before** (static):
```bicep
resource openAiBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: 'openai-backend'
  properties: {
    url: 'https://my-openai.openai.azure.com/openai'
  }
}
```

**After** (dynamic):
```json
{
  "llmBackendConfig": [
    {
      "backendId": "openai-backend",
      "backendType": "azure-openai",
      "endpoint": "https://my-openai.openai.azure.com",
      "authScheme": "managedIdentity",
      "supportedModels": ["gpt-4", "gpt-35-turbo"]
    }
  ]
}
```

## Advanced Scenarios

### Regional Load Balancing

```json
[
  {
    "backendId": "eastus-primary",
    "endpoint": "https://eastus.inference.ml.azure.com",
    "supportedModels": ["gpt-4"],
    "priority": 1,
    "weight": 100
  },
  {
    "backendId": "westus-secondary",
    "endpoint": "https://westus.inference.ml.azure.com",
    "supportedModels": ["gpt-4"],
    "priority": 2,
    "weight": 100
  }
]
```

### Multi-Model Deployment

```json
[
  {
    "backendId": "gpt-backend",
    "supportedModels": ["gpt-4", "gpt-4-turbo", "gpt-4o"]
  },
  {
    "backendId": "embedding-backend",
    "supportedModels": ["text-embedding-ada-002", "text-embedding-3-large"]
  },
  {
    "backendId": "open-source-backend",
    "supportedModels": ["Llama-3.3-70B-Instruct", "phi-4"]
  }
]
```

### Cost Optimization

Route to cheapest backend first:

```json
[
  {
    "backendId": "ai-foundry-cheap",
    "endpoint": "https://cheap-models.inference.ml.azure.com",
    "supportedModels": ["gpt-4"],
    "priority": 1
  },
  {
    "backendId": "azure-openai-premium",
    "endpoint": "https://premium.openai.azure.com",
    "supportedModels": ["gpt-4"],
    "priority": 2
  }
]
```

## Testing

### Verify Deployment

```bash
# List backends
az apim backend list -g <rg> --service-name <apim>

# Check specific backend
az apim backend show -g <rg> --service-name <apim> --backend-id ai-foundry-gpt4

# List policy fragments
az apim policy-fragment list -g <rg> --service-name <apim>

# Get set-backend-pools fragment
az apim policy-fragment show -g <rg> --service-name <apim> --policy-fragment-id set-backend-pools
```

### Test Routing

```bash
# Test gpt-4 request
curl -X POST "https://<apim>.azure-api.net/llm/openai/chat/completions" \
  -H "api-key: <key>" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hi"}]}'

# Test different model
curl -X POST "https://<apim>.azure-api.net/llm/openai/chat/completions" \
  -H "api-key: <key>" \
  -d '{"model": "phi-4", "messages": [{"role": "user", "content": "Hi"}]}'
```

## Monitoring

### Key Metrics

1. **Backend Health**: APIM → Backends → Health status
2. **Request Distribution**: Analytics → Backend dimension
3. **Error Rates**: Failures by backend
4. **Latency**: Response time per backend

### Application Insights Query

```kusto
requests
| where name == "universal-llm-api"
| extend model = tostring(customDimensions.model)
| extend backend = tostring(customDimensions.backend)
| summarize 
    requests = count(),
    avg_duration = avg(duration),
    p95_duration = percentile(duration, 95)
    by model, backend, bin(timestamp, 5m)
| order by timestamp desc
```

## Troubleshooting

### Common Issues

1. **"Model not supported" error**
   - Check model name in `supportedModels` array
   - Verify backend pool was created
   - Review policy fragment deployment

2. **"403 Forbidden" error**
   - Check `allowedBackendPools` policy variable
   - Verify RBAC configuration
   - Review Entra ID token claims

3. **"503 Service Unavailable" error**
   - Check backend health in APIM
   - Verify circuit breaker status
   - Review backend endpoint connectivity

## Security Best Practices

1. **Use Managed Identity**: Always prefer managed identity over API keys
2. **Private Endpoints**: Deploy backends with private endpoints
3. **Network Isolation**: Use VNet integration for APIM
4. **RBAC**: Implement `allowedBackendPools` for access control
5. **Audit Logs**: Enable diagnostic logs for compliance

## Performance Considerations

1. **Backend Co-location**: Deploy backends in same region as APIM when possible
2. **Circuit Breakers**: Tune thresholds based on expected load
3. **Connection Pooling**: APIM reuses connections to backends
4. **Caching**: Consider response caching for deterministic requests
5. **Rate Limiting**: Implement per-backend rate limits if needed

## Future Enhancements

Potential improvements:

1. **Dynamic RBAC**: Load `allowedBackendPools` from Azure AD groups
2. **Cost Tracking**: Add custom dimensions for cost allocation
3. **A/B Testing**: Route percentage of traffic to experimental backends
4. **Geographic Routing**: Route based on client location
5. **Model Fallback**: Automatically use alternative model if primary unavailable

## Support

For issues or questions:

1. Review [Dynamic LLM Backend Configuration Guide](../guides/dynamic-llm-backend-configuration.md)
2. Check [Module README](../infra/modules/apim/README-llm-backends.md)
3. Review Application Insights logs
4. Open GitHub issue with:
   - Backend configuration
   - Error messages
   - APIM diagnostic logs

## References

- [Azure API Management Backends](https://learn.microsoft.com/azure/api-management/backends)
- [Azure AI Foundry Inference](https://learn.microsoft.com/azure/ai-foundry/how-to/inference)
- [Azure OpenAI Service](https://learn.microsoft.com/azure/ai-services/openai/)
- [APIM Policy Expressions](https://learn.microsoft.com/azure/api-management/api-management-policy-expressions)
- [Circuit Breaker Pattern](https://learn.microsoft.com/azure/architecture/patterns/circuit-breaker)

---

**Implementation Date**: November 2025  
**Status**: Production Ready  
**Complexity**: Medium  
**Impact**: High - Enables multi-provider LLM routing with zero policy changes
