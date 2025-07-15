### 3. Multi-Service AI Requirements

Standard recommendation is to create single APIM product for each AI service that a use-case requires (so a single use case may have multiple APIM Products/Subscriptions to avail different AI services with unique key for each), but in some cases it may be necessary to combine multiple AI services into a single product. This is especially true for complex use-cases that require orchestration of multiple AI services to deliver end-to-end functionality.

>**NOTE:** Consider only this section if your use-case requires multiple AI services to work together. If the use-case only requires a single AI service or if you will be creating separate APIM products for the different AI services required, you can skip this section and focus on the other decision areas. 

- **Service Composition**: What combination of AI services does this use-case require?
  - OpenAI models (GPT-4o, GPT-4, GPT-3.5 Turbo)
  - Azure AI Search
  - Document Intelligence
  - Open-source models (Llama 3, etc.)
  - Vector databases
- **Service Orchestration**: How will these services communicate with each other?
  - Direct service-to-service communication
  - Client-side orchestration
  - Gateway-managed orchestration



## Multi-Service AI Requirements (if applicable)
- Service Composition: [List all required services, e.g., "OpenAI GPT-4o, Azure AI Search, Document Intelligence"]
- Primary Service: [Which service is considered the primary/dominant one]
- Service Orchestration Method: [Client-side/Gateway-managed/Direct service-to-service]

### Example 3: Legal RAG with Multi-Service Integration (Custom JWT Authentication)

This example demonstrates a complex multi-service use-case with custom JWT authentication that supports different client applications for different services.

#### use-case Information
- Name: Legal Document RAG System
- Description: Multi-service solution for legal document analysis and Q&A using RAG pattern
- Business Unit/Team: Legal Department
- Contact: Legal Technology Team

#### Product Naming
- AI Service Prefix: MULTI (Multiple Services)
- Department/Team Code: LEGAL
- use-case Type: RAG
- Special Processing Indicator: PII
- Environment: PROD
- Product Name: MULTI-LEGAL-RAG-PII-PROD

#### Multi-Service Requirements
- Service Composition: OpenAI GPT-4o, Azure AI Search, Document Intelligence
- Primary Service: OpenAI
- Service Orchestration: Gateway-managed orchestration
- Cross-Service Authentication: Consistent JWT across all services with service-specific client applications

#### Authentication and Security
- Authentication Method: Subscription keys + JWT validation
- JWT Authentication Approach: Custom (policy variables)
- Entra ID Integration: Yes
- Tenant ID: contoso.onmicrosoft.com
- Client Application ID: Multiple (legal-rag-openai-client, legal-rag-search-client, legal-rag-docint-client)
- Audience Value: Dynamic (service-specific audiences)
- Additional Claims Required: groups (must contain 'Legal-Document-Users'), scp (service-specific scopes)
- Conditional Authentication: Yes (different client apps and audiences per service)

#### APIM Product Policy Configuration

