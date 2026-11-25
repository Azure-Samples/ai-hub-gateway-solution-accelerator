# 🔔 AI Gateway — Application Insights Alerting

Provisions **Azure Monitor alert rules** on the gateway's `AI Gateway Alert` custom metric
(namespace `ai-gateway-alerts`) emitted by the [`raise-alert-events`](../modules/apim/policies/frag-raise-alert-events.xml)
APIM policy fragment, plus an **Action Group** that optionally emails your team when a rule fires.
Email is not required: with no primary or additional recipients, the action group has
an empty receiver list while alert rules still evaluate and fire.

One alert rule is created per entry in the `alerts` parameter, each **filtered by the `alertType`
dimension** and wired to a single shared action group. This turns the gateway's opt-in alert metrics
into actionable notifications.

## Two alerting modes (`alertMode`)

| Mode | Resource | Availability | Use when |
|------|----------|--------------|----------|
| **`logQuery`** (default) | `Microsoft.Insights/scheduledQueryRules` (log search alert on the `customMetrics` table) | **Immediate** — customMetrics telemetry is written to the App Insights **Logs** the moment the gateway emits it. | Always safe to deploy up front, including on a fresh hub before any traffic. |
| `metric` | `Microsoft.Insights/metricAlerts` (on the `ai-gateway-alerts` namespace) | **Delayed** — the pre-aggregated custom metric **namespace only registers *after* the metric has first been emitted** (minutes), and until then it is not visible under App Insights → Metrics/Alerts. | Once the namespace has registered; slightly lower latency/cost than log queries. |

> **Why `logQuery` is the default:** an Azure Monitor **metric** alert can only target a metric
> namespace that already exists. APIM `emit-metric` custom metrics land in the `customMetrics` **log**
> table immediately, but the pre-aggregated **metric** namespace is created lazily on first emission —
> so a metric alert can't reliably be created before any traffic has flowed. The log-query mode reads
> the same telemetry from Logs and works right away. Switch to `metric` once
> `az monitor metrics list-namespaces` shows `ai-gateway-alerts`.

