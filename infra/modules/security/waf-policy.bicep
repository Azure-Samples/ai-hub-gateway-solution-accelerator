@description('Name of the WAF Policy resource')
param name string

@description('Location for the WAF Policy resource')
param location string = resourceGroup().location

@description('WAF Policy mode - Detection (log only) or Prevention (block requests)')
@allowed([
  'Detection'
  'Prevention'
])
param mode string = 'Detection'

@description('Request body size limit in KB (1-128)')
@minValue(1)
@maxValue(128)
param requestBodySizeLimitInKb int = 128

@description('Maximum request body size in KB (1-128)')
@minValue(1)
@maxValue(128)
param maxRequestBodySizeInKb int = 128

@description('File upload size limit in MB (1-500)')
@minValue(1)
@maxValue(500)
param fileUploadSizeLimitInMb int = 100

@description('Custom rules to add to the WAF policy')
param customRules array = []

@description('Rule exclusions for the WAF policy')
param exclusions array = []


@description('Tags to apply to the WAF Policy resource')
param tags object = {}

// Create the WAF Policy resource (following accelerator pattern)
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-08-01' = {
  name: name
  location: location
  tags: union(tags, {
    'azd-service-name': name
    'waf-mode': mode
    'owasp-version': '3.2'
  })
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: toLower(mode)  // Accelerator uses lowercase: 'detection'/'prevention'
      requestBodyCheck: true
      maxRequestBodySizeInKb: maxRequestBodySizeInKb
      fileUploadLimitInMb: fileUploadSizeLimitInMb
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'  // Accelerator uses 3.2 in Bicep
        }
      ]
      exclusions: exclusions
    }
    customRules: customRules
  }
}

// Outputs
@description('Resource ID of the WAF Policy')
output wafPolicyId string = wafPolicy.id

@description('Name of the WAF Policy')
output wafPolicyName string = wafPolicy.name

@description('WAF Policy mode (detection/prevention)')
output wafPolicyMode string = wafPolicy.properties.policySettings.mode

@description('WAF Policy configuration details')
output wafPolicyConfig object = {
  mode: wafPolicy.properties.policySettings.mode
  state: wafPolicy.properties.policySettings.state
  requestBodyCheck: wafPolicy.properties.policySettings.requestBodyCheck
  maxRequestBodySizeInKb: wafPolicy.properties.policySettings.maxRequestBodySizeInKb
  fileUploadLimitInMb: wafPolicy.properties.policySettings.fileUploadLimitInMb
  managedRuleSets: length(wafPolicy.properties.managedRules.managedRuleSets)
  customRules: length(wafPolicy.properties.customRules)
  exclusions: length(wafPolicy.properties.managedRules.exclusions)
}