```xml
<policies>
    <inbound>
        <base />
        
        <!-- Store the original URL for service routing -->
        <set-variable name="originalUrl" value="@(context.Request.Url.ToString())" />
        <set-variable name="serviceType" value="@{
            var url = context.Request.Url.ToString().ToLower();
            if (url.Contains("/openai/")) return "openai";
            if (url.Contains("/aisearch/")) return "aisearch";
            if (url.Contains("/documentintelligence/")) return "docint";
            return "unknown";
        }" />

        <!-- Service-specific JWT authentication configuration -->
        <choose>
            <!-- OpenAI Service Authentication -->
            <when condition="@(context.Variables["serviceType"] == "openai")">
                <set-variable name="entra-auth" value="true" />
                <set-variable name="tenant-id" value="contoso.onmicrosoft.com" />
                <set-variable name="client-id" value="legal-rag-openai-client" />
                <set-variable name="audience" value="api://legal-rag-openai.contoso.com" />
                <!-- Enable custom JWT token validation -->
                <include-fragment fragment-id="aad-auth-custom" />
            </when>
            
            <!-- AI Search Service Authentication -->
            <when condition="@(context.Variables["serviceType"] == "aisearch")">
                <set-variable name="entra-auth" value="true" />
                <set-variable name="tenant-id" value="contoso.onmicrosoft.com" />
                <set-variable name="client-id" value="legal-rag-search-client" />
                <set-variable name="audience" value="api://legal-rag-search.contoso.com" />
                <include-fragment fragment-id="aad-auth-custom" />
            </when>
            
            <!-- Document Intelligence Service Authentication -->
            <when condition="@(context.Variables["serviceType"] == "docint")">
                <set-variable name="entra-auth" value="true" />
                <set-variable name="tenant-id" value="contoso.onmicrosoft.com" />
                <set-variable name="client-id" value="legal-rag-docint-client" />
                <set-variable name="audience" value="api://legal-rag-docint.contoso.com" />
                <include-fragment fragment-id="aad-auth-custom" />
            </when>
            
            <otherwise>
                <return-response>
                    <set-status code="400" reason="Unsupported service type" />
                    <set-body>{"error": "The requested service is not supported by this product"}</set-body>
                </return-response>
            </otherwise>
        </choose>

        <!-- Service-specific configuration based on the detected service type -->
        <choose>
            <!-- OpenAI Service Configuration -->
            <when condition="@(context.Variables["serviceType"] == "openai")">
                <!-- Model restrictions for OpenAI -->
                <choose>
                    <when condition="@(!new [] { "gpt-4o", "embedding" }.Contains(context.Request.MatchedParameters["deployment-id"] ?? String.Empty))">
                        <return-response>
                            <set-status code="401" reason="Unauthorized model access" />
                        </return-response>
                    </when>
                </choose>
                
                <!-- Token limits for OpenAI -->
                <azure-openai-token-limit 
                    counter-key="@(context.Subscription.Id + "-openai")" 
                    tokens-per-minute="15000" 
                    estimate-prompt-tokens="false" 
                    tokens-consumed-header-name="consumed-tokens" 
                    remaining-tokens-header-name="remaining-tokens" 
                    token-quota="200000"
                    token-quota-period="Monthly"
                    retry-after-header-name="retry-after" />
                    
                <!-- Content safety for OpenAI -->
                <llm-content-safety backend-id="content-safety-backend" shield-prompt="true">
                    <categories output-type="EightSeverityLevels">
                        <category name="Hate" threshold="3" />
                        <category name="Violence" threshold="3" />
                        <category name="SelfHarm" threshold="3" />
                    </categories>
                </llm-content-safety>
                
                <!-- Backend selection for OpenAI -->
                <set-variable name="allowedBackend" value="openai-backend-0,openai-backend-1" />
            </when>
            
            <!-- AI Search Configuration -->
            <when condition="@(context.Variables["serviceType"] == "aisearch")">
                <!-- Configure AI Search specific policies -->
                <set-backend-service backend-id="aisearch-backend" />
                
                <!-- Rate limiting for AI Search -->
                <rate-limit calls="60" renewal-period="60" />
            </when>
            
            <!-- Document Intelligence Configuration -->
            <when condition="@(context.Variables["serviceType"] == "docint")">
                <!-- Configure Document Intelligence specific policies -->
                <set-backend-service backend-id="docint-backend" />
                
                <!-- Rate limiting for Document Intelligence -->
                <rate-limit calls="30" renewal-period="60" />
            </when>
            
            <otherwise>
                <return-response>
                    <set-status code="400" reason="Unsupported service type" />
                    <set-body>{"error": "The requested service is not supported by this product"}</set-body>
                </return-response>
            </otherwise>
        </choose>

        <!-- Common PII processing across all services -->
        <set-variable name="piiAnonymizationEnabled" value="true" />
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true")">
                <!-- Configure PII detection settings -->
                <set-variable name="piiConfidenceThreshold" value="0.8" />
                <set-variable name="piiEntityCategoryExclusions" value="" />
                <set-variable name="piiDetectionLanguage" value="en" /> 
                
                <!-- Add legal-specific PII patterns -->
                <set-variable name="piiRegexPatterns" value="@{
                    var patterns = new JArray {
                        new JObject {
                            ["pattern"] = @"\b[A-Z]{2}\d{6}[A-Z]\b",
                            ["category"] = "CASE_NUMBER"
                        },
                        new JObject {
                            ["pattern"] = @"\bCASE[- ]?\d{2}[- ]?\d{4}\b",
                            ["category"] = "CASE_REFERENCE"
                        }
                    };
                    return patterns.ToString();
                }" />
                
                <set-variable name="piiInputContent" value="@(context.Request.Body.As<string>(preserveContent: true))" />
                <include-fragment fragment-id="pii-anonymization" />
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiAnonymizedContent"))</set-body>
            </when>
        </choose>
        
        <!-- Cross-service usage tracking -->
        <set-header name="X-Service-Type" exists-action="override">
            <value>@(context.Variables["serviceType"])</value>
        </set-header>
        <set-header name="X-Multi-Service-Flow" exists-action="override">
            <value>MULTI-LEGAL-RAG</value>
        </set-header>
    
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- Service-specific response handling -->
        <set-variable name="responseBodyContent" value="@(context.Response.Body.As<string>(preserveContent: true))" />
        
        <!-- PII Deanonymization for all services -->
        <choose>
            <when condition="@(context.Variables.GetValueOrDefault<string>("piiAnonymizationEnabled") == "true" && 
                            context.Variables.ContainsKey("piiMappings"))">
                <set-variable name="piiDeanonymizeContentInput" value="@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))" />
                <include-fragment fragment-id="pii-deanonymization" />
                <set-body>@(context.Variables.GetValueOrDefault<string>("piiDeanonymizedContentOutput"))</set-body>
            </when>
            <otherwise>
                <set-body>@(context.Variables.GetValueOrDefault<string>("responseBodyContent"))</set-body>
            </otherwise>
        </choose>
        
        <!-- Add usage tracking headers -->
        <set-header name="X-Service-Response-Time" exists-action="override">
            <value>@(context.Response.Headers.GetValueOrDefault("Duration", "0"))</value>
        </set-header>
    </outbound>
    <on-error>
        <base />
        <!-- Error handling with appropriate fallback -->
        <choose>
            <when condition="@(context.LastError.Source == "aisearch-backend")">
                <set-variable name="errorMessage" value="AI Search service is currently unavailable. Using fallback." />
                <set-header name="X-Error-Source" exists-action="override">
                    <value>AI Search</value>
                </set-header>
                <!-- Could implement fallback logic here -->
            </when>
            <when condition="@(context.LastError.Source == "docint-backend")">
                <set-variable name="errorMessage" value="Document Intelligence service is currently unavailable." />
                <set-header name="X-Error-Source" exists-action="override">
                    <value>Document Intelligence</value>
                </set-header>
            </when>
            <otherwise>
                <set-variable name="errorMessage" value="An error occurred in the gateway." />
            </otherwise>
        </choose>
        
        <set-header name="X-Error-Message" exists-action="override">
            <value>@(context.Variables.GetValueOrDefault<string>("errorMessage"))</value>
        </set-header>
    </on-error>
</policies>
```

