param serviceName string

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: serviceName
}
// Policy Fragments
resource backendManagedIdntityPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'backend-managed-identity'
  properties: {
    value: loadTextContent('./policies/fragments/frag-backend-managed-identity.xml')
    format: 'rawxml'
  }
}
resource entraIdAuthPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'entraid-auth'
  properties: {
    value: loadTextContent('./policies/fragments/frag-entraid-auth.xml')
    format: 'rawxml'
  }
 
}


resource openAIUsageStreamingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-usage-streaming'
  properties: {
    value: loadTextContent('./policies/fragments/frag-openai-usage-streaming.xml')
    format: 'rawxml'
  }
 
}

resource throttlingEventsPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'throttling-events'
  properties: {
    value: loadTextContent('./policies/fragments/frag-throttling-events.xml')
    format: 'rawxml'
  }
}

resource genericErrorFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'generic-error'
  properties: {
    value: loadTextContent('./policies/fragments/frag-generic-error.xml')
    format: 'rawxml'
  }
}


resource aiUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'ai-usage'
  properties: {
    value: loadTextContent('./policies/fragments/frag-ai-usage.xml')
    format: 'rawxml'
  }
}

resource openAIUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'openai-usage'
  properties: {
    value: loadTextContent('./policies/fragments/frag-openai-usage.xml')
    format: 'rawxml'
  }
 
}

/*


resource validateRoutesPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'validate-routes'
  properties: {
    value: loadTextContent('./policies/fragments/frag-validate-routes.xml')
    format: 'rawxml'
  }
}

resource backendRoutingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'backend-routing'
  properties: {
    value: loadTextContent('./policies/fragments/frag-backend-routing.xml')
    format: 'rawxml'
  }
}


resource dynamicThrottlingAssignmentFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'dynamic-throttling-assignment'
  properties: {
    value: loadTextContent('./policies/fragments/frag-dynamic-throttling-assignment.xml')
    format: 'rawxml'
  }
}
*/
