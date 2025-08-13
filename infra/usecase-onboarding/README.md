# Use Case Onboarding for AI Hub Gateway (APIM)

This independent Bicep solution automates onboarding of a new use case to an existing API Management (APIM) based AI Gateway.

What it does:
- Creates per-service APIM Product named `<serviceCode>-<BU>-<UseCase>-<ENV>`
- Adds APIs to the product and attaches a policy (default or custom)
- Creates a Subscription named `<product>-SUB-01`
- Stores endpoint URL and subscription primary key into your target Key Vault
- Optional: you can later wire Container Apps env vars to these secrets

## Folder layout
- `main.bicep` – Orchestrates APIM product + subscription + Key Vault secrets per requested AI service
- `modules/`
  - `apimOnboardService.bicep` – Creates a product, links APIs, applies policy, and creates a subscription
  - `apimProduct.bicep` – Lower-level product module (not directly used; kept for reuse)
  - `apimSubscription.bicep` – Lower-level subscription module (not directly used)
  - `kvSecrets.bicep` – Creates/updates Key Vault secrets
- `policies/default-ai-product-policy.xml` – Safe default policy
- `samples/usecase.parameters.json` – Example parameter file

## Parameters (main.bicep)
- `apim` object: `{ subscriptionId, resourceGroupName, name }`
- `keyVault` object: `{ subscriptionId, resourceGroupName, name }`
- `useCase` object: `{ businessUnit, useCaseName, environment }`
- `existingServices` object: `{ OAI: { apiResourceIds: [...] }, DOC: { ... }, ... }`
- `services` array: items like `{ code: "OAI", endpointSecretName: "OAI_ENDPOINT", apiKeySecretName: "OAI_KEY", policyXml?: "<policies>..</policies>" }`
- `productTerms` string: optional terms

Endpoint secret value format: `${apimGatewayUrl}/${apiPath}` where `apiPath` comes from the first API in the list for that service.

## Quickstart
1. Update `samples/usecase.parameters.json` with your APIM and Key Vault details and the API resource IDs.
2. Deploy at subscription scope.

Azure CLI:
```
az deployment sub create \
  --name usecase-onboarding \
  --location <region> \
  --template-file infra/usecase-onboarding/main.bicep \
  --parameters @infra/usecase-onboarding/samples/usecase.parameters.json
```

## Outputs
- `apimGatewayUrl` – APIM gateway base URL
- `products[]` – list of created products
- `subscriptions[]` – list with KV secret names for endpoint and API key

## Notes and best practices
- Ensure the deploying principal has RBAC to read APIM and write Key Vault secrets.
- APIM APIs must already exist; provide their resource IDs in `existingServices`.
- If you need per-product policy overrides, set `policyXml` on the matching service item.
- For Container Apps, configure env vars to reference Key Vault secrets (not automated in this pack to avoid overreach).