## Multi-Service AI Architecture Considerations

When implementing multi-service AI solutions through AI Hub Gateway, consider these architectural patterns:

### 1. Gateway-Orchestrated Pattern

The gateway handles service routing, coordination, and error handling:

```
Client → Gateway → [Service 1 → Service 2 → Service 3]
```

**Benefits:**
- Simplified client implementation
- Consistent policy enforcement
- Centralized observability
- Unified error handling

**Challenges:**
- Higher gateway processing overhead
- Complex policy configuration
- Potential bottlenecks

### 2. Client-Orchestrated Pattern

The client application coordinates multiple service calls:

```
Client → Gateway → Service 1
       ↓
Client → Gateway → Service 2
       ↓
Client → Gateway → Service 3
```

**Benefits:**
- More client control
- Lower gateway overhead
- Client-specific orchestration logic

**Challenges:**
- More complex client implementation
- Inconsistent handling across clients
- Distributed observability

### 3. Hybrid Orchestration Pattern

Some orchestration in gateway, some in client:

```
Client → Gateway → [Service 1 → Service 2]
       ↓
Client → Gateway → Service 3
```

**Benefits:**
- Balances control and simplicity
- Optimizes for common patterns
- Flexible implementation

**Challenges:**
- Clear responsibility boundaries needed
- Complex debugging across components