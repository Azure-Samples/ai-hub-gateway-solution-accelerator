using 'main.bicep'

// Explicitly opt in to platform-wide monitoring. Supply real existing resource IDs.
// Verify both diagnostic channels and the API population before deploying.
var apimId = readEnvironmentVariable('CITADEL_APIM_RESOURCE_ID')
var workspaceId = readEnvironmentVariable('CITADEL_LOG_ANALYTICS_RESOURCE_ID')
var workspaceLocation = readEnvironmentVariable('CITADEL_LOG_ANALYTICS_LOCATION')
var aiSubscription = readEnvironmentVariable('AZURE_SUBSCRIPTION_ID')
var aiResourceGroup = readEnvironmentVariable('AZURE_RESOURCE_GROUP')
var aiName = readEnvironmentVariable('APIM_APP_INSIGHTS_NAME')
var appInsightsId = '/subscriptions/${aiSubscription}/resourceGroups/${aiResourceGroup}/providers/Microsoft.Insights/components/${aiName}'
var usageAppId = readEnvironmentVariable('CITADEL_USAGE_LOGIC_APP_RESOURCE_ID')
// Comma-separated APIM API IDs known to have both Azure Monitor and App Insights diagnostics.
var monitoredApiIds = readEnvironmentVariable('CITADEL_MONITORED_API_IDS')


// ============================================================================
// AI Gateway — Application Insights Alerting Parameters
// ----------------------------------------------------------------------------
// Provisions Azure Monitor metric alerts on the gateway's "AI Gateway Alert"
// custom metric (emitted by the raise-alert-events APIM policy fragment) and an
// email Action Group.
//
// Values default to azd environment variables where available; override any
// value with a literal string as needed. See ./README.md.
// ============================================================================

// ----------------------------------------------------------------------------
// REQUIRED: Application Insights component the gateway emits metrics to.
// The hub's APIM logs to a component named "appi-apim-<token>" by default.
// ----------------------------------------------------------------------------
param appInsights = {
  subscriptionId: aiSubscription
  resourceGroupName: aiResourceGroup
  name: aiName
}

// Resource group for the alert rules + action group (defaults to the App Insights RG).
// param alertResourceGroupName = readEnvironmentVariable('AZURE_RESOURCE_GROUP', 'REPLACE')

// ----------------------------------------------------------------------------
// REQUIRED: email address that receives alert notifications.
// ----------------------------------------------------------------------------
param alertEmailAddress = readEnvironmentVariable('ALERT_EMAIL_ADDRESS', 'REPLACE@example.com')

// Optional additional recipients.
// param additionalEmailReceivers = [
//   { name: 'oncall', email: 'oncall@example.com' }
// ]

// Optional: scope every alert rule to a single access contract (product) name.
// NOTE: use the APIM product DISPLAY NAME emitted in the productName dimension (space-separated),
// NOT the hyphenated product id.
// Platform-wide overrides reject a non-empty productNameFilter.

// Naming + metric identity (defaults match the shipped raise-alert-events fragment).
param namePrefix = 'ai-gateway'
param actionGroupShortName = 'aigwalerts'
param metricNamespace = 'ai-gateway-alerts'
param metricName = 'AI Gateway Alert'
param alertsEnabled = true

// Alerting mode:
//   'logQuery' (DEFAULT) — scheduled query alerts on the customMetrics table (work immediately).
//   'metric'             — metric alerts on the ai-gateway-alerts namespace (only after it registers).
param alertMode = 'logQuery'

