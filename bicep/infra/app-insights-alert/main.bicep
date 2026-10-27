targetScope = 'subscription'

// ============================================================================
// AI Gateway — Application Insights Alerting
// ----------------------------------------------------------------------------
// Provisions Azure Monitor alert rules on the gateway's "AI Gateway Alert"
// custom metric, emitted by the `raise-alert-events` APIM policy fragment. One
// alert rule is created per entry in `alerts`, each filtered by the alertType
// dimension and wired to a single email Action Group.
//
// Two alerting modes (see `alertMode`):
//   logQuery (DEFAULT) — scheduled query (log search) alerts on the customMetrics
//                        table. Works immediately; the metric data is in the logs
//                        as soon as the gateway emits it.
//   metric             — metric alerts on the `ai-gateway-alerts` custom metric
//                        namespace. Only works AFTER the metric has first been
//                        emitted and the namespace has registered.
//
// Prerequisite: a Citadel Governance Hub deployment whose APIM instance emits
// the alert metric to an Application Insights component (the `appinsights-logger`).
//
// See guides/throttling-events-handling.md and guides/resiliency-guide.md.
// ============================================================================

@description('Application Insights component the gateway emits custom metrics to. { subscriptionId, resourceGroupName, name }')
param appInsights object

@description('Resource group to create the alert rules and action group in. Defaults to the App Insights resource group.')
param alertResourceGroupName string = appInsights.resourceGroupName

@description('Prefix used to name the action group and alert rules.')
param namePrefix string = 'ai-gateway'

@description('Action group short name (max 12 chars) shown as the email sender label.')
@maxLength(12)
param actionGroupShortName string = 'aigwalerts'

@description('Optional primary email address for notifications. Empty = no primary email receiver; alert rules still run.')
param alertEmailAddress string = ''

@description('Optional additional email receivers. Each item: { name: string, email: string }.')
param additionalEmailReceivers array = []

@description('Custom metric namespace emitted by the gateway alerting fragment (emit-metric namespace).')
param metricNamespace string = 'ai-gateway-alerts'

@description('Custom metric name emitted by the gateway alerting fragment.')
param metricName string = 'AI Gateway Alert'

@description('Optional productName (access contract) to scope ALL alert rules to a single use case. This must be the APIM product DISPLAY NAME emitted in the productName dimension (space-separated, e.g. \'LLM Ops AlertProbe DEV\'), NOT the hyphenated product id. Empty = all use cases.')
param productNameFilter string = ''

@description('Whether the alert rules are enabled on creation.')
param alertsEnabled bool = true

@description('''Alerting mode:
  logQuery : (DEFAULT) scheduled query (log search) alerts on the App Insights `customMetrics` table.
             Works immediately because customMetrics telemetry is written to logs as soon as the gateway
             emits it — no waiting for the pre-aggregated custom metric namespace to register.
  metric   : Azure Monitor metric alerts on the `ai-gateway-alerts` custom metric namespace. More
             efficient/lower-latency, but can ONLY be created AFTER the metric has first been emitted and
             the namespace has registered (which can take minutes). Switch to this once the metric is
             visible under App Insights → Metrics.''')
@allowed([
  'logQuery'
  'metric'
])
param alertMode string = 'logQuery'

@description('''Alert rules to create — one Azure Monitor metric alert per entry, all wired to the same action group.
Each item:
  name                : short unique suffix for the rule (e.g. "throttling")
  alertType           : dimension value to filter on (throttling | backend-failure | auth-failure | content-safety | pii-failure)
  severity            : 0 Critical .. 4 Verbose
  operator            : GreaterThan | GreaterThanOrEqual | Equals
  threshold           : event count that must be crossed
  timeAggregation     : Total (event count over the window)
  windowSize          : ISO 8601 look-back window (e.g. PT5M)
  evaluationFrequency : ISO 8601 evaluation cadence (e.g. PT1M)
  description         : text included in the notification email''')
param alerts array = [
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
]

// Effective email receiver list = primary address + any additional receivers.
var emailReceivers = concat(
  !empty(trim(alertEmailAddress)) ? [
    {
      name: 'primary'
      email: trim(alertEmailAddress)
    }
  ] : [],
  additionalEmailReceivers
)

resource alertRg 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription(appInsights.subscriptionId)
  name: alertResourceGroupName
}

// Resolve the Application Insights component resource id for the alert scope.
resource appInsightsComponent 'Microsoft.Insights/components@2020-02-02' existing = {
  scope: resourceGroup(appInsights.subscriptionId, appInsights.resourceGroupName)
  name: appInsights.name
}

// ---- Action Group (email notifications) ----
module actionGroup 'modules/action-group.bicep' = {
  name: 'deploy-ag-${uniqueString(namePrefix, appInsightsComponent.id)}'
  scope: alertRg
  params: {
    name: '${namePrefix}-alerts-ag'
    shortName: actionGroupShortName
    emailReceivers: emailReceivers
  }
}

// ---- DEFAULT: one scheduled query (log search) alert per entry in `alerts` ----
// Uses the customMetrics table so it works immediately (no waiting for the metric namespace).
module logQueryAlertRules 'modules/log-query-alert.bicep' = [
  for alert in alerts: if (alertMode == 'logQuery') {
    name: 'deploy-logalert-${uniqueString(namePrefix, alert.name, appInsightsComponent.id)}'
    scope: alertRg
    params: {
      name: '${namePrefix}-${alert.name}-alert'
      location: appInsightsComponent.location
      alertDescription: alert.description
      severity: alert.severity
      enabled: alertsEnabled
      scopes: [ appInsightsComponent.id ]
      evaluationFrequency: alert.evaluationFrequency
      windowSize: alert.windowSize
      metricName: metricName
      operator: alert.operator
      threshold: alert.threshold
      alertType: alert.alertType
      productNameFilter: productNameFilter
      actionGroupId: actionGroup.outputs.id
    }
  }
]

// ---- OPT-IN: one metric alert per entry in `alerts` (requires the metric namespace to be registered) ----
module metricAlertRules 'modules/metric-alert.bicep' = [
  for alert in alerts: if (alertMode == 'metric') {
    name: 'deploy-metricalert-${uniqueString(namePrefix, alert.name, appInsightsComponent.id)}'
    scope: alertRg
    params: {
      name: '${namePrefix}-${alert.name}-alert'
      alertDescription: alert.description
      severity: alert.severity
      enabled: alertsEnabled
      scopes: [ appInsightsComponent.id ]
      evaluationFrequency: alert.evaluationFrequency
      windowSize: alert.windowSize
      metricNamespace: metricNamespace
      metricName: metricName
      operator: alert.operator
      threshold: alert.threshold
      timeAggregation: alert.timeAggregation
      alertType: alert.alertType
      productNameFilter: productNameFilter
      actionGroupId: actionGroup.outputs.id
    }
  }
]

output actionGroupId string = actionGroup.outputs.id
output alertMode string = alertMode
// Rule names are deterministic (same for both modes); emitted as strings so this output
// never references a conditionally-undeployed module.
output alertRuleNames array = [for alert in alerts: '${namePrefix}-${alert.name}-alert']
output appInsightsId string = appInsightsComponent.id
