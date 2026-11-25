// ============================================================================
// Metric Alert — one Azure Monitor static-threshold alert on the gateway's
// "AI Gateway Alert" custom metric (namespace "ai-gateway-alerts"), filtered
// by the alertType dimension (and optionally productName).
// Scope: resource group (deployed by ../main.bicep into the App Insights RG)
// ============================================================================

@description('Metric alert resource name.')
param name string

@description('Human-readable description included verbatim in the alert email (via common alert schema).')
param alertDescription string

@description('Alert severity: 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose.')
@allowed([0, 1, 2, 3, 4])
param severity int = 2

@description('Whether the alert rule is enabled.')
param enabled bool = true

@description('Resource IDs the alert monitors (the Application Insights component).')
param scopes array

@description('How often the rule evaluates (ISO 8601 duration, e.g. PT1M).')
param evaluationFrequency string = 'PT1M'

@description('Look-back window aggregated on each evaluation (ISO 8601 duration, e.g. PT5M).')
param windowSize string = 'PT5M'

@description('Custom metric namespace emitted by the gateway alerting fragment.')
param metricNamespace string = 'ai-gateway-alerts'

@description('Custom metric name emitted by the gateway alerting fragment.')
param metricName string = 'AI Gateway Alert'

@description('Comparison operator for the threshold.')
@allowed([
  'GreaterThan'
  'GreaterThanOrEqual'
  'Equals'
])
param operator string = 'GreaterThan'

@description('Threshold the aggregated metric must cross to fire.')
param threshold int = 10

@description('Aggregation applied over the window. Total = event count over the window.')
@allowed([
  'Total'
  'Count'
  'Average'
  'Maximum'
  'Minimum'
])
param timeAggregation string = 'Total'

@description('alertType dimension value to filter on (throttling | backend-failure | auth-failure | content-safety | pii-failure). Empty = do not filter by alertType.')
param alertType string = ''

@description('Optional productName (access contract) dimension value to scope the alert to a single use case. Must be the APIM product DISPLAY NAME (space-separated, e.g. \'LLM Ops AlertProbe DEV\'), matching the emitted productName dimension. Empty = all use cases.')
param productNameFilter string = ''

@description('Action group resource ID that receives the notification.')
param actionGroupId string

@allowed([''])
param platformScopeValidation string = ''

param skipMetricValidation bool = true


@description('Automatically resolve the alert when the condition clears.')
param autoMitigate bool = true

// Build the metric dimension filters from the provided values.
var alertTypeDimension = empty(alertType) ? [] : [
  {
    name: 'alertType'
    operator: 'Include'
    values: [ alertType ]
  }
]

var productDimension = empty(productNameFilter) ? [] : [
  {
    name: 'productName'
    operator: 'Include'
    values: [ productNameFilter ]
  }
]

var dimensions = concat(alertTypeDimension, productDimension)

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: name
  location: 'global'
  properties: {
    description: alertDescription
    severity: severity
    enabled: enabled
    scopes: scopes
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AIGatewayAlertCondition'
          metricNamespace: metricNamespace
          metricName: metricName
          operator: operator
          threshold: threshold
          timeAggregation: timeAggregation
          criterionType: 'StaticThresholdCriterion'
          // The custom metric may not exist yet at first deployment (it appears only
          // after the gateway first emits it). Skip validation so the rule deploys anyway.
          skipMetricValidation: skipMetricValidation
          dimensions: dimensions
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}

output id string = metricAlert.id
output name string = metricAlert.name
