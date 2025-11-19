/**
 * @module policy-fragments
 * @description This module creates all policy fragments for the API Management service.
 * It includes configurations for authentication, routing, usage tracking, and PII handling.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('The name of the API Management service')
param apimServiceName string

@description('Enable PII Anonymization features')
param enablePIIAnonymization bool = true

@description('Enable AI Model Inference features')
param enableAIModelInference bool = true

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimServiceName
}

resource aadAuthPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'aad-auth'
  properties: {
    value: loadTextContent('./policies/frag-aad-auth.xml')
    format: 'rawxml'
  }
}

resource validateRoutesPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'validate-routes'
  properties: {
    value: loadTextContent('./policies/frag-validate-routes.xml')
    format: 'rawxml'
  }
}

resource backendRoutingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'backend-routing'
  properties: {
    value: loadTextContent('./policies/frag-backend-routing.xml')
    format: 'rawxml'
  }
}

resource openAIUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'openai-usage'
  properties: {
    value: loadTextContent('./policies/frag-openai-usage.xml')
    format: 'rawxml'
  }
}

resource openAIUsageStreamingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'openai-usage-streaming'
  properties: {
    value: loadTextContent('./policies/frag-openai-usage-streaming.xml')
    format: 'rawxml'
  }
}

resource aiUsagePolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'ai-usage'
  properties: {
    value: loadTextContent('./policies/frag-ai-usage.xml')
    format: 'rawxml'
  }
}

resource throttlingEventsPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'throttling-events'
  properties: {
    value: loadTextContent('./policies/frag-throttling-events.xml')
    format: 'rawxml'
  }
}

resource dynamicThrottlingAssignmentFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'dynamic-throttling-assignment'
  properties: {
    value: loadTextContent('./policies/frag-dynamic-throttling-assignment.xml')
    format: 'rawxml'
  }
}

resource piiAnonymizationPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'pii-anonymization'
  properties: {
    value: loadTextContent('./policies/frag-pii-anonymization.xml')
    format: 'rawxml'
  }
}

resource piiDenonymizationPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = {
  parent: apimService
  name: 'pii-deanonymization'
  properties: {
    value: loadTextContent('./policies/frag-pii-deanonymization.xml')
    format: 'rawxml'
  }
}

resource piiStateSavingPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = if (enablePIIAnonymization) {
  parent: apimService
  name: 'pii-state-saving'
  properties: {
    value: loadTextContent('./policies/frag-pii-state-saving.xml')
    format: 'rawxml'
  }
}

resource aiFoundryCompatibilityPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = if (enablePIIAnonymization) {
  parent: apimService
  name: 'ai-foundry-compatibility'
  properties: {
    value: loadTextContent('./policies/frag-ai-foundry-compatibility.xml')
    format: 'rawxml'
  }
}

resource aiFoundryDeploymentsPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2022-08-01' = if (enableAIModelInference) {
  parent: apimService
  name: 'ai-foundry-deployments'
  properties: {
    value: loadTextContent('./policies/frag-ai-foundry-deployments.xml')
    format: 'rawxml'
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('The name of the AAD auth policy fragment')
output aadAuthPolicyFragmentName string = aadAuthPolicyFragment.name

@description('The name of the validate routes policy fragment')
output validateRoutesPolicyFragmentName string = validateRoutesPolicyFragment.name

@description('The name of the backend routing policy fragment')
output backendRoutingPolicyFragmentName string = backendRoutingPolicyFragment.name

@description('The name of the OpenAI usage policy fragment')
output openAIUsagePolicyFragmentName string = openAIUsagePolicyFragment.name

@description('The name of the OpenAI usage streaming policy fragment')
output openAIUsageStreamingPolicyFragmentName string = openAIUsageStreamingPolicyFragment.name

@description('The name of the AI usage policy fragment')
output aiUsagePolicyFragmentName string = aiUsagePolicyFragment.name

@description('The name of the throttling events policy fragment')
output throttlingEventsPolicyFragmentName string = throttlingEventsPolicyFragment.name

@description('The name of the dynamic throttling assignment policy fragment')
output dynamicThrottlingAssignmentFragmentName string = dynamicThrottlingAssignmentFragment.name

@description('The name of the PII anonymization policy fragment')
output piiAnonymizationPolicyFragmentName string = piiAnonymizationPolicyFragment.name

@description('The name of the PII deanonymization policy fragment')
output piiDenonymizationPolicyFragmentName string = piiDenonymizationPolicyFragment.name

@description('The name of the PII state saving policy fragment')
output piiStateSavingPolicyFragmentName string = enablePIIAnonymization ? piiStateSavingPolicyFragment.name : ''

@description('The name of the AI Foundry compatibility policy fragment')
output aiFoundryCompatibilityPolicyFragmentName string = enablePIIAnonymization ? aiFoundryCompatibilityPolicyFragment.name : ''

@description('The name of the AI Foundry deployments policy fragment')
output aiFoundryDeploymentsPolicyFragmentName string = enableAIModelInference ? aiFoundryDeploymentsPolicyFragment.name : ''
