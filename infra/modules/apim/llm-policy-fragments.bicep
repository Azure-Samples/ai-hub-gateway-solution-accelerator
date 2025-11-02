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
var setBackendPoolsFragmentXml = '''<fragment>
    <!--
        Fragment: Set Backend Pools
        Purpose: Defines backend pool configurations with their supported models and routing settings
        
        Expected Input Variables:
        - requestedModel: The model name extracted from the request payload
        - defaultBackendPool: Default backend pool to use when model is not mapped (empty string = error for unmapped models)
        - allowedBackendPools: Comma-separated list of allowed backend pool IDs (empty string = all pools allowed)
        
        Output Variables:
        - backendPools: JArray containing all backend pool configurations
    -->
    
    <!-- Define backend pools with their supported models and routing configurations -->
    <set-variable name="backendPools" value="@{
        JArray backendPools = new JArray();
        
        // Update the below if condition when using multiple APIM gateway regions/SHGW to get different configurations for each region
        if(context.Deployment.Region == "All Regions" || true)
        {
            // Backend Pools Configuration (Auto-generated from Bicep deployment)
            {backendPoolsCode}
        }
        else
        {
            // No backend pools found for selected region
            // Either return error (default behavior) or set default pools in the else section
        }
        
        return backendPools;   
    }" />
</fragment>'''

var updatedSetBackendPoolsFragmentXml = replace(setBackendPoolsFragmentXml, '{backendPoolsCode}', backendPoolsCode)

/**
 * Enhanced authorization fragment that supports multiple backend types
 */
var setBackendAuthorizationFragmentXml = '''<fragment>
    <!--
        Fragment: Set Target Authorization
        Purpose: Configures authentication headers and URL rewriting based on backend pool type
        
        Expected Input Variables:
        - targetPoolType: The type of the target backend pool (e.g., "azure-openai", "ai-foundry")
        - targetBackendPool: The selected backend pool name
        - requestedModel: The model name extracted from the request payload
        
        Expected Named Values:
        - uami-client-id: User-assigned managed identity client ID for authentication
        
        Side Effects:
        - Sets Authorization header with managed identity token
        - Rewrites request URL for Azure OpenAI to include deployment path
        - Sets backend service to the target backend pool
    -->
    
    <!-- Configure authentication and URL rewriting based on backend pool type -->
    <choose>
        <when condition="@(((string)context.Variables["targetPoolType"]) == "azure-openai")">
            <!-- Azure OpenAI: Use managed identity authentication with Cognitive Services resource -->
            <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" client-id="{{uami-client-id}}" ignore-error="false" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
            </set-header>
            
            <!-- Rewrite URL to inject /deployments/{model}/ path for Azure OpenAI API format -->
            <set-variable name="rewriteTemplate" value="@{
                string requestedModel = (string)context.Variables[&quot;requestedModel&quot;];
                return string.Format(&quot;/deployments/{0}/chat/completions&quot;, requestedModel);
            }" />
            <rewrite-uri template="@((string)context.Variables["rewriteTemplate"])" copy-unmatched-params="true" />
        </when>
        <when condition="@(((string)context.Variables["targetPoolType"]) == "ai-foundry")">
            <!-- AI Foundry: Use managed identity authentication with Cognitive Services resource -->
            <!-- No URL rewriting needed - AI Foundry uses standard OpenAI-compatible paths -->
            <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" client-id="{{uami-client-id}}" ignore-error="false" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
            </set-header>
        </when>
        <when condition="@(((string)context.Variables["targetPoolType"]) == "external")">
            <!-- External LLM Provider: Authentication handled by backend credentials configuration -->
            <!-- No URL rewriting or additional headers needed -->
        </when>
        <otherwise>
            <!-- Default case: Use managed identity authentication -->
            <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" client-id="{{uami-client-id}}" ignore-error="false" />
            <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
            </set-header>
        </otherwise>
    </choose>
    
    <!-- Route request to the selected backend pool -->
    <set-backend-service backend-id="@((string)context.Variables["targetBackendPool"])" />
</fragment>'''

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
