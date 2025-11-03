/**
 * @module llm-policy-fragments
 * @description Generates APIM policy fragments with backend pool configurations
 * 
 * This module creates policy fragments that contain the dynamically generated
 * backend pool configurations based on the LLM backend setup. These fragments
 * are used by the Universal LLM API policy to route requests appropriately.
 */

// ------------------
//    PARAMETERS
// ------------------

@description('Name of the API Management service')
param apimServiceName string

@description('Policy fragment configuration from backend pools module')
param policyFragmentConfig object

@description('User-assigned managed identity client ID for authentication')
param managedIdentityClientId string

// ------------------
//    VARIABLES
// ------------------

/**
 * Generate the backend pools array for the set-backend-pools fragment
 * This creates the C# code that will be injected into the policy fragment
 */
var allPools = union(policyFragmentConfig.backendPools, policyFragmentConfig.directBackends)

// Generate C# code for each backend pool with unique variable names using index
var backendPoolsArray = [for (pool, index) in allPools: replace(replace(replace(replace('''
// Pool: POOLNAME (Type: POOLTYPE)
var pool_INDEX = new JObject()
{
    { "poolName", "POOLNAME" },
    { "poolType", "POOLTYPE" },
    { "supportedModels", new JArray(MODELS) }
};
backendPools.Add(pool_INDEX);
''', 'POOLNAME', pool.poolName), 'POOLTYPE', pool.poolType), 'INDEX', string(index)), 'MODELS', join(map(pool.supportedModels, (model) => '"${model}"'), ', '))]

var backendPoolsCode = join(backendPoolsArray, '\n')

/**
 * Complete policy fragment XML with backend pools configuration
 */
var setBackendPoolsFragmentXml = loadTextContent('./policies/frag-set-backend-pools.xml')

var updatedSetBackendPoolsFragmentXml = replace(setBackendPoolsFragmentXml, '//{backendPoolsCode}', backendPoolsCode)

/**
 * Enhanced authorization fragment that supports multiple backend types
 */
var setBackendAuthorizationFragmentXml = loadTextContent('./policies/frag-set-backend-authorization.xml')

// ------------------
//    RESOURCES
// ------------------

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimServiceName
}

/**
 * Policy Fragment: Set Backend Pools
 * Contains the dynamically generated backend pool configurations
 */
resource setBackendPoolsFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-pools'
  parent: apimService
  properties: {
    description: 'Dynamically generated backend pool configurations for LLM routing'
    format: 'rawxml'
    value: updatedSetBackendPoolsFragmentXml
  }
}

/**
 * Policy Fragment: Set Backend Authorization
 * Handles authentication for different backend types (Azure OpenAI, AI Foundry, External)
 */
resource setBackendAuthorizationFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  name: 'set-backend-authorization'
  parent: apimService
  properties: {
    description: 'Authentication and routing configuration for different LLM backend types'
    format: 'rawxml'
    value: setBackendAuthorizationFragmentXml
  }
}

/**
 * Policy Fragment: Set Target Backend Pool
 * Determines which backend pool to route requests to based on model and permissions
 */
resource setTargetBackendPoolPolicyFragment 'Microsoft.ApiManagement/service/policyFragments@2024-06-01-preview' = {
  parent: apimService
  name: 'set-target-backend-pool'
  properties: {
    value: loadTextContent('./policies/frag-set-target-backend-pool.xml')
    format: 'rawxml'
  }
}

// ------------------
//    OUTPUTS
// ------------------

@description('Name of the set-backend-pools fragment')
output setBackendPoolsFragmentName string = setBackendPoolsFragment.name

@description('Name of the set-backend-authorization fragment')
output setBackendAuthorizationFragmentName string = setBackendAuthorizationFragment.name

@description('Name of the set-target-backend-pool fragment')
output setTargetBackendPoolFragmentName string = setTargetBackendPoolPolicyFragment.name

@description('Generated backend pools configuration code')
output backendPoolsCode string = backendPoolsCode