> **Background:** the alerting model (one metric, many alert types, opt-in per access contract) is
> described in [Throttling & Critical Event Alerting](../../../guides/throttling-events-handling.md)
> and [Resiliency Guide — Alerting on Critical Events](../../../guides/resiliency-guide.md#5-alerting-on-critical-events).

## What gets deployed

| Resource | Purpose |
|----------|---------|
| `Microsoft.Insights/actionGroups` | Email notification target (common alert schema — the email includes the rule description and the fired dimension values). |
| `Microsoft.Insights/scheduledQueryRules` **or** `Microsoft.Insights/metricAlerts` (one per `alerts` entry) | Alert on `AI Gateway Alert`, filtered by `alertType` (and optionally `productName`). Which type is created depends on `alertMode`. |

The default `alerts` create **throttling**, **quota-exceeded**, and **backend-failure** rules. Extend the array with
`auth-failure`, `content-safety`, or `pii-failure` entries (only meaningful once those categories are
opted-in on the relevant access contracts).

## Prerequisites

- A deployed Citadel Governance Hub (APIM emitting the alert metric to an Application Insights component).
- The Application Insights component name. The hub creates one named `appi-apim-<token>` by default; the
  APIM `appinsights-logger` points at it.
- Permission to create alert rules / action groups in the App Insights resource group.

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `appInsights` | ✅ | — | `{ subscriptionId, resourceGroupName, name }` of the App Insights component. |
| `alertEmailAddress` | | `''` | Optional primary email. Empty omits that receiver; rules remain enabled. |
| `alertResourceGroupName` | | App Insights RG | RG to create the alert rules + action group in. |
| `additionalEmailReceivers` | | `[]` | Extra recipients: `[{ name, email }]`. |
| `metricNamespace` | | `ai-gateway-alerts` | Custom metric namespace (matches the fragment). |
| `metricName` | | `AI Gateway Alert` | Custom metric name (matches the fragment). |
| `productNameFilter` | | `''` | Scope **all** rules to one access contract. Use the APIM product **display name** (space-separated, e.g. `LLM Ops AlertProbe DEV`) — matches the `productName` dimension, **not** the hyphenated product id. |
| `alertMode` | | `logQuery` | `logQuery` = scheduled query (log search) alerts on `customMetrics` (immediate). `metric` = metric alerts on the `ai-gateway-alerts` namespace (after it registers). |
| `namePrefix` | | `ai-gateway` | Prefix for the action group + rule names. Internal nested deployment names use deterministic hashes so timestamped prefixes cannot exceed ARM's 64-character deployment-name limit. |
| `actionGroupShortName` | | `aigwalerts` | Action group short name (≤ 12 chars). |
| `alertsEnabled` | | `true` | Enable rules on creation. |
| `alerts` | | throttling + quota-exceeded + backend-failure | Array of rule definitions (see below). |

Each `alerts` entry:

```bicep
{
  name: 'throttling'          // unique suffix for the rule name
  alertType: 'throttling'     // throttling | backend-failure | auth-failure | content-safety | pii-failure
  severity: 2                 // 0 Critical .. 4 Verbose
  operator: 'GreaterThan'
  threshold: 10               // event count over the window
  timeAggregation: 'Total'
  windowSize: 'PT5M'
  evaluationFrequency: 'PT1M'
  description: 'Included verbatim in the alert email.'
}
```

> **Note (`logQuery` mode):** the rule runs a KQL query over `customMetrics` (`sum(valueSum)` of the
> `AI Gateway Alert` events, filtered by `alertType`) — no dependency on the metric namespace, so it
> works immediately. **Note (`metric` mode):** the metric alert uses `skipMetricValidation: true` so it
> deploys even before the custom metric namespace registers, but it only starts **evaluating** once the
> namespace exists (which happens after the first emission).

## Deploy

```bash
# 1) Fill in bicepparam values (or export the azd env vars it reads).
#    Required: appInsights.name, appInsights.resourceGroupName. Email is optional.

# 2) Deploy at subscription scope.
az deployment sub create \
  --name ai-gateway-alerts \
  --location <region> \
  --template-file bicep/infra/app-insights-alert/main.bicep \
  --parameters bicep/infra/app-insights-alert/main.bicepparam
```

## Validate

Trigger and verify an alert end-to-end with the
[citadel-alerting-tests.ipynb](../../../validation/citadel-alerting-tests.ipynb) notebook: it deploys a
restrictive access contract, bursts load to force `429` throttling **and** exhausts the token-quota to
force `403` (`quota-exceeded`), deploys these alert rules, and confirms the `AI Gateway Alert` metric +
alert rule state.


## Optional operational and security monitoring

The default parameter file, Action Group, custom metric identity, rule names and
default alert mode remain unchanged. No APIM policies or diagnostic settings are
changed by this package. Use [enhanced.bicepparam](./enhanced.bicepparam) as an
**opt-in starting profile**, not as a universally valid deployment. It retains
the three existing definitions verbatim. Existing custom arrays can instead
append individual definitions with unique names.

Two mutually exclusive optional properties on an alert entry select the rule type
independently of the global `alertMode`:

| Property | Shape | Behavior |
| --- | --- | --- |
| `logQueryOverride` | `{ scope, location, query }` | Scheduled query rule; scope is an existing resource ID, location is its region, query returns a numeric `AggregatedValue` column. The result is summed over the window. |
| `nativeMetric` | `{ scope, namespace, name }` | Static threshold metric rule on an existing single resource; namespace and name use REST metric identifiers. Native metric validation stays enabled. |

For override entries supply the normal common fields and `alertType: ''`.
Platform-wide overrides require an empty `productNameFilter` (the nested module
rejects incompatible configurations); do not use them for a product-scoped
deployment. Ordinary custom-metric entries still inherit the global mode and
product filter. Never change an already deployed alert's type or scope under the
same name. Use unique names; changing modes does not remove old rules.

### Signal and coverage matrix

| Optional rule | Source and condition | Severity | Limitations |
| --- | --- | --- | --- |
| gateway-failure | ApiManagementGatewayLogs, gateway 5xx, backend not 5xx, ExpressionValueEvaluationFailure, >5/15m | 1 | Narrow policy failure signal, not full outage detection. Legacy backend-failure can also count these 5xx; correlate rather than assume distinct incidents. |
| backend-latency | APIM BackendDuration average >5000 ms/15m | 2 | Native metric across APIs; tune for streaming and traffic mix. Not a percentile or time-to-first-token measurement. |
| telemetry-freshness-failure | >=10 successful monitored API gateway log records and zero AppRequests, 45–15 minutes ago | 2 | Independent APIM diagnostic channel, shared workspace dependency; detects complete request telemetry absence only. |
| usage-telemetry-failure | >=10 positive-token ApiManagementGatewayLlmLog records and zero Total Tokens AppMetrics, 45–15 minutes ago | 2 | LLM emission only; verify metric names and eligible APIs. Does not prove non-LLM/MCP/A2A or downstream persistence integrity. |
| usage-pipeline-failure | Logic Apps Standard WorkflowRunsFailureRate >0/15m | 2 | Existing usage app only; any positive failure sample, not a calculated percentage over the window. Cannot detect an entirely missed run or a successful run that loses data. |
| auth-failure | Existing custom metric auth-failure >10/15m | 2 | Requires alertOnAuthFailure; authorization and authentication are combined; legacy classification limitations remain. |
| content-safety | Existing custom metric content-safety >10/15m | 2 | Requires alertOnContentSafety; source-based classification can include evaluation errors. Not a confirmed jailbreak or confirmed successful detection count. |
| guardrail-evaluation-failure | APIM log with content-safety LastErrorSource and HTTP 5xx | 1 | Conservative policy-error indicator, not proof of every dependency/evaluation failure; excludes ordinary 403 blocks. Verify actual source in controlled tests. |
| pii-failure | Existing pii-failure metric >0/5m | 1 | Requires alertOnPiiFailure; correlate overlapping incidents. |

**Coverage gaps:** No reliable dedicated jailbreak/Prompt Shield signal was
identified in the current event contract. Do not deploy a fabricated event
counter. The built-in content safety policy may also return 403 for size limits
and can terminate a streaming response without a 403. The generic content-safety
metric is intentionally low severity. Do not treat its absence as proof that
guardrails ran. A dedicated Content Safety account can additionally be monitored
with its documented ServerErrors native metric (Microsoft.CognitiveServices/accounts);
this covers service-side 5xx, not all failed evaluations. The alert profile does
not assume access to a dedicated account.

LLM usage ingestion is scheduled; the observability guide describes eight runs
per day by default. MCP and A2A have separate scheduled workflows and non-LLM
usage may use Event Hub. Validate the live schedules and success/persistence
signals before adding overdue-processing or Cosmos DB reconciliation rules.
A successful workflow run is not proof of persistence. A missing reference
signal is unknown health, not a healthy result; these passive rules cannot
detect shared diagnostic/workspace outages or a completely silent gateway.

### Prerequisites and deployment

Set the original AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP,
APIM_APP_INSIGHTS_NAME and ALERT_EMAIL_ADDRESS variables to the existing
deployment's values. Set CITADEL_APIM_RESOURCE_ID,
CITADEL_LOG_ANALYTICS_RESOURCE_ID, CITADEL_LOG_ANALYTICS_LOCATION,
CITADEL_USAGE_LOGIC_APP_RESOURCE_ID (the existing Standard Logic App site), and
CITADEL_MONITORED_API_IDS (comma-separated exact API IDs with both diagnostic
channels enabled, no whitespace). Do not point to a shared Application Insights
component receiving unrelated traffic. Verify the same workspace contains the
resource-specific gateway and LLM tables plus AppRequests and AppMetrics for
the specified dedicated component. Verify permissions to read the workspace,
metrics and create the rules. No diagnostic settings, identities or RBAC grants
are created. Review the profile and remove inapplicable rules.

In Logs, run each override query before deployment; verify the real table names,
resource IDs, expected population, arrival latency, observed metric names and
empty results. For usage compare positive-token LLM logs only where Citadel
emits Total Tokens; remove the rule if the population differs. The delayed
window is intentionally conservative and configurable in the query. Tune latency
and volume thresholds against healthy traffic. If traffic is sparse the absence
alerts intentionally do not fire; if another API still emits telemetry, a partial
outage can be masked. Never interpret no alert as a health guarantee.

Use the same subscription deployment command as above with
`--parameters bicep/infra/app-insights-alert/enhanced.bicepparam`.
First run `az deployment sub validate` and
`az deployment sub what-if` with the same arguments as create. For the original
parameter file expect no material alert or Action Group changes; for enhanced,
expect only additional alert resources. These are expected outcomes, not
executed results.

### Validation and rollback

Run the existing notebook for legacy enforcement, telemetry and firing checks.
For the new profile, use a non-production hub and unique namePrefix, inspect
what-if, deploy only after approval, and test:

- Healthy and low-volume traffic: no freshness/usage absence alert.
- At least ten eligible requests in the delayed window, selectively suppress
  only App Insights diagnostics or token emission in the isolated test API:
  verify reference data remains present, observed data is zero, rule fires,
  then restore and verify resolution. Do not use a shared component with
  unrelated traffic. If reference data also disappears, condition is unknown.
- Repeat controlled authentication failures and content policy blocks with the
  existing switches enabled; inspect the metric and alert firing, not just HTTP
  status. A single 403 must not trigger the high-severity guardrail rule.
- In an isolated test, generate a confirmed content-safety policy 5xx and
  verify the LastErrorSource value before relying on the guardrail query.
  If the runtime signal differs, remove/tune the rule. Test PII independently.
- Generate a safe policy expression failure, a slow backend and a failed
  Standard usage workflow; confirm native metrics/logs, firing and recovery.
- Simulate no reference data and delayed arrival to confirm these do not
  falsely assert telemetry loss. Separately investigate missing reference data.

The existing default deployment needs no migration. Enhanced rules incur
additional Azure Monitor rule/evaluation costs; higher query frequencies and
additional diagnostics (if independently enabled) may add ingestion costs.
No new Azure services are provisioned. Removing entries from an incremental
deployment does **not** delete their rules: disable or explicitly delete only
the additional rule IDs after reviewing what-if and resource inventory. Do not
delete the shared Action Group or any original rule. Reapply the original
configuration to preserve legacy resources.

References: [APIM metrics](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-apimanagement-service-metrics),
[gateway logs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewaylogs),
[LLM logs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apimanagementgatewayllmlog),
[AppRequests](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests),
[AppMetrics](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appmetrics),
[Standard Logic App metrics](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-web-sites-metrics),
[APIM policy errors](https://learn.microsoft.com/azure/api-management/api-management-error-handling-policies),
[content safety policy](https://learn.microsoft.com/azure/api-management/llm-content-safety-policy),
[log alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-log-alert-rule).
