// ============================================================================
// Log Query Alert — a scheduled query rule (log search alert) on the App
// Insights `customMetrics` table for the gateway's "AI Gateway Alert" metric.
//
// This is the DEFAULT alerting mode because customMetrics telemetry is written
// to the Log Analytics/App Insights logs IMMEDIATELY, whereas the pre-aggregated
// custom metric namespace (used by metric alerts) only registers after the
// metric has first been emitted — so a metric alert can't reliably be created up
// front. See ../README.md and guides/throttling-events-handling.md.
//
// Scope: resource group (deployed by ../main.bicep into the App Insights RG).
// ============================================================================

@description('Scheduled query rule (log alert) name.')
param name string

@description('Azure region for the rule. Scheduled query rules are regional (unlike global metric alerts).')
param location string

@description('Human-readable description included in the alert notification.')
param alertDescription string

@description('Alert severity: 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose.')
@allowed([0, 1, 2, 3, 4])
param severity int = 2

@description('Whether the alert rule is enabled.')
param enabled bool = true

@description('Resource IDs the rule targets (the Application Insights component).')
param scopes array

@description('How often the rule evaluates (ISO 8601 duration, e.g. PT5M).')
param evaluationFrequency string = 'PT5M'

@description('Look-back window aggregated on each evaluation (ISO 8601 duration, e.g. PT5M).')
param windowSize string = 'PT5M'

@description('Custom metric name emitted by the gateway alerting fragment (customMetrics.name).')
param metricName string = 'AI Gateway Alert'

@description('alertType dimension value to filter on (throttling | quota-exceeded | backend-failure | auth-failure | content-safety | pii-failure). Empty = do not filter by alertType.')
param alertType string = ''

@description('Optional productName (access contract) dimension value to scope the alert to a single use case. Must be the APIM product DISPLAY NAME (space-separated, e.g. \'LLM Ops AlertProbe DEV\'), matching the emitted productName dimension. Empty = all use cases.')
param productNameFilter string = ''

@description('Comparison operator for the threshold.')
@allowed([
  'GreaterThan'
  'GreaterThanOrEqual'
  'Equal'
])
param operator string = 'GreaterThan'

@description('Threshold the aggregated event count must cross to fire.')
param threshold int = 0

@description('Action group resource ID that receives the notification.')
param actionGroupId string

@description('Platform-wide overrides require an empty productNameFilter and cannot be combined.')
@allowed([
  ''
])
param platformScopeValidation string = ''

@description('Optional KQL override returning a numeric AggregatedValue column.')
param queryOverride string = ''


@description('Automatically resolve the alert when the condition clears.')
param autoMitigate bool = true

// Build the KQL against the App Insights customMetrics table. Each alert event is
// emitted with value 1, so sum(valueSum) over the window == number of events.
// Literal single quotes in the query are escaped with a backslash (\').
var alertTypeClause = empty(alertType) ? '' : '| where tostring(customDimensions.alertType) == \'${alertType}\' '
var productClause = empty(productNameFilter) ? '' : '| where tostring(customDimensions.productName) == \'${productNameFilter}\' '
var query = 'customMetrics | where name == \'${metricName}\' ${alertTypeClause}${productClause}| summarize AggregatedValue = sum(valueSum) by bin(timestamp, 1m)'

resource logQueryRule 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: name
  location: location
  properties: {
    displayName: name
    description: alertDescription
    severity: severity
    enabled: enabled
    scopes: scopes
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    // App Insights is a Log Analytics-backed (workspace) resource; no dedicated
    // alerts storage is required for these queries.
    checkWorkspaceAlertsStorageConfigured: false
    criteria: {
      allOf: [
        {
          query: empty(queryOverride) ? query : queryOverride
          timeAggregation: 'Total'
          metricMeasureColumn: 'AggregatedValue'
          operator: operator
          threshold: threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output id string = logQueryRule.id
output name string = logQueryRule.name
