# Decision and SystemOne models

The Unified AI API supports bounded, typed decisions without converting them into
chat completions or translating between provider schemas.

| Public POST route | Backend path | Compatible backend types |
|---|---|---|
| `/unified-ai/v1/decisions` | `/openai/v1/decisions` | `ai-foundry`, `azure-openai` |
| `/unified-ai/openai/v1/decisions` | `/openai/v1/decisions` | `ai-foundry`, `azure-openai` |
| `/unified-ai/providers/microsoft/v1/systemone` | `/providers/microsoft/v1/systemone` | `azure-decision` |

These are Unified AI routes, not additions to the legacy deployment-style API.
Only POST inference is supported. A trailing slash is accepted; descendants and
prefix lookalikes are rejected. There is no Decision GET/DELETE lifecycle or
streaming endpoint in this release. Inherited `api-version` query parameters are
removed on these routes; other query parameters and native payloads are retained.

## Prerequisites and backends

Use an existing supported model deployment and the [staged gateway
upgrade](../bicep/infra/apim-gateway-upgrade/README.md#decision--systemone-release-upgrade).
The notebook does not provision models. Both providers take the **deployment
name** in `model`; the response may identify a different, underlying model name.

Azure OpenAI Decisions currently documents `gpt-6-luna`, subject to regional
rollout restrictions. Check [current provider
availability](https://learn.microsoft.com/azure/foundry/openai/how-to/decisions)
before deployment. The gateway deliberately does not hard-code that model name.

OpenAI Decisions reuses a normal Foundry/OpenAI backend. Microsoft Decision-1
requires a separate backend even when hosted by the same account:

```bicep
// Append to the COMPLETE existing llmBackendConfig, not a replacement array.
{
  backendId: 'foundry-systemone'
  backendType: 'azure-decision'
  endpoint: 'https://REPLACE.services.ai.azure.com/'
  authType: 'managed-identity'
  supportedModels: [
    {
      name: 'REPLACE'
      modelFormat: 'Microsoft'
      operations: ['systemone']
    }
  ]
  priority: 1
  weight: 100
}
```

The endpoint is the **resource root**, without `/providers/microsoft/v1/systemone`.
The path template appends that path exactly once. Managed identity uses the
existing `https://cognitiveservices.azure.com` audience and appropriate model
inference RBAC on the resource. API-key backends can instead use the existing
`api-key-header` authentication with independent named-value/Key Vault references.
Never put provider secrets in checked-in parameters.

The Decision notebook discovers live `gpt-6-luna` and `Decision-1` registrations
automatically, without operation overrides. For other OpenAI deployment names,
declare `operations: ['decisions']` or use `operation_overrides`. Include `chat`, `responses` and
`streaming` too if those operations should remain eligible in other notebooks:
explicit lists replace inferred capabilities. The new `azure-decision` type
defaults to `systemone` in validation; an arbitrary GPT deployment does not
automatically become Decision-capable.

## Native requests

Use the **access-contract subscription key**, not the backend's provider key.
The same OpenAI body works on either OpenAI route:

```http
POST https://<gateway>/unified-ai/v1/decisions
api-key: <contract-subscription-key>
Content-Type: application/json

{
  "model": "<openai-deployment>",
  "input": "The checkout API returns 500 for every customer.",
  "questions": [
    {
      "name": "outage",
      "type": "predicate",
      "instructions": "Is the service failing?"
    }
  ]
}
```

OpenAI uses an `input` string or user-message content (including `input_text` and
`input_image`), a `questions` **array**, and an ordered `answers` **array**.
Question types are `predicate`, `choice` and `score`. Each question can return
`refusal`; check answer type before reading a value. The documented SDK minimums
are OpenAI Python 3.26.0 and JavaScript 7.30.0; REST does not need an SDK upgrade.

Microsoft uses a different contract:

```http
POST https://<gateway>/unified-ai/providers/microsoft/v1/systemone
api-key: <contract-subscription-key>
Content-Type: application/json

{
  "model": "<microsoft-deployment>",
  "state": "The checkout API returns 500 for every customer.",
  "questions": {
    "outage": {
      "type": "noul",
      "instructions": "Is the service failing?"
    }
  }
}
```

Microsoft accepts text or JSON `state`, a named `questions` **object**, and an
`answers` **object** keyed by question name. Its types are `noul`, `choice` and
`score`. A Noul answer carries its numeric value in `noul`, not `probability`.
Microsoft usage can contain `input_tokens` and `output_tokens` without
`total_tokens`; the notebook validates the returned native fields without
fabricating a total. Do not send an OpenAI `input`/array payload to SystemOne or vice versa.

## Access contracts, capacity and observability

Existing LLM Access Contract parameters, subscription/JWT authentication and
`allowedModels` grants are reused. Pool eligibility is isolated:

- OpenAI Decision requests select only Foundry/OpenAI pools.
- SystemOne requests select only `azure-decision` pools.
- Legacy surfaces cannot select `azure-decision`, including via aliases,
  default backend settings or retry candidates.
- Aliases may resolve within a compatible provider family; there is no
  cross-schema failover or payload conversion.

**Token-policy limitation:** APIM's [built-in token
limiter](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
and [token metrics](https://learn.microsoft.com/azure/api-management/llm-emit-token-metric-policy)
do not currently document either Decision schema. An existing token-only product
does not automatically provide reliable Decision token enforcement.

Use an explicitly **request-governed** product policy, with the existing model
extraction/RBAC fragments, `rate-limit-by-key`, and `quota-by-key`. The
[validation helper](../shared/decisiontools.py) builds this policy dynamically
from deployment grants and positive request limits. Production quota renewal
periods must be at least 300 seconds. Reuse this pattern when granting Decision
access; do not silently remove token limits from unrelated existing products.

The gateway keeps returned `usage` intact and exposes normal opt-in `UAIG-*`
routing headers. It explicitly skips unsupported automatic token-metric emission
on the three new routes and records a diagnostic trace. This release does not
add Decision token usage to the ingestion/reporting pipeline or fabricate zero
usage. Custom token enforcement, token telemetry, semantic-cache integration,
content-safety/PII schema adapters and automatic model-selection orchestration
are not included.

## Validation and compatibility

Run [Decision models validation](../validation/citadel-decision-models-tests.ipynb).
Run All uses live gateway registrations, not azd's saved backend list. If the
enabled targets are registered on compatible backends, it skips backend
onboarding and creates the Access Contract immediately. Stale source snapshots,
missing local additions files and older empty `apim` reporting metadata do not
force reconfiguration of otherwise working backends.

Run All reloads the Decision helper in the configuration cell, so an existing
kernel does not retain an outdated helper implementation after code updates.

The summary remains strict about real provider failures. A registered model is
not proof that every member of its backend pool supports Decisions: for example,
the provider rollout excludes East US 2. A backend's unsupported-operation
response is reported with its region, not hidden by changing the pool or
turning the result into a pass.

Step 6 includes a test matrix, the three gateway endpoints and complete native
request examples for both provider families. The run also prints its generated
sample with the actual deployment name. Positive requests require a nonempty
JSON `model` before transmission; only the deliberate missing-model negative
probe bypasses that check. HTTP errors are reported with the request model,
provider message and region before success-schema validation, so an error body
without `model` is not misreported as a request missing its deployment name.

Only when an enabled provider is missing and source/additions are explicitly
configured does optional onboarding run. Its inventory check covers the published LLM contract, backends marked as LLMs
or advertising supported models, and members of LLM model pools. Independent
APIM resources such as `content-safety-backend`, search and published-tool
backends are retained outside `llmBackendConfig`, even when they share a Foundry
hostname. They must not be copied into the LLM contract just to satisfy preview.
If an actual LLM backend is omitted, the error lists its ID: supply its full
original configuration in the complete source or explicit backend additions.
Inventory descriptions cannot reconstruct model metadata, authentication or
Key Vault references. The check runs again immediately before deployment.

1. Verify gateway context and common Decision fragments.
2. Discover live backends and model registrations, including backend-type eligibility.
3. If targets are present, skip backend-source loading, generation and deployment.
4. If a target is missing, use explicitly configured complete-source onboarding,
   or report the unavailable provider as a skip. Never reconstruct deployment
   credentials from a public contract.
5. Create a request-governed Access Contract and exercise both native schemas.
6. Check actual typed answers, usage, routing, authentication, RBAC and bounded
   request limits. Rate/quota probes use separate products and run-scoped
   counters so they do not contaminate the main contract.
7. Print explicit provider coverage and skips. A configured failed request is
   a failure; no successful provider means the run cannot pass.

Model deployments must already exist. Backend additions are shared and retained.
Product/deployment identities are stable across runs; run artifacts and test
counters are run-scoped. Cleanup defaults off and deletes only products proven
to have been created by that run, never predecessors or shared backends.

Existing backend/access contract files require no new fields, and existing
chat, embeddings, Responses, image and native-provider paths retain their
behavior. See [release 1.1.0](../releases/1.1.0.md) for version tracks, upgrade
verification and rollback.

## Provider references

- [Microsoft Decision-1](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/use-foundry-models-microsoft-decision)
- [Azure OpenAI Decisions](https://learn.microsoft.com/azure/foundry/openai/how-to/decisions)