// Keep the three legacy rules unchanged. Review and remove optional entries whose
// telemetry prerequisites are not met before deploying this platform-wide profile.
param alerts = [
  {
    name: 'throttling'
    alertType: 'throttling'
    severity: 2
    operator: 'GreaterThan'
    threshold: 10
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway throttling: the gateway returned HTTP 429 more than the threshold within the window. Likely a use case exceeded its per-minute token rate (TPM) or a backend ran out of capacity. Investigate the productName / deploymentName / backendId dimensions of the "AI Gateway Alert" metric. Remediation: review the access contract llm-token-limit tokens-per-minute, add backend pool capacity, or configure a model alias fallback. See guides/throttling-events-handling.md.'
  }
  {
    name: 'quota-exceeded'
    alertType: 'quota-exceeded'
    severity: 2
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway token-quota exceeded: the gateway returned HTTP 403 (AITokenQuotaExceeded) because a use case exhausted its long-term token-quota for the period. All further calls for that use case are blocked until the quota window resets. Investigate the productName / deploymentName dimensions of the "AI Gateway Alert" metric. Remediation: raise the access contract llm-token-limit token-quota / shorten token-quota-period, or expect the use case to be blocked until reset. See guides/throttling-events-handling.md.'
  }
  {
    name: 'backend-failure'
    alertType: 'backend-failure'
    severity: 1
    operator: 'GreaterThan'
    threshold: 5
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'AI Gateway backend failure: the gateway saw HTTP 5xx / connectivity errors from a backend more than the threshold within the window. Investigate the backendId / deploymentName dimensions. Remediation: check backend health, circuit-breaker state, and pool capacity. See guides/resiliency-guide.md.'
  }

  {
    name: 'gateway-failure'
    alertType: ''
    severity: 1
    operator: 'GreaterThan'
    threshold: 5
    timeAggregation: 'Total'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Repeated gateway policy expression failures. Check APIM gateway logs and correlate with the existing backend-failure alert.'
    logQueryOverride: {
      scope: workspaceId
      location: workspaceLocation
      query: replace(replace(replace('''
ApiManagementGatewayLogs
| where _ResourceId =~ "__APIM__"
| where ResponseCode between (500 .. 599)
| where coalesce(BackendResponseCode, 0) !between (500 .. 599)
| where LastErrorReason =~ "ExpressionValueEvaluationFailure"
| summarize AggregatedValue = count()
''', '__APIM__', apimId), '__APPINSIGHTS__', appInsightsId), '__APIS__', monitoredApiIds)
    }
  }
  {
    name: 'backend-latency'
    alertType: ''
    severity: 2
    operator: 'GreaterThan'
    threshold: 5000
    timeAggregation: 'Average'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Sustained average APIM backend request duration exceeds 5000 ms. Tune for streaming and model workloads.'
    nativeMetric: {
      scope: apimId
      namespace: 'Microsoft.ApiManagement/service'
      name: 'BackendDuration'
    }
  }
  {
    name: 'telemetry-freshness-failure'
    alertType: ''
    severity: 2
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT1H'
    evaluationFrequency: 'PT5M'
    description: 'At least ten successful monitored gateway requests but no Application Insights request telemetry in a delayed 30-minute window. Check diagnostics.'
    logQueryOverride: {
      scope: workspaceId
      location: workspaceLocation
      query: replace(replace(replace('''
let expected = toscalar(ApiManagementGatewayLogs
    | where TimeGenerated between (ago(45m) .. ago(15m))
    | where _ResourceId =~ "__APIM__"
    | where ApiId in~ (split("__APIS__", ","))
    | where ResponseCode between (200 .. 399)
    | summarize count());
let observed = toscalar(AppRequests
    | where TimeGenerated between (ago(45m) .. ago(15m))
    | where _ResourceId =~ "__APPINSIGHTS__"
    | summarize sum(ItemCount));
print AggregatedValue = iff(expected >= 10 and observed == 0, 1, 0)
''', '__APIM__', apimId), '__APPINSIGHTS__', appInsightsId), '__APIS__', monitoredApiIds)
    }
  }
  {
    name: 'usage-telemetry-failure'
    alertType: ''
    severity: 2
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT1H'
    evaluationFrequency: 'PT5M'
    description: 'At least ten token-bearing LLM log records but no Total Tokens metric in the delayed window. Check usage emission and ingestion.'
    logQueryOverride: {
      scope: workspaceId
      location: workspaceLocation
      query: replace(replace(replace('''
let expected = toscalar(ApiManagementGatewayLlmLog
    | where TimeGenerated between (ago(45m) .. ago(15m))
    | where _ResourceId =~ "__APIM__"
    | where TotalTokens > 0
    | summarize count());
let observed = toscalar(AppMetrics
    | where TimeGenerated between (ago(45m) .. ago(15m))
    | where _ResourceId =~ "__APPINSIGHTS__"
    | where Name =~ "Total Tokens"
    | summarize sum(Sum));
print AggregatedValue = iff(expected >= 10 and observed == 0, 1, 0)
''', '__APIM__', apimId), '__APPINSIGHTS__', appInsightsId), '__APIS__', monitoredApiIds)
    }
  }
  {
    name: 'usage-pipeline-failure'
    alertType: ''
    severity: 2
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Usage Logic App Standard reports workflow run failures. Inspect workflow run history. This does not prove persistence.'
    nativeMetric: {
      scope: usageAppId
      namespace: 'Microsoft.Web/sites'
      name: 'WorkflowRunsFailureRate'
    }
  }
  {
    name: 'auth-failure'
    alertType: 'auth-failure'
    severity: 2
    operator: 'GreaterThan'
    threshold: 10
    timeAggregation: 'Total'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Repeated authentication or authorization rejections. Check access contracts and credentials. Requires alertOnAuthFailure.'
  }
  {
    name: 'content-safety'
    alertType: 'content-safety'
    severity: 2
    operator: 'GreaterThan'
    threshold: 10
    timeAggregation: 'Total'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Repeated content safety policy events. Inspect errors to distinguish detections from evaluation issues. Requires alertOnContentSafety.'
  }
  {
    name: 'pii-failure'
    alertType: 'pii-failure'
    severity: 1
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
    description: 'PII evaluation failures. Check the configured PII dependency and enforcement. Requires alertOnPiiFailure.'
  }

  {
    name: 'guardrail-evaluation-failure'
    alertType: ''
    severity: 1
    operator: 'GreaterThan'
    threshold: 0
    timeAggregation: 'Total'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
    description: 'Server-side content safety policy error. Check whether the required evaluation failed. This excludes ordinary 403 blocks and does not prove all guardrail failures are visible.'
    logQueryOverride: {
      scope: workspaceId
      location: workspaceLocation
      query: replace('''
ApiManagementGatewayLogs
| where _ResourceId =~ "__APIM__"
| where ResponseCode between (500 .. 599)
| where LastErrorSource contains "content-safety"
| summarize AggregatedValue = count()
''', '__APIM__', apimId)
    }
  }
]
